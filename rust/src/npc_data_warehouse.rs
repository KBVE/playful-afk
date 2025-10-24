use godot::prelude::*;
use godot::classes::{PackedScene, Node2D, AnimatedSprite2D};
use crate::holymap::HolyMap;
use crate::bytemap::ByteMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering, AtomicU64};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use bitflags::bitflags;
use crossbeam_queue::SegQueue;
use dashmap::DashMap;
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

/// NPC stats stored internally in Rust (avoids GDScript interop during combat)
#[derive(Clone, Copy)]
struct RustNPCStats {
    max_hp: f32,
    attack: f32,
    defense: f32,
    static_state: i32, // Combat type + faction bitflags
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
    /// ULID for combat tracking (128-bit / 16 bytes)
    ulid: [u8; 16],
    /// Is this NPC currently active (spawned) or in pool (inactive)?
    is_active: bool,
    /// Stats for this NPC (extracted during instantiation)
    stats: RustNPCStats,
}

impl RustNPC {
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

        // Find the AnimatedSprite2D child node
        let animated_sprite = node.try_get_node_as::<AnimatedSprite2D>("AnimatedSprite2D");

        // Extract stats from the NPC by calling create_stats() static method
        let stats = Self::extract_stats(&mut node, npc_type);

        // Convert first 8 bytes to hex for logging
        let ulid_hex = format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            ulid[0], ulid[1], ulid[2], ulid[3], ulid[4], ulid[5], ulid[6], ulid[7]);
        godot_print!("[RUST NPC] Created {} with ULID: {}", npc_type, ulid_hex);

        Some(Self {
            node,
            animated_sprite,
            npc_type: npc_type.to_string(),
            ulid,
            is_active: false,
            stats,
        })
    }

    /// Extract stats from NPC scene by calling create_stats()
    fn extract_stats(node: &mut Gd<Node2D>, npc_type: &str) -> RustNPCStats {
        // Default stats (fallback if extraction fails)
        let mut stats = RustNPCStats {
            max_hp: 100.0,
            attack: 10.0,
            defense: 5.0,
            static_state: 0,
        };

        // Get the script attached to this node and call create_stats()
        let script_var = node.get("script");
        let stats_obj = script_var.call("create_stats", &[]);
        // Extract max_hp, attack, defense from stats object
        let max_hp_var = stats_obj.call("get", &["max_hp".to_variant()]);
        if let Ok(max_hp) = max_hp_var.try_to::<f32>() {
            stats.max_hp = max_hp;
        }
        let attack_var = stats_obj.call("get", &["attack".to_variant()]);
        if let Ok(attack) = attack_var.try_to::<f32>() {
            stats.attack = attack;
        }
        let defense_var = stats_obj.call("get", &["defense".to_variant()]);
        if let Ok(defense) = defense_var.try_to::<f32>() {
            stats.defense = defense;
        }

        // Get static_state from the node (set in GDScript _ready())
        // Note: static_state might not be set until _ready() is called, so we'll set it later
        // For now, determine it from npc_type
        stats.static_state = Self::get_static_state_for_type(npc_type);

        stats
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
        self.node.set_global_position(position);
        godot_print!("[RUST NPC] Activated {} at {:?}", self.npc_type, position);
    }

    /// Deactivate this NPC (return to pool)
    fn deactivate(&mut self) {
        self.is_active = false;
        self.node.set_visible(false);
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
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
struct SafeString(String);

impl From<GString> for SafeString {
    fn from(s: GString) -> Self {
        SafeString(s.to_string())
    }
}

impl From<SafeString> for GString {
    fn from(s: SafeString) -> Self {
        GString::from(s.0)
    }
}

impl From<String> for SafeString {
    fn from(s: String) -> Self {
        SafeString(s)
    }
}

impl From<&str> for SafeString {
    fn from(s: &str) -> Self {
        SafeString(s.to_string())
    }
}

unsafe impl Send for SafeString {}
unsafe impl Sync for SafeString {}

// Thread-safe value wrapper (JSON-serialized data)
#[derive(Clone, Debug)]
struct SafeValue(String);

impl From<Variant> for SafeValue {
    fn from(v: Variant) -> Self {
        SafeValue(format!("{:?}", v))
    }
}

impl From<SafeValue> for Variant {
    fn from(s: SafeValue) -> Self {
        Variant::from(GString::from(s.0))
    }
}

impl From<String> for SafeValue {
    fn from(s: String) -> Self {
        SafeValue(s)
    }
}

unsafe impl Send for SafeValue {}
unsafe impl Sync for SafeValue {}

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
    /// Main storage using HolyMap for high-performance concurrent access
    storage: HolyMap<SafeString, SafeValue>,

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
    error_log: HolyMap<SafeString, SafeValue>,

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
    active_npc_pool: DashMap<Vec<u8>, RustNPC>,

    /// Inactive NPCs (in pool, ready to spawn)
    /// Key: NPC type -> Vec of inactive NPCs
    inactive_npc_pool: DashMap<String, Vec<RustNPC>>,

    /// PackedScene cache (NPC type -> PackedScene)
    /// Cached to avoid reloading .tscn files repeatedly
    scene_cache: HolyMap<SafeString, SafeValue>,

    /// Scene tree container node (set by GDScript, NPCs are added as children)
    /// This is the Layer4Objects container from the background
    /// Wrapped in Arc<Mutex<>> for thread-safe mutable access
    scene_container: Arc<Mutex<Option<Gd<Node2D>>>>,

    // ============================================================================
    // BYTE-KEYED STORAGE - Efficient storage using ULID bytes as keys
    // ============================================================================

    /// NPC positions (ULID bytes -> "x,y")
    npc_positions: ByteMap,

    /// NPC combat stats (ULID bytes -> value string)
    npc_hp: ByteMap,
    npc_static_state: ByteMap,
    npc_behavioral_state: ByteMap,
    npc_attack: ByteMap,
    npc_defense: ByteMap,
    npc_cooldown: ByteMap,
}

