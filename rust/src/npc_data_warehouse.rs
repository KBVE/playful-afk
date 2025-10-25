use godot::prelude::*;
use godot::classes::{PackedScene, Node2D, AnimatedSprite2D};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering, AtomicU64};
use std::time::{SystemTime, UNIX_EPOCH};
use bitflags::bitflags;
use crossbeam_queue::SegQueue;
use dashmap::DashMap;
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};

// ============================================================================
// ULID CONVERSION HELPERS
// ============================================================================

/// Convert byte ULID to hex string (32 chars)
fn bytes_to_hex(bytes: &[u8; 16]) -> String {
    format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
}

/// Convert hex string (32 chars) to byte ULID
fn hex_to_bytes(hex: &str) -> Result<[u8; 16], String> {
    if hex.len() != 32 {
        return Err(format!("Invalid hex length: {}, expected 32", hex.len()));
    }

    let mut bytes = [0u8; 16];
    for i in 0..16 {
        let byte_str = &hex[i*2..i*2+2];
        bytes[i] = u8::from_str_radix(byte_str, 16)
            .map_err(|e| format!("Invalid hex at position {}: {}", i, e))?;
    }
    Ok(bytes)
}

// ============================================================================
// RUST NPC SPAWNER - Controls PackedScene instantiation and animation
// ============================================================================

/// NPC combat stats - single source of truth for all NPC stats
/// Stored in ByteMap for efficient lookup by ULID
/// Used during initialization, combat, and UI display
#[derive(Clone, Copy, Serialize, Deserialize)]
pub struct NPCCombatStats {
    pub hp: f32,
    pub max_hp: f32,
    pub attack: f32,
    pub defense: f32,
    pub static_state: i32, // Combat type + faction bitflags (immutable)
    pub emotional_state: i32,
    pub mana: f32,
    pub max_mana: f32,
    pub energy: f32,
    pub max_energy: f32,
}

/// Rust-controlled NPC instance with direct scene node access
/// This replaces GDScript pool management - Rust owns the NPCs
struct RustNPC {
    /// The root Node2D of the NPC scene
    node: Gd<Node2D>,
    /// Reference to the AnimatedSprite2D child for animation control
    animated_sprite: Option<Gd<AnimatedSprite2D>>,
    /// NPC type (warrior, archer, goblin, etc.)
    npc_type: String,
    /// Generated name for this NPC
    name: String,
    /// ULID for combat tracking (128-bit / 16 bytes)
    ulid: [u8; 16],
    /// Is this NPC currently active (spawned) or in pool (inactive)?
    is_active: bool,
    /// Stats for this NPC (extracted during instantiation)
    stats: NPCCombatStats,
}

impl RustNPC {
    /// Generate a fantasy name for an NPC based on their type
    fn generate_name(npc_type: &str) -> String {
        crate::name_generator::generate_name(npc_type)
    }

    /// Create a new NPC by instantiating a PackedScene
    fn from_scene(scene_path: &str, npc_type: &str, ulid: [u8; 16]) -> Option<Self> {
        // Load the packed scene
        let scene = match try_load::<PackedScene>(scene_path) {
            Ok(s) => s,
            Err(e) => {
                godot_error!("[RUST NPC] Failed to load scene {}: {:?}", scene_path, e);
                return None;
            }
        };

        // Instantiate as Node2D
        let mut node = match scene.try_instantiate_as::<Node2D>() {
            Some(n) => n,
            None => {
                godot_error!("[RUST NPC] Failed to instantiate scene as Node2D: {}", scene_path);
                return None;
            }
        };

        // Make invisible initially (will be made visible on spawn)
        node.set_visible(false);

        // Find the AnimatedSprite2D child node
        let animated_sprite = node.try_get_node_as::<AnimatedSprite2D>("AnimatedSprite2D");

        // Extract stats from the NPC by calling create_stats() static method
        let stats = Self::extract_stats(&mut node, npc_type);

        // Generate a unique name for this NPC
        let name = Self::generate_name(npc_type);

        // Convert first 8 bytes to hex for logging
        let ulid_hex = format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            ulid[0], ulid[1], ulid[2], ulid[3], ulid[4], ulid[5], ulid[6], ulid[7]);
        godot_print!("[RUST NPC] Created {} '{}' with ULID: {}", npc_type, name, ulid_hex);

        Some(Self {
            node,
            animated_sprite,
            npc_type: npc_type.to_string(),
            name,
            ulid,
            is_active: false,
            stats,
        })
    }

    /// Extract stats from NPC scene - now uses hardcoded stats by type
    /// GDScript create_stats() has been removed - Rust is the single source of truth
    fn extract_stats(node: &mut Gd<Node2D>, npc_type: &str) -> NPCCombatStats {
        // Get stats based on NPC type (hardcoded for now - could be config file later)
        let stats = Self::get_stats_for_type(npc_type);
        stats
    }

    /// Get stats based on NPC type (hardcoded for performance)
    fn get_stats_for_type(npc_type: &str) -> NPCCombatStats {
        match npc_type {
            // Allies
            "warrior" => NPCCombatStats {
                hp: 200.0,
                max_hp: 200.0,
                attack: 25.0,
                defense: 20.0,
                static_state: (NPCStaticState::MELEE.bits() | NPCStaticState::ALLY.bits()) as i32,
                emotional_state: 0, // Neutral
                mana: 50.0,
                max_mana: 50.0,
                energy: 100.0,
                max_energy: 100.0,
            },
            "archer" => NPCCombatStats {
                hp: 150.0,
                max_hp: 150.0,
                attack: 12.0,
                defense: 15.0,
                static_state: (NPCStaticState::RANGED.bits() | NPCStaticState::ALLY.bits()) as i32,
                emotional_state: 0,
                mana: 30.0,
                max_mana: 30.0,
                energy: 120.0,
                max_energy: 120.0,
            },

            // Monsters
            "goblin" => NPCCombatStats {
                hp: 100.0,
                max_hp: 100.0,
                attack: 15.0,
                defense: 8.0,
                static_state: (NPCStaticState::MELEE.bits() | NPCStaticState::MONSTER.bits()) as i32,
                emotional_state: 0,
                mana: 0.0,
                max_mana: 0.0,
                energy: 80.0,
                max_energy: 80.0,
            },
            "skeleton" => NPCCombatStats {
                hp: 120.0,
                max_hp: 120.0,
                attack: 18.0,
                defense: 10.0,
                static_state: (NPCStaticState::MELEE.bits() | NPCStaticState::MONSTER.bits()) as i32,
                emotional_state: 0,
                mana: 0.0,
                max_mana: 0.0,
                energy: 70.0,
                max_energy: 70.0,
            },
            "mushroom" => NPCCombatStats {
                hp: 80.0,
                max_hp: 80.0,
                attack: 10.0,
                defense: 5.0,
                static_state: (NPCStaticState::MELEE.bits() | NPCStaticState::MONSTER.bits()) as i32,
                emotional_state: 0,
                mana: 20.0,
                max_mana: 20.0,
                energy: 60.0,
                max_energy: 60.0,
            },
            "eyebeast" => NPCCombatStats {
                hp: 150.0,
                max_hp: 150.0,
                attack: 20.0,
                defense: 12.0,
                static_state: (NPCStaticState::RANGED.bits() | NPCStaticState::MONSTER.bits()) as i32,
                emotional_state: 0,
                mana: 100.0,
                max_mana: 100.0,
                energy: 90.0,
                max_energy: 90.0,
            },

            // Passive
            "chicken" => NPCCombatStats {
                hp: 1000.0,
                max_hp: 1000.0,
                attack: 0.0,
                defense: 2.0,
                static_state: NPCStaticState::PASSIVE.bits() as i32,
                emotional_state: 0,
                mana: 0.0,
                max_mana: 0.0,
                energy: 50.0,
                max_energy: 50.0,
            },
            "cat" => NPCCombatStats {
                hp: 100.0,
                max_hp: 100.0,
                attack: 5.0,
                defense: 5.0,
                static_state: NPCStaticState::PASSIVE.bits() as i32,
                emotional_state: 0,
                mana: 0.0,
                max_mana: 0.0,
                energy: 80.0,
                max_energy: 80.0,
            },

            // Default to basic stats if unknown type
            _ => NPCCombatStats {
                hp: 100.0,
                max_hp: 100.0,
                attack: 10.0,
                defense: 5.0,
                static_state: NPCStaticState::PASSIVE.bits() as i32,
                emotional_state: 0,
                mana: 0.0,
                max_mana: 0.0,
                energy: 100.0,
                max_energy: 100.0,
            },
        }
    }

    /// Get static state flags based on NPC type
    fn get_static_state_for_type(npc_type: &str) -> i32 {
        match npc_type {
            // Allies (MELEE or RANGED + ALLY)
            "warrior" => NPCStaticState::MELEE.bits() as i32 | NPCStaticState::ALLY.bits() as i32,
            "archer" => NPCStaticState::RANGED.bits() as i32 | NPCStaticState::ALLY.bits() as i32,

            // Monsters (various combat types + MONSTER)
            "goblin" => NPCStaticState::MELEE.bits() as i32 | NPCStaticState::MONSTER.bits() as i32,
            "skeleton" => NPCStaticState::MELEE.bits() as i32 | NPCStaticState::MONSTER.bits() as i32,
            "mushroom" => NPCStaticState::RANGED.bits() as i32 | NPCStaticState::MONSTER.bits() as i32,
            "eyebeast" => NPCStaticState::MAGIC.bits() as i32 | NPCStaticState::MONSTER.bits() as i32,

            // Passive
            "chicken" => NPCStaticState::PASSIVE.bits() as i32,
            "cat" => NPCStaticState::PASSIVE.bits() as i32,

            // Default to PASSIVE if unknown
            _ => NPCStaticState::PASSIVE.bits() as i32,
        }
    }

    /// Activate this NPC (spawn it into the world)
    fn activate(&mut self, position: Vector2) {
        self.is_active = true;
        self.node.set_visible(true);
        // Use local position (relative to parent Layer4Objects) not global
        self.node.set_position(position);

        // Start with idle animation when spawning
        if let Some(ref sprite) = self.animated_sprite {
            let mut sprite_mut = sprite.clone();
            sprite_mut.set_animation(&StringName::from("idle"));
            sprite_mut.play();
            godot_print!("[RUST NPC] Set animation to 'idle' and playing");
        } else {
            godot_warn!("[RUST NPC] No AnimatedSprite2D found for {}!", self.npc_type);
        }

        godot_print!("[RUST NPC] Activated {} at local position {:?}, visible={}",
            self.npc_type, position, self.node.is_visible());
    }

    /// Deactivate this NPC (return to pool)
    fn deactivate(&mut self) {
        self.is_active = false;
        self.node.set_visible(false);
    }

    /// Reset NPC for reuse (called when returning to pool)
    /// Resets stats to max but keeps ULID and name
    fn reset(&mut self) {
        // Note: ULID and name are preserved for pool reuse
        // Only reset dynamic state and stats
        self.is_active = false;
        self.node.set_visible(false);

        // Stats will be reset in the ByteMaps by the warehouse
        // The RustNPC just stores the template stats, actual HP is in ByteMaps
    }

    /// Play an animation
    fn play_animation(&mut self, animation_name: &str) {
        if let Some(ref mut sprite) = self.animated_sprite {
            sprite.set_animation(animation_name);
            sprite.play();
        }
    }

    /// Set sprite flip (for facing direction)
    fn set_flip_h(&mut self, flip: bool) {
        if let Some(ref mut sprite) = self.animated_sprite {
            sprite.set_flip_h(flip);
        }
    }
}

// ============================================================================
// NPCState bitflags - BEHAVIORAL states only (dynamic, changes during gameplay)
bitflags! {
    /// NPC behavioral state flags - these change dynamically during gameplay
    ///
    /// Matches the GDScript NPCState enum in npc_manager.gd
    /// Each NPC can have multiple behavioral states combined via bitwise OR
    ///
    /// Example: IDLE (idle behavior)
    ///          WALKING | COMBAT (moving during combat)
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
    pub struct NPCState: u32 {
        // Behavioral States (bits 0-5) - Change during gameplay (SIMPLIFIED)
        const IDLE       = 1 << 0;   // 1:  Idle (not moving, not attacking)
        const WALKING    = 1 << 1;   // 2:  Walking/moving
        const ATTACKING  = 1 << 2;   // 4:  Currently attacking (animation playing)
        const COMBAT     = 1 << 3;   // 8:  Engaged in combat
        const DAMAGED    = 1 << 4;   // 16: Taking damage - plays hurt/damage animation
        const DEAD       = 1 << 5;   // 32: Dead - plays death animation
    }
}

// Implement Send + Sync for thread safety
unsafe impl Send for NPCState {}
unsafe impl Sync for NPCState {}

// NPCStaticState bitflags - IMMUTABLE properties set once at spawn
bitflags! {
    /// Static/immutable NPC properties (set once, never change during gameplay)
    ///
    /// These flags determine the NPC's core identity and should NEVER be modified.
    /// Matches the GDScript NPCStaticState enum in npc_manager.gd
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
    pub struct NPCStaticState: u32 {
        // Combat Types (0-3) - Each NPC has exactly ONE combat type (immutable)
        const MELEE   = 1 << 0;  // 1:   Melee attacker (warriors, knights, goblins)
        const RANGED  = 1 << 1;  // 2:   Ranged attacker (archers, crossbowmen)
        const MAGIC   = 1 << 2;  // 4:   Magic attacker (mages, wizards)
        const HEALER  = 1 << 3;  // 8:   Healer/support (clerics, druids)

        // Factions (4-6) - Determines who can attack whom (immutable)
        const ALLY    = 1 << 4;  // 16:  Player's allies - don't attack each other
        const MONSTER = 1 << 5;  // 32:  Hostile creatures - attack allies
        const PASSIVE = 1 << 6;  // 64:  Doesn't attack/do damage (chickens, critters)
    }
}

// Thread-safe for HolyMap
unsafe impl Send for NPCStaticState {}
unsafe impl Sync for NPCStaticState {}

impl NPCStaticState {
    /// Convert to i32 for GDScript interop
    pub fn to_i32(self) -> i32 {
        self.bits() as i32
    }

    /// Convert from i32 (from GDScript)
    pub fn from_i32(value: i32) -> Option<Self> {
        NPCStaticState::from_bits(value as u32)
    }

    /// Convert from i32 with fallback to ALLY
    pub fn from_i32_or_ally(value: i32) -> Self {
        NPCStaticState::from_bits(value as u32).unwrap_or(NPCStaticState::ALLY)
    }
}

// Helper methods for NPCState
impl NPCState {
    /// Convert to i32 for GDScript interop (Godot uses int for enums)
    pub fn to_i32(self) -> i32 {
        self.bits() as i32
    }

    /// Convert from i32 (from GDScript)
    pub fn from_i32(value: i32) -> Option<Self> {
        NPCState::from_bits(value as u32)
    }

    /// Convert from i32 (from GDScript) with fallback to IDLE
    pub fn from_i32_or_idle(value: i32) -> Self {
        NPCState::from_bits(value as u32).unwrap_or(NPCState::IDLE)
    }
}

// World bounds constants - NPCs stay within these coordinates during combat
// These bounds match the typical viewport size (1280x720) with margins for parallax
const WORLD_MIN_X: f32 = 50.0;    // Left edge with margin
const WORLD_MAX_X: f32 = 1230.0;  // Right edge with margin
const WORLD_MIN_Y: f32 = 100.0;   // Top of playable area
const WORLD_MAX_Y: f32 = 650.0;   // Below bottom of screen

/// ULID wrapper for binary storage (16 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UlidBytes([u8; 16]);

impl UlidBytes {
    /// Create from ulid crate's Ulid
    pub fn from_ulid(ulid: ulid::Ulid) -> Self {
        UlidBytes(ulid.to_bytes())
    }

    /// Create from raw bytes (16 bytes)
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        if bytes.len() != 16 {
            return Err(format!("Invalid ULID length: expected 16 bytes, got {}", bytes.len()));
        }
        let mut arr = [0u8; 16];
        arr.copy_from_slice(bytes);
        Ok(UlidBytes(arr))
    }

    /// Convert to ulid crate's Ulid
    pub fn to_ulid(&self) -> ulid::Ulid {
        ulid::Ulid::from_bytes(self.0)
    }

    /// Convert to lowercase hex string (32 chars) for HolyMap keys
    pub fn to_hex_string(&self) -> String {
        self.0.iter()
            .map(|b| format!("{:02x}", b))
            .collect()
    }

    /// Parse from hex string (from GDScript - legacy support)
    pub fn from_hex_string(hex: &str) -> Result<Self, String> {
        if hex.len() != 32 {
            return Err(format!("Invalid hex ULID length: expected 32 chars, got {}", hex.len()));
        }

        let mut bytes = [0u8; 16];
        for i in 0..16 {
            let byte_str = &hex[i*2..i*2+2];
            bytes[i] = u8::from_str_radix(byte_str, 16)
                .map_err(|e| format!("Invalid hex at position {}: {}", i*2, e))?;
        }
        Ok(UlidBytes(bytes))
    }

    /// Get raw bytes
    pub fn as_bytes(&self) -> &[u8; 16] {
        &self.0
    }
}

// Thread-safe for HolyMap
unsafe impl Send for UlidBytes {}
unsafe impl Sync for UlidBytes {}

/// Helper: Convert PackedByteArray to hex string for HolyMap keys
/// This is the FFI boundary optimization - GDScript passes raw bytes instead of strings
fn packed_bytes_to_hex(bytes: &PackedByteArray) -> Result<String, String> {
    let slice = bytes.as_slice();
    if slice.len() != 16 {
        return Err(format!("Invalid ULID length: expected 16 bytes, got {}", slice.len()));
    }

    Ok(slice.iter()
        .map(|b| format!("{:02x}", b))
        .collect())
}

/// NPCStats - Structured stat data matching GDScript NPCStats class
///
/// This struct mirrors the NPCStats Resource in GDScript and provides
/// automatic JSON serialization via serde.
///
/// Matches: afk/nodes/npc/npc_stats.gd
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NPCStats {
    /// Unique identifier (hex string format for JSON compatibility)
    pub ulid: String,

    /// NPC's generated name (e.g., "Aldric Ironwood")
    pub npc_name: String,

    /// NPC type (e.g., "warrior", "archer")
    pub npc_type: String,

    /// Current health points
    pub hp: f32,

    /// Maximum health points
    pub max_hp: f32,

    /// Current mana
    pub mana: f32,

    /// Maximum mana
    pub max_mana: f32,

    /// Current energy/stamina
    pub energy: f32,

    /// Maximum energy/stamina
    pub max_energy: f32,

    /// Hunger level (0 = starving, 100 = full)
    pub hunger: f32,

    /// Physical attack power
    pub attack: f32,

    /// Physical defense/damage reduction
    pub defense: f32,

    /// Current emotional state (0-7, maps to Emotion enum)
    pub emotion: i32,
}

