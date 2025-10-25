use godot::prelude::*;
use godot::classes::{PackedScene, Node, Node2D};
use dashmap::DashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use parking_lot::RwLock;

/// Generic animation/effect pool
/// Pre-instantiates scenes to avoid runtime overhead
/// Can be used for death animations, particles, floating text, etc.
pub struct EffectPool {
    /// Effect pool (pool index -> Effect node)
    pool: DashMap<usize, Gd<Node>>,

    /// Tracks which effects are currently in use
    /// Pool index -> true (in use) / false (available)
    availability: DashMap<usize, bool>,

    /// Tracks when each effect was triggered (for auto-return)
    /// Pool index -> Unix timestamp in milliseconds
    trigger_times: DashMap<usize, u64>,

    /// Next available pool index (atomic for thread safety)
    pool_size: Arc<AtomicUsize>,

    /// Animation duration in milliseconds (how long before auto-return)
    animation_duration_ms: RwLock<u64>,

    /// Scene container for adding effects to the scene tree
    scene_container: Arc<RwLock<Option<Gd<Node2D>>>>,

    /// Scene path for this pool (wrapped for interior mutability)
    scene_path: RwLock<String>,

    /// Pool name for logging
    pool_name: String,
}

impl EffectPool {
    /// Create a new empty effect pool
    pub fn new(scene_container: Arc<RwLock<Option<Gd<Node2D>>>>, pool_name: &str) -> Self {
        Self {
            pool: DashMap::new(),
            availability: DashMap::new(),
            trigger_times: DashMap::new(),
            pool_size: Arc::new(AtomicUsize::new(0)),
            animation_duration_ms: RwLock::new(1000), // Default 1 second
            scene_container,
            scene_path: RwLock::new(String::new()),
            pool_name: pool_name.to_string(),
        }
    }

    /// Initialize the effect pool by loading and instantiating the packed scene
    /// animation_duration_ms: How long each effect plays before auto-returning to pool
    pub fn initialize(&self, pool_size: usize, scene_path: &str, animation_duration_ms: u64) {
        *self.scene_path.write() = scene_path.to_string();
        *self.animation_duration_ms.write() = animation_duration_ms;
        godot_print!("[{} POOL] Initializing: size={}, scene={}, duration={}ms",
            self.pool_name, pool_size, scene_path, animation_duration_ms);

        // Load the effect scene
        let scene: Gd<PackedScene> = match try_load::<PackedScene>(scene_path) {
            Ok(scene) => scene,
            Err(err) => {
                godot_error!("[{} POOL] Failed to load scene: {} - {:?}", self.pool_name, scene_path, err);
                return;
            }
        };

        // Get the scene container
        let container_opt = {
            let container_guard = self.scene_container.read();
            container_guard.clone()
        };

        if container_opt.is_none() {
            godot_error!("[{} POOL] Cannot initialize - scene container not set!", self.pool_name);
            return;
        }

        let mut container = container_opt.unwrap();

        // Instantiate effects and add to pool
        for _i in 0..pool_size {
            let effect = scene.instantiate_as::<Node>();

            // Add to scene tree
            container.add_child(&effect);

            // Configure effect
            if let Ok(mut node2d_effect) = effect.clone().try_cast::<Node2D>() {
                node2d_effect.set_visible(false); // Hide until triggered
                node2d_effect.set_z_index(50);     // Render between NPCs and healthbars
            }

            // Add to pool and mark as available
            let index = self.pool_size.fetch_add(1, Ordering::Relaxed);
            self.pool.insert(index, effect);
            self.availability.insert(index, false); // false = available
        }

        godot_print!("[{} POOL] Initialized {} effects", self.pool_name, pool_size);
    }

    /// Get an available effect from the pool
    /// Returns the effect node and its pool index, or None if all are in use
    pub fn get_effect(&self) -> Option<(Gd<Node>, usize)> {
        // Find first effect not currently in use
        for entry in self.availability.iter() {
            let pool_index = *entry.key();
            let in_use = *entry.value();

            if !in_use {
                // Mark as in use
                self.availability.insert(pool_index, true);

                // Get the effect node
                if let Some(effect_ref) = self.pool.get(&pool_index) {
                    let effect = effect_ref.value().clone();
                    return Some((effect, pool_index));
                }
            }
        }

        // All effects are in use
        None
    }

    /// Return an effect to the pool after animation completes
    pub fn return_to_pool(&self, pool_index: usize) -> bool {
        if let Some(effect_ref) = self.pool.get(&pool_index) {
            let mut effect = effect_ref.value().clone();

            // Hide and reset the effect
            if let Ok(mut node2d_effect) = effect.try_cast::<Node2D>() {
                node2d_effect.set_visible(false);
            }

            // Mark as available
            self.availability.insert(pool_index, false);

            godot_print!("[{} POOL] Returned effect {} to pool", self.pool_name, pool_index);
            true
        } else {
            godot_warn!("[{} POOL] Invalid pool index: {}", self.pool_name, pool_index);
            false
        }
    }

    /// Get the number of effects in the pool
    pub fn count(&self) -> usize {
        self.pool.len()
    }

    /// Get the number of effects currently in use
    pub fn active_count(&self) -> usize {
        self.availability
            .iter()
            .filter(|entry| *entry.value())
            .count()
    }

    /// Trigger an effect at a specific position
    /// Returns true if effect was triggered, false if pool is full
    pub fn trigger_at_position(&self, position: Vector2) -> bool {
        if let Some((mut effect, pool_index)) = self.get_effect() {
            // Record when this effect was triggered
            let now_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64;
            self.trigger_times.insert(pool_index, now_ms);

            // Position the effect
            if let Ok(mut node2d_effect) = effect.clone().try_cast::<Node2D>() {
                node2d_effect.set_global_position(position);
                node2d_effect.set_visible(true);

                godot_print!("[{} POOL] Triggered effect {} at {:?}", self.pool_name, pool_index, position);
            }

            // Call play on the effect to start the animation
            // Rust will auto-return it to the pool after animation_duration_ms via tick()
            let _ = effect.call("play", &[]);

            true
        } else {
            godot_print!("[{} POOL] No effects available (all in use)", self.pool_name);
            false
        }
    }

    /// Tick function - automatically returns effects to pool after animation duration
    /// Call this regularly (e.g., from combat tick) to process expired effects
    pub fn tick(&self, now_ms: u64) {
        let duration = *self.animation_duration_ms.read();

        // Find effects that have exceeded their animation duration
        let mut to_return = Vec::new();
        for entry in self.trigger_times.iter() {
            let pool_index = *entry.key();
            let trigger_time = *entry.value();

            if now_ms >= trigger_time + duration {
                to_return.push(pool_index);
            }
        }

        // Return expired effects to pool
        for pool_index in to_return {
            self.trigger_times.remove(&pool_index);
            self.return_to_pool(pool_index);
        }
    }
}