impl NPCDataWarehouse {
    /// Create a new NPCDataWarehouse with the specified sync interval
    pub fn new(sync_interval_ms: u64) -> Self {
        godot_print!("NPCDataWarehouse: Initializing with {}ms sync interval", sync_interval_ms);
        Self {
            storage: HolyMap::new(sync_interval_ms),
            sync_interval_ms,
            combat_event_queue: Arc::new(SegQueue::new()),
            combat_thread_running: Arc::new(AtomicBool::new(false)),
            active_combat_npcs: DashMap::new(),
            error_log: HolyMap::new(sync_interval_ms),
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
            scene_cache: HolyMap::new(sync_interval_ms),
            scene_container: Arc::new(Mutex::new(None)),  // Will be set by GDScript via set_scene_container()

            // Initialize byte-keyed storage
            npc_positions: ByteMap::new(sync_interval_ms),
            npc_hp: ByteMap::new(sync_interval_ms),
            npc_static_state: ByteMap::new(sync_interval_ms),
            npc_behavioral_state: ByteMap::new(sync_interval_ms),
            npc_attack: ByteMap::new(sync_interval_ms),
            npc_defense: ByteMap::new(sync_interval_ms),
            npc_cooldown: ByteMap::new(sync_interval_ms),
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

        let key = SafeString::from(format!("pool:{}", npc_type));
        let value = SafeValue::from(pool_def.to_json());

        self.storage.insert(key, value);
        godot_print!("NPCDataWarehouse: Registered pool '{}' (max: {}, scene: {})",
                     npc_type, max_size, scene_path);
    }

    /// Get pool definition for an NPC type
    pub fn get_pool(&self, npc_type: &str) -> Option<PoolDefinition> {
        let key = SafeString::from(format!("pool:{}", npc_type));
        self.storage.get(&key)
            .and_then(|v| PoolDefinition::from_json(&v.0))
    }

    /// Store active NPC data
    pub fn store_npc(&self, ulid: &str, npc_data: &str) {
        let key = SafeString::from(format!("active:{}", ulid));
        let value = SafeValue::from(npc_data.to_string());
        self.storage.insert(key, value);
    }

    /// Get active NPC data
    pub fn get_npc(&self, ulid: &str) -> Option<String> {
        let key = SafeString::from(format!("active:{}", ulid));
        self.storage.get(&key).map(|v| v.0.clone())
    }

    /// Remove NPC from active pool
    pub fn remove_npc(&self, ulid: &str) -> bool {
        let key = SafeString::from(format!("active:{}", ulid));
        self.storage.remove(&key).is_some()
    }

    /// Store AI state for an NPC
    pub fn store_ai_state(&self, ulid: &str, ai_data: &str) {
        let key = SafeString::from(format!("ai:{}", ulid));
        let value = SafeValue::from(ai_data.to_string());
        self.storage.insert(key, value);
    }

    /// Get AI state for an NPC
    pub fn get_ai_state(&self, ulid: &str) -> Option<String> {
        let key = SafeString::from(format!("ai:{}", ulid));
        self.storage.get(&key).map(|v| v.0.clone())
    }

    /// Store combat state for an NPC
    pub fn store_combat_state(&self, ulid: &str, combat_data: &str) {
        let key = SafeString::from(format!("combat:{}", ulid));
        let value = SafeValue::from(combat_data.to_string());
        self.storage.insert(key, value);
    }

    /// Get combat state for an NPC
    pub fn get_combat_state(&self, ulid: &str) -> Option<String> {
        let key = SafeString::from(format!("combat:{}", ulid));
        self.storage.get(&key).map(|v| v.0.clone())
    }

    // ============================================================================
    // RUST NPC POOL MANAGEMENT - Replaces GDScript pool system
    // ============================================================================

    /// Pre-populate the inactive pool with NPCs of a given type
    /// This loads and instantiates PackedScenes, creating a pool ready for spawning
    pub fn initialize_npc_pool(&self, npc_type: &str, pool_size: usize, scene_path: &str) {
        godot_print!("[RUST POOL] Initializing pool for {} (size: {})", npc_type, pool_size);

        // Cache the PackedScene for this NPC type
        let scene_key = SafeString::from(format!("scene:{}", npc_type));
        let scene_value = SafeValue::from(scene_path.to_string());
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
        if let Ok(mut guard) = self.scene_container.lock() {
            *guard = Some(container);
        } else {
            godot_error!("[RUST POOL] Failed to lock scene_container mutex");
        }
    }

    /// Spawn an NPC from the inactive pool
    /// Returns the ULID bytes of the spawned NPC, or None if pool is empty
    pub fn rust_spawn_npc(&self, npc_type: &str, position: Vector2) -> Option<[u8; 16]> {
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

        // Add NPC to scene tree if container is set
        if let Ok(mut container_guard) = self.scene_container.lock() {
            if let Some(ref mut container) = *container_guard {
                container.add_child(&npc.node);
            } else {
                godot_error!("[RUST POOL] Cannot spawn NPC - scene container not set!");
                return None;
            }
        } else {
            godot_error!("[RUST POOL] Failed to lock scene_container mutex");
            return None;
        }

        // Activate the NPC
        npc.activate(position);

        // Register for combat using the stats extracted during pool initialization
        let npc_stats = npc.stats;
        self.register_npc_with_stats(&ulid, &npc_stats);

        // Store position for combat system using ByteMap (no hex conversion!)
        self.npc_positions.insert_ulid(&ulid, format!("{},{}", position.x, position.y));

        // Move to active pool (use Vec<u8> as key for DashMap compatibility)
        self.active_npc_pool.insert(ulid.to_vec(), npc);

        // Log spawn with first 8 bytes in hex
        let ulid_hex_short = format!("{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
            ulid[0], ulid[1], ulid[2], ulid[3], ulid[4], ulid[5], ulid[6], ulid[7]);
        godot_print!("[RUST POOL] Spawned {} at {:?} with ULID {}", npc_type, position, ulid_hex_short);

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
        if let Ok(mut container_guard) = self.scene_container.lock() {
            if let Some(ref mut container) = *container_guard {
                container.remove_child(&npc.node);
            }
        }

        // Deactivate
        npc.deactivate();

        // Return to inactive pool
        let npc_type = npc.npc_type.clone();
        if let Some(mut pool_entry) = self.inactive_npc_pool.get_mut(&npc_type) {
            pool_entry.push(npc);
            let ulid_hex = ulid.iter().take(8).map(|b| format!("{:02x}", b)).collect::<String>();
            godot_print!("[RUST POOL] Despawned {} (ULID: {})", npc_type, ulid_hex);
            true
        } else {
            godot_error!("[RUST POOL] Cannot return NPC to pool - pool not found for type: {}", npc_type);
            false
        }
    }

    /// Register NPC for combat using pre-extracted Rust stats
    fn register_npc_with_stats(&self, ulid: &[u8; 16], stats: &RustNPCStats) {
        self.register_npc_for_combat_internal(
            ulid,
            stats.static_state,
            0, // behavioral_state (IDLE)
            stats.max_hp,
            stats.attack,
            stats.defense
        );
    }

    /// Check if NPC exists in active pool
    pub fn has_npc(&self, ulid: &str) -> bool {
        let key = SafeString::from(format!("active:{}", ulid));
        self.storage.contains_key(&key)
    }

    /// Get total number of entries in storage
    pub fn total_entries(&self) -> usize {
        self.storage.len()
    }

    /// Get number of entries in read store (Papaya)
    pub fn read_store_count(&self) -> usize {
        self.storage.read_count()
    }

    /// Get number of entries in write store (DashMap)
    pub fn write_store_count(&self) -> usize {
        self.storage.write_count()
    }

    /// Manually trigger sync from write store to read store
    pub fn sync(&self) {
        self.storage.sync();
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
        self.storage.insert(SafeString(key), SafeValue(value));
    }

    /// Get NPC position - public for Arc access (accepts hex ULID for backward compat)
    pub fn get_npc_position_internal(&self, ulid: &str) -> Option<(f32, f32)> {
        // Convert hex string to bytes, then lookup in ByteMap
        let ulid_bytes = hex_to_bytes(ulid).ok()?;
        if let Some(pos_str) = self.npc_positions.get_ulid(&ulid_bytes) {
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
        self.npc_hp.insert_ulid(ulid, max_hp.to_string());
        self.npc_static_state.insert_ulid(ulid, static_state.to_string());
        self.npc_behavioral_state.insert_ulid(ulid, behavioral_state.to_string());
        self.npc_attack.insert_ulid(ulid, attack.to_string());
        self.npc_defense.insert_ulid(ulid, defense.to_string());
        self.npc_cooldown.insert_ulid(ulid, "0".to_string());

        // Still use hex string for active_combat_npcs DashMap (for iteration)
        self.active_combat_npcs.insert(ulid_hex, ());
    }

    /// Unregister NPC from combat (on death/despawn)
    /// Cleans up all combat-related data from HolyMaps
    pub fn unregister_npc_from_combat_internal(&self, ulid: &str) {
        // Remove combat data from storage HolyMap
        self.storage.remove(&SafeString(format!("combat:{}", ulid)));
        self.storage.remove(&SafeString(format!("pos:{}", ulid)));
        self.storage.remove(&SafeString(format!("hp:{}", ulid)));
        self.storage.remove(&SafeString(format!("static_state:{}", ulid)));
        self.storage.remove(&SafeString(format!("behavioral_state:{}", ulid)));
        self.storage.remove(&SafeString(format!("attack:{}", ulid)));
        self.storage.remove(&SafeString(format!("defense:{}", ulid)));
        self.storage.remove(&SafeString(format!("cooldown:{}", ulid)));

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
            self.error_log.remove(&SafeString(format!("{}:{}", error_type, ulid)));
        }

        // Remove from active NPCs set
        self.active_combat_npcs.remove(ulid);
    }

    /// Log error once per error_type:ulid combination using error_log HolyMap
    /// This prevents spam by tracking which errors have been logged
    fn log_error_once(&self, error_type: &str, ulid: &str, message: &str) {
        let key = SafeString(format!("{}:{}", error_type, ulid));

        // Check if we've already logged this error
        if self.error_log.get(&key).is_none() {
            // First time seeing this error - log it and mark as seen
            godot_error!("{}", message);
            self.error_log.insert(key, SafeValue("1".to_string()));
        }
        // If already logged, silently skip (no spam)
    }

    /// Get NPC current HP
    pub fn get_npc_hp_internal(&self, ulid: &str) -> Option<f32> {
        let key = SafeString(format!("hp:{}", ulid));
        if let Some(SafeValue(hp_str)) = self.storage.get(&key) {
            return hp_str.parse::<f32>().ok();
        }
        None
    }

    /// Combat tick - public for Arc access
    /// Called by autonomous thread every 16ms (60fps)
    pub fn tick_combat_internal(&self, _delta: f32) -> Vec<CombatEvent> {
        let mut events = Vec::new();
        let now_ms = Self::get_current_time_ms();

        // 0. INITIAL SPAWN: Check if this is the first tick and spawn minimal entities
        // This must run BEFORE the active_npcs check so NPCs can be spawned
        let initial_spawn_events = self.check_initial_spawn(now_ms);
        events.extend(initial_spawn_events);

        // 1. Get all active NPCs with positions
        let active_npcs = self.get_active_npcs_with_positions();
        if active_npcs.is_empty() {
            // Return early but include any spawn events from initial spawn
            return events;
        }

        // 2. Calculate movement for all NPCs (pursue nearest hostile)
        self.calculate_movement_directions(&active_npcs);

        // 3. Find combat pairs (proximity + hostility checks)
        let combat_pairs = self.find_combat_pairs(&active_npcs);

        // Validation check: Report if no combat despite having NPCs
        if combat_pairs.is_empty() && active_npcs.len() > 1 {
            static mut LAST_WARNING: u64 = 0;
            let now = Self::get_current_time_ms();
            unsafe {
                if now - LAST_WARNING > 5000 {  // Warn every 5 seconds
                    godot_warn!("[COMBAT] {} active NPCs but no combat pairs found - check faction/range settings", active_npcs.len());
                    LAST_WARNING = now;
                }
            }
        }

        if combat_pairs.is_empty() {
            return events; // No combat happening
        }

        // 3. Process each combat pair
        let now_ms = Self::get_current_time_ms();

        for (attacker_ulid, target_ulid, _distance) in combat_pairs {

            // DEFENSIVE: Validate attacker and target are different
            if attacker_ulid == target_ulid {
                self.log_error_once("self_attack", &attacker_ulid,
                    &format!("[COMBAT ERROR] NPC {} is attacking itself! Skipping.", &attacker_ulid[0..8.min(attacker_ulid.len())]));
                continue;
            }

            // DEFENSIVE: Validate both NPCs exist and are alive
            if let Some(attacker_hp) = self.get_stat_value(&attacker_ulid, "hp") {
                if attacker_hp <= 0.0 {
                    self.log_error_once("dead_attacker", &attacker_ulid,
                        &format!("[COMBAT ERROR] Dead attacker {} (HP: {}) trying to attack. Skipping.",
                            &attacker_ulid[0..8.min(attacker_ulid.len())], attacker_hp));
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

                // Calculate damage
                let damage = (attacker_attack - (target_defense / 2.0)).max(1.0);

                // DEBUG: Log damage calculation (only for first 3 attacks)
                static mut DAMAGE_LOG_COUNT: i32 = 0;
                unsafe {
                    if DAMAGE_LOG_COUNT < 3 {
                        godot_print!("[COMBAT DEBUG] Attack: {} -> Defense: {} -> Damage: {}", attacker_attack, target_defense, damage);
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

        // 4. Check if we need to spawn monsters (Rust manages monster spawn timing)
        let monster_spawn_events = self.check_spawn_wave(now_ms);
        events.extend(monster_spawn_events);

        // 5. Check if we need to spawn allies (gradual ramp-up)
        let ally_spawn_events = self.check_ally_spawn(now_ms);
        events.extend(ally_spawn_events);

        events
    }

    /// Calculate movement directions for all NPCs (pursue nearest hostile)
    /// Stores movement direction in HolyMap as "move_dir:ulid" -> "x,y"
    fn calculate_movement_directions(&self, npcs: &[(String, f32, f32, i32, i32, f32, f32, f32)]) {
        for (ulid_a, x_a, y_a, static_state_a, behavioral_state_a, _, _, _) in npcs {
            // Skip if dead
            if (*behavioral_state_a & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            // Skip if PASSIVE
            if (*static_state_a & NPCStaticState::PASSIVE.bits() as i32) != 0 {
                continue;
            }

            let mut nearest_hostile: Option<(f32, f32, f32)> = None; // (x, y, distance)
            let mut nearest_distance = f32::MAX;

            // Find nearest hostile NPC
            for (ulid_b, x_b, y_b, static_state_b, behavioral_state_b, _, _, _) in npcs {
                if ulid_a == ulid_b {
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

            // Calculate waypoint (target position to move toward)
            if let Some((target_x, target_y, distance)) = nearest_hostile {
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
                            self.storage.insert(
                                SafeString(format!("waypoint:{}", ulid_a)),
                                SafeValue(format!("{},{}", clamped_x, clamped_y))
                            );
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

                        self.storage.insert(
                            SafeString(format!("waypoint:{}", ulid_a)),
                            SafeValue(format!("{},{}", clamped_x, clamped_y))
                        );
                    } else {
                        // OPTIMAL RANGE (100-200px) - Stop and shoot
                        self.storage.remove(&SafeString(format!("waypoint:{}", ulid_a)));
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

                        self.storage.insert(
                            SafeString(format!("waypoint:{}", ulid_a)),
                            SafeValue(format!("{},{}", clamped_x, clamped_y))
                        );
                    } else {
                        // In range - stop moving
                        self.storage.remove(&SafeString(format!("waypoint:{}", ulid_a)));
                    }
                }
            } else {
                // No enemies - clear waypoint
                self.storage.remove(&SafeString(format!("waypoint:{}", ulid_a)));
            }
        }
    }

    /// Get all active NPCs with their positions
    /// Returns: Vec<(ulid, x, y, static_state, behavioral_state, hp, attack, defense)>
    fn get_active_npcs_with_positions(&self) -> Vec<(String, f32, f32, i32, i32, f32, f32, f32)> {
        let mut npcs = Vec::new();

        // Iterate over active combat NPCs DashMap
        for entry in self.active_combat_npcs.iter() {
            let ulid = entry.key();

            // Get position
            let pos = self.get_npc_position_internal(ulid);
            if pos.is_none() {
                // DEFENSIVE: Log missing position once per NPC using error_log HolyMap
                self.log_error_once("missing_position", ulid,
                    &format!("[COMBAT ERROR] NPC {} registered for combat but has no position - skipping from combat pairs",
                        &ulid[0..8.min(ulid.len())]));
                continue;
            }
            let (x, y) = pos.unwrap();

            // Get static state (combat type + faction - immutable)
            let static_state = self.get_stat_value(ulid, "static_state")
                .unwrap_or(0.0) as i32;

            // Get behavioral state (IDLE, WALKING, etc. - changes during gameplay)
            let behavioral_state = self.get_stat_value(ulid, "behavioral_state")
                .unwrap_or(0.0) as i32;

            // Skip if dead (check behavioral state for DEAD flag)
            if (behavioral_state & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            // Get combat stats
            let hp = self.get_stat_value(ulid, "hp").unwrap_or(100.0);
            let attack = self.get_stat_value(ulid, "attack").unwrap_or(10.0);
            let defense = self.get_stat_value(ulid, "defense").unwrap_or(5.0);

            npcs.push((ulid.clone(), x, y, static_state, behavioral_state, hp, attack, defense));
        }

        npcs
    }

    /// Find combat pairs based on proximity and faction hostility
    /// Returns: Vec<(attacker_ulid, target_ulid, distance)>
    fn find_combat_pairs(&self, npcs: &[(String, f32, f32, i32, i32, f32, f32, f32)]) -> Vec<(String, String, f32)> {
        let mut pairs = Vec::new();

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

                // If in range, add to pairs (both directions possible)
                if distance <= range_a {
                    // DEFENSIVE: Validate we're not creating self-attack pairs
                    if ulid_a == ulid_b {
                        self.log_error_once("self_attack_pair", ulid_a,
                            &format!("[COMBAT ERROR] Attempted to create self-attack pair for {}", ulid_a));
                    } else {
                        pairs.push((ulid_a.clone(), ulid_b.clone(), distance));
                    }
                }
                if distance <= range_b {
                    // DEFENSIVE: Validate we're not creating self-attack pairs
                    if ulid_a == ulid_b {
                        self.log_error_once("self_attack_pair", ulid_b,
                            &format!("[COMBAT ERROR] Attempted to create self-attack pair for {}", ulid_b));
                    } else {
                        pairs.push((ulid_b.clone(), ulid_a.clone(), distance));
                    }
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

        // Lookup in appropriate ByteMap
        let value_str = match stat_name {
            "hp" => self.npc_hp.get_ulid(&ulid_bytes)?,
            "static_state" => self.npc_static_state.get_ulid(&ulid_bytes)?,
            "behavioral_state" => self.npc_behavioral_state.get_ulid(&ulid_bytes)?,
            "attack" => self.npc_attack.get_ulid(&ulid_bytes)?,
            "defense" => self.npc_defense.get_ulid(&ulid_bytes)?,
            "cooldown" => self.npc_cooldown.get_ulid(&ulid_bytes)?,
            _ => return None,
        };

        value_str.parse::<f32>().ok()
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
            let cooldown_duration_ms = 2000; // 1 attack per 2 seconds (slower combat)
            return now_ms >= (last_attack_ms as u64) + cooldown_duration_ms;
        }
        true // No cooldown record = can attack
    }

    /// Update attack cooldown
    fn update_cooldown(&self, ulid: &str, now_ms: u64) {
        self.storage.insert(
            SafeString(format!("cooldown:{}", ulid)),
            SafeValue(now_ms.to_string())
        );
    }

    /// Apply damage to target, return new HP
    fn apply_damage(&self, target_ulid: &str, damage: f32) -> f32 {
        let current_hp = self.get_stat_value(target_ulid, "hp").unwrap_or(100.0);
        let new_hp = (current_hp - damage).max(0.0);

        self.storage.insert(
            SafeString(format!("hp:{}", target_ulid)),
            SafeValue(new_hp.to_string())
        );

        new_hp
    }

    /// Mark NPC as dead and remove from active combat
    fn mark_dead(&self, ulid: &str) {
        // Set behavioral state to DEAD only (clear all other flags)
        let dead_state = NPCState::DEAD.bits() as i32;
        self.storage.insert(
            SafeString(format!("behavioral_state:{}", ulid)),
            SafeValue(dead_state.to_string())
        );

        // IMPORTANT: Remove from active combat immediately
        // This prevents dead NPCs from being included in combat processing next tick
        self.active_combat_npcs.remove(ulid);
    }

    /// Add ATTACKING state flag (set during attack)
    fn add_attacking_state(&self, ulid: &str) {
        let current = self.get_stat_value(ulid, "behavioral_state").unwrap_or(0.0) as i32;
        let new_state = current | NPCState::ATTACKING.bits() as i32;
        self.storage.insert(
            SafeString(format!("behavioral_state:{}", ulid)),
            SafeValue(new_state.to_string())
        );
    }

    /// Add DAMAGED state flag (set when taking damage)
    fn add_damaged_state(&self, ulid: &str) {
        let current = self.get_stat_value(ulid, "behavioral_state").unwrap_or(0.0) as i32;
        let new_state = current | NPCState::DAMAGED.bits() as i32;
        self.storage.insert(
            SafeString(format!("behavioral_state:{}", ulid)),
            SafeValue(new_state.to_string())
        );
    }

    /// Remove ATTACKING state flag (called by GDScript after attack animation finishes)
    pub fn remove_attacking_state(&self, ulid: &str) {
        let current = self.get_stat_value(ulid, "behavioral_state").unwrap_or(0.0) as i32;
        let new_state = current & !(NPCState::ATTACKING.bits() as i32);
        self.storage.insert(
            SafeString(format!("behavioral_state:{}", ulid)),
            SafeValue(new_state.to_string())
        );
    }

    /// Remove DAMAGED state flag (called by GDScript after hurt animation finishes)
    pub fn remove_damaged_state(&self, ulid: &str) {
        let current = self.get_stat_value(ulid, "behavioral_state").unwrap_or(0.0) as i32;
        let new_state = current & !(NPCState::DAMAGED.bits() as i32);
        self.storage.insert(
            SafeString(format!("behavioral_state:{}", ulid)),
            SafeValue(new_state.to_string())
        );
    }

    /// Check if this is the first combat tick and spawn minimal entities for debugging
    /// Spawns: 1 warrior, 1 archer, 2 random monsters
    fn check_initial_spawn(&self, now_ms: u64) -> Vec<CombatEvent> {
        use std::sync::atomic::Ordering;

        // Check if initial spawn already done
        if self.initial_spawn_done.load(Ordering::Relaxed) {
            return Vec::new(); // Already spawned
        }

        // Check if scene container is set (required for spawning)
        {
            if let Ok(container_guard) = self.scene_container.lock() {
                if container_guard.is_none() {
                    // Container not set yet - likely still in title/intro scene
                    // Don't mark as done, just skip this tick
                    return Vec::new();
                }
            } else {
                return Vec::new();
            }
        }

        // Mark initial spawn as done
        self.initial_spawn_done.store(true, Ordering::Relaxed);

        // Set the timers so regular spawning doesn't trigger immediately
        self.last_spawn_time_ms.store(now_ms, Ordering::Relaxed);
        self.last_ally_spawn_time_ms.store(now_ms, Ordering::Relaxed);

        godot_print!("[RUST SPAWN] Initial spawn starting...");

        // Calculate spawn positions
        let world_min_x = f32::from_bits(self.world_min_x.load(Ordering::Relaxed));
        let world_max_x = f32::from_bits(self.world_max_x.load(Ordering::Relaxed));
        let world_min_y = f32::from_bits(self.world_min_y.load(Ordering::Relaxed));
        let world_max_y = f32::from_bits(self.world_max_y.load(Ordering::Relaxed));

        // Spawn 1 warrior on left side
        let warrior_pos = Vector2::new(world_min_x + 50.0, (world_min_y + world_max_y) / 2.0);
        if let Some(ulid) = self.rust_spawn_npc("warrior", warrior_pos) {
            // Register warrior for combat
            self.register_npc_for_combat_internal(
                &ulid,
                (NPCStaticState::MELEE | NPCStaticState::ALLY).bits() as i32,
                NPCState::IDLE.bits() as i32,
                100.0, // max_hp
                15.0,  // attack
                10.0,  // defense
            );
        }

        // Spawn 1 archer on left side
        let archer_pos = Vector2::new(world_min_x + 100.0, (world_min_y + world_max_y) / 2.0 + 20.0);
        if let Some(ulid) = self.rust_spawn_npc("archer", archer_pos) {
            // Register archer for combat
            self.register_npc_for_combat_internal(
                &ulid,
                (NPCStaticState::RANGED | NPCStaticState::ALLY).bits() as i32,
                NPCState::IDLE.bits() as i32,
                80.0,  // max_hp
                20.0,  // attack
                5.0,   // defense
            );
        }

        // Spawn 2 random monsters on right side
        use rand::Rng;
        let mut rng = rand::rng();
        let monster_types = vec!["goblin", "mushroom", "skeleton", "eyebeast"];

        for i in 0..2 {
            let monster_type = monster_types[rng.random_range(0..monster_types.len())];
            let monster_pos = Vector2::new(
                world_max_x - 50.0,
                world_min_y + ((i as f32 + 1.0) * (world_max_y - world_min_y) / 3.0)
            );

            if let Some(ulid) = self.rust_spawn_npc(monster_type, monster_pos) {
                // Register monster for combat
                self.register_npc_for_combat_internal(
                    &ulid,
                    (NPCStaticState::MELEE | NPCStaticState::MONSTER).bits() as i32,
                    NPCState::IDLE.bits() as i32,
                    60.0,  // max_hp
                    12.0,  // attack
                    8.0,   // defense
                );
            }
        }

        godot_print!("[RUST SPAWN] Initial spawn complete: 1 warrior, 1 archer, 2 random monsters");

        Vec::new() // No events needed - NPCs are spawned directly
    }

    /// Check if we should spawn a new wave of monsters
    /// Returns spawn events for GDScript to handle
    fn check_spawn_wave(&self, now_ms: u64) -> Vec<CombatEvent> {
        use std::sync::atomic::Ordering;
        let events = Vec::new();

        // Check if scene container is set (required for spawning)
        {
            if let Ok(container_guard) = self.scene_container.lock() {
                if container_guard.is_none() {
                    return events; // Container not set yet
                }
            } else {
                return events;
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

            // Spawn each monster directly
            for _ in 0..wave_size {
                let monster_type = monster_types[rng.random_range(0..monster_types.len())];
                let spawn_pos = Vector2::new(
                    world_max_x - 50.0,
                    rng.random_range(world_min_y..world_max_y)
                );

                if let Some(ulid) = self.rust_spawn_npc(monster_type, spawn_pos) {
                    // Register for combat
                    self.register_npc_for_combat_internal(
                        &ulid,
                        (NPCStaticState::MELEE | NPCStaticState::MONSTER).bits() as i32,
                        NPCState::IDLE.bits() as i32,
                        60.0, // max_hp
                        12.0, // attack
                        8.0,  // defense
                    );
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
            if let Ok(container_guard) = self.scene_container.lock() {
                if container_guard.is_none() {
                    return events; // Container not set yet
                }
            } else {
                return events;
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

            // Spawn ally on left side
            use rand::Rng;
            let mut rng = rand::rng();
            let spawn_pos = Vector2::new(
                world_min_x + 50.0,
                rng.random_range(world_min_y..world_max_y)
            );

            if let Some(ulid) = self.rust_spawn_npc(ally_type, spawn_pos) {
                // Register for combat
                let (static_state, max_hp, attack, defense) = if ally_type == "warrior" {
                    (
                        (NPCStaticState::MELEE | NPCStaticState::ALLY).bits() as i32,
                        100.0, // max_hp
                        15.0,  // attack
                        10.0,  // defense
                    )
                } else {
                    // archer
                    (
                        (NPCStaticState::RANGED | NPCStaticState::ALLY).bits() as i32,
                        80.0,  // max_hp
                        20.0,  // attack
                        5.0,   // defense
                    )
                };

                self.register_npc_for_combat_internal(
                    &ulid,
                    static_state,
                    NPCState::IDLE.bits() as i32,
                    max_hp,
                    attack,
                    defense,
                );

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
        match packed_bytes_to_hex(&ulid_bytes) {
            Ok(ulid_hex) => {
                let key = SafeString(format!("waypoint:{}", ulid_hex));
                if let Some(SafeValue(pos_str)) = self.warehouse.storage.get(&key) {
                    if let Some((x_str, y_str)) = pos_str.split_once(',') {
                        if let (Ok(x), Ok(y)) = (x_str.parse::<f32>(), y_str.parse::<f32>()) {
                            return PackedFloat32Array::from(&[x, y]);
                        }
                    }
                }
                // No waypoint - return empty array
                PackedFloat32Array::new()
            }
            Err(_) => PackedFloat32Array::new()
        }
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
    #[func]
    pub fn get_npc_position(&self, ulid: GString) -> PackedFloat32Array {
        if let Some((x, y)) = self.warehouse.get_npc_position_internal(&ulid.to_string()) {
            let mut arr = PackedFloat32Array::new();
            arr.push(x);
            arr.push(y);
            arr
        } else {
            PackedFloat32Array::new()
        }
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