impl NPCStats {
    /// Create new NPCStats from JSON string
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    /// Serialize to JSON string
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }
}

/// CombatEvent - Events generated by Rust combat system for GDScript to render
///
/// Rust determines all combat logic and outputs these events.
/// GDScript subscribes to events and handles visual presentation only.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CombatEvent {
    /// Event type: "attack", "damage", "death", "heal", etc.
    pub event_type: String,

    /// Attacker/source NPC ULID (hex string)
    pub attacker_ulid: String,

    /// Target/victim NPC ULID (hex string)
    pub target_ulid: String,

    /// Damage/heal amount
    pub amount: f32,

    /// Animation to play on attacker ("attack_melee", "attack_ranged", "cast_spell")
    pub attacker_animation: String,

    /// Animation to play on target ("hurt", "death", "heal")
    pub target_animation: String,

    /// Target position (x, y) for projectiles/effects
    pub target_x: f32,
    pub target_y: f32,
}

impl CombatEvent {
    /// Serialize to JSON for GDScript
    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}

/// NPCDataWarehouse - High-performance NPC pool and state management
///
/// This is the Rust-based replacement for NPCManager's Dictionary-based pools.
/// Uses HolyMap for lock-free reads and fast concurrent writes.
///
/// Key Design:
/// - Lock-free reads for combat/AI queries (90%+ of operations)
/// - Fast concurrent writes for spawn/despawn
/// - WASM-safe with threading support
/// - Migrates logic from GDScript to Rust for better performance
///
/// Storage Keys:
/// - "pool:{npc_type}" → Pool definition (max size, scene path, etc.)
/// - "active:{ulid}" → Active NPC data (state, position, etc.)
/// - "ai:{ulid}" → AI behavior state
/// - "combat:{ulid}" → Combat stats and state

// Thread-safe String wrapper for HolyMap keys/values
// SafeString and SafeValue removed - using String directly with DashMap

/// Pool definition for an NPC type
#[derive(Clone, Debug)]
pub struct PoolDefinition {
    pub npc_type: String,
    pub max_size: i32,
    pub scene_path: String,
    pub current_active: i32,
}

impl PoolDefinition {
    /// Serialize to JSON string for storage
    pub fn to_json(&self) -> String {
        format!(
            r#"{{"npc_type":"{}","max_size":{},"scene_path":"{}","current_active":{}}}"#,
            self.npc_type, self.max_size, self.scene_path, self.current_active
        )
    }

    /// Deserialize from JSON string (basic implementation)
    pub fn from_json(json: &str) -> Option<Self> {
        // TODO: Proper JSON parsing - for now using simple parse
        // This is a placeholder - in production use serde_json
        Some(PoolDefinition {
            npc_type: String::from("warrior"),
            max_size: 10,
            scene_path: String::from("res://nodes/npc/warrior/warrior.tscn"),
            current_active: 0,
        })
    }
}

/// Core NPC data warehouse
pub struct NPCDataWarehouse {
    /// Main storage using DashMap for concurrent access
    storage: DashMap<String, String>,

    /// Sync interval in milliseconds
    sync_interval_ms: u64,

    /// Combat event queue - lock-free MPMC queue for Rust → GDScript communication
    combat_event_queue: Arc<SegQueue<CombatEvent>>,

    /// Combat thread running flag
    combat_thread_running: Arc<AtomicBool>,

    /// Active NPCs in combat system - Set of ULIDs for iteration
    active_combat_npcs: DashMap<String, ()>,

    /// Error tracking - prevents spam by logging each error type once per NPC
    /// Key format: "error_type:ulid" -> "1"
    error_log: DashMap<String, String>,

    /// Spawn wave management - track last spawn time and counts
    /// Rust manages ALL spawning (allies + monsters) with gradual ramp-up
    last_spawn_time_ms: Arc<AtomicU64>,
    last_ally_spawn_time_ms: Arc<AtomicU64>,  // Separate timer for allies

    /// Monster spawn configuration
    spawn_interval_ms: u64,  // Time between monster waves (default 10 seconds)
    min_wave_size: i32,       // Minimum monsters per wave (default 4)
    max_wave_size: i32,       // Maximum monsters per wave (default 10)
    min_active_monsters: i32, // Spawn new wave when below this count (default 3)

    /// Ally spawn configuration (warriors, archers)
    ally_spawn_interval_ms: u64,  // Time between ally spawns (default 3 seconds)
    max_warriors: i32,             // Max warrior count (default 6)
    max_archers: i32,              // Max archer count (default 6)

    /// Spawn tracking (defensive programming)
    spawn_requests: Arc<AtomicU64>,  // Total spawn requests sent
    spawn_confirmations: Arc<AtomicU64>,  // Total spawns confirmed by GDScript

    /// Initial spawn flag (spawn minimal entities on first tick)
    initial_spawn_done: Arc<AtomicBool>,

    /// World bounds for clamping waypoints (set by GDScript from BackgroundManager)
    /// These can be updated dynamically when background changes
    world_min_x: Arc<std::sync::atomic::AtomicU32>,  // Stored as f32 bits
    world_max_x: Arc<std::sync::atomic::AtomicU32>,
    world_min_y: Arc<std::sync::atomic::AtomicU32>,
    world_max_y: Arc<std::sync::atomic::AtomicU32>,

    // ============================================================================
    // RUST NPC POOL SYSTEM - Replaces GDScript pool management
    // ============================================================================

    /// Active NPCs (currently spawned and visible)
    /// Key: ULID bytes (Vec for HashMap compatibility) -> RustNPC instance
    active_npc_pool: DashMap<[u8; 16], RustNPC>,

    /// Inactive NPCs (in pool, ready to spawn)
    /// Key: NPC type -> Vec of inactive NPCs
    inactive_npc_pool: DashMap<String, Vec<RustNPC>>,

    /// PackedScene cache (NPC type -> PackedScene) - NO LONGER USED, kept for compatibility
    /// Cached to avoid reloading .tscn files repeatedly
    scene_cache: DashMap<String, String>,

    /// Scene tree container node (set by GDScript, NPCs are added as children)
    /// This is the Layer4Objects container from the background
    /// Wrapped in RwLock for thread-safe access (write-once, read-many pattern)
    scene_container: RwLock<Option<Gd<Node2D>>>,

    // ============================================================================
    // BYTE-KEYED STORAGE - ByteMap now uses DashMap internally for strong consistency
    // ============================================================================

    /// NPC positions (ULID bytes -> "x,y")
    npc_positions: DashMap<[u8; 16], String>,

    /// NPC metadata (ULID bytes -> value string)
    npc_names: DashMap<[u8; 16], String>,      // ULID -> generated name
    npc_types: DashMap<[u8; 16], String>,      // ULID -> npc_type (warrior, archer, etc.)

    /// NPC combat stats (ULID bytes -> NPCCombatStats struct serialized as JSON)
    /// Contains: hp, max_hp, attack, defense, static_state
    npc_combat_stats: DashMap<[u8; 16], String>,

    /// NPC dynamic state (ULID bytes -> value string)
    npc_behavioral_state: DashMap<[u8; 16], String>,
    npc_cooldown: DashMap<[u8; 16], String>,
    npc_state_timestamps: DashMap<[u8; 16], String>, // Timestamp when ATTACKING/DAMAGED states were set
    npc_aggro_targets: DashMap<[u8; 16], String>,     // Target ULID (hex) that this NPC should attack

    /// NPC movement data (ULID bytes -> "x,y" coordinates)
    npc_waypoints: DashMap<[u8; 16], String>,      // Target position for movement
    npc_move_directions: DashMap<[u8; 16], String>, // Calculated movement direction
}

impl NPCDataWarehouse {
    /// Helper to track all state writes for debugging
    fn set_behavioral_state(&self, ulid: &[u8; 16], new_state: i32, caller: &str) {
        static mut STATE_WRITE_COUNT: u32 = 0;
        unsafe {
            STATE_WRITE_COUNT += 1;
            if STATE_WRITE_COUNT <= 30 {
                let ulid_hex = bytes_to_hex(ulid);
                godot_print!("[STATE WRITE] {} - ULID {} - setting to {}", caller, &ulid_hex[..8], new_state);
            }
        }
        self.npc_behavioral_state.insert(*ulid,  new_state.to_string());
    }

    /// Create a new NPCDataWarehouse with the specified sync interval
    pub fn new(sync_interval_ms: u64) -> Self {
        godot_print!("NPCDataWarehouse: Initializing with {}ms sync interval", sync_interval_ms);
        Self {
            storage: DashMap::new(),
            sync_interval_ms,
            combat_event_queue: Arc::new(SegQueue::new()),
            combat_thread_running: Arc::new(AtomicBool::new(false)),
            active_combat_npcs: DashMap::new(),
            error_log: DashMap::new(),
            last_spawn_time_ms: Arc::new(AtomicU64::new(0)),
            last_ally_spawn_time_ms: Arc::new(AtomicU64::new(0)),
            spawn_interval_ms: 10000,  // 10 seconds between monster waves
            min_wave_size: 4,
            max_wave_size: 10,
            min_active_monsters: 3,    // Spawn new wave when below 3 monsters
            ally_spawn_interval_ms: 3000,  // 3 seconds between ally spawns (gradual ramp-up)
            max_warriors: 6,           // Cap at 6 warriors
            max_archers: 6,            // Cap at 6 archers
            spawn_requests: Arc::new(AtomicU64::new(0)),
            spawn_confirmations: Arc::new(AtomicU64::new(0)),
            initial_spawn_done: Arc::new(AtomicBool::new(false)),
            // Initialize with default world bounds (will be updated by GDScript from BackgroundManager)
            world_min_x: Arc::new(std::sync::atomic::AtomicU32::new(WORLD_MIN_X.to_bits())),
            world_max_x: Arc::new(std::sync::atomic::AtomicU32::new(WORLD_MAX_X.to_bits())),
            world_min_y: Arc::new(std::sync::atomic::AtomicU32::new(WORLD_MIN_Y.to_bits())),
            world_max_y: Arc::new(std::sync::atomic::AtomicU32::new(WORLD_MAX_Y.to_bits())),
            // Initialize Rust NPC pool system
            active_npc_pool: DashMap::new(),
            inactive_npc_pool: DashMap::new(),
            scene_cache: DashMap::new(),
            scene_container: RwLock::new(None),  // Will be set by GDScript via set_scene_container()

            // Initialize DashMap storage directly (no wrappers)
            npc_positions: DashMap::new(),
            npc_names: DashMap::new(),
            npc_types: DashMap::new(),
            npc_combat_stats: DashMap::new(),
            npc_behavioral_state: DashMap::new(),
            npc_cooldown: DashMap::new(),
            npc_state_timestamps: DashMap::new(),
            npc_aggro_targets: DashMap::new(),
            npc_waypoints: DashMap::new(),
            npc_move_directions: DashMap::new(),
        }
    }

    /// Register a new NPC pool
    pub fn register_pool(&self, npc_type: &str, max_size: i32, scene_path: &str) {
        let pool_def = PoolDefinition {
            npc_type: npc_type.to_string(),
            max_size,
            scene_path: scene_path.to_string(),
            current_active: 0,
        };

        let key = format!("pool:{}", npc_type);
        let value = pool_def.to_json();

        self.storage.insert(key, value);
        godot_print!("NPCDataWarehouse: Registered pool '{}' (max: {}, scene: {})",
                     npc_type, max_size, scene_path);
    }

    /// Get pool definition for an NPC type
    pub fn get_pool(&self, npc_type: &str) -> Option<PoolDefinition> {
        let key = format!("pool:{}", npc_type);
        self.storage.get(&key)
            .and_then(|v| PoolDefinition::from_json(v.value()))
    }

    /// Store active NPC data
    pub fn store_npc(&self, ulid: &str, npc_data: &str) {
        let key = format!("active:{}", ulid);
        let value = npc_data.to_string();
        self.storage.insert(key, value);
    }

    /// Get active NPC data
    pub fn get_npc(&self, ulid: &str) -> Option<String> {
        let key = format!("active:{}", ulid);
        self.storage.get(&key).map(|v| v.value().clone())
    }

    /// Remove NPC from active pool
    pub fn remove_npc(&self, ulid: &str) -> bool {
        let key = format!("active:{}", ulid);
        self.storage.remove(&key).is_some()
    }

    /// Store AI state for an NPC
    pub fn store_ai_state(&self, ulid: &str, ai_data: &str) {
        let key = format!("ai:{}", ulid);
        let value = ai_data.to_string();
        self.storage.insert(key, value);
    }

    /// Get AI state for an NPC
    pub fn get_ai_state(&self, ulid: &str) -> Option<String> {
        let key = format!("ai:{}", ulid);
        self.storage.get(&key).map(|v| v.value().clone())
    }

    /// Store combat state for an NPC
    pub fn store_combat_state(&self, ulid: &str, combat_data: &str) {
        let key = format!("combat:{}", ulid);
        let value = combat_data.to_string();
        self.storage.insert(key, value);
    }

    /// Get combat state for an NPC
    pub fn get_combat_state(&self, ulid: &str) -> Option<String> {
        let key = format!("combat:{}", ulid);
        self.storage.get(&key).map(|v| v.value().clone())
    }

    // ============================================================================
    // RUST NPC POOL MANAGEMENT - Replaces GDScript pool system
    // ============================================================================

    /// Pre-populate the inactive pool with NPCs of a given type
    /// This loads and instantiates PackedScenes, creating a pool ready for spawning
    pub fn initialize_npc_pool(&self, npc_type: &str, pool_size: usize, scene_path: &str) {
        godot_print!("[RUST POOL] Initializing pool for {} (size: {})", npc_type, pool_size);

        // Cache the PackedScene for this NPC type
        let scene_key = format!("scene:{}", npc_type);
        let scene_value = scene_path.to_string();
        self.scene_cache.insert(scene_key, scene_value);

        // Create pool of inactive NPCs
        let mut pool_vec = Vec::with_capacity(pool_size);
        for i in 0..pool_size {
            // Generate ULID as 16 bytes
            let ulid = ulid::Ulid::new().to_bytes();
            if let Some(npc) = RustNPC::from_scene(scene_path, npc_type, ulid) {
                pool_vec.push(npc);
            } else {
                godot_error!("[RUST POOL] Failed to create NPC {}/{} for type {}", i+1, pool_size, npc_type);
            }
        }

        let created_count = pool_vec.len();
        self.inactive_npc_pool.insert(npc_type.to_string(), pool_vec);
        godot_print!("[RUST POOL] Created {} inactive NPCs for type {}", created_count, npc_type);
    }

    /// Set the scene container (Layer4Objects) where NPCs will be added
    pub fn set_scene_container(&self, container: Gd<Node2D>) {
        godot_print!("[RUST POOL] Setting scene container");
        *self.scene_container.write() = Some(container);
    }

    /// Spawn an NPC from the inactive pool
    /// Returns the ULID bytes of the spawned NPC, or None if pool is empty
    pub fn rust_spawn_npc(&self, npc_type: &str, position: Vector2) -> Option<[u8; 16]> {
        godot_print!("[RUST SPAWN DEBUG] rust_spawn_npc called for type: {}", npc_type);

        // Get an inactive NPC from the pool
        let mut npc = {
            let mut pool_entry = match self.inactive_npc_pool.get_mut(npc_type) {
                Some(entry) => entry,
                None => {
                    // Pool doesn't exist yet - might be during initialization
                    godot_warn!("[RUST POOL] No pool found for NPC type: {} (may not be initialized yet)", npc_type);
                    return None;
                }
            };

            if pool_entry.is_empty() {
                godot_warn!("[RUST POOL] Pool empty for NPC type: {} (all NPCs in use, consider increasing pool size)", npc_type);
                return None;
            }

            pool_entry.pop().unwrap()
        };

        let ulid = npc.ulid;

        // Set ULID as a property on the NPC node BEFORE adding to tree
        // Use the existing 'ulid' property defined in npc.gd base class
        let ulid_bytes = PackedByteArray::from(&ulid[..]);
        let ulid_variant = ulid_bytes.to_variant();
        let _ = npc.node.set("ulid", &ulid_variant);

        // Add NPC to scene tree if container is set
        {
            let mut container_guard = self.scene_container.write();
            if let Some(ref mut container) = *container_guard {
                let container_path = container.get_path();
                container.add_child(&npc.node);
                let node_path = npc.node.get_path();
                godot_print!("[RUST POOL] Added {} to scene tree: container={}, node_path={}",
                    npc_type, container_path, node_path);
            } else {
                godot_error!("[RUST POOL] Cannot spawn NPC - scene container not set!");
                return None;
            }
        }

        // Activate the NPC AFTER adding to tree (important for visibility to work)
        npc.activate(position);

        // Store NPC metadata (name, type) in ByteMaps
        let npc_name = npc.name.clone();
        let npc_type_str = npc.npc_type.clone();
        self.npc_names.insert(*&ulid,  npc_name.clone());
        self.npc_types.insert(*&ulid,  npc_type_str.clone());

        // Register for combat using the stats extracted during pool initialization
        let npc_stats = npc.stats;
        let ulid_hex = bytes_to_hex(&ulid);
        godot_print!("[RUST SPAWN DEBUG] About to register NPC {} with ULID: {}", npc_type, ulid_hex);
        self.register_npc_with_stats(&ulid, &npc_stats);

        // Store position for combat system using ByteMap (no hex conversion!)
        self.npc_positions.insert(*&ulid,  format!("{},{}", position.x, position.y));

        // Set initial wander cooldown so NPC stays idle for a bit after spawning (5-10 seconds)
        use rand::Rng;
        let mut rng = rand::rng();
        let initial_idle_time = rng.random_range(5000..10000); // 5-10 seconds in milliseconds
        let ulid_hex = bytes_to_hex(&ulid);
        let now_ms = Self::get_current_time_ms();
        self.storage.insert(
            format!("wander_cooldown:{}", ulid_hex),
            (now_ms + initial_idle_time.to_string())
        );

        // Move to active pool (use [u8; 16] directly as key)
        self.active_npc_pool.insert(ulid, npc);

        // Log spawn with first 8 bytes in hex and static_state
        let ulid_hex_short = format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            ulid[0], ulid[1], ulid[2], ulid[3], ulid[4], ulid[5], ulid[6], ulid[7]);
        let is_ally = (npc_stats.static_state & NPCStaticState::ALLY.bits() as i32) != 0;
        let is_monster = (npc_stats.static_state & NPCStaticState::MONSTER.bits() as i32) != 0;
        godot_print!("[RUST POOL] Spawned {} at {:?} with ULID {} (ally={}, monster={}, static_state={})",
            npc_type, position, ulid_hex_short, is_ally, is_monster, npc_stats.static_state);

