use godot::prelude::*;
use crate::holymap::HolyMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};
use bitflags::bitflags;
use crossbeam_queue::SegQueue;
use dashmap::DashMap;
use serde::{Deserialize, Serialize};

// NPCState bitflags - matches GDScript NPCManager.NPCState enum
bitflags! {
    /// NPC state flags - supports bitwise operations for complex state management
    ///
    /// Matches the GDScript NPCState enum in npc_manager.gd
    /// Each NPC can have multiple states combined via bitwise OR
    ///
    /// Example: IDLE | MELEE | ALLY (idle melee ally unit)
    ///          WALKING | RANGED | MONSTER (moving ranged monster)
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
    pub struct NPCState: u32 {
        // Behavioral States (0-10)
        const IDLE       = 1 << 0;   // 1:      Idle (not moving, not attacking)
        const WALKING    = 1 << 1;   // 2:      Walking/moving
        const ATTACKING  = 1 << 2;   // 4:      Currently attacking (animation playing)
        const WANDERING  = 1 << 3;   // 8:      Normal wandering/idle behavior (no combat)
        const COMBAT     = 1 << 4;   // 16:     Engaged in combat
        const RETREATING = 1 << 5;   // 32:     Retreating from enemy (archer kiting)
        const PURSUING   = 1 << 6;   // 64:     Moving towards enemy
        const HURT       = 1 << 7;   // 128:    Low health - triggers defensive behavior
        const DAMAGED    = 1 << 8;   // 256:    Taking damage - plays hurt/damage animation
        const DEAD       = 1 << 9;   // 512:    Dead - plays death animation
        const SPAWN      = 1 << 10;  // 1024:   Just spawned - routing to safe zone

        // Combat Types (11-14) - Each NPC has exactly ONE combat type
        const MELEE      = 1 << 11;  // 2048:   Melee attacker (warriors, knights, goblins)
        const RANGED     = 1 << 12;  // 4096:   Ranged attacker (archers, crossbowmen)
        const MAGIC      = 1 << 13;  // 8192:   Magic attacker (mages, wizards)
        const HEALER     = 1 << 14;  // 16384:  Healer/support (clerics, druids)

        // Factions (15-17) - Determines who can attack whom
        const ALLY       = 1 << 15;  // 32768:  Player's allies - don't attack each other
        const MONSTER    = 1 << 16;  // 65536:  Hostile creatures - attack allies
        const PASSIVE    = 1 << 17;  // 131072: Doesn't attack/do damage (chickens, critters)

        // Waypoint
        const WAYPOINT   = 1 << 18;  // 262144: Following waypoint path
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

/// ULID wrapper for binary storage (16 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct UlidBytes([u8; 16]);

impl UlidBytes {
    /// Create from ulid crate's Ulid
    pub fn from_ulid(ulid: ulid::Ulid) -> Self {
        UlidBytes(ulid.to_bytes())
    }

    /// Convert to ulid crate's Ulid
    pub fn to_ulid(&self) -> ulid::Ulid {
        ulid::Ulid::from_bytes(self.0)
    }

    /// Convert to hex string for GDScript
    pub fn to_hex_string(&self) -> String {
        self.to_ulid().to_string()
    }

    /// Parse from hex string (from GDScript)
    pub fn from_hex_string(hex: &str) -> Result<Self, String> {
        ulid::Ulid::from_string(hex)
            .map(|ulid| UlidBytes(ulid.to_bytes()))
            .map_err(|e| format!("Invalid ULID: {}", e))
    }

    /// Get raw bytes
    pub fn as_bytes(&self) -> &[u8; 16] {
        &self.0
    }
}

// Thread-safe for HolyMap
unsafe impl Send for UlidBytes {}
unsafe impl Sync for UlidBytes {}

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
        let key = format!("pos:{}", ulid);
        let value = format!("{},{}", x, y);
        self.storage.insert(SafeString(key), SafeValue(value));
    }

    /// Get NPC position - public for Arc access
    pub fn get_npc_position_internal(&self, ulid: &str) -> Option<(f32, f32)> {
        let key = format!("pos:{}", ulid);
        if let Some(SafeValue(pos_str)) = self.storage.get(&SafeString(key)) {
            let parts: Vec<&str> = pos_str.split(',').collect();
            if parts.len() == 2 {
                if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
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
    /// Stores combat-relevant data in HolyMap for autonomous thread access
    pub fn register_npc_for_combat_internal(
        &self,
        ulid: &str,
        initial_state: i32,
        max_hp: f32,
        attack: f32,
        defense: f32,
    ) {
        // Mark as active in combat system
        self.storage.insert(
            SafeString(format!("combat:{}", ulid)),
            SafeValue("active".to_string())
        );

        // Store HP
        self.storage.insert(
            SafeString(format!("hp:{}", ulid)),
            SafeValue(max_hp.to_string())
        );

        // Store state flags
        self.storage.insert(
            SafeString(format!("state:{}", ulid)),
            SafeValue(initial_state.to_string())
        );

        // Store attack stat
        self.storage.insert(
            SafeString(format!("attack:{}", ulid)),
            SafeValue(attack.to_string())
        );

        // Store defense stat
        self.storage.insert(
            SafeString(format!("defense:{}", ulid)),
            SafeValue(defense.to_string())
        );

        // Initialize cooldown to 0 (can attack immediately)
        self.storage.insert(
            SafeString(format!("cooldown:{}", ulid)),
            SafeValue("0".to_string())
        );

        // Add to active NPCs set for combat thread iteration
        self.active_combat_npcs.insert(ulid.to_string(), ());
    }

    /// Unregister NPC from combat (on death/despawn)
    /// Cleans up all combat-related data from HolyMap
    pub fn unregister_npc_from_combat_internal(&self, ulid: &str) {
        self.storage.remove(&SafeString(format!("combat:{}", ulid)));
        self.storage.remove(&SafeString(format!("pos:{}", ulid)));
        self.storage.remove(&SafeString(format!("hp:{}", ulid)));
        self.storage.remove(&SafeString(format!("state:{}", ulid)));
        self.storage.remove(&SafeString(format!("attack:{}", ulid)));
        self.storage.remove(&SafeString(format!("defense:{}", ulid)));
        self.storage.remove(&SafeString(format!("cooldown:{}", ulid)));

        // Remove from active NPCs set
        self.active_combat_npcs.remove(ulid);
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

        // 1. Get all active NPCs with positions
        let active_npcs = self.get_active_npcs_with_positions();
        if active_npcs.is_empty() {
            return events; // No NPCs in combat
        }

        // 2. Find combat pairs (proximity + hostility checks)
        let combat_pairs = self.find_combat_pairs(&active_npcs);
        if combat_pairs.is_empty() {
            return events; // No combat happening
        }

        // 3. Process each combat pair
        let now_ms = Self::get_current_time_ms();

        for (attacker_ulid, target_ulid, _distance) in combat_pairs {
            // Check cooldown
            if !self.check_attack_cooldown(&attacker_ulid, now_ms) {
                continue; // Still on cooldown
            }

            // Get attacker and target stats
            let attacker_attack = self.get_stat_value(&attacker_ulid, "attack").unwrap_or(10.0);
            let target_defense = self.get_stat_value(&target_ulid, "defense").unwrap_or(5.0);

            // Calculate damage
            let damage = (attacker_attack - (target_defense / 2.0)).max(1.0);

            // Apply damage and get new HP
            let target_hp = self.apply_damage(&target_ulid, damage);

            // Update attacker cooldown
            self.update_cooldown(&attacker_ulid, now_ms);

            // Get target position for VFX
            let (target_x, target_y) = self.get_npc_position_internal(&target_ulid)
                .unwrap_or((0.0, 0.0));

            // Generate attack event
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

            // Generate damage/death event
            let target_animation = if target_hp <= 0.0 {
                "death".to_string()
            } else {
                "hurt".to_string()
            };

            events.push(CombatEvent {
                event_type: if target_hp <= 0.0 { "death" } else { "damage" }.to_string(),
                attacker_ulid,
                target_ulid: target_ulid.clone(),
                amount: damage,
                attacker_animation: "".to_string(),
                target_animation,
                target_x,
                target_y,
            });

            // Mark target as dead if HP <= 0
            if target_hp <= 0.0 {
                self.mark_dead(&target_ulid);
            }
        }

        events
    }

    /// Get all active NPCs with their positions
    /// Returns: Vec<(ulid, x, y, state, hp, attack, defense)>
    fn get_active_npcs_with_positions(&self) -> Vec<(String, f32, f32, i32, f32, f32, f32)> {
        let mut npcs = Vec::new();

        // Iterate over active combat NPCs DashMap
        for entry in self.active_combat_npcs.iter() {
            let ulid = entry.key();

            // Get position
            let pos = self.get_npc_position_internal(ulid);
            if pos.is_none() {
                continue; // No position yet, skip
            }
            let (x, y) = pos.unwrap();

            // Get state
            let state = self.get_stat_value(ulid, "state")
                .unwrap_or(0.0) as i32;

            // Skip if dead
            if (state & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            // Get combat stats
            let hp = self.get_stat_value(ulid, "hp").unwrap_or(100.0);
            let attack = self.get_stat_value(ulid, "attack").unwrap_or(10.0);
            let defense = self.get_stat_value(ulid, "defense").unwrap_or(5.0);

            npcs.push((ulid.clone(), x, y, state, hp, attack, defense));
        }

        npcs
    }

    /// Find combat pairs based on proximity and faction hostility
    /// Returns: Vec<(attacker_ulid, target_ulid, distance)>
    fn find_combat_pairs(&self, npcs: &[(String, f32, f32, i32, f32, f32, f32)]) -> Vec<(String, String, f32)> {
        let mut pairs = Vec::new();

        for i in 0..npcs.len() {
            let (ulid_a, x_a, y_a, state_a, _, _, _) = &npcs[i];

            // Skip if dead
            if (*state_a & NPCState::DEAD.bits() as i32) != 0 {
                continue;
            }

            for j in (i + 1)..npcs.len() {
                let (ulid_b, x_b, y_b, state_b, _, _, _) = &npcs[j];

                // Skip if dead
                if (*state_b & NPCState::DEAD.bits() as i32) != 0 {
                    continue;
                }

                // Check if hostile factions
                if !Self::are_factions_hostile(*state_a, *state_b) {
                    continue;
                }

                // Calculate distance
                let distance = Self::distance(*x_a, *y_a, *x_b, *y_b);

                // Get attack range based on combat type
                let range_a = Self::get_attack_range(*state_a);
                let range_b = Self::get_attack_range(*state_b);

                // If in range, add to pairs (both directions possible)
                if distance <= range_a {
                    pairs.push((ulid_a.clone(), ulid_b.clone(), distance));
                }
                if distance <= range_b {
                    pairs.push((ulid_b.clone(), ulid_a.clone(), distance));
                }
            }
        }

        pairs
    }

    /// Check if two faction states are hostile
    fn are_factions_hostile(state1: i32, state2: i32) -> bool {
        let ally1 = (state1 & NPCState::ALLY.bits() as i32) != 0;
        let monster1 = (state1 & NPCState::MONSTER.bits() as i32) != 0;
        let passive1 = (state1 & NPCState::PASSIVE.bits() as i32) != 0;

        let ally2 = (state2 & NPCState::ALLY.bits() as i32) != 0;
        let monster2 = (state2 & NPCState::MONSTER.bits() as i32) != 0;
        let passive2 = (state2 & NPCState::PASSIVE.bits() as i32) != 0;

        // Passive never hostile
        if passive1 || passive2 {
            return false;
        }

        // Ally vs Monster = hostile
        (ally1 && monster2) || (monster1 && ally2)
    }

    /// Get attack range based on combat type
    fn get_attack_range(state: i32) -> f32 {
        if (state & NPCState::MELEE.bits() as i32) != 0 {
            50.0 // Melee range
        } else if (state & NPCState::RANGED.bits() as i32) != 0 {
            200.0 // Ranged range
        } else if (state & NPCState::MAGIC.bits() as i32) != 0 {
            150.0 // Magic range
        } else {
            50.0 // Default
        }
    }

    /// Helper to get stat value from HolyMap
    fn get_stat_value(&self, ulid: &str, stat_name: &str) -> Option<f32> {
        let key = SafeString(format!("{}:{}", stat_name, ulid));
        if let Some(SafeValue(value_str)) = self.storage.get(&key) {
            return value_str.parse::<f32>().ok();
        }
        None
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
            let cooldown_duration_ms = 1000; // 1 attack per second
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

    /// Mark NPC as dead
    fn mark_dead(&self, ulid: &str) {
        if let Some(state) = self.get_stat_value(ulid, "state") {
            let mut state_i32 = state as i32;
            state_i32 |= NPCState::DEAD.bits() as i32;
            self.storage.insert(
                SafeString(format!("state:{}", ulid)),
                SafeValue(state_i32.to_string())
            );
        }
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

    // ===== NPCState Bitflag Helper Methods =====
    // These expose NPCState bitflag constants and operations to GDScript

    /// Get NPCState constant value by name
    /// Usage in GDScript: NPCDataWarehouse.get_state("IDLE") returns 1
    #[func]
    pub fn get_state(&self, state_name: GString) -> i32 {
        match state_name.to_string().to_uppercase().as_str() {
            "IDLE" => NPCState::IDLE.to_i32(),
            "WALKING" => NPCState::WALKING.to_i32(),
            "ATTACKING" => NPCState::ATTACKING.to_i32(),
            "WANDERING" => NPCState::WANDERING.to_i32(),
            "COMBAT" => NPCState::COMBAT.to_i32(),
            "RETREATING" => NPCState::RETREATING.to_i32(),
            "PURSUING" => NPCState::PURSUING.to_i32(),
            "HURT" => NPCState::HURT.to_i32(),
            "DAMAGED" => NPCState::DAMAGED.to_i32(),
            "DEAD" => NPCState::DEAD.to_i32(),
            "SPAWN" => NPCState::SPAWN.to_i32(),
            "MELEE" => NPCState::MELEE.to_i32(),
            "RANGED" => NPCState::RANGED.to_i32(),
            "MAGIC" => NPCState::MAGIC.to_i32(),
            "HEALER" => NPCState::HEALER.to_i32(),
            "ALLY" => NPCState::ALLY.to_i32(),
            "MONSTER" => NPCState::MONSTER.to_i32(),
            "PASSIVE" => NPCState::PASSIVE.to_i32(),
            "WAYPOINT" => NPCState::WAYPOINT.to_i32(),
            _ => 0,
        }
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

    /// Get a human-readable string representation of a state
    /// Usage: NPCDataWarehouse.state_to_string(npc_state) returns "IDLE | MELEE | ALLY"
    #[func]
    pub fn state_to_string(&self, state: i32) -> GString {
        let npc_state = NPCState::from_i32_or_idle(state);
        let mut parts = Vec::new();

        // Behavioral states
        if npc_state.contains(NPCState::IDLE) { parts.push("IDLE"); }
        if npc_state.contains(NPCState::WALKING) { parts.push("WALKING"); }
        if npc_state.contains(NPCState::ATTACKING) { parts.push("ATTACKING"); }
        if npc_state.contains(NPCState::WANDERING) { parts.push("WANDERING"); }
        if npc_state.contains(NPCState::COMBAT) { parts.push("COMBAT"); }
        if npc_state.contains(NPCState::RETREATING) { parts.push("RETREATING"); }
        if npc_state.contains(NPCState::PURSUING) { parts.push("PURSUING"); }
        if npc_state.contains(NPCState::HURT) { parts.push("HURT"); }
        if npc_state.contains(NPCState::DAMAGED) { parts.push("DAMAGED"); }
        if npc_state.contains(NPCState::DEAD) { parts.push("DEAD"); }
        if npc_state.contains(NPCState::SPAWN) { parts.push("SPAWN"); }

        // Combat types
        if npc_state.contains(NPCState::MELEE) { parts.push("MELEE"); }
        if npc_state.contains(NPCState::RANGED) { parts.push("RANGED"); }
        if npc_state.contains(NPCState::MAGIC) { parts.push("MAGIC"); }
        if npc_state.contains(NPCState::HEALER) { parts.push("HEALER"); }

        // Factions
        if npc_state.contains(NPCState::ALLY) { parts.push("ALLY"); }
        if npc_state.contains(NPCState::MONSTER) { parts.push("MONSTER"); }
        if npc_state.contains(NPCState::PASSIVE) { parts.push("PASSIVE"); }

        // Waypoint
        if npc_state.contains(NPCState::WAYPOINT) { parts.push("WAYPOINT"); }

        GString::from(parts.join(" | "))
    }

    // ===== ULID Generation (Binary Format) =====

    /// Generate a new ULID as raw bytes (16 bytes / 128 bits)
    /// Returns PackedByteArray for maximum performance - zero allocations!
    /// Usage: var ulid_bytes = NPCDataWarehouse.generate_ulid_bytes()
    #[func]
    pub fn generate_ulid_bytes(&self) -> PackedByteArray {
        let ulid = ulid::Ulid::new();
        let bytes = ulid.to_bytes();
        PackedByteArray::from(&bytes[..])
    }

    /// Generate a new ULID as hex string (for backwards compatibility)
    /// Usage: var ulid = NPCDataWarehouse.generate_ulid()
    #[func]
    pub fn generate_ulid(&self) -> GString {
        let ulid = ulid::Ulid::new();
        GString::from(ulid.to_string())
    }

    /// Convert ULID bytes to hex string
    /// Usage: var hex = NPCDataWarehouse.ulid_bytes_to_hex(ulid_bytes)
    #[func]
    pub fn ulid_bytes_to_hex(&self, bytes: PackedByteArray) -> GString {
        if bytes.len() != 16 {
            return GString::from("");
        }
        let mut ulid_bytes = [0u8; 16];
        ulid_bytes.copy_from_slice(&bytes.to_vec());
        let ulid = ulid::Ulid::from_bytes(ulid_bytes);
        GString::from(ulid.to_string())
    }

    /// Convert hex string to ULID bytes
    /// Usage: var bytes = NPCDataWarehouse.ulid_hex_to_bytes(hex_string)
    #[func]
    pub fn ulid_hex_to_bytes(&self, hex: GString) -> PackedByteArray {
        match ulid::Ulid::from_string(&hex.to_string()) {
            Ok(ulid) => {
                let bytes = ulid.to_bytes();
                PackedByteArray::from(&bytes[..])
            }
            Err(_) => PackedByteArray::new()
        }
    }

    /// Parse and validate a ULID string
    /// Returns true if valid, false otherwise
    #[func]
    pub fn validate_ulid(&self, ulid: GString) -> bool {
        ulid::Ulid::from_string(&ulid.to_string()).is_ok()
    }

    // ===== COMBAT LOGIC (Rust-side for maximum performance) =====

    /// Calculate damage dealt by attacker to victim
    /// Returns final damage after defense calculation
    #[func]
    pub fn calculate_damage(&self, attacker_attack: f32, victim_defense: f32) -> f32 {
        // Simple formula: damage = attack - (defense / 2)
        // Minimum damage is 1
        let damage = attacker_attack - (victim_defense / 2.0);
        damage.max(1.0)
    }

    /// Check if two NPCs are hostile to each other based on faction flags
    /// Returns true if they should fight
    #[func]
    pub fn are_hostile(&self, state1: i32, state2: i32) -> bool {
        let npc1_state = NPCState::from_i32_or_idle(state1);
        let npc2_state = NPCState::from_i32_or_idle(state2);

        // Passive NPCs never fight
        if npc1_state.contains(NPCState::PASSIVE) || npc2_state.contains(NPCState::PASSIVE) {
            return false;
        }

        // Allies vs Monsters are hostile
        let npc1_is_ally = npc1_state.contains(NPCState::ALLY);
        let npc1_is_monster = npc1_state.contains(NPCState::MONSTER);
        let npc2_is_ally = npc2_state.contains(NPCState::ALLY);
        let npc2_is_monster = npc2_state.contains(NPCState::MONSTER);

        (npc1_is_ally && npc2_is_monster) || (npc1_is_monster && npc2_is_ally)
    }

    /// Check if NPC can attack based on state flags
    /// Returns true if NPC is in a valid attacking state
    #[func]
    pub fn can_attack(&self, state: i32) -> bool {
        let npc_state = NPCState::from_i32_or_idle(state);

        // Can't attack if dead or passive
        if npc_state.contains(NPCState::DEAD) || npc_state.contains(NPCState::PASSIVE) {
            return false;
        }

        // Can attack if in combat and has a combat type
        let has_combat_type = npc_state.contains(NPCState::MELEE)
            || npc_state.contains(NPCState::RANGED)
            || npc_state.contains(NPCState::MAGIC)
            || npc_state.contains(NPCState::HEALER);

        has_combat_type
    }

    /// Get combat type from state flags (MELEE, RANGED, MAGIC, or HEALER)
    /// Returns the combat type flag value, or 0 if none
    #[func]
    pub fn get_combat_type(&self, state: i32) -> i32 {
        let npc_state = NPCState::from_i32_or_idle(state);

        if npc_state.contains(NPCState::MELEE) {
            return NPCState::MELEE.to_i32();
        }
        if npc_state.contains(NPCState::RANGED) {
            return NPCState::RANGED.to_i32();
        }
        if npc_state.contains(NPCState::MAGIC) {
            return NPCState::MAGIC.to_i32();
        }
        if npc_state.contains(NPCState::HEALER) {
            return NPCState::HEALER.to_i32();
        }
        0
    }

    /// Check if NPC is in combat (has COMBAT or ATTACKING flag)
    #[func]
    pub fn is_in_combat(&self, state: i32) -> bool {
        let npc_state = NPCState::from_i32_or_idle(state);
        npc_state.contains(NPCState::COMBAT) || npc_state.contains(NPCState::ATTACKING)
    }

    // ============================================================================
    // RUST-FIRST COMBAT SYSTEM - GDScript Wrapper Methods
    // ============================================================================

    /// Update NPC position (called from GDScript each frame)
    #[func]
    pub fn update_npc_position(&self, ulid: GString, x: f32, y: f32) {
        self.warehouse.as_ref().update_npc_position_internal(&ulid.to_string(), x, y);
    }

    /// Get NPC position - returns PackedFloat32Array [x, y] or empty if not found
    #[func]
    pub fn get_npc_position(&self, ulid: GString) -> PackedFloat32Array {
        if let Some((x, y)) = self.warehouse.as_ref().get_npc_position_internal(&ulid.to_string()) {
            return PackedFloat32Array::from(&[x, y][..]);
        }
        PackedFloat32Array::new()
    }

    /// Combat tick - processes all combat logic and returns JSON event array
    ///
    /// Call this once per frame from GDScript. Returns Array of JSON strings (CombatEvents).
    /// GDScript parses events and handles visual presentation.
    #[func]
    pub fn tick_combat(&self, delta: f32) -> Array<GString> {
        let events = self.warehouse.as_ref().tick_combat_internal(delta);

        // Convert Vec<CombatEvent> to Array<GString>
        let events_array: Array<GString> = events
            .into_iter()
            .map(|event| GString::from(event.to_json()))
            .collect();

        events_array
    }

    // ============================================================================
    // COMBAT THREAD CONTROL (GDScript API)
    // ============================================================================

    /// Start autonomous combat thread
    /// Thread runs at 60fps independently, processing combat logic
    #[func]
    pub fn start_combat_system(&self) {
        self.warehouse.start_combat_thread();
    }

    /// Stop combat thread gracefully
    #[func]
    pub fn stop_combat_system(&self) {
        self.warehouse.as_ref().stop_combat_thread();
    }

    /// Poll combat events from autonomous thread
    /// Returns Array of JSON strings (CombatEvent)
    /// Call this once per frame from GDScript to drain event queue
    #[func]
    pub fn poll_combat_events(&self) -> Array<GString> {
        let mut events_array = Array::new();

        // Drain queue until empty (lock-free)
        while let Some(event) = self.warehouse.as_ref().combat_event_queue.pop() {
            events_array.push(&GString::from(event.to_json()));
        }

        events_array
    }

    // ============================================================================
    // COMBAT REGISTRATION (GDScript API)
    // ============================================================================

    /// Register NPC for combat system
    /// Call this when NPC spawns - stores combat data in Rust HolyMap
    #[func]
    pub fn register_npc_for_combat(
        &self,
        ulid: GString,
        initial_state: i32,
        max_hp: f32,
        attack: f32,
        defense: f32,
    ) {
        self.warehouse.as_ref().register_npc_for_combat_internal(
            &ulid.to_string(),
            initial_state,
            max_hp,
            attack,
            defense,
        );
    }

    /// Unregister NPC from combat system
    /// Call this when NPC despawns or dies - cleans up combat data
    #[func]
    pub fn unregister_npc_from_combat(&self, ulid: GString) {
        self.warehouse.as_ref().unregister_npc_from_combat_internal(&ulid.to_string());
    }

    /// Get NPC current HP
    /// Returns current HP or 0.0 if not found
    #[func]
    pub fn get_npc_hp(&self, ulid: GString) -> f32 {
        self.warehouse.as_ref()
            .get_npc_hp_internal(&ulid.to_string())
            .unwrap_or(0.0)
    }

    // ============================================================================
    // STATE TRANSITION METHODS
    // ============================================================================

    /// Transition state to combat mode (add COMBAT flag, remove WANDERING/IDLE)
    /// Returns new state value
    #[func]
    pub fn enter_combat_state(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);

        // Remove peaceful states
        state.remove(NPCState::IDLE);
        state.remove(NPCState::WANDERING);

        // Add combat state
        state.insert(NPCState::COMBAT);

        state.to_i32()
    }

    /// Transition state to idle mode (remove combat flags)
    /// Returns new state value
    #[func]
    pub fn exit_combat_state(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);

        // Remove combat states
        state.remove(NPCState::COMBAT);
        state.remove(NPCState::ATTACKING);
        state.remove(NPCState::PURSUING);
        state.remove(NPCState::RETREATING);
        state.remove(NPCState::WALKING);

        // Check if monster - monsters return to wandering, allies to idle
        if state.contains(NPCState::MONSTER) {
            state.insert(NPCState::WANDERING);
        } else {
            state.insert(NPCState::IDLE);
        }

        state.to_i32()
    }

    /// Start attacking animation (add ATTACKING flag, keep COMBAT)
    /// Returns new state value
    #[func]
    pub fn start_attack(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);
        state.insert(NPCState::ATTACKING);
        state.remove(NPCState::WALKING);
        state.remove(NPCState::IDLE);
        state.to_i32()
    }

    /// Stop attacking animation (remove ATTACKING flag)
    /// Returns new state value
    #[func]
    pub fn stop_attack(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);
        state.remove(NPCState::ATTACKING);
        state.to_i32()
    }

    // ===== AI STATE TRANSITIONS =====

    /// Start walking (add WALKING flag, remove IDLE)
    /// Returns new state value
    #[func]
    pub fn start_walking(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);
        state.insert(NPCState::WALKING);
        state.remove(NPCState::IDLE);
        state.to_i32()
    }

    /// Stop walking (remove WALKING flag, add IDLE)
    /// Returns new state value
    #[func]
    pub fn stop_walking(&self, current_state: i32) -> i32 {
        let mut state = NPCState::from_i32_or_idle(current_state);
        state.remove(NPCState::WALKING);
        state.insert(NPCState::IDLE);
        state.to_i32()
    }

    /// Mark NPC as dead (set DEAD flag, remove all other behavioral flags)
    /// Returns new state value
    #[func]
    pub fn mark_dead(&self, current_state: i32) -> i32 {
        let state = NPCState::from_i32_or_idle(current_state);

        // Keep only faction and combat type, remove all behavioral states
        let preserved = state.bits() & (
            NPCState::MELEE.bits() |
            NPCState::RANGED.bits() |
            NPCState::MAGIC.bits() |
            NPCState::HEALER.bits() |
            NPCState::ALLY.bits() |
            NPCState::MONSTER.bits() |
            NPCState::PASSIVE.bits()
        );

        // Add DEAD flag
        (preserved | NPCState::DEAD.bits()) as i32
    }
}