        Some(ulid)
    }

    /// Despawn an NPC and return it to the inactive pool
    pub fn rust_despawn_npc(&self, ulid: &[u8]) -> bool {
        // Remove from active pool
        let mut npc = match self.active_npc_pool.remove(ulid) {
            Some((_, npc)) => npc,
            None => {
                let ulid_hex = ulid.iter().take(8).map(|b| format!("{:02x}", b)).collect::<String>();
                godot_warn!("[RUST POOL] Cannot despawn - NPC not found: {}", ulid_hex);
                return false;
            }
        };

        // Remove from scene tree
        {
            let mut container_guard = self.scene_container.write();
            if let Some(ref mut container) = *container_guard {
                container.remove_child(&npc.node);
            }
        }

        // Convert ulid slice to array for ByteMap access
        let ulid_array: [u8; 16] = if ulid.len() == 16 {
            ulid.try_into().unwrap_or([0u8; 16])
        } else {
            [0u8; 16]
        };

        // Reset NPC stats in ByteMaps (HP back to max, remove DEAD state)
        // Get current combat stats and reset HP to max
        if let Some(stats_json) = self.npc_combat_stats.get(&ulid_array).map(|v| v.value().clone()) {
            if let Ok(mut combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                combat_stats.hp = combat_stats.max_hp;  // Reset HP to max
                if let Ok(updated_json) = serde_json::to_string(&combat_stats) {
                    self.npc_combat_stats.insert(*&ulid_array,  updated_json);
                }
            }
        }

        // Behavioral state: reset to IDLE (0)
        self.npc_behavioral_state.insert(*&ulid_array,  "0".to_string());

        // Cooldown: reset to 0
        self.npc_cooldown.insert(*&ulid_array,  "0".to_string());

        // Note: Keep name and type - they don't change when pooled NPCs respawn
        // Note: Static state (faction, combat type) never changes

        // Reset the NPC node
        npc.reset();

        // Return to inactive pool
        let npc_type = npc.npc_type.clone();
        if let Some(mut pool_entry) = self.inactive_npc_pool.get_mut(&npc_type) {
            pool_entry.push(npc);
            let ulid_hex = ulid.iter().take(8).map(|b| format!("{:02x}", b)).collect::<String>();
            godot_print!("[RUST POOL] Despawned {} '{}' (ULID: {}) - Reset and returned to pool",
                        npc_type,
                        self.npc_names.get(&ulid_array).map(|v| v.value().clone()).unwrap_or_else(|| "Unknown".to_string()),
                        ulid_hex);
            true
        } else {
            godot_error!("[RUST POOL] Cannot return NPC to pool - pool not found for type: {}", npc_type);
            false
        }
    }

    /// Register NPC for combat using pre-extracted combat stats
    fn register_npc_with_stats(&self, ulid: &[u8; 16], stats: &NPCCombatStats) {
        self.register_npc_for_combat_internal(
            ulid,
            stats.static_state,
            NPCState::IDLE.bits() as i32, // behavioral_state starts as IDLE
            stats.max_hp,
            stats.attack,
            stats.defense
        );
    }

    /// Check if NPC exists in active pool
    pub fn has_npc(&self, ulid: &str) -> bool {
        let key = format!("active:{}", ulid);
        self.storage.contains_key(&key)
    }

    /// Get total number of entries in storage
    pub fn total_entries(&self) -> usize {
        self.storage.len()
    }

    /// Get number of entries in storage (DashMap)
    pub fn read_store_count(&self) -> usize {
        self.storage.len()
    }

    /// Get number of entries in write store (DashMap)
    pub fn write_store_count(&self) -> usize {
        self.storage.len()
    }

    /// Manually trigger sync from write store to read store - no-op for DashMap
    pub fn sync(&self) {
        // DashMap doesn't need syncing - it's always consistent
    }

    /// Clear all data (use with caution!)
    pub fn clear_all(&self) {
        self.storage.clear();
        godot_print!("NPCDataWarehouse: All data cleared");
    }

    // ============================================================================
    // RUST-FIRST COMBAT SYSTEM - Internal Implementation
    // ============================================================================
    // These methods are called by GodotNPCDataWarehouse wrapper (below)
    // Rust owns all combat logic. GDScript only renders visual feedback.

    /// Update NPC position - public for Arc access
    pub fn update_npc_position_internal(&self, ulid: &str, x: f32, y: f32) {
        // DEFENSIVE: Validate position values are finite
        if !x.is_finite() {
            self.log_error_once("invalid_position_x", ulid, &format!("[COMBAT ERROR] Cannot update position for {} - invalid x: {}", ulid, x));
            return;
        }
        if !y.is_finite() {
            self.log_error_once("invalid_position_y", ulid, &format!("[COMBAT ERROR] Cannot update position for {} - invalid y: {}", ulid, y));
            return;
        }

        let key = format!("pos:{}", ulid);
        let value = format!("{},{}", x, y);
        self.storage.insert(key, value);
    }

    /// Get NPC position - public for Arc access (accepts hex ULID for backward compat)
    pub fn get_npc_position_internal(&self, ulid: &str) -> Option<(f32, f32)> {
        // Convert hex string to bytes, then lookup in ByteMap
        let ulid_bytes = hex_to_bytes(ulid).ok()?;
        if let Some(pos_str) = self.npc_positions.get(&ulid_bytes).map(|v| v.value().clone()) {
            let parts: Vec<&str> = pos_str.split(',').collect();
            if parts.len() == 2 {
                if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
                    // DEFENSIVE: Validate parsed values are finite
                    if !x.is_finite() || !y.is_finite() {
                        self.log_error_once("nan_position", ulid, &format!("[COMBAT ERROR] NPC {} has invalid position: ({}, {})", ulid, x, y));
                        return None;
                    }
                    return Some((x, y));
                }
            }
        }
        None
    }

    // ============================================================================
    // COMBAT REGISTRATION - Track NPCs in combat system
    // ============================================================================

    /// Register NPC for combat tracking
    /// Stores combat-relevant data in HolyMap for combat tick access
    pub fn register_npc_for_combat_internal(
        &self,
        ulid: &[u8; 16],
        static_state: i32,
        behavioral_state: i32,
        max_hp: f32,
        attack: f32,
        defense: f32,
    ) {
        // Convert ULID bytes to hex string for storage (combat system still uses strings internally)
        let ulid_hex = format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            ulid[0], ulid[1], ulid[2], ulid[3], ulid[4], ulid[5], ulid[6], ulid[7],
            ulid[8], ulid[9], ulid[10], ulid[11], ulid[12], ulid[13], ulid[14], ulid[15]);

        let ulid_str = &ulid_hex;

        // DEFENSIVE: Validate stats are finite and non-negative
        if !max_hp.is_finite() || max_hp < 0.0 {
            self.log_error_once("invalid_hp", ulid_str, &format!("[COMBAT ERROR] Cannot register NPC {} - invalid max_hp: {}", ulid_str, max_hp));
            return;
        }
        if !attack.is_finite() || attack < 0.0 {
            self.log_error_once("invalid_attack", ulid_str, &format!("[COMBAT ERROR] Cannot register NPC {} - invalid attack: {}", ulid_str, attack));
            return;
        }
        if !defense.is_finite() || defense < 0.0 {
            self.log_error_once("invalid_defense", ulid_str, &format!("[COMBAT ERROR] Cannot register NPC {} - invalid defense: {}", ulid_str, defense));
            return;
        }

        // DEFENSIVE: Validate exactly one combat type is set
        let combat_type_bits = [
            NPCStaticState::MELEE.bits() as i32,
            NPCStaticState::RANGED.bits() as i32,
            NPCStaticState::MAGIC.bits() as i32,
        ];
        let combat_type_count = combat_type_bits.iter()
            .filter(|&&bit| (static_state & bit) != 0)
            .count();

        if combat_type_count != 1 {
            self.log_error_once("invalid_combat_type", ulid_str, &format!("[COMBAT ERROR] Cannot register NPC {} - must have exactly one combat type (MELEE/RANGED/MAGIC), found: {}", ulid_str, combat_type_count));
            return;
        }

        // DEFENSIVE: Validate exactly one faction is set (ALLY, MONSTER, or PASSIVE)
        let faction_bits = [
            NPCStaticState::ALLY.bits() as i32,
            NPCStaticState::MONSTER.bits() as i32,
            NPCStaticState::PASSIVE.bits() as i32,
        ];
        let faction_count = faction_bits.iter()
            .filter(|&&bit| (static_state & bit) != 0)
            .count();

        if faction_count != 1 {
            self.log_error_once("invalid_faction", ulid_str, &format!("[COMBAT ERROR] Cannot register NPC {} - must have exactly one faction (ALLY/MONSTER/PASSIVE), found: {}", ulid_str, faction_count));
            return;
        }

        // All validations passed - register NPC for combat using ByteMap
        let combat_stats = NPCCombatStats {
            hp: max_hp,
            max_hp,
            attack,
            defense,
            static_state,
            emotional_state: 0, // Default neutral emotion
            mana: 0.0,          // Will be set by NPC type later if needed
            max_mana: 0.0,
            energy: 100.0,      // Default full energy
            max_energy: 100.0,
        };
        self.npc_combat_stats.insert(*ulid,  serde_json::to_string(&combat_stats).unwrap());
        let ulid_hex = bytes_to_hex(ulid);
        godot_print!("[RUST STATE] register_npc_for_combat_internal ULID {} - setting state to {}", ulid_hex, behavioral_state);
        self.npc_behavioral_state.insert(*ulid,  behavioral_state.to_string());
        self.npc_cooldown.insert(*ulid,  "0".to_string());

        // Still use hex string for active_combat_npcs DashMap (for iteration)
        self.active_combat_npcs.insert(ulid_hex, ());
    }

    /// Unregister NPC from combat (on death/despawn)
    /// Cleans up all combat-related data from HolyMaps
    pub fn unregister_npc_from_combat_internal(&self, ulid: &str) {
        // Remove combat data from storage HolyMap
        self.storage.remove(&format!("combat:{}", ulid));
        self.storage.remove(&format!("pos:{}", ulid));
        self.storage.remove(&format!("hp:{}", ulid));
        self.storage.remove(&format!("static_state:{}", ulid));
        self.storage.remove(&format!("behavioral_state:{}", ulid));
        self.storage.remove(&format!("attack:{}", ulid));
        self.storage.remove(&format!("defense:{}", ulid));
        self.storage.remove(&format!("cooldown:{}", ulid));

        // Clean up error_log entries for this NPC
        // We need to remove all error types for this ulid
        let error_types = [
            "invalid_ulid", "invalid_hp", "invalid_attack", "invalid_defense",
            "invalid_combat_type", "invalid_faction", "invalid_position_x",
            "invalid_position_y", "nan_position", "missing_position",
            "dead_attacker", "dead_target", "missing_hp", "self_attack",
            "self_attack_pair"
        ];

        for error_type in error_types {
            self.error_log.remove(&format!("{}:{}", error_type, ulid));
        }

        // Remove from active NPCs set
        self.active_combat_npcs.remove(ulid);
    }

    /// Log error once per error_type:ulid combination using error_log HolyMap
    /// This prevents spam by tracking which errors have been logged
    fn log_error_once(&self, error_type: &str, ulid: &str, message: &str) {
        let key = format!("{}:{}", error_type, ulid);

        // Check if we've already logged this error
        if self.error_log.get(&key).is_none() {
            // First time seeing this error - log it and mark as seen
            godot_error!("{}", message);
            self.error_log.insert(key, "1".to_string());
        }
        // If already logged, silently skip (no spam)
    }

    /// Get NPC current HP
    pub fn get_npc_hp_internal(&self, ulid: &str) -> Option<f32> {
        // Convert hex string to bytes
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            // Get combat stats from ByteMap
            if let Some(stats_json) = self.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
                if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                    return Some(combat_stats.hp);
                }
            }
        }
        None
    }

    /// Combat tick - public for Arc access
    /// Called by autonomous thread every 16ms (60fps)
    // ============================================================================
    // THREE-PHASE TICK SYSTEM
    // ============================================================================
    // Split into separate phases to prevent state corruption:
    // 1. Combat Phase: Calculate damage, update HP, set states (ATTACKING, DAMAGED, DEAD)
    // 2. Movement Phase: Handle wandering, calculate directions, update positions
    // 3. Animation Phase: Update sprites based on states, clear temporary states

    /// PHASE 1: COMBAT - Calculate damage, update HP, set behavioral states
    /// This phase ONLY handles combat logic and state changes
    /// Returns combat events for GDScript to handle VFX/sounds
    pub fn tick_combat_phase(&self) -> Vec<CombatEvent> {
        let mut events = Vec::new();
        let now_ms = Self::get_current_time_ms();

        // Get all active NPCs with positions
        let active_npcs = self.get_active_npcs_with_positions();
        if active_npcs.is_empty() {
            return events;
        }

        // Debug: Count NPCs by faction (disabled - too spammy)
        // static mut DEBUG_COUNT: u32 = 0;
        // unsafe {
        //     DEBUG_COUNT += 1;
        //     if DEBUG_COUNT % 300 == 1 { // Log once every 5 seconds
        //         let mut ally_count = 0;
        //         let mut monster_count = 0;
        //         for (_ulid, _x, _y, static_state, _behavioral_state, _hp, _max_hp, _attack) in &active_npcs {
        //             let is_ally = (*static_state & NPCStaticState::ALLY.bits() as i32) != 0;
        //             let is_monster = (*static_state & NPCStaticState::MONSTER.bits() as i32) != 0;
        //             if is_ally { ally_count += 1; }
        //             if is_monster { monster_count += 1; }
        //         }
        //         godot_print!("[COMBAT] {} active NPCs ({} allies, {} monsters)",
        //             active_npcs.len(), ally_count, monster_count);
        //     }
        // }

        // Find combat pairs (proximity + hostility checks)
        let combat_pairs = self.find_combat_pairs(&active_npcs);

        if combat_pairs.is_empty() {
            return events; // No combat happening (removed spam logging)
        }

        // Log when we first find combat pairs
        static mut FIRST_COMBAT_LOG: bool = false;
        unsafe {
            if !FIRST_COMBAT_LOG {
                godot_print!("[PHASE 1: COMBAT] *** FIRST COMBAT PAIRS FOUND! Processing {} combat pairs ***", combat_pairs.len());
                FIRST_COMBAT_LOG = true;
            }
        }

        // Process each combat pair
        for (attacker_ulid, target_ulid, _distance) in combat_pairs {

            // DEFENSIVE: Validate attacker and target are different
            if attacker_ulid == target_ulid {
                self.log_error_once("self_attack", &attacker_ulid,
                    &format!("[COMBAT ERROR] NPC {} is attacking itself! Skipping.", &attacker_ulid[0..8.min(attacker_ulid.len())]));
                continue;
            }

            // DEFENSIVE: Validate both NPCs exist and are alive
            // Check DEAD flag first (most reliable - updated immediately when NPC dies)
            if let Ok(attacker_bytes) = hex_to_bytes(&attacker_ulid) {
                if let Some(state_str) = self.npc_behavioral_state.get(&attacker_bytes).map(|v| v.value().clone()) {
                    if let Ok(state) = state_str.parse::<i32>() {
                        if (state & NPCState::DEAD.bits() as i32) != 0 {
                            // Silently skip - NPC died this tick or earlier
                            continue;
                        }
                    }
                }
            }

            // Also check HP as fallback
            if let Some(attacker_hp) = self.get_stat_value(&attacker_ulid, "hp") {
                if attacker_hp <= 0.0 {
                    // HP is 0 but DEAD flag not set yet - skip silently
                    continue;
                }
            } else {
                self.log_error_once("missing_hp", &attacker_ulid,
                    &format!("[COMBAT ERROR] Attacker {} has no HP stat. Skipping.", &attacker_ulid[0..8.min(attacker_ulid.len())]));
                continue;
            }

            if let Some(target_hp) = self.get_stat_value(&target_ulid, "hp") {
                if target_hp <= 0.0 {
                    // Target already dead, skip silently (common case during combat)
                    continue;
                }
            } else {
                self.log_error_once("missing_hp", &target_ulid,
                    &format!("[COMBAT ERROR] Target {} has no HP stat. Skipping.", &target_ulid[0..8.min(target_ulid.len())]));
                continue;
            }

            // Check cooldown
            if !self.check_attack_cooldown(&attacker_ulid, now_ms) {
                continue; // Still on cooldown
            }

            // Get attacker static state to check if RANGED
            let attacker_static_state = self.get_stat_value(&attacker_ulid, "static_state").unwrap_or(0.0) as i32;
            let is_ranged = (attacker_static_state & NPCStaticState::RANGED.bits() as i32) != 0;
            let is_magic = (attacker_static_state & NPCStaticState::MAGIC.bits() as i32) != 0;

            // Get attacker and target positions
            let (attacker_x, attacker_y) = self.get_npc_position_internal(&attacker_ulid)
                .unwrap_or((0.0, 0.0));
            let (target_x, target_y) = self.get_npc_position_internal(&target_ulid)
                .unwrap_or((0.0, 0.0));

            // Update attacker cooldown
            self.update_cooldown(&attacker_ulid, now_ms);

            // Set ATTACKING state on attacker (Rust manages all states)
            self.add_attacking_state(&attacker_ulid);

            // Generate attack event (for animation)
            events.push(CombatEvent {
                event_type: "attack".to_string(),
                attacker_ulid: attacker_ulid.clone(),
                target_ulid: target_ulid.clone(),
                amount: 0.0,
                attacker_animation: "attack".to_string(),
                target_animation: "".to_string(),
                target_x,
                target_y,
            });

            // RANGED attacks (archers) use projectiles - GDScript handles collision and calls back
            if is_ranged && !is_magic {
                // Generate projectile event for GDScript to spawn arrow
                // GDScript will read attacker position from attacker NPC node
                events.push(CombatEvent {
                    event_type: "projectile".to_string(),
                    attacker_ulid: attacker_ulid.clone(),
                    target_ulid: target_ulid.clone(),
                    amount: 0.0, // Damage will be calculated on hit
                    attacker_animation: "arrow".to_string(), // Projectile type
                    target_animation: format!("{},{}", attacker_y, 300.0), // Encode attacker_y and arrow speed
                    target_x, // Target position
                    target_y,
                });
                // Damage will be applied when GDScript calls projectile_hit()
            } else {
                // MELEE and MAGIC attacks: Apply damage instantly
                let attacker_attack = self.get_stat_value(&attacker_ulid, "attack").unwrap_or(10.0);
                let target_defense = self.get_stat_value(&target_ulid, "defense").unwrap_or(5.0);

                // Calculate damage (heavily reduced formula for much slower, strategic combat)
                // Formula: (attack / 6) - (defense / 8), minimum 1.5 damage
                // This makes fights last much longer and animations more visible
                let damage = ((attacker_attack / 6.0) - (target_defense / 8.0)).max(1.5);

                // Log damage calculation for first few attacks
                static mut DAMAGE_LOG_COUNT: i32 = 0;
                unsafe {
                    if DAMAGE_LOG_COUNT < 10 {
                        godot_print!("[COMBAT] Attacker ATK: {:.1} vs Target DEF: {:.1} = {:.1} damage",
                            attacker_attack, target_defense, damage);
                        DAMAGE_LOG_COUNT += 1;
                    }
                }

                // Apply damage and get new HP
                let target_hp = self.apply_damage(&target_ulid, damage);

                // Handle target state based on HP
                if target_hp <= 0.0 {
                    // Mark target as dead (Rust manages all states)
                    self.mark_dead(&target_ulid);

                    // Generate death event
                    events.push(CombatEvent {
                        event_type: "death".to_string(),
                        attacker_ulid,
                        target_ulid: target_ulid.clone(),
                        amount: damage,
                        attacker_animation: "".to_string(),
                        target_animation: "death".to_string(),
                        target_x,
                        target_y,
                    });
                } else {
                    // Set DAMAGED state on target (Rust manages all states)
                    self.add_damaged_state(&target_ulid);

                    // Set aggro: target should now attack their attacker
                    self.set_aggro_target(&target_ulid, &attacker_ulid);

                    // Generate damage event
                    events.push(CombatEvent {
                        event_type: "damage".to_string(),
                        attacker_ulid,
                        target_ulid: target_ulid.clone(),
                        amount: damage,
                        attacker_animation: "".to_string(),
                        target_animation: "hurt".to_string(),
                        target_x,
                        target_y,
                    });
                }
            }
        }

        // Removed: Too spammy
        // godot_print!("[PHASE 1: COMBAT] Generated {} combat events", events.len());
        events
    }

    /// PHASE 2: MOVEMENT - Handle wandering, calculate directions, update positions
    /// This phase ONLY handles movement and position updates
    /// Returns spawn events for new NPCs
    pub fn tick_movement_phase(&self, delta: f32) -> Vec<CombatEvent> {
        let mut events = Vec::new();
        let now_ms = Self::get_current_time_ms();

        // 0. INITIAL SPAWN: Check if this is the first tick and spawn minimal entities
        let initial_spawn_events = self.check_initial_spawn(now_ms);
        events.extend(initial_spawn_events);

        // Get all active NPCs with positions
        let active_npcs = self.get_active_npcs_with_positions();
        if active_npcs.is_empty() {
            return events;
        }

        // Reduced logging
        // Removed: Too spammy
        // static mut MOVE_LOG_COUNT: u32 = 0;
        // unsafe {
        //     MOVE_LOG_COUNT += 1;
        //     if MOVE_LOG_COUNT % 60 == 1 {
        //         godot_print!("[PHASE 2: MOVEMENT] Processing {} NPCs", active_npcs.len());
        //     }
        // }

        // 1. Handle idle wandering (NPCs that are IDLE and not in combat will get random waypoints)
        self.handle_idle_wandering(&active_npcs);

        // 2. Calculate movement directions for all NPCs (pursue nearest hostile)
        self.calculate_movement_directions(&active_npcs);

        // 3. Apply waypoint movement (move NPCs towards their waypoints)
        self.apply_waypoint_movement(&active_npcs, delta);

        // 4. DISABLED: Check if we need to spawn monsters (Rust manages monster spawn timing)
        // TODO: Re-enable once initial spawn is stable
        // let monster_spawn_events = self.check_spawn_wave(now_ms);
        // events.extend(monster_spawn_events);

        // 5. DISABLED: Check if we need to spawn allies (gradual ramp-up)
        // TODO: Re-enable once initial spawn is stable
        // let ally_spawn_events = self.check_ally_spawn(now_ms);
        // events.extend(ally_spawn_events);

        // Removed: Too spammy
        events
    }

    /// PHASE 3: ANIMATION - Update sprites based on states, clear temporary states
    /// This phase ONLY handles visual updates and state cleanup
    /// No events are returned as animations are updated directly
    pub fn tick_animation_phase(&self) {
        // Get all active NPCs INCLUDING dead ones (for death animation)
        let active_npcs = self.get_active_npcs_for_animation();
        if active_npcs.is_empty() {
            return;
        }

        // DEBUG: Count dead NPCs in animation phase
        let mut dead_count = 0;
        for (ulid_bytes, _, _, _, _, _, _, _) in &active_npcs {
            if let Some(state_str) = self.npc_behavioral_state.get(ulid_bytes).map(|v| v.value().clone()) {
                if let Ok(state) = state_str.parse::<i32>() {
                    if (state & NPCState::DEAD.bits() as i32) != 0 {
                        dead_count += 1;
                        let ulid_hex = bytes_to_hex(ulid_bytes);
                        godot_print!("[ANIM PHASE] Found DEAD NPC: {} (state={})", ulid_hex, state);
                    }
                }
            }
        }
        if dead_count > 0 {
            godot_print!("[ANIM PHASE] Processing {} NPCs, {} are DEAD", active_npcs.len(), dead_count);
        }

        // Update animations based on behavioral state (Rust controls animations)
        self.update_npc_animations(&active_npcs);

        // Clear temporary states (ATTACKING, DAMAGED) after animation duration
        self.clear_expired_animation_states();
    }

    /// Legacy tick_combat_internal - now calls three phases sequentially
    /// This maintains backward compatibility while using the new three-phase system
    pub fn tick_combat_internal(&self, delta: f32) -> Vec<CombatEvent> {
        let mut all_events = Vec::new();

        // Reduced logging
        static mut TICK_LOG_COUNT: u32 = 0;
        unsafe {
            TICK_LOG_COUNT += 1;
            if TICK_LOG_COUNT % 60 == 1 { // Log once per second
                godot_print!("[TICK] === Starting three-phase tick ===");
            }
        }

        // Phase 1: Combat (damage calculations and state changes)
        let combat_events = self.tick_combat_phase();
        all_events.extend(combat_events);

        // Phase 2: Movement (position updates and spawning)
        let movement_events = self.tick_movement_phase(delta);
        all_events.extend(movement_events);

        // Phase 3: Animation (visual updates)
        self.tick_animation_phase();

        // Phase 4: Cleanup (despawn dead NPCs AFTER they've played death animation)
        let now_ms = Self::get_current_time_ms();
        self.cleanup_dead_npcs(now_ms);

        // Reduced logging
        static mut TICK_END_LOG: u32 = 0;
        unsafe {
            TICK_END_LOG += 1;
            if TICK_END_LOG % 60 == 1 { // Log once per second
                godot_print!("[TICK] === Completed three-phase tick with {} total events ===", all_events.len());
            }
        }

        all_events
    }

    /// Handle idle wandering for NPCs that are IDLE and not in COMBAT
    /// Sets random waypoints within world bounds for NPCs to wander around
    fn handle_idle_wandering(&self, npcs: &[([u8; 16], f32, f32, i32, i32, f32, f32, f32)]) {
        use rand::Rng;
        let mut rng = rand::rng();
        let now_ms = Self::get_current_time_ms();

        // Load world bounds
        let min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
        let max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
        let min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
        let max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

        for (ulid_bytes, x, y, static_state, _behavioral_state, _, _, _) in npcs {
            // Skip if scheduled for despawn (check first - most important)
            let ulid_hex = bytes_to_hex(ulid_bytes);
            let despawn_key = format!("despawn_at:{}", ulid_hex);
            if self.storage.contains_key(&despawn_key) {
                // Scheduled for despawn - skip all processing
                continue;
            }

            // Get current behavioral state from ByteMap
            let behavioral_state = if let Some(state_str) = self.npc_behavioral_state.get(ulid_bytes).map(|v| v.value().clone()) {
                state_str.parse::<i32>().unwrap_or(NPCState::IDLE.bits() as i32)
            } else {
                NPCState::IDLE.bits() as i32
            };

            // Skip if DEAD
            let is_dead = (behavioral_state & NPCState::DEAD.bits() as i32) != 0;
            if is_dead {
                continue;
            }

            // Only wander if IDLE and NOT in COMBAT
            let is_idle = (behavioral_state & NPCState::IDLE.bits() as i32) != 0;
            let in_combat = (behavioral_state & NPCState::COMBAT.bits() as i32) != 0;
            let is_passive = (*static_state & NPCStaticState::PASSIVE.bits() as i32) != 0;

            if is_idle && !in_combat && !is_passive {
                // Convert ULID to hex for storage key
                let ulid_hex = bytes_to_hex(ulid_bytes);

                // Check if NPC already has a waypoint
                let has_waypoint = self.npc_waypoints.contains_key(ulid_bytes);

                // Check wander cooldown (don't wander too frequently)
                let cooldown_key = format!("wander_cooldown:{}", ulid_hex);
                let can_wander = if let Some(cooldown_str) = self.storage.get(&cooldown_key) {
                    if let Ok(cooldown_until_ms) = cooldown_str.value().parse::<u64>() {
                        now_ms >= cooldown_until_ms // Can wander if current time is past the cooldown time
                    } else {
                        true
                    }
                } else {
                    true
                };

                if !has_waypoint && can_wander {
                    // Determine faction-specific bounds (allies on left, monsters on right)
                    let is_ally = (*static_state & NPCStaticState::ALLY.bits() as i32) != 0;
                    let is_monster = (*static_state & NPCStaticState::MONSTER.bits() as i32) != 0;

                    let (wander_min_x, wander_max_x) = if is_ally {
                        // Allies wander on left side (friendly area)
                        (min_x, min_x + (max_x - min_x) * 0.4)
                    } else if is_monster {
                        // Monsters wander on right side
                        (min_x + (max_x - min_x) * 0.6, max_x)
                    } else {
                        // Default to full bounds
                        (min_x, max_x)
                    };

                    // Generate random waypoint within faction bounds
                    let target_x = rng.random_range(wander_min_x..wander_max_x);
                    let target_y = rng.random_range(min_y..max_y);

                    // Store waypoint in ByteMap
                    self.npc_waypoints.insert(*ulid_bytes,  format!("{},{}", target_x, target_y));

                    // Update wander cooldown - set to 3 seconds in the future
                    self.storage.insert(
                        cooldown_key,
                        (now_ms + 3000.to_string())
                    );

                    // Set state to WALKING (remove IDLE, add WALKING, keep other flags like COMBAT if present)
                    let new_state = (behavioral_state & !(NPCState::IDLE.bits() as i32 | NPCState::ATTACKING.bits() as i32)) | NPCState::WALKING.bits() as i32;
                    godot_print!("[RUST WANDER] ULID {} - Setting waypoint: old_state={}, new_state={}", ulid_hex, behavioral_state, new_state);
                    self.set_behavioral_state(ulid_bytes, new_state, "handle_idle_wandering");

                    // Verify the write worked
                    if let Some(verify_str) = self.npc_behavioral_state.get(ulid_bytes).map(|v| v.value().clone()) {
                        let verify_state = verify_str.parse::<i32>().unwrap_or(0);
                        godot_print!("[RUST WANDER VERIFY] ULID {} - verified state after write: {}", ulid_hex, verify_state);
                    }
                }
            }
        }
    }

    /// Calculate movement directions for all NPCs (pursue nearest hostile)
    /// Stores movement direction in HolyMap as "move_dir:ulid" -> "x,y"
    fn calculate_movement_directions(&self, npcs: &[([u8; 16], f32, f32, i32, i32, f32, f32, f32)]) {
        // static mut DIR_LOG_COUNT: u32 = 0;
        // unsafe {
        //     DIR_LOG_COUNT += 1;
        //     if DIR_LOG_COUNT == 1 {
        //         godot_print!("[RUST CALC] calculate_movement_directions called with {} NPCs", npcs.len());
        //     }
        // }

        for (ulid_bytes_a, x_a, y_a, static_state_a, behavioral_state_a, _, _, _) in npcs {
            // Skip if dead
            if (*behavioral_state_a & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            // Skip if PASSIVE
            if (*static_state_a & NPCStaticState::PASSIVE.bits() as i32) != 0 {
                continue;
            }

            // Convert ULID bytes to hex for storage keys (only once)
            let ulid_hex_a = bytes_to_hex(ulid_bytes_a);

            let mut nearest_hostile: Option<(f32, f32, f32)> = None; // (x, y, distance)
            let mut nearest_distance = f32::MAX;

            // AGGRO SYSTEM: Check if this NPC has an aggro target (from being attacked)
            if let Some(aggro_target_hex) = self.npc_aggro_targets.get(ulid_bytes_a).map(|v| v.value().clone()) {
                // Find the aggro target in the NPC list
                for (ulid_bytes_b, x_b, y_b, static_state_b, behavioral_state_b, _, _, _) in npcs {
                    let ulid_hex_b = bytes_to_hex(ulid_bytes_b);

                    // Check if this is our aggro target
                    if ulid_hex_b == aggro_target_hex {
                        // Verify target is still alive
                        if (*behavioral_state_b & NPCState::DEAD.bits() as i32) == 0 {
                            let distance = Self::distance(*x_a, *y_a, *x_b, *y_b);
                            nearest_hostile = Some((*x_b, *y_b, distance));
                            nearest_distance = distance;
                            break; // Prioritize aggro target
                        } else {
                            // Aggro target is dead, clear it
                            self.npc_aggro_targets.remove(ulid_bytes_a).map(|(_, v)| v);
                        }
                    }
                }
            }

            // If no aggro target (or aggro target is dead), find nearest hostile NPC
            if nearest_hostile.is_none() {
                for (ulid_bytes_b, x_b, y_b, static_state_b, behavioral_state_b, _, _, _) in npcs {
                    if ulid_bytes_a == ulid_bytes_b {
                        continue; // Skip self
                    }

                    // Skip if dead
                    if (*behavioral_state_b & NPCState::DEAD.bits() as i32) != 0 {
                        continue;
                    }

                    // Check if hostile
                    if !Self::are_factions_hostile(*static_state_a, *static_state_b) {
                        continue;
                    }

                    let distance = Self::distance(*x_a, *y_a, *x_b, *y_b);
                    if distance < nearest_distance {
                        nearest_distance = distance;
                        nearest_hostile = Some((*x_b, *y_b, distance));
                    }
                }
            }

            // Calculate waypoint (target position to move toward)
            // static mut HOSTILE_LOG_COUNT: u32 = 0;
            // unsafe {
            //     HOSTILE_LOG_COUNT += 1;
            //     if HOSTILE_LOG_COUNT < 5 {
            //         if nearest_hostile.is_some() {
            //             godot_print!("[RUST HOSTILE] Found hostile target");
            //         } else {
            //             godot_print!("[RUST HOSTILE] No hostile target found");
            //         }
            //     }
            // }

            if let Some((target_x, target_y, distance)) = nearest_hostile {
                // COMBAT ENGAGEMENT RANGE: Only enter combat if enemy is within 400px
                // This prevents NPCs from permanently being in combat state when enemies are far away
                const COMBAT_DETECTION_RANGE: f32 = 400.0;

                if distance > COMBAT_DETECTION_RANGE {
                    // Enemy too far - clear combat state and let idle wandering take over
                    if let Some(state_str) = self.npc_behavioral_state.get(ulid_bytes_a).map(|v| v.value().clone()) {
                        if let Ok(current_state) = state_str.parse::<i32>() {
                            if (current_state & NPCState::COMBAT.bits() as i32) != 0 {
                                // Remove COMBAT flag
                                let new_state = current_state & !(NPCState::COMBAT.bits() as i32);
                                self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                            }
                        }
                    }
                    continue; // Skip movement calculation for distant enemies
                }

                // Get attack range for this NPC
                let attack_range = Self::get_attack_range(*static_state_a);

                // Check if this is a RANGED unit (archer)
                let is_ranged = (*static_state_a & NPCStaticState::RANGED.bits() as i32) != 0;

                // RANGED units (archers) use kiting behavior
                if is_ranged {
                    let min_safe_distance = 100.0; // Archers want to keep at least 100px from enemies

                    if distance < min_safe_distance {
                        // TOO CLOSE - Retreat away from enemy (kiting)
                        // Calculate retreat position: move away from target
                        let dir_x = *x_a - target_x;
                        let dir_y = *y_a - target_y;
                        let dir_len = (dir_x * dir_x + dir_y * dir_y).sqrt();

                        if dir_len > 0.01 {
                            // Normalize and scale to retreat distance
                            let retreat_distance = 150.0; // Retreat 150 pixels away
                            let retreat_x = *x_a + (dir_x / dir_len) * retreat_distance;
                            let retreat_y = *y_a + (dir_y / dir_len) * retreat_distance;

                            // Clamp waypoint to world bounds (prevent NPCs from going off-screen)
                            // Read bounds atomically (can be updated by GDScript from BackgroundManager)
                            let min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
                            let max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
                            let min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
                            let max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

                            let clamped_x = retreat_x.clamp(min_x, max_x);
                            let clamped_y = retreat_y.clamp(min_y, max_y);

                            // Store retreat waypoint (clamped)
                            self.npc_waypoints.insert(*ulid_bytes_a,  format!("{},{}", clamped_x, clamped_y));

                            // Update behavioral state to COMBAT only (remove IDLE)
                            // WALKING will be set in apply_waypoint_movement when actually moving
                            let current_state = *behavioral_state_a;
                            let new_state = (current_state & !(NPCState::IDLE.bits() as i32))
                                | NPCState::COMBAT.bits() as i32;

                            self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                        }
                    } else if distance > attack_range {
                        // TOO FAR - Move toward target to get in range
                        // Clamp waypoint to world bounds
                        let min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
                        let max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
                        let min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
                        let max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

                        let clamped_x = target_x.clamp(min_x, max_x);
                        let clamped_y = target_y.clamp(min_y, max_y);

                        self.npc_waypoints.insert(*ulid_bytes_a,  format!("{},{}", clamped_x, clamped_y));

                        // Update behavioral state to COMBAT only (remove IDLE)
                        // WALKING will be set in apply_waypoint_movement when actually moving
                        let current_state = *behavioral_state_a;
                        let new_state = (current_state & !(NPCState::IDLE.bits() as i32))
                            | NPCState::COMBAT.bits() as i32;
                        self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                    } else {
                        // OPTIMAL RANGE (100-200px) - Stop and shoot
                        self.npc_waypoints.remove(ulid_bytes_a).map(|(_, v)| v);

                        // Update behavioral state to COMBAT only (remove WALKING, remove IDLE)
                        let current_state = *behavioral_state_a;
                        let new_state = (current_state & !(NPCState::IDLE.bits() as i32) & !(NPCState::WALKING.bits() as i32))
                            | NPCState::COMBAT.bits() as i32;
                        self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                    }
                } else {
                    // MELEE/MAGIC units: Simple pursue behavior (original logic)
                    if distance > attack_range {
                        // Move toward target (clamp to world bounds)
                        let min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
                        let max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
                        let min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
                        let max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

                        let clamped_x = target_x.clamp(min_x, max_x);
                        let clamped_y = target_y.clamp(min_y, max_y);

                        self.npc_waypoints.insert(*ulid_bytes_a,  format!("{},{}", clamped_x, clamped_y));

                        // Update behavioral state to COMBAT only (remove IDLE)
                        // WALKING will be set in apply_waypoint_movement when actually moving
                        let current_state = *behavioral_state_a;
                        let new_state = (current_state & !(NPCState::IDLE.bits() as i32))
                            | NPCState::COMBAT.bits() as i32;
                        self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                    } else {
                        // In range - stop moving
                        self.npc_waypoints.remove(ulid_bytes_a).map(|(_, v)| v);

                        // Update behavioral state: IDLE | COMBAT (remove WALKING)
                        let current_state = *behavioral_state_a;
                        let had_walking = (current_state & NPCState::WALKING.bits() as i32) != 0;
                        let new_state = (current_state & !(NPCState::WALKING.bits() as i32))
                            | NPCState::IDLE.bits() as i32
                            | NPCState::COMBAT.bits() as i32;

                        if had_walking {
                            static mut MELEE_IN_RANGE_LOG: u32 = 0;
                            unsafe {
                                MELEE_IN_RANGE_LOG += 1;
                                if MELEE_IN_RANGE_LOG <= 10 {
                                    godot_print!("[COMBAT MOVEMENT] ULID {} - Melee in attack range, removing WALKING: {} -> {}",
                                        ulid_hex_a, current_state, new_state);
                                }
                            }
                        }

                        self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                    }
                }
            } else {
                // No enemies - only clear COMBAT state, don't touch idle wandering waypoints!
                // Idle wandering waypoints are managed by handle_idle_wandering()
                // We should only clear combat-related state here
                let current_state = *behavioral_state_a;

                // Only modify state if NPC was in COMBAT
                if (current_state & NPCState::COMBAT.bits() as i32) != 0 {
                    // Remove COMBAT flag, but keep WALKING/IDLE as-is (for idle wandering)
                    let new_state = current_state & !(NPCState::COMBAT.bits() as i32);
                    self.npc_behavioral_state.insert(*ulid_bytes_a,  new_state.to_string());
                }
                // If not in combat, leave state alone (might be idle wandering with WALKING state)
            }
        }
    }

    /// Apply waypoint movement - move NPCs towards their waypoints
    /// Called every combat tick with delta time
    /// Rust directly updates both the position data AND the Node2D visual position
    fn apply_waypoint_movement(&self, npcs: &[([u8; 16], f32, f32, i32, i32, f32, f32, f32)], delta_time: f32) {
        const MOVEMENT_SPEED: f32 = 80.0; // pixels per second (increased for smoother visible movement)
        const LERP_WEIGHT: f32 = 0.15; // Smoothing factor (0.0 = no movement, 1.0 = instant)

        static mut MOVEMENT_LOG_COUNT: u32 = 0;
        unsafe {
            MOVEMENT_LOG_COUNT += 1;
            if MOVEMENT_LOG_COUNT <= 5 {
                // Removed spam log
            }
        }

        for (ulid_bytes, _x, _y, _static_state, _behavioral_state, _, _, _) in npcs {
            // Convert bytes to hex for storage key lookup
            let ulid_hex = bytes_to_hex(ulid_bytes);

            // Get current position from npc_positions ByteMap (stored as "x,y")
            let pos_str = self.npc_positions.get(&ulid_bytes).map(|v| v.value().clone()).unwrap_or_default();
            let coords: Vec<&str> = pos_str.split(',').collect();
            if coords.len() != 2 {
                // static mut POS_FAIL_COUNT: u32 = 0;
                // unsafe {
                //     POS_FAIL_COUNT += 1;
                //     if POS_FAIL_COUNT < 3 {
                //         godot_print!("[RUST MOVEMENT] Invalid position for NPC: '{}'", pos_str);
                //     }
                // }
                continue;
            }
            let current_x: f32 = coords[0].parse().unwrap_or(0.0);
            let current_y: f32 = coords[1].parse().unwrap_or(0.0);

            // Get waypoint from ByteMap (ULID bytes -> "x,y")
            if let Some(waypoint_value) = self.npc_waypoints.get(&ulid_bytes).map(|v| v.value().clone()) {
                // Removed spam logging
                let waypoint_coords: Vec<&str> = waypoint_value.split(',').collect();
                if waypoint_coords.len() != 2 {
                    continue;
                }
                let target_x: f32 = waypoint_coords[0].parse().unwrap_or(0.0);
                let target_y: f32 = waypoint_coords[1].parse().unwrap_or(0.0);

                // Calculate direction to waypoint
                let dx = target_x - current_x;
                let dy = target_y - current_y;
                let distance = (dx * dx + dy * dy).sqrt();

                if distance > 1.0 {
                    // Calculate target position with smooth movement
                    let move_distance = MOVEMENT_SPEED * delta_time;
                    let move_ratio = (move_distance / distance).min(1.0);

                    let target_x = current_x + dx * move_ratio;
                    let target_y = current_y + dy * move_ratio;

                    // Store normalized movement direction for sprite flipping
                    let dir_x = dx / distance;
                    let dir_y = dy / distance;
                    self.npc_move_directions.insert(*&ulid_bytes,  format!("{},{}", dir_x, dir_y));

                    // Update position in npc_positions ByteMap (data store)
                    self.npc_positions.insert(*&ulid_bytes,  format!("{},{}", target_x, target_y));

                    // Set WALKING state since NPC is actually moving
                    // CRITICAL: Remove IDLE when adding WALKING (mutually exclusive)
                    if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                        if let Ok(current_state) = state_str.parse::<i32>() {
                            let has_combat = (current_state & NPCState::COMBAT.bits() as i32) != 0;
                            let has_walking = (current_state & NPCState::WALKING.bits() as i32) != 0;

                            // Add WALKING flag and remove IDLE (mutually exclusive)
                            if !has_walking {
                                let new_state = (current_state & !(NPCState::IDLE.bits() as i32)) | NPCState::WALKING.bits() as i32;
                                self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());

                                // Removed spam logging
                            }
                        }
                    }

                    // Update Node2D visual position with lerp for smooth interpolation
                    for pool_entry in self.active_npc_pool.iter() {
                        let npc = pool_entry.value();
                        if &npc.ulid == ulid_bytes {
                            // Clone the Gd handle (creates new reference to same node)
                            let mut node = npc.node.clone();
                            let current_visual_pos = node.get_position();

                            // Lerp from current visual position to target position for smooth movement
                            let lerped_x = current_visual_pos.x + (target_x - current_visual_pos.x) * LERP_WEIGHT;
                            let lerped_y = current_visual_pos.y + (target_y - current_visual_pos.y) * LERP_WEIGHT;

                            node.set_position(Vector2::new(lerped_x, lerped_y));
                            break;
                        }
                    }
                    // Removed spam logging
                } else {
                    // Reached waypoint! Clear it and movement direction
                    self.npc_waypoints.remove(&ulid_bytes).map(|(_, v)| v);
                    self.npc_move_directions.remove(&ulid_bytes).map(|(_, v)| v);

                    // Set state to IDLE (remove WALKING and ATTACKING flags, add IDLE, keep other flags like COMBAT)
                    if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                        if let Ok(current_state) = state_str.parse::<i32>() {
                            // Remove WALKING and ATTACKING, add IDLE (keep COMBAT flag if present)
                            let new_state = (current_state & !(NPCState::WALKING.bits() as i32 | NPCState::ATTACKING.bits() as i32)) | NPCState::IDLE.bits() as i32;
                            self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());
                        }
                    }
                }
            }
        }
    }

    /// Update NPC animations based on behavioral state (Rust controls animations)
    /// Called every frame during combat tick
    /// Animation names match SpriteFrames: "idle", "walking", "attacking", "hurt", "dead"
    fn update_npc_animations(&self, npcs: &[([u8; 16], f32, f32, i32, i32, f32, f32, f32)]) {
        for (ulid_bytes, _, _, _static_state, _old_behavioral_state, _, _, _) in npcs {
            // Fetch the CURRENT behavioral state (not the stale one from npcs array)
            // This is important because apply_waypoint_movement() may have updated it
            let behavioral_state = if let Some(state_str) = self.npc_behavioral_state.get(ulid_bytes).map(|v| v.value().clone()) {
                let state = state_str.parse::<i32>().unwrap_or(NPCState::IDLE.bits() as i32);

                // Removed spam logging
                state
            } else {
                NPCState::IDLE.bits() as i32
            };

            // Determine animation based on behavioral state (priority order)
            let animation_name = if (behavioral_state & NPCState::DEAD.bits() as i32) != 0 {
                "dead"
            } else if (behavioral_state & NPCState::DAMAGED.bits() as i32) != 0 {
                "hurt"
            } else if (behavioral_state & NPCState::ATTACKING.bits() as i32) != 0 {
                "attacking"
            } else if (behavioral_state & NPCState::WALKING.bits() as i32) != 0 {
                "walking"
            } else {
                "idle"
            };

            // Log death animation (always log, not just first few times)
            if animation_name == "dead" {
                let ulid_hex = bytes_to_hex(ulid_bytes);
                godot_print!("[DEATH ANIM] Playing death animation for ULID {} (state={})", ulid_hex, behavioral_state);
            }

            // Removed spam logging

            // Find the NPC in the active pool and update its animation
            for pool_entry in self.active_npc_pool.iter() {
                let npc = pool_entry.value();
                if &npc.ulid == ulid_bytes {
                    // Update animation and sprite direction
                    if let Some(ref sprite) = npc.animated_sprite {
                        let mut sprite_mut = sprite.clone();
                        let new_anim = StringName::from(animation_name);

                        // Log when setting death animation
                        if animation_name == "dead" {
                            let ulid_hex = bytes_to_hex(ulid_bytes);
                            let current_anim = sprite_mut.get_animation();
                            godot_print!("[DEATH ANIM SET] ULID {} - Setting animation from '{}' to 'dead', playing={}",
                                ulid_hex, current_anim, sprite_mut.is_playing());
                        }

                        // Check if animation changed
                        let current_anim = sprite_mut.get_animation();
                        let animation_changed = current_anim != new_anim;

                        // Set animation (Godot is smart about redundant calls)
                        sprite_mut.set_animation(&new_anim);

                        // Only call play() if:
                        // 1. Animation changed (including to "dead")
                        // 2. Animation is not currently playing (for non-death animations)
                        // IMPORTANT: Never replay death animation once it's already playing/finished
                        if animation_name == "dead" {
                            // Only play death animation if it just changed from something else
                            if animation_changed {
                                sprite_mut.play();
                            }
                            // Otherwise, let it finish naturally (loop=false handles staying on last frame)
                        } else if animation_changed {
                            // Non-death animation changed - play it
                            sprite_mut.play();
                        } else if !sprite_mut.is_playing() {
                            // Animation didn't change but stopped playing (non-death only)
                            sprite_mut.play();
                        }
                        // For death animation: only play once when it first changes to "dead"
                        // After that, let it finish and stay on last frame (loop=false in SpriteFrames)

                        // SPRITE FLIPPING: Determine which way the sprite should face
                        // Skip flipping for dead NPCs (death animation should stay as-is)
                        let is_dead = (behavioral_state & NPCState::DEAD.bits() as i32) != 0;

                        let should_flip = if is_dead {
                            // Keep current flip state for dead NPCs
                            sprite_mut.is_flipped_h()
                        } else if let Some(move_dir) = self.npc_move_directions.get(ulid_bytes).map(|v| v.value().clone()) {
                            // Has movement direction - parse it
                            let parts: Vec<&str> = move_dir.split(',').collect();
                            if parts.len() == 2 {
                                if let Ok(dir_x) = parts[0].parse::<f32>() {
                                    dir_x < 0.0 // Flip if moving left (negative x)
                                } else {
                                    false
                                }
                            } else {
                                false
                            }
                        } else if let Some(waypoint) = self.npc_waypoints.get(ulid_bytes).map(|v| v.value().clone()) {
                            // Has waypoint - compare with current position
                            let current_pos = self.npc_positions.get(ulid_bytes).map(|v| v.value().clone());
                            if let Some(current_pos_str) = current_pos {
                                let current_parts: Vec<&str> = current_pos_str.split(',').collect();
                                let waypoint_parts: Vec<&str> = waypoint.split(',').collect();
                                if current_parts.len() == 2 && waypoint_parts.len() == 2 {
                                    if let (Ok(curr_x), Ok(target_x)) = (
                                        current_parts[0].parse::<f32>(),
                                        waypoint_parts[0].parse::<f32>()
                                    ) {
                                        target_x < curr_x // Flip if target is to the left
                                    } else {
                                        false
                                    }
                                } else {
                                    false
                                }
                            } else {
                                false
                            }
                        } else {
                            // Default: face right (don't flip) for allies, face left (flip) for monsters
                            let static_state = if let Some(stats_json) = self.npc_combat_stats.get(ulid_bytes).map(|v| v.value().clone()) {
                                if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                                    combat_stats.static_state
                                } else {
                                    0
                                }
                            } else {
                                0
                            };

                            let is_monster = (static_state & NPCStaticState::MONSTER.bits() as i32) != 0;
                            is_monster // Monsters face left by default (flip), allies face right
                        };

                        // Apply horizontal flip
                        sprite_mut.set_flip_h(should_flip);
                    }

                    // Sync behavioral state to GDScript property (for chat UI and other systems)
                    let mut node = npc.node.clone();
                    let state_variant = Variant::from(behavioral_state);
                    let _ = node.set("current_state", &state_variant);

                    break;
                }
            }
        }
    }

    /// Get all active NPCs with their positions
    /// Returns: Vec<(ulid_bytes, x, y, static_state, behavioral_state, hp, attack, defense)>
    /// Get active NPCs for animation phase (includes DEAD NPCs for death animation)
    fn get_active_npcs_for_animation(&self) -> Vec<([u8; 16], f32, f32, i32, i32, f32, f32, f32)> {
        let mut npcs = Vec::new();

        // Iterate over active NPC pool (not active_combat_npcs, which filters out dead)
        for entry in self.active_npc_pool.iter() {
            let npc = entry.value();
            let ulid_bytes = npc.ulid;

            // Get position using ByteMap
            let pos = self.npc_positions.get(&ulid_bytes).map(|v| v.value().clone())
                .and_then(|pos_str| {
                    let parts: Vec<&str> = pos_str.split(',').collect();
                    if parts.len() == 2 {
                        if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
                            return Some((x, y));
                        }
                    }
                    None
                });

            if pos.is_none() {
                continue; // Skip NPCs without position
            }
            let (x, y) = pos.unwrap();

            // Get behavioral state from ByteMap
            let behavioral_state = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone())
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0);

            // Get combat stats from ByteMap
            let (hp, attack, defense, static_state) = if let Some(stats_json) = self.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
                if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                    (combat_stats.hp, combat_stats.attack, combat_stats.defense, combat_stats.static_state)
                } else {
                    continue;
                }
            } else {
                continue;
            };

            let max_hp = hp; // For animation phase, we don't need accurate max_hp
            npcs.push((ulid_bytes, x, y, static_state, behavioral_state, hp, max_hp, attack));
        }

        npcs
    }

    /// Get active NPCs for combat/movement (excludes DEAD NPCs)
    fn get_active_npcs_with_positions(&self) -> Vec<([u8; 16], f32, f32, i32, i32, f32, f32, f32)> {
        let mut npcs = Vec::new();

        // Iterate over active combat NPCs DashMap
        for entry in self.active_combat_npcs.iter() {
            let ulid_hex = entry.key();

            // Convert hex to bytes (only once per NPC)
            let ulid_bytes = match hex_to_bytes(ulid_hex) {
                Ok(bytes) => bytes,
                Err(_) => {
                    self.log_error_once("invalid_ulid", ulid_hex,
                        &format!("[COMBAT ERROR] Invalid ULID hex: {}", &ulid_hex[0..8.min(ulid_hex.len())]));
                    continue;
                }
            };

            // Get position using ByteMap (takes bytes directly)
            let pos = self.npc_positions.get(&ulid_bytes).map(|v| v.value().clone())
                .and_then(|pos_str| {
                    let parts: Vec<&str> = pos_str.split(',').collect();
                    if parts.len() == 2 {
                        if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
                            return Some((x, y));
                        }
                    }
                    None
                });

            if pos.is_none() {
                self.log_error_once("missing_position", ulid_hex,
                    &format!("[COMBAT ERROR] NPC {} has no position - skipping from combat",
                        &ulid_hex[0..8.min(ulid_hex.len())]));
                continue;
            }
            let (x, y) = pos.unwrap();

            // Get behavioral state from ByteMap
            let behavioral_state = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone())
                .and_then(|s| s.parse::<i32>().ok())
                .unwrap_or(0);

            // Skip if dead
            if (behavioral_state & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            // Get combat stats from ByteMap
            let (hp, attack, defense, static_state) = if let Some(stats_json) = self.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
                if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                    (combat_stats.hp, combat_stats.attack, combat_stats.defense, combat_stats.static_state)
                } else {
                    (100.0, 10.0, 5.0, 0)
                }
            } else {
                (100.0, 10.0, 5.0, 0)
            };

            npcs.push((ulid_bytes, x, y, static_state, behavioral_state, hp, attack, defense));
        }

        npcs
    }

    /// Find combat pairs based on proximity and faction hostility
    /// Returns: Vec<(attacker_ulid_hex, target_ulid_hex, distance)>
    fn find_combat_pairs(&self, npcs: &[([u8; 16], f32, f32, i32, i32, f32, f32, f32)]) -> Vec<(String, String, f32)> {
        let mut pairs = Vec::new();

        // Debug: Log first close encounter
        static mut FIRST_CLOSE_LOG: bool = false;

        for i in 0..npcs.len() {
            let (ulid_a, x_a, y_a, static_state_a, behavioral_state_a, _, _, _) = &npcs[i];

            // Skip if dead (check behavioral state)
            if (*behavioral_state_a & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            for j in (i + 1)..npcs.len() {
                let (ulid_b, x_b, y_b, static_state_b, behavioral_state_b, _, _, _) = &npcs[j];

                // Skip if dead (check behavioral state)
                if (*behavioral_state_b & NPCState::DEAD.bits() as i32) != 0 {
                    continue;
                }

                // Check if hostile factions (use static state)
                if !Self::are_factions_hostile(*static_state_a, *static_state_b) {
                    continue;
                }

                // Calculate distance
                let distance = Self::distance(*x_a, *y_a, *x_b, *y_b);

                // Get attack range based on combat type (use static state)
                let range_a = Self::get_attack_range(*static_state_a);
                let range_b = Self::get_attack_range(*static_state_b);

                // Debug: Log when hostile NPCs are close but not in range yet
                unsafe {
                    if !FIRST_CLOSE_LOG && distance < 300.0 {
                        let ulid_hex_a = bytes_to_hex(ulid_a);
                        let ulid_hex_b = bytes_to_hex(ulid_b);
                        godot_print!("[COMBAT PAIRS] Found hostile NPCs: {} at ({:.1},{:.1}) vs {} at ({:.1},{:.1}), distance: {:.1}, range_a: {}, range_b: {}",
                            ulid_hex_a, x_a, y_a, ulid_hex_b, x_b, y_b, distance, range_a, range_b);
                        FIRST_CLOSE_LOG = true;
                    }
                }

                // If in range, add to pairs (both directions possible)
                // Convert to hex strings only for the final result
                if distance <= range_a {
                    pairs.push((bytes_to_hex(ulid_a), bytes_to_hex(ulid_b), distance));
                }
                if distance <= range_b {
                    pairs.push((bytes_to_hex(ulid_b), bytes_to_hex(ulid_a), distance));
                }
            }
        }

        pairs
    }

    /// Check if two faction states are hostile
    fn are_factions_hostile(static_state1: i32, static_state2: i32) -> bool {
        let ally1 = (static_state1 & NPCStaticState::ALLY.bits() as i32) != 0;
        let monster1 = (static_state1 & NPCStaticState::MONSTER.bits() as i32) != 0;
        let passive1 = (static_state1 & NPCStaticState::PASSIVE.bits() as i32) != 0;

        let ally2 = (static_state2 & NPCStaticState::ALLY.bits() as i32) != 0;
        let monster2 = (static_state2 & NPCStaticState::MONSTER.bits() as i32) != 0;
        let passive2 = (static_state2 & NPCStaticState::PASSIVE.bits() as i32) != 0;

        // Passive never hostile
        if passive1 || passive2 {
            return false;
        }

        // Ally vs Monster = hostile
        (ally1 && monster2) || (monster1 && ally2)
    }

    /// Get attack range based on combat type (from static_state)
    fn get_attack_range(static_state: i32) -> f32 {
        if (static_state & NPCStaticState::MELEE.bits() as i32) != 0 {
            50.0 // Melee range
        } else if (static_state & NPCStaticState::RANGED.bits() as i32) != 0 {
            200.0 // Ranged range
        } else if (static_state & NPCStaticState::MAGIC.bits() as i32) != 0 {
            150.0 // Magic range
        } else {
            50.0 // Default
        }
    }

    /// Helper to get stat value from HolyMap
    fn get_stat_value(&self, ulid: &str, stat_name: &str) -> Option<f32> {
        // Convert hex string to bytes
        let ulid_bytes = hex_to_bytes(ulid).ok()?;

        // For combat stats, read from the struct
        match stat_name {
            "hp" | "max_hp" | "attack" | "defense" | "static_state" => {
                let stats_json = self.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone())?;
                let combat_stats = serde_json::from_str::<NPCCombatStats>(&stats_json).ok()?;
                match stat_name {
                    "hp" => Some(combat_stats.hp),
                    "max_hp" => Some(combat_stats.max_hp),
                    "attack" => Some(combat_stats.attack),
                    "defense" => Some(combat_stats.defense),
                    "static_state" => Some(combat_stats.static_state as f32),
                    _ => None,
                }
            },
            // For other stats, use ByteMap lookup
            _ => {
                let value_str = match stat_name {
                    "behavioral_state" => self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone())?,
                    "cooldown" => self.npc_cooldown.get(&ulid_bytes).map(|v| v.value().clone())?,
                    _ => return None,
                };
                value_str.parse::<f32>().ok()
            }
        }
    }

    /// Calculate distance between two points
    fn distance(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
        let dx = x2 - x1;
        let dy = y2 - y1;
        (dx * dx + dy * dy).sqrt()
    }

    /// Check if attacker can attack (cooldown expired)
    fn check_attack_cooldown(&self, ulid: &str, now_ms: u64) -> bool {
        if let Some(last_attack_ms) = self.get_stat_value(ulid, "cooldown") {
            let cooldown_duration_ms = 3500; // 1 attack per 3.5 seconds (much slower, more tactical combat)
            return now_ms >= (last_attack_ms as u64) + cooldown_duration_ms;
        }
        true // No cooldown record = can attack
    }

    /// Update attack cooldown
    fn update_cooldown(&self, ulid: &str, now_ms: u64) {
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            self.npc_cooldown.insert(*&ulid_bytes,  now_ms.to_string());
        }
    }

    /// Apply damage to target, return new HP
    fn apply_damage(&self, target_ulid: &str, damage: f32) -> f32 {
        // Convert hex string to bytes
        if let Ok(ulid_bytes) = hex_to_bytes(target_ulid) {
            // Get current combat stats
            if let Some(stats_json) = self.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
                if let Ok(mut combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                    // Apply damage
                    combat_stats.hp = (combat_stats.hp - damage).max(0.0);

                    // Store updated stats
                    if let Ok(updated_json) = serde_json::to_string(&combat_stats) {
                        self.npc_combat_stats.insert(*&ulid_bytes,  updated_json);
                    }

                    return combat_stats.hp;
                }
            }
        }

        // Fallback if ULID not found
        0.0
    }

    /// Cleanup dead NPCs that have finished their death animation
    fn cleanup_dead_npcs(&self, now_ms: u64) {
        // Collect ULIDs of NPCs to despawn
        let mut to_despawn = Vec::new();

        // Check all active NPCs for scheduled despawn
        for pool_entry in self.active_npc_pool.iter() {
            let npc = pool_entry.value();
            let ulid_hex = bytes_to_hex(&npc.ulid);
            let despawn_key = format!("despawn_at:{}", ulid_hex);

            if let Some(despawn_time_str) = self.storage.get(&despawn_key) {
                if let Ok(despawn_time) = despawn_time_str.value().parse::<u64>() {
                    if now_ms >= despawn_time {
                        to_despawn.push(npc.ulid);
                    }
                }
            }
        }

        // Despawn scheduled NPCs
        for ulid_bytes in to_despawn {
            godot_print!("[RUST CLEANUP] Despawning dead NPC: {:?}", &ulid_bytes[..8]);
            self.rust_despawn_npc(&ulid_bytes);
        }
    }

    /// Mark NPC as dead and remove from active combat
    fn mark_dead(&self, ulid: &str) {
        // Convert hex to bytes for ByteMap storage
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            // Set behavioral state to DEAD only (clear all other flags)
            let dead_state = NPCState::DEAD.bits() as i32;
            self.npc_behavioral_state.insert(*&ulid_bytes,  dead_state.to_string());

            godot_print!("[DEATH] Marked NPC {} as DEAD (state={})", ulid, dead_state);

            // IMPORTANT: Remove from active combat immediately
            // This prevents dead NPCs from being included in combat processing next tick
            self.active_combat_npcs.remove(ulid);

            // Schedule despawn after death animation (2 seconds)
            let now_ms = Self::get_current_time_ms();
            let despawn_time = now_ms + 2000; // 2 seconds for death animation
            self.storage.insert(
                format!("despawn_at:{}", ulid),
                despawn_time.to_string()
            );
        }
    }

    /// Add ATTACKING state flag (set during attack)
    fn add_attacking_state(&self, ulid: &str) {
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            let current = if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                state_str.parse::<i32>().unwrap_or(0)
            } else {
                0
            };
            let new_state = current | NPCState::ATTACKING.bits() as i32;
            self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());

            // Record timestamp for auto-clearing (format: "attacking:timestamp,damaged:timestamp")
            let now_ms = Self::get_current_time_ms();
            self.npc_state_timestamps.insert(*&ulid_bytes,  format!("attacking:{}", now_ms));

            godot_print!("[ATTACK STATE] NPC {} - Setting ATTACKING flag (old_state={}, new_state={})",
                &ulid[0..8.min(ulid.len())], current, new_state);
        }
    }

    /// Add DAMAGED state flag (set when taking damage)
    fn add_damaged_state(&self, ulid: &str) {
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            let current = if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                state_str.parse::<i32>().unwrap_or(0)
            } else {
                0
            };
            let new_state = current | NPCState::DAMAGED.bits() as i32;
            self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());

            // Record timestamp for auto-clearing
            let now_ms = Self::get_current_time_ms();
            self.npc_state_timestamps.insert(*&ulid_bytes,  format!("damaged:{}", now_ms));

            godot_print!("[DAMAGED STATE] NPC {} - Setting DAMAGED flag (old_state={}, new_state={})",
                &ulid[0..8.min(ulid.len())], current, new_state);
        }
    }

    /// Remove ATTACKING state flag (called by GDScript after attack animation finishes)
    pub fn remove_attacking_state(&self, ulid: &str) {
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            let current = if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                state_str.parse::<i32>().unwrap_or(0)
            } else {
                0
            };
            let new_state = current & !(NPCState::ATTACKING.bits() as i32);
            self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());
        }
    }

    /// Remove DAMAGED state flag (called by GDScript after hurt animation finishes)
    pub fn remove_damaged_state(&self, ulid: &str) {
        if let Ok(ulid_bytes) = hex_to_bytes(ulid) {
            let current = if let Some(state_str) = self.npc_behavioral_state.get(&ulid_bytes).map(|v| v.value().clone()) {
                state_str.parse::<i32>().unwrap_or(0)
            } else {
                0
            };
            let new_state = current & !(NPCState::DAMAGED.bits() as i32);
            self.npc_behavioral_state.insert(*&ulid_bytes,  new_state.to_string());
        }
    }

    /// Set aggro target for an NPC (makes them prioritize attacking this target)
    fn set_aggro_target(&self, npc_ulid: &str, target_ulid: &str) {
        if let Ok(ulid_bytes) = hex_to_bytes(npc_ulid) {
            self.npc_aggro_targets.insert(*&ulid_bytes,  target_ulid.to_string());
            godot_print!("[AGGRO] NPC {} now targets {} (retaliation)",
                &npc_ulid[0..8.min(npc_ulid.len())], &target_ulid[0..8.min(target_ulid.len())]);
        }
    }

    /// Clear ATTACKING and DAMAGED states after animation duration
    fn clear_expired_animation_states(&self) {
        let now_ms = Self::get_current_time_ms();
        const ATTACK_ANIM_DURATION_MS: u64 = 800;  // Attack animation duration (800ms)
        const DAMAGED_ANIM_DURATION_MS: u64 = 500; // Hurt animation duration (500ms)

        // Iterate through all active NPCs
        for entry in self.active_npc_pool.iter() {
            let npc = entry.value();
            let ulid_bytes = &npc.ulid;

            // Check if this NPC has timestamp records
            if let Some(timestamp_str) = self.npc_state_timestamps.get(ulid_bytes).map(|v| v.value().clone()) {
                let mut should_clear_attacking = false;
                let mut should_clear_damaged = false;

                // Parse timestamps (format: "attacking:123456" or "damaged:123456")
                if timestamp_str.starts_with("attacking:") {
                    if let Ok(set_at_ms) = timestamp_str[10..].parse::<u64>() {
                        if now_ms >= set_at_ms + ATTACK_ANIM_DURATION_MS {
                            should_clear_attacking = true;
                        }
                    }
                } else if timestamp_str.starts_with("damaged:") {
                    if let Ok(set_at_ms) = timestamp_str[8..].parse::<u64>() {
                        if now_ms >= set_at_ms + DAMAGED_ANIM_DURATION_MS {
                            should_clear_damaged = true;
                        }
                    }
                }

                // Clear expired states
                if should_clear_attacking || should_clear_damaged {
                    if let Some(state_str) = self.npc_behavioral_state.get(ulid_bytes).map(|v| v.value().clone()) {
                        if let Ok(current_state) = state_str.parse::<i32>() {
                            let mut new_state = current_state;

                            if should_clear_attacking {
                                new_state &= !(NPCState::ATTACKING.bits() as i32);
                                let ulid_hex = bytes_to_hex(ulid_bytes);
                                godot_print!("[ANIM CLEAR] NPC {} - Clearing ATTACKING flag after {}ms",
                                    &ulid_hex[0..8.min(ulid_hex.len())], ATTACK_ANIM_DURATION_MS);
                            }

                            if should_clear_damaged {
                                new_state &= !(NPCState::DAMAGED.bits() as i32);
                                let ulid_hex = bytes_to_hex(ulid_bytes);
                                godot_print!("[ANIM CLEAR] NPC {} - Clearing DAMAGED flag after {}ms",
                                    &ulid_hex[0..8.min(ulid_hex.len())], DAMAGED_ANIM_DURATION_MS);
                            }

                            // Update state and remove timestamp
                            self.npc_behavioral_state.insert(*ulid_bytes,  new_state.to_string());
                            self.npc_state_timestamps.remove(ulid_bytes).map(|(_, v)| v);
                        }
                    }
                }
            }
        }
    }

    /// Check if this is the first combat tick and spawn minimal entities for debugging
    /// Spawns: 1 warrior, 1 archer, 2 random monsters
    fn check_initial_spawn(&self, now_ms: u64) -> Vec<CombatEvent> {
        use std::sync::atomic::Ordering;

        // Check if initial spawn already done
        if self.initial_spawn_done.load(Ordering::Relaxed) {
            return Vec::new(); // Already spawned
        }

        godot_print!("[RUST SPAWN] check_initial_spawn called - checking prerequisites...");

        // Check if scene container is set (required for spawning)
        {
            let container_guard = self.scene_container.read();
            if container_guard.is_none() {
                godot_print!("[RUST SPAWN] Scene container not set yet - skipping spawn");
                // Container not set yet - likely still in title/intro scene
                // Don't mark as done, just skip this tick
                return Vec::new();
            }
        }

        godot_print!("[RUST SPAWN] Prerequisites met - starting initial spawn!");

        // Mark initial spawn as done FIRST to prevent race conditions
        self.initial_spawn_done.store(true, Ordering::Relaxed);

        // Set the timers so regular spawning doesn't trigger immediately
        self.last_spawn_time_ms.store(now_ms, Ordering::Relaxed);
        self.last_ally_spawn_time_ms.store(now_ms, Ordering::Relaxed);

        godot_print!("[RUST SPAWN] Initial spawn starting...");

        // Calculate spawn positions and center point
        let world_min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
        let world_max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
        let world_min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
        let world_max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));
        let center_x = (world_min_x + world_max_x) / 2.0;
        let center_y = (world_min_y + world_max_y) / 2.0;

        // Spawn 1 warrior on left side - closer to center for quicker engagement
        // Allies spawn around x=350 (30% from left edge, moving toward center at 50%)
        let warrior_pos = Vector2::new(350.0, center_y - 30.0);
        let warrior_ulid = self.rust_spawn_npc("warrior", warrior_pos);

        // Give warrior initial waypoint toward center-right (to meet monsters)
        if let Some(ulid_bytes) = warrior_ulid {
            self.npc_waypoints.insert(*&ulid_bytes,  format!("{},{}", center_x - 100.0, center_y - 30.0));
            godot_print!("[RUST SPAWN] Warrior spawned with waypoint toward center");
        }

        // Spawn 1 archer on left side - slightly behind warrior
        let archer_pos = Vector2::new(300.0, center_y + 30.0);
        let archer_ulid = self.rust_spawn_npc("archer", archer_pos);

        // Give archer waypoint toward center-right (stays behind warrior)
        if let Some(ulid_bytes) = archer_ulid {
            self.npc_waypoints.insert(*&ulid_bytes,  format!("{},{}", center_x - 150.0, center_y + 30.0));
            godot_print!("[RUST SPAWN] Archer spawned with waypoint toward center");
        }

        // Spawn 2 random monsters on right side - closer to center
        use rand::Rng;
        let mut rng = rand::rng();
        let monster_types = vec!["goblin", "mushroom", "skeleton", "eyebeast"];

        for i in 0..2 {
            let monster_type = monster_types[rng.random_range(0..monster_types.len())];
            // Spawn monsters closer to center (70% from left edge, moving toward center at 50%)
            let monster_y = center_y + ((i as f32 - 0.5) * 60.0); // Spread vertically
            let monster_pos = Vector2::new(850.0, monster_y);

            let monster_ulid = self.rust_spawn_npc(monster_type, monster_pos);

            // Give monster waypoint toward center-left (to meet allies)
            if let Some(ulid_bytes) = monster_ulid {
                self.npc_waypoints.insert(*&ulid_bytes,  format!("{},{}", center_x + 100.0, monster_y));
                godot_print!("[RUST SPAWN] Monster {} spawned with waypoint toward center", monster_type);
            }
        }

        godot_print!("[RUST SPAWN] Initial spawn complete: 1 warrior, 1 archer, 2 random monsters (all moving toward center)");

        Vec::new() // No events needed - NPCs are spawned directly
    }

    /// Check if we should spawn a new wave of monsters
    /// Returns spawn events for GDScript to handle
    fn check_spawn_wave(&self, now_ms: u64) -> Vec<CombatEvent> {
        use std::sync::atomic::Ordering;
        let events = Vec::new();

        // Check if scene container is set (required for spawning)
        {
            let container_guard = self.scene_container.read();
            if container_guard.is_none() {
                return events; // Container not set yet
            }
        }

        // Count active monsters (NPCs with MONSTER faction)
        let monster_count = self.active_combat_npcs.iter()
            .filter(|entry| {
                let ulid = entry.key();
                if let Some(static_state) = self.get_stat_value(ulid, "static_state") {
                    let state = static_state as i32;
                    (state & NPCStaticState::MONSTER.bits() as i32) != 0
                } else {
                    false
                }
            })
            .count();

        // Check if we need a new wave (low monster count or interval elapsed)
        let last_spawn = self.last_spawn_time_ms.load(Ordering::Relaxed);
        let time_since_spawn = now_ms - last_spawn;

        let should_spawn = (monster_count < self.min_active_monsters as usize) ||
                          (time_since_spawn >= self.spawn_interval_ms);

        if should_spawn {
            // Update last spawn time
            self.last_spawn_time_ms.store(now_ms, Ordering::Relaxed);

            // Generate wave size (random between min and max)
            use rand::Rng;
            let mut rng = rand::rng();
            let wave_size = rng.random_range(self.min_wave_size..=self.max_wave_size);

            // Monster types to spawn from (weighted random)
            let monster_types = vec!["goblin", "mushroom", "skeleton", "eyebeast"];

            godot_print!("[RUST SPAWN] Spawning wave of {} monsters (current: {})", wave_size, monster_count);

            // Get spawn positions
            let world_max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
            let world_min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
            let world_max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

            // Spawn each monster directly (right side of visible screen)
            for _ in 0..wave_size {
                let monster_type = monster_types[rng.random_range(0..monster_types.len())];
                let spawn_pos = Vector2::new(
                    1050.0, // Right side of screen
                    rng.random_range(world_min_y..world_max_y)
                );

                if let Some(_ulid) = self.rust_spawn_npc(monster_type, spawn_pos) {
                    // Note: rust_spawn_npc already registers for combat via register_npc_with_stats
                }
            }
        }

        events
    }

    /// Check if we should spawn allies (warriors, archers)
    /// Returns spawn events for GDScript to handle
    /// Spawns gradually to ramp up (one ally every 3 seconds until cap reached)
    fn check_ally_spawn(&self, now_ms: u64) -> Vec<CombatEvent> {
        use std::sync::atomic::Ordering;
        let events = Vec::new();

        // Check if scene container is set (required for spawning)
        {
            let container_guard = self.scene_container.read();
            if container_guard.is_none() {
                return events; // Container not set yet
            }
        }

        // Count active warriors and archers
        let mut warrior_count = 0;
        let mut archer_count = 0;

        for entry in self.active_combat_npcs.iter() {
            let ulid = entry.key();
            if let Some(static_state) = self.get_stat_value(ulid, "static_state") {
                let state = static_state as i32;
                // Check if ALLY faction
                if (state & NPCStaticState::ALLY.bits() as i32) != 0 {
                    // Check combat type
                    if (state & NPCStaticState::MELEE.bits() as i32) != 0 {
                        warrior_count += 1;
                    } else if (state & NPCStaticState::RANGED.bits() as i32) != 0 {
                        archer_count += 1;
                    }
                }
            }
        }

        // Check if enough time has passed since last ally spawn
        let last_ally_spawn = self.last_ally_spawn_time_ms.load(Ordering::Relaxed);
        let time_since_spawn = now_ms - last_ally_spawn;

        if time_since_spawn < self.ally_spawn_interval_ms {
            return events; // Not time yet
        }

        // Spawn one ally at a time (warrior or archer, alternating priority)
        // Prioritize whichever is further from cap
        let warrior_deficit = self.max_warriors - warrior_count;
        let archer_deficit = self.max_archers - archer_count;

        if warrior_deficit > 0 || archer_deficit > 0 {
            // Update last spawn time
            self.last_ally_spawn_time_ms.store(now_ms, Ordering::Relaxed);

            // Decide which to spawn (prioritize bigger deficit)
            let ally_type = if warrior_deficit >= archer_deficit && warrior_deficit > 0 {
                "warrior"
            } else if archer_deficit > 0 {
                "archer"
            } else {
                return events; // Both at cap
            };

            // Get spawn positions
            let world_min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
            let world_min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
            let world_max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

            // Spawn ally on left side (visible screen area)
            use rand::Rng;
            let mut rng = rand::rng();
            let spawn_pos = Vector2::new(
                150.0, // Left side of screen
                rng.random_range(world_min_y..world_max_y)
            );

            if let Some(_ulid) = self.rust_spawn_npc(ally_type, spawn_pos) {
                // Note: rust_spawn_npc already registers for combat via register_npc_with_stats
                godot_print!("[RUST SPAWN] Spawned {} (Warriors: {}/{}, Archers: {}/{})",
                    ally_type, warrior_count, self.max_warriors, archer_count, self.max_archers);
            }
        }

        events
    }

    /// Get current time in milliseconds
    fn get_current_time_ms() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
    }

    // ============================================================================
    // COMBAT THREAD LIFECYCLE
    // ============================================================================

    /// Enable combat system (no-op, kept for API compatibility)
    /// Combat is now ticked manually from GDScript to avoid threading issues
    pub fn start_combat_thread(self: &Arc<Self>) {
        self.combat_thread_running.store(true, Ordering::Relaxed);
    }

    /// Disable combat system (no-op, kept for API compatibility)
    pub fn stop_combat_thread(&self) {
        self.combat_thread_running.store(false, Ordering::Relaxed);
    }

    /// Check if combat system is enabled
    pub fn is_combat_enabled(&self) -> bool {
        self.combat_thread_running.load(Ordering::Relaxed)
    }
}

/// Godot FFI wrapper for NPCDataWarehouse
///
/// This will be registered as an autoload singleton in Godot.
/// Replaces Dictionary-based pools in NPCManager.
///
/// Usage in GDScript:
/// ```gdscript
/// # Register a pool
/// NPCDataWarehouse.register_pool("warrior", 10, "res://nodes/npc/warrior/warrior.tscn")
///
/// # Store NPC data
/// NPCDataWarehouse.store_npc(ulid, npc_json_data)
///
/// # Get NPC data
/// var npc_data = NPCDataWarehouse.get_npc(ulid)
///
/// # Check pool health
/// var read_count = NPCDataWarehouse.read_store_count()
/// var write_count = NPCDataWarehouse.write_store_count()
/// ```
#[derive(GodotClass)]
#[class(base=Node)]
pub struct GodotNPCDataWarehouse {
    warehouse: Arc<NPCDataWarehouse>,
    base: Base<Node>,
}

#[godot_api]
impl INode for GodotNPCDataWarehouse {
    fn init(base: Base<Node>) -> Self {
        godot_print!("=== NPCDataWarehouse Initializing ===");
        Self {
            warehouse: Arc::new(NPCDataWarehouse::new(1000)), // 1 second sync interval
            base,
        }
    }

    fn ready(&mut self) {
        godot_print!("NPCDataWarehouse: Ready! High-performance NPC pool active.");
    }
}

#[godot_api]
impl GodotNPCDataWarehouse {
    /// Emitted when an NPC is stored in the warehouse
    /// Parameters: (ulid: String, npc_type: String)
    #[signal]
    fn npc_stored(ulid: GString, npc_type: GString);

    /// Emitted when an NPC is removed from the warehouse
    /// Parameters: (ulid: String, npc_type: String)
    #[signal]
    fn npc_removed(ulid: GString, npc_type: GString);

    /// Emitted when AI state changes
    /// Parameters: (ulid: String, ai_data: String)
    #[signal]
    fn ai_state_changed(ulid: GString, ai_data: GString);

    /// Emitted when combat state changes
    /// Parameters: (ulid: String, combat_data: String)
    #[signal]
    fn combat_state_changed(ulid: GString, combat_data: GString);

    /// Emitted when a pool is registered
    /// Parameters: (npc_type: String, max_size: int)
    #[signal]
    fn pool_registered(npc_type: GString, max_size: i32);

    /// Emitted when sync completes
    /// Parameters: (synced_count: int)
    #[signal]
    fn sync_completed(synced_count: i32);

    // ===== Pool Management Methods =====
    /// Register a new NPC pool
    #[func]
    pub fn register_pool(&mut self, npc_type: GString, max_size: i32, scene_path: GString) {
        self.warehouse.register_pool(
            &npc_type.to_string(),
            max_size,
            &scene_path.to_string()
        );
        // Emit signal
        self.base_mut().emit_signal("pool_registered", &[npc_type.to_variant(), max_size.to_variant()]);
    }

    // ===== Rust NPC Pool System Methods =====

    /// Initialize an NPC pool (exposed to GDScript)
    /// Call this on game start for each NPC type
    #[func]
    pub fn initialize_npc_pool(&self, npc_type: GString, pool_size: i32, scene_path: GString) {
        self.warehouse.initialize_npc_pool(
            &npc_type.to_string(),
            pool_size as usize,
            &scene_path.to_string()
        );
    }

    /// Set the scene container where NPCs will be added as children
    #[func]
    pub fn set_scene_container(&self, container: Gd<Node2D>) {
        self.warehouse.set_scene_container(container);
    }

    /// Spawn an NPC from the Rust pool
    /// Returns the ULID bytes of the spawned NPC, or empty array if failed
    #[func]
    pub fn rust_spawn_npc(&self, npc_type: GString, position: Vector2) -> PackedByteArray {
        if let Some(ulid_bytes) = self.warehouse.rust_spawn_npc(&npc_type.to_string(), position) {
            return PackedByteArray::from(&ulid_bytes[..]);
        }
        PackedByteArray::new()
    }

    /// Despawn an NPC and return it to the pool
    #[func]
    pub fn rust_despawn_npc(&self, ulid: PackedByteArray) -> bool {
        let ulid_slice = ulid.as_slice();
        self.warehouse.rust_despawn_npc(ulid_slice)
    }

    /// Get NPC name by ULID bytes
    #[func]
    pub fn get_npc_name(&self, ulid: PackedByteArray) -> GString {
        if ulid.len() != 16 {
            return GString::from("");
        }
        let ulid_bytes: [u8; 16] = ulid.as_slice().try_into().unwrap_or([0u8; 16]);
        self.warehouse.npc_names.get(&ulid_bytes).map(|v| v.value().clone())
            .map(|name| GString::from(name))
            .unwrap_or_else(|| GString::from(""))
    }

    /// Get NPC type by ULID bytes
    #[func]
    pub fn get_npc_type(&self, ulid: PackedByteArray) -> GString {
        if ulid.len() != 16 {
            return GString::from("");
        }
        let ulid_bytes: [u8; 16] = ulid.as_slice().try_into().unwrap_or([0u8; 16]);
        self.warehouse.npc_types.get(&ulid_bytes).map(|v| v.value().clone())
            .map(|npc_type| GString::from(npc_type))
            .unwrap_or_else(|| GString::from(""))
    }

    /// Get NPC stats dictionary by ULID bytes
    /// Returns a Dictionary with keys: name, type, max_hp, attack, defense
    #[func]
    pub fn get_npc_stats_dict(&self, ulid: PackedByteArray) -> Dictionary {
        let mut dict = Dictionary::new();
        if ulid.len() != 16 {
            return dict;
        }
        let ulid_bytes: [u8; 16] = ulid.as_slice().try_into().unwrap_or([0u8; 16]);

        // Get name
        if let Some(name) = self.warehouse.npc_names.get(&ulid_bytes).map(|v| v.value().clone()) {
            dict.set("name", name);
        }

        // Get type
        if let Some(npc_type) = self.warehouse.npc_types.get(&ulid_bytes).map(|v| v.value().clone()) {
            dict.set("type", npc_type);
        }

        // Get combat stats (hp, max_hp, attack, defense) from single struct
        if let Some(stats_json) = self.warehouse.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
            if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                dict.set("hp", combat_stats.hp);
                dict.set("max_hp", combat_stats.max_hp);
                dict.set("attack", combat_stats.attack);
                dict.set("defense", combat_stats.defense);
            }
        }

        dict
    }

    /// Get NPC data as JSON string (name, type, stats)
    #[func]
    pub fn get_npc_data_json(&self, ulid: PackedByteArray) -> GString {
        if ulid.len() != 16 {
            return GString::from("{}");
        }
        let ulid_bytes: [u8; 16] = ulid.as_slice().try_into().unwrap_or([0u8; 16]);

        let mut name = String::from("");
        let mut npc_type = String::from("");
        let mut hp = 0.0_f32;
        let mut max_hp = 0.0_f32;
        let mut attack = 0.0_f32;
        let mut defense = 0.0_f32;
        let mut emotional_state = 0_i32;
        let mut mana = 0.0_f32;
        let mut max_mana = 0.0_f32;
        let mut energy = 0.0_f32;
        let mut max_energy = 0.0_f32;

        // Get name
        if let Some(n) = self.warehouse.npc_names.get(&ulid_bytes).map(|v| v.value().clone()) {
            name = n;
        }

        // Get type
        if let Some(t) = self.warehouse.npc_types.get(&ulid_bytes).map(|v| v.value().clone()) {
            npc_type = t;
        }

        // Get combat stats
        if let Some(stats_json) = self.warehouse.npc_combat_stats.get(&ulid_bytes).map(|v| v.value().clone()) {
            if let Ok(combat_stats) = serde_json::from_str::<NPCCombatStats>(&stats_json) {
                hp = combat_stats.hp;
                max_hp = combat_stats.max_hp;
                attack = combat_stats.attack;
                defense = combat_stats.defense;
                emotional_state = combat_stats.emotional_state;
                mana = combat_stats.mana;
                max_mana = combat_stats.max_mana;
                energy = combat_stats.energy;
                max_energy = combat_stats.max_energy;
            }
        }

        // Build JSON string manually (simple and fast)
        let json = format!(
            r#"{{"name":"{}","type":"{}","hp":{},"max_hp":{},"attack":{},"defense":{},"emotional_state":{},"mana":{},"max_mana":{},"energy":{},"max_energy":{}}}"#,
            name, npc_type, hp, max_hp, attack, defense, emotional_state, mana, max_mana, energy, max_energy
        );

        GString::from(json)
    }

    /// Store active NPC data
    /// npc_data should be JSON with at minimum {"type":"npc_type_here"}
    #[func]
    pub fn store_npc(&mut self, ulid: GString, npc_data: GString) {
        self.warehouse.store_npc(&ulid.to_string(), &npc_data.to_string());

        // Extract npc_type from JSON (simple parse - assumes format {"type":"value"})
        let npc_type = GString::from("unknown"); // TODO: Parse JSON properly

        // Emit signal
        self.base_mut().emit_signal("npc_stored", &[ulid.to_variant(), npc_type.to_variant()]);
    }

    /// Get active NPC data
    #[func]
    pub fn get_npc(&self, ulid: GString) -> GString {
        self.warehouse.get_npc(&ulid.to_string())
            .map(|s| GString::from(s))
            .unwrap_or_else(|| GString::from(""))
    }

    /// Remove NPC from active pool
    #[func]
    pub fn remove_npc(&mut self, ulid: GString) -> bool {
        let removed = self.warehouse.remove_npc(&ulid.to_string());
        if removed {
            // Emit signal
            self.base_mut().emit_signal("npc_removed", &[ulid.to_variant(), GString::from("unknown").to_variant()]);
        }
        removed
    }

    /// Store NPC state flags (raw integer, not JSON)
    /// Much faster than storing in AI state JSON
    #[func]
    pub fn store_npc_state(&mut self, ulid: GString, state: i32) {
        // Store as simple integer string for fast access
        self.warehouse.store_combat_state(&format!("{}_state", ulid.to_string()), &state.to_string());
    }

    /// Get NPC state flags (raw integer)
    #[func]
    pub fn get_npc_state(&self, ulid: GString) -> i32 {
        self.warehouse.get_combat_state(&format!("{}_state", ulid.to_string()))
            .and_then(|s| s.parse::<i32>().ok())
            .unwrap_or(NPCState::IDLE.to_i32())
    }

    /// Store AI state
    #[func]
    pub fn store_ai_state(&mut self, ulid: GString, ai_data: GString) {
        self.warehouse.store_ai_state(&ulid.to_string(), &ai_data.to_string());
        // Emit signal
        self.base_mut().emit_signal("ai_state_changed", &[ulid.to_variant(), ai_data.to_variant()]);
    }

    /// Get AI state
    #[func]
    pub fn get_ai_state(&self, ulid: GString) -> GString {
        self.warehouse.get_ai_state(&ulid.to_string())
            .map(|s| GString::from(s))
            .unwrap_or_else(|| GString::from(""))
    }

    /// Store combat state
    #[func]
    pub fn store_combat_state(&mut self, ulid: GString, combat_data: GString) {
        self.warehouse.store_combat_state(&ulid.to_string(), &combat_data.to_string());
        // Emit signal
        self.base_mut().emit_signal("combat_state_changed", &[ulid.to_variant(), combat_data.to_variant()]);
    }

    /// Get combat state
    #[func]
    pub fn get_combat_state(&self, ulid: GString) -> GString {
        self.warehouse.get_combat_state(&ulid.to_string())
            .map(|s| GString::from(s))
            .unwrap_or_else(|| GString::from(""))
    }

    /// Check if NPC exists
    #[func]
    pub fn has_npc(&self, ulid: GString) -> bool {
        self.warehouse.has_npc(&ulid.to_string())
    }

    /// Get total entries
    #[func]
    pub fn total_entries(&self) -> i32 {
        self.warehouse.total_entries() as i32
    }

    /// Get read store count (Papaya - lock-free)
    #[func]
    pub fn read_store_count(&self) -> i32 {
        self.warehouse.read_store_count() as i32
    }

    /// Get write store count (DashMap - concurrent)
    #[func]
    pub fn write_store_count(&self) -> i32 {
        self.warehouse.write_store_count() as i32
    }

    /// Manually trigger sync
    #[func]
    pub fn sync(&mut self) {
        self.warehouse.sync();
        let count_after = self.warehouse.read_store_count();

        // Emit signal with count of synced entries
        self.base_mut().emit_signal("sync_completed", &[(count_after as i32).to_variant()]);
    }

    /// Clear all data
    #[func]
    pub fn clear_all(&self) {
        self.warehouse.clear_all();
    }

    // ===== State Helper Methods (MINIMAL - Rust handles combat) =====

    /// Get NPCState constant value by name (behavioral states only)
    /// Usage in GDScript: NPCDataWarehouse.get_state("IDLE") returns 1
    #[func]
    pub fn get_state(&self, state_name: GString) -> i32 {
        match state_name.to_string().to_uppercase().as_str() {
            "IDLE" => NPCState::IDLE.to_i32(),
            "WALKING" => NPCState::WALKING.to_i32(),
            "ATTACKING" => NPCState::ATTACKING.to_i32(),
            "COMBAT" => NPCState::COMBAT.to_i32(),
            "DAMAGED" => NPCState::DAMAGED.to_i32(),
            "DEAD" => NPCState::DEAD.to_i32(),
            _ => 0,
        }
    }

    /// Confirm spawn completed successfully (called by GDScript after spawn)
    /// Defensive programming: tracks spawn success rate
    /// Usage: NPCDataWarehouse.confirm_spawn(ulid_bytes, monster_type, static_state, behavioral_state)
    #[func]
    pub fn confirm_spawn(&self, ulid_bytes: PackedByteArray, monster_type: GString, static_state: i32, behavioral_state: i32) {
        use std::sync::atomic::Ordering;

        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                // Increment confirmation counter
                self.warehouse.spawn_confirmations.fetch_add(1, Ordering::Relaxed);

                // Log confirmation (every 10th spawn)
                let confirmations = self.warehouse.spawn_confirmations.load(Ordering::Relaxed);
                let requests = self.warehouse.spawn_requests.load(Ordering::Relaxed);

                if confirmations % 10 == 0 {
                    let success_rate = if requests > 0 {
                        (confirmations as f32 / requests as f32 * 100.0) as u64
                    } else {
                        100
                    };
                    godot_print!("[RUST SPAWN] Spawn stats: {} requests, {} confirmed ({}% success)",
                        requests, confirmations, success_rate);
                }

                // Verify the spawned NPC has correct state
                if let Some(actual_static) = self.warehouse.get_stat_value(&ulid_hex, "static_state") {
                    if (actual_static as i32) != static_state {
                        godot_warn!("[RUST SPAWN] NPC {} spawned with incorrect static_state! Expected: {}, Got: {}",
                            &ulid_hex[0..8], static_state, actual_static as i32);
                    }
                }

                if let Some(actual_behavioral) = self.warehouse.get_stat_value(&ulid_hex, "behavioral_state") {
                    if (actual_behavioral as i32) != behavioral_state {
                        godot_warn!("[RUST SPAWN] NPC {} spawned with incorrect behavioral_state! Expected: {}, Got: {}",
                            &ulid_hex[0..8], behavioral_state, actual_behavioral as i32);
                    }
                }
            }
            Err(e) => {
                godot_error!("[RUST SPAWN] Invalid ULID in confirm_spawn: {}", e);
            }
        }
    }

    /// Handle projectile hit - called by GDScript when arrow/projectile collides with target
    /// Calculates damage, applies it, and returns events (damage or death)
    /// Usage: var events_json = NPCDataWarehouse.projectile_hit(attacker_ulid, target_ulid)
    #[func]
    pub fn projectile_hit(&self, attacker_ulid_bytes: PackedByteArray, target_ulid_bytes: PackedByteArray) -> Array<GString> {
        use std::sync::atomic::Ordering;

        let attacker_result = packed_bytes_to_hex(&attacker_ulid_bytes);
        let target_result = packed_bytes_to_hex(&target_ulid_bytes);

        if attacker_result.is_err() || target_result.is_err() {
            godot_error!("[PROJECTILE] Invalid ULID bytes in projectile_hit");
            return Array::new();
        }

        let attacker_ulid = attacker_result.unwrap();
        let target_ulid = target_result.unwrap();

        // Validate target is alive
        let target_hp = self.warehouse.get_stat_value(&target_ulid, "hp").unwrap_or(0.0);
        if target_hp <= 0.0 {
            // Target already dead, no damage
            return Array::new();
        }

        // Get attacker and target stats
        let attacker_attack = self.warehouse.get_stat_value(&attacker_ulid, "attack").unwrap_or(10.0);
        let target_defense = self.warehouse.get_stat_value(&target_ulid, "defense").unwrap_or(5.0);

        // Calculate damage
        let damage = (attacker_attack - (target_defense / 2.0)).max(1.0);

        // Apply damage
        let new_target_hp = self.warehouse.apply_damage(&target_ulid, damage);

        // Get target position for event
        let (target_x, target_y) = self.warehouse.get_npc_position_internal(&target_ulid)
            .unwrap_or((0.0, 0.0));

        // Generate event based on result
        let event = if new_target_hp <= 0.0 {
            // Mark target as dead
            self.warehouse.mark_dead(&target_ulid);

            CombatEvent {
                event_type: "death".to_string(),
                attacker_ulid,
                target_ulid,
                amount: damage,
                attacker_animation: "".to_string(),
                target_animation: "death".to_string(),
                target_x,
                target_y,
            }
        } else {
            // Set DAMAGED state on target
            self.warehouse.add_damaged_state(&target_ulid);

            CombatEvent {
                event_type: "damage".to_string(),
                attacker_ulid,
                target_ulid,
                amount: damage,
                attacker_animation: "".to_string(),
                target_animation: "hurt".to_string(),
                target_x,
                target_y,
            }
        };

        // Return event as JSON array
        let mut godot_array = Array::new();
        let json = serde_json::to_string(&event).unwrap_or_default();
        godot_array.push(&GString::from(&json));
        godot_array
    }

    /// Get NPCStaticState constant value by name (combat types + factions)
    /// Usage in GDScript: NPCDataWarehouse.get_static_state("MELEE") returns 1
    #[func]
    pub fn get_static_state(&self, state_name: GString) -> i32 {
        match state_name.to_string().to_uppercase().as_str() {
            "MELEE" => NPCStaticState::MELEE.to_i32(),
            "RANGED" => NPCStaticState::RANGED.to_i32(),
            "MAGIC" => NPCStaticState::MAGIC.to_i32(),
            "HEALER" => NPCStaticState::HEALER.to_i32(),
            "ALLY" => NPCStaticState::ALLY.to_i32(),
            "MONSTER" => NPCStaticState::MONSTER.to_i32(),
            "PASSIVE" => NPCStaticState::PASSIVE.to_i32(),
            _ => 0,
        }
    }

    /// Set world bounds for waypoint clamping (from BackgroundManager safe_rectangle)
    /// Usage: NPCDataWarehouse.set_world_bounds(min_x, max_x, min_y, max_y)
    /// Should be called when background loads/changes
    #[func]
    pub fn set_world_bounds(&self, min_x: f32, max_x: f32, min_y: f32, max_y: f32) {
        use std::sync::atomic::Ordering;
        self.warehouse.world_min_x.store(min_x.to_bits(), Ordering::Relaxed);
        self.warehouse.world_max_x.store(max_x.to_bits(), Ordering::Relaxed);
        self.warehouse.world_min_y.store(min_y.to_bits(), Ordering::Relaxed);
        self.warehouse.world_max_y.store(max_y.to_bits(), Ordering::Relaxed);
        godot_print!("[RUST BOUNDS] Updated world bounds: X({} to {}), Y({} to {})", min_x, max_x, min_y, max_y);
    }

    /// Check if a state has a specific flag set
    /// Usage: NPCDataWarehouse.has_state_flag(npc_state, "IDLE")
    #[func]
    pub fn has_state_flag(&self, state: i32, flag_name: GString) -> bool {
        let flag_value = self.get_state(flag_name);
        (state & flag_value) != 0
    }

    /// Combine multiple states using bitwise OR
    /// Usage: NPCDataWarehouse.combine_states(state1, state2)
    #[func]
    pub fn combine_states(&self, state1: i32, state2: i32) -> i32 {
        state1 | state2
    }

    /// Remove a flag from a state using bitwise AND NOT
    /// Usage: NPCDataWarehouse.remove_state_flag(npc_state, "IDLE")
    #[func]
    pub fn remove_state_flag(&self, state: i32, flag_name: GString) -> i32 {
        let flag_value = self.get_state(flag_name);
        state & !flag_value
    }

    /// Add a flag to a state using bitwise OR
    /// Usage: NPCDataWarehouse.add_state_flag(npc_state, "WALKING")
    #[func]
    pub fn add_state_flag(&self, state: i32, flag_name: GString) -> i32 {
        let flag_value = self.get_state(flag_name);
        state | flag_value
    }

    /// Remove ATTACKING state flag after attack animation finishes
    /// Called by GDScript animation_finished handler
    /// Usage: NPCDataWarehouse.clear_attacking_state(ulid_bytes)
    #[func]
    pub fn clear_attacking_state(&self, ulid_bytes: PackedByteArray) {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.remove_attacking_state(&ulid_hex);
            }
            Err(e) => {
                godot_error!("[COMBAT ERROR] Invalid ULID bytes for clear_attacking_state: {}", e);
            }
        }
    }

    /// Remove DAMAGED state flag after hurt animation finishes
    /// Called by GDScript animation_finished handler
    /// Usage: NPCDataWarehouse.clear_damaged_state(ulid_bytes)
    #[func]
    pub fn clear_damaged_state(&self, ulid_bytes: PackedByteArray) {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.remove_damaged_state(&ulid_hex);
            }
            Err(e) => {
                godot_error!("[COMBAT ERROR] Invalid ULID bytes for clear_damaged_state: {}", e);
            }
        }
    }

    /// Get NPC waypoint (target position calculated by Rust AI)
    /// Returns PackedFloat32Array [x, y] world position, or empty array if no waypoint
    /// Usage: var waypoint = NPCDataWarehouse.get_npc_waypoint(ulid_bytes)
    #[func]
    pub fn get_npc_waypoint(&self, ulid_bytes: PackedByteArray) -> PackedFloat32Array {
        if ulid_bytes.len() == 16 {
            if let Ok(ulid_array) = ulid_bytes.as_slice().try_into() {
                if let Some(pos_str) = self.warehouse.npc_waypoints.get(ulid_array).map(|v| v.value().clone()) {
                    if let Some((x_str, y_str)) = pos_str.split_once(',') {
                        if let (Ok(x), Ok(y)) = (x_str.parse::<f32>(), y_str.parse::<f32>()) {
                            return PackedFloat32Array::from(&[x, y]);
                        }
                    }
                }
            }
        }
        // No waypoint or invalid ULID - return empty array
        PackedFloat32Array::new()
    }

    // ===== COMBAT SYSTEM FUNCTIONS =====

    /// Register an NPC for combat processing
    /// Usage: NPCDataWarehouse.register_npc_for_combat(ulid_bytes, static_state, behavioral_state, max_hp, attack, defense)
    /// ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
    #[func]
    pub fn register_npc_for_combat(
        &self,
        ulid_bytes: PackedByteArray,
        static_state: i32,
        behavioral_state: i32,
        max_hp: f32,
        attack: f32,
        defense: f32,
    ) {
        // Convert PackedByteArray to [u8; 16]
        let ulid_slice = ulid_bytes.as_slice();
        if ulid_slice.len() != 16 {
            godot_error!("[COMBAT ERROR] Invalid ULID bytes in register_npc_for_combat: expected 16 bytes, got {}", ulid_slice.len());
            return;
        }

        let mut ulid_array = [0u8; 16];
        ulid_array.copy_from_slice(ulid_slice);

        self.warehouse.register_npc_for_combat_internal(
            &ulid_array,
            static_state,
            behavioral_state,
            max_hp,
            attack,
            defense,
        );
    }

    /// Unregister an NPC from combat processing
    /// Usage: NPCDataWarehouse.unregister_npc_from_combat(ulid_bytes)
    /// ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
    #[func]
    pub fn unregister_npc_from_combat(&self, ulid_bytes: PackedByteArray) {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.unregister_npc_from_combat_internal(&ulid_hex);
            }
            Err(e) => {
                godot_error!("[COMBAT ERROR] Invalid ULID bytes in unregister_npc_from_combat: {}", e);
            }
        }
    }

    /// Update NPC position for combat calculations
    /// Usage: NPCDataWarehouse.update_npc_position(ulid_bytes, x, y)
    /// ulid_bytes: PackedByteArray (16 bytes) - raw ULID bytes from stats.ulid
    #[func]
    pub fn update_npc_position(&self, ulid_bytes: PackedByteArray, x: f32, y: f32) {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.update_npc_position_internal(&ulid_hex, x, y);
            }
            Err(e) => {
                godot_error!("[COMBAT ERROR] Invalid ULID bytes in update_npc_position: {}", e);
            }
        }
    }

    /// Start the combat system (sets flag, no actual thread)
    /// Usage: NPCDataWarehouse.start_combat_system()
    #[func]
    pub fn start_combat_system(&self) {
        self.warehouse.start_combat_thread();
    }

    /// Stop the combat system
    /// Usage: NPCDataWarehouse.stop_combat_system()
    #[func]
    pub fn stop_combat_system(&self) {
        self.warehouse.stop_combat_thread();
    }

    /// Tick combat logic and get events
    /// Returns array of JSON strings representing combat events
    /// Usage: var events = NPCDataWarehouse.tick_combat(delta)
    #[func]
    pub fn tick_combat(&self, delta: f32) -> Array<GString> {
        let events = self.warehouse.tick_combat_internal(delta);
        let mut godot_array = Array::new();

        for event in events {
            let json = serde_json::to_string(&event).unwrap_or_default();
            let gstring = GString::from(&json);
            godot_array.push(&gstring);
        }

        godot_array
    }

    /// Get NPC current HP
    /// Usage: var hp = NPCDataWarehouse.get_npc_hp(ulid_bytes)
    #[func]
    pub fn get_npc_hp(&self, ulid_bytes: PackedByteArray) -> f32 {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.get_npc_hp_internal(&ulid_hex).unwrap_or(0.0)
            }
            Err(_) => 0.0
        }
    }

    /// Get NPC behavioral state (IDLE, WALKING, ATTACKING, DAMAGED, DEAD, etc.)
    /// Usage: var state = NPCDataWarehouse.get_npc_behavioral_state(ulid_bytes)
    #[func]
    pub fn get_npc_behavioral_state(&self, ulid_bytes: PackedByteArray) -> i32 {
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                self.warehouse.get_stat_value(&ulid_hex, "behavioral_state").unwrap_or(0.0) as i32
            }
            Err(_) => 0
        }
    }

    /// Get NPC position
    /// Usage: var pos = NPCDataWarehouse.get_npc_position(ulid)
    /// Accepts ULID as PackedByteArray (16 bytes)
    #[func]
    pub fn get_npc_position(&self, ulid: PackedByteArray) -> PackedFloat32Array {
        if ulid.len() != 16 {
            return PackedFloat32Array::new();
        }
        let ulid_bytes: [u8; 16] = ulid.as_slice().try_into().unwrap_or([0u8; 16]);

        // Get position from npc_positions ByteMap (stored as "x,y")
        if let Some(pos_str) = self.warehouse.npc_positions.get(&ulid_bytes).map(|v| v.value().clone()) {
            let coords: Vec<&str> = pos_str.split(',').collect();
            if coords.len() == 2 {
                if let (Ok(x), Ok(y)) = (coords[0].parse::<f32>(), coords[1].parse::<f32>()) {
                    let mut arr = PackedFloat32Array::new();
                    arr.push(x);
                    arr.push(y);
                    return arr;
                }
            }
        }
        PackedFloat32Array::new()
    }

    // ===== ULID FUNCTIONS =====

    /// Generate a new ULID as raw bytes (16 bytes / 128 bits)
    /// Returns PackedByteArray for maximum performance
    #[func]
    pub fn generate_ulid_bytes(&self) -> PackedByteArray {
        let ulid = ulid::Ulid::new();
        PackedByteArray::from(ulid.to_bytes().as_slice())
    }

    /// Generate a new ULID as hex string
    #[func]
    pub fn generate_ulid(&self) -> GString {
        let ulid = ulid::Ulid::new();
        GString::from(format!("{}", ulid))
    }

    /// Convert ULID bytes to hex string
    #[func]
    pub fn ulid_bytes_to_hex(&self, bytes: PackedByteArray) -> GString {
        if bytes.len() == 16 {
            let mut arr = [0u8; 16];
            arr.copy_from_slice(&bytes.to_vec());
            let ulid = ulid::Ulid::from_bytes(arr);
            GString::from(format!("{}", ulid))
        } else {
            GString::new()
        }
    }

    /// Convert hex string to ULID bytes
    #[func]
    pub fn ulid_hex_to_bytes(&self, hex: GString) -> PackedByteArray {
        if let Ok(ulid) = ulid::Ulid::from_string(&hex.to_string()) {
            PackedByteArray::from(ulid.to_bytes().as_slice())
        } else {
            PackedByteArray::new()
        }
    }

    /// Validate a ULID string
    #[func]
    pub fn validate_ulid(&self, ulid: GString) -> bool {
        ulid::Ulid::from_string(&ulid.to_string()).is_ok()
    }

    // ===== STATE HELPER FUNCTIONS =====

    /// Convert state bitflags to human-readable string
    #[func]
    pub fn state_to_string(&self, state: i32) -> GString {
        let mut parts = Vec::new();

        // NPCState flags (SIMPLIFIED)
        if state & NPCState::IDLE.bits() as i32 != 0 { parts.push("IDLE"); }
        if state & NPCState::WALKING.bits() as i32 != 0 { parts.push("WALKING"); }
        if state & NPCState::ATTACKING.bits() as i32 != 0 { parts.push("ATTACKING"); }
        if state & NPCState::COMBAT.bits() as i32 != 0 { parts.push("COMBAT"); }
        if state & NPCState::DAMAGED.bits() as i32 != 0 { parts.push("DAMAGED"); }
        if state & NPCState::DEAD.bits() as i32 != 0 { parts.push("DEAD"); }

        if parts.is_empty() {
            GString::from("NONE")
        } else {
            GString::from(parts.join(" | "))
        }
    }

    // ===== COMBAT HELPER FUNCTIONS (old API, kept for compatibility) =====

    /// Calculate damage (basic formula)
    #[func]
    pub fn calculate_damage(&self, attacker_attack: f32, victim_defense: f32) -> f32 {
        (attacker_attack - victim_defense * 0.5).max(1.0)
    }

    /// Check if two NPCs are hostile (uses static_state for faction)
    #[func]
    pub fn are_hostile(&self, static_state1: i32, static_state2: i32) -> bool {
        let ally1 = (static_state1 & NPCStaticState::ALLY.bits() as i32) != 0;
        let monster1 = (static_state1 & NPCStaticState::MONSTER.bits() as i32) != 0;
        let ally2 = (static_state2 & NPCStaticState::ALLY.bits() as i32) != 0;
        let monster2 = (static_state2 & NPCStaticState::MONSTER.bits() as i32) != 0;

        (ally1 && monster2) || (monster1 && ally2)
    }

    /// Check if NPC can attack (not passive)
    #[func]
    pub fn can_attack(&self, static_state: i32) -> bool {
        (static_state & NPCStaticState::PASSIVE.bits() as i32) == 0
    }

    /// Get combat type from static state
    #[func]
    pub fn get_combat_type(&self, static_state: i32) -> i32 {
        if static_state & NPCStaticState::MELEE.bits() as i32 != 0 {
            NPCStaticState::MELEE.bits() as i32
        } else if static_state & NPCStaticState::RANGED.bits() as i32 != 0 {
            NPCStaticState::RANGED.bits() as i32
        } else if static_state & NPCStaticState::MAGIC.bits() as i32 != 0 {
            NPCStaticState::MAGIC.bits() as i32
        } else {
            0
        }
    }

    /// Enter combat state (behavioral state changes)
    #[func]
    pub fn enter_combat_state(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state &= !(NPCState::IDLE.bits() as i32);
        new_state |= NPCState::COMBAT.bits() as i32;
        new_state
    }

    /// Exit combat state (behavioral state changes)
    #[func]
    pub fn exit_combat_state(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state &= !(NPCState::COMBAT.bits() as i32);
        new_state &= !(NPCState::ATTACKING.bits() as i32);
        new_state |= NPCState::IDLE.bits() as i32;
        new_state
    }

    /// Start attacking (behavioral state changes)
    #[func]
    pub fn start_attack(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state |= NPCState::ATTACKING.bits() as i32;
        new_state &= !(NPCState::IDLE.bits() as i32);
        new_state
    }

    /// Stop attacking (behavioral state changes)
    #[func]
    pub fn stop_attack(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state &= !(NPCState::ATTACKING.bits() as i32);
        new_state |= NPCState::IDLE.bits() as i32;
        new_state
    }

    /// Start walking (behavioral state changes)
    #[func]
    pub fn start_walking(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state |= NPCState::WALKING.bits() as i32;
        new_state &= !(NPCState::IDLE.bits() as i32);
        new_state
    }

    /// Stop walking (behavioral state changes)
    #[func]
    pub fn stop_walking(&self, current_state: i32) -> i32 {
        let mut new_state = current_state;
        new_state &= !(NPCState::WALKING.bits() as i32);
        new_state |= NPCState::IDLE.bits() as i32;
        new_state
    }

    /// Mark NPC as dead (behavioral state changes)
    #[func]
    pub fn mark_dead(&self, current_state: i32) -> i32 {
        NPCState::DEAD.bits() as i32
    }

    /// Check if NPC is in combat
    #[func]
    pub fn is_in_combat(&self, state: i32) -> bool {
        (state & NPCState::COMBAT.bits() as i32) != 0
    }

    /// Poll combat events (deprecated - use tick_combat instead)
    #[func]
    pub fn poll_combat_events(&self) -> Array<GString> {
        // Returns empty array - events are now returned from tick_combat
        Array::new()
    }
}
