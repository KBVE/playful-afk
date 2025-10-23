# Rust Autonomous Combat System - Implementation Plan

## Overview

This document outlines the implementation of a **bi-directional autonomous combat system** where:
- **Rust owns ALL combat logic** (damage, HP, cooldowns, state management)
- **GDScript owns positions** (physics/movement) and **visual rendering** (animations, effects)
- **Combat thread runs autonomously** at 60fps using `std::thread::spawn` (works via Emscripten pthreads)
- **Bi-directional communication** via thread-safe queues and HolyMap storage

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│  Rust Autonomous Combat Thread (60fps, independent)          │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ loop {                                                 │  │
│  │   sleep(16ms);                                         │  │
│  │   1. Query HolyMap for NPC positions ("pos:{ulid}")   │  │
│  │   2. Find combat pairs (proximity + faction hostile)  │  │
│  │   3. Check attack cooldowns                           │  │
│  │   4. Calculate damage (attack vs defense)             │  │
│  │   5. Update HP in HolyMap ("hp:{ulid}")              │  │
│  │   6. Update cooldowns ("cooldown:{ulid}")            │  │
│  │   7. Push CombatEvent to queue                        │  │
│  │ }                                                      │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  HolyMap Storage (lock-free reads, fast writes):            │
│    "pos:{ulid}"      -> "x,y"                               │
│    "hp:{ulid}"       -> "current_hp"                        │
│    "state:{ulid}"    -> "state_bitflags"                    │
│    "cooldown:{ulid}" -> "last_attack_timestamp_ms"          │
│    "stats:{ulid}"    -> JSON (attack, defense, max_hp)      │
└──────────────────────────────────────────────────────────────┘
         │                                     ▲
         │ CombatEvent Queue                   │ Position Updates
         │ (Vec<CombatEvent>)                  │ Command Queue
         ▼                                     │
┌──────────────────────────────────────────────────────────────┐
│  GDScript _process(delta) - Every Frame                      │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 1. NPCs update positions:                             │  │
│  │    NPCDataWarehouse.update_npc_position(ulid, x, y)   │  │
│  │                                                        │  │
│  │ 2. Poll combat events:                                │  │
│  │    events = NPCDataWarehouse.poll_combat_events()     │  │
│  │                                                        │  │
│  │ 3. Render events:                                     │  │
│  │    - "attack" -> play attack animation                │  │
│  │    - "damage" -> show damage number, hurt anim        │  │
│  │    - "death"  -> play death animation, despawn        │  │
│  │    - "heal"   -> show heal effect                     │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

---

## Data Flow: Bi-Directional Communication

### GDScript → Rust (Inputs to Combat System)

| Method | Purpose | Frequency |
|--------|---------|-----------|
| `update_npc_position(ulid, x, y)` | Sync NPC position for proximity detection | Every frame per NPC |
| `register_npc_for_combat(ulid, state, max_hp, attack, defense)` | Register spawned NPC | On spawn |
| `unregister_npc_from_combat(ulid)` | Remove NPC from combat | On despawn/death |
| `apply_healing(ulid, amount)` | Player uses health potion | On item use |
| `apply_damage(ulid, amount)` | Environmental damage (fire, traps) | On trigger |
| `trigger_manual_attack(attacker_ulid, target_ulid)` | Player-initiated attack | On player input |

### Rust → GDScript (Outputs from Combat System)

| Method | Returns | Purpose |
|--------|---------|---------|
| `poll_combat_events()` | `Array<GString>` (JSON) | Combat events for visual rendering |
| `get_npc_hp(ulid)` | `f32` | Current HP for health bar display |
| `get_all_active_combat_npcs()` | `Array<GString>` | List of ULIDs in combat |

### CombatEvent Structure (Rust → GDScript)

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CombatEvent {
    pub event_type: String,        // "attack", "damage", "death", "heal"
    pub attacker_ulid: String,      // Who initiated the action
    pub target_ulid: String,        // Who received the action
    pub amount: f32,                // Damage/heal amount
    pub attacker_animation: String, // "attack", "cast_spell", etc.
    pub target_animation: String,   // "hurt", "death", "heal_glow"
    pub target_x: f32,              // Target position for VFX
    pub target_y: f32,
}
```

---

## Implementation Phases

### Phase 1: Combat Thread Infrastructure ✅ PRIORITY

**Goal**: Add thread-safe event queue and combat thread spawn mechanism.

**Files to Modify**:
- `rust/src/npc_data_warehouse.rs`

**Changes**:

1. **Add imports**:
```rust
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicBool, Ordering};
use std::collections::VecDeque;
use std::thread;
use std::time::Duration;
```

2. **Add fields to NPCDataWarehouse struct** (~line 193):
```rust
pub struct NPCDataWarehouse {
    storage: HolyMap<SafeString, SafeValue>,

    // Combat thread infrastructure
    combat_event_queue: Arc<Mutex<VecDeque<CombatEvent>>>,
    combat_thread_running: Arc<AtomicBool>,
    combat_thread_handle: Option<std::thread::JoinHandle<()>>,
}
```

3. **Update constructor** (~line 200):
```rust
impl NPCDataWarehouse {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            storage: HolyMap::new(),
            combat_event_queue: Arc::new(Mutex::new(VecDeque::new())),
            combat_thread_running: Arc::new(AtomicBool::new(false)),
            combat_thread_handle: None,
        })
    }
}
```

4. **Add thread lifecycle methods**:
```rust
impl NPCDataWarehouse {
    /// Start autonomous combat thread (60fps)
    pub fn start_combat_thread(self: &Arc<Self>) {
        if self.combat_thread_running.load(Ordering::Relaxed) {
            return; // Already running
        }

        self.combat_thread_running.store(true, Ordering::Relaxed);

        let running = self.combat_thread_running.clone();
        let queue = self.combat_event_queue.clone();
        let storage = self.storage.clone();

        thread::spawn(move || {
            while running.load(Ordering::Relaxed) {
                thread::sleep(Duration::from_millis(16)); // 60fps

                // Process combat tick
                let events = Self::process_combat_tick_static(&storage);

                // Push events to queue
                if let Ok(mut q) = queue.lock() {
                    q.extend(events);
                }
            }
        });
    }

    /// Stop combat thread gracefully
    pub fn stop_combat_thread(&self) {
        self.combat_thread_running.store(false, Ordering::Relaxed);
    }
}
```

5. **Add GDScript wrapper for event polling** (~line 978):
```rust
impl GodotNPCDataWarehouse {
    /// Poll combat events from Rust combat thread
    /// Returns Array of JSON strings (CombatEvent)
    #[func]
    pub fn poll_combat_events(&self) -> Array<GString> {
        let mut events_array = Array::new();

        if let Ok(mut queue) = self.warehouse.as_ref().combat_event_queue.lock() {
            while let Some(event) = queue.pop_front() {
                let event_json = GString::from(event.to_json());
                events_array.push(&event_json);
            }
        }

        events_array
    }

    /// Start autonomous combat thread
    #[func]
    pub fn start_combat_system(&self) {
        self.warehouse.start_combat_thread();
    }

    /// Stop combat thread (for cleanup)
    #[func]
    pub fn stop_combat_system(&self) {
        self.warehouse.as_ref().stop_combat_thread();
    }
}
```

**Compilation Test**:
```bash
cd rust && bash sync.sh
# Should compile without errors
```

---

### Phase 2: NPC Registration & Position Tracking ✅ PRIORITY

**Goal**: Track which NPCs are active in combat and their positions.

**Changes**:

1. **Add registration methods to NPCDataWarehouse**:
```rust
impl NPCDataWarehouse {
    /// Register NPC for combat tracking
    pub fn register_npc_for_combat_internal(
        &self,
        ulid: &str,
        initial_state: i32,
        max_hp: f32,
        attack: f32,
        defense: f32,
    ) {
        // Store initial combat data
        self.storage.insert(
            SafeString(format!("combat:{}", ulid)),
            SafeValue("active".to_string())
        );

        self.storage.insert(
            SafeString(format!("hp:{}", ulid)),
            SafeValue(max_hp.to_string())
        );

        self.storage.insert(
            SafeString(format!("state:{}", ulid)),
            SafeValue(initial_state.to_string())
        );

        self.storage.insert(
            SafeString(format!("attack:{}", ulid)),
            SafeValue(attack.to_string())
        );

        self.storage.insert(
            SafeString(format!("defense:{}", ulid)),
            SafeValue(defense.to_string())
        );

        self.storage.insert(
            SafeString(format!("cooldown:{}", ulid)),
            SafeValue("0".to_string()) // No cooldown initially
        );
    }

    /// Unregister NPC from combat (on death/despawn)
    pub fn unregister_npc_from_combat_internal(&self, ulid: &str) {
        self.storage.remove(&SafeString(format!("combat:{}", ulid)));
        self.storage.remove(&SafeString(format!("pos:{}", ulid)));
        self.storage.remove(&SafeString(format!("hp:{}", ulid)));
        self.storage.remove(&SafeString(format!("state:{}", ulid)));
        self.storage.remove(&SafeString(format!("attack:{}", ulid)));
        self.storage.remove(&SafeString(format!("defense:{}", ulid)));
        self.storage.remove(&SafeString(format!("cooldown:{}", ulid)));
    }

    /// Get all active combat NPCs
    pub fn get_all_active_combat_npcs_internal(&self) -> Vec<String> {
        let mut active_npcs = Vec::new();

        // Iterate over HolyMap looking for "combat:{ulid}" keys
        // Note: This requires HolyMap iteration support
        // For now, we'll implement a simpler approach using a separate active list

        active_npcs
    }
}
```

2. **Add GDScript wrappers**:
```rust
impl GodotNPCDataWarehouse {
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

    #[func]
    pub fn unregister_npc_from_combat(&self, ulid: GString) {
        self.warehouse.as_ref().unregister_npc_from_combat_internal(&ulid.to_string());
    }
}
```

**Position tracking already exists**:
- ✅ `update_npc_position_internal()` at line 475
- ✅ `get_npc_position_internal()` at line 482
- ✅ GDScript wrappers at lines 978-993

**Compilation Test**:
```bash
cd rust && bash sync.sh
```

---

### Phase 3: Combat Tick Logic (Proximity Detection) ✅ PRIORITY

**Goal**: Implement core combat loop - find NPCs that should fight.

**Changes**:

1. **Add combat tick implementation**:
```rust
impl NPCDataWarehouse {
    /// Process one combat tick (called by autonomous thread)
    fn process_combat_tick_static(storage: &HolyMap<SafeString, SafeValue>) -> Vec<CombatEvent> {
        let mut events = Vec::new();

        // 1. Get all active NPCs with positions
        let active_npcs = Self::get_active_npcs_with_positions_static(storage);

        // 2. Find combat pairs (proximity + hostility)
        let combat_pairs = Self::find_combat_pairs_static(&active_npcs);

        // 3. Process each combat pair
        for (attacker_ulid, target_ulid, distance) in combat_pairs {
            // Check cooldown
            if let Some(can_attack) = Self::check_attack_cooldown_static(storage, &attacker_ulid) {
                if !can_attack {
                    continue; // Still on cooldown
                }
            }

            // Calculate damage
            let damage = Self::calculate_damage_static(storage, &attacker_ulid, &target_ulid);

            // Apply damage and get target's new HP
            let target_hp = Self::apply_damage_static(storage, &target_ulid, damage);

            // Update attacker cooldown
            Self::update_cooldown_static(storage, &attacker_ulid);

            // Get target position for VFX
            let (target_x, target_y) = Self::get_position_static(storage, &target_ulid)
                .unwrap_or((0.0, 0.0));

            // Generate attack event
            events.push(CombatEvent {
                event_type: "attack".to_string(),
                attacker_ulid: attacker_ulid.clone(),
                target_ulid: target_ulid.clone(),
                amount: 0.0, // Just notification
                attacker_animation: "attack".to_string(),
                target_animation: "".to_string(),
                target_x,
                target_y,
            });

            // Generate damage event
            let target_animation = if target_hp <= 0.0 {
                "death".to_string()
            } else {
                "hurt".to_string()
            };

            events.push(CombatEvent {
                event_type: if target_hp <= 0.0 { "death" } else { "damage" }.to_string(),
                attacker_ulid: attacker_ulid.clone(),
                target_ulid: target_ulid.clone(),
                amount: damage,
                attacker_animation: "".to_string(),
                target_animation,
                target_x,
                target_y,
            });

            // Mark target as dead if HP <= 0
            if target_hp <= 0.0 {
                Self::mark_dead_static(storage, &target_ulid);
            }
        }

        events
    }

    /// Get all active NPCs with positions
    /// Returns: Vec<(ulid, x, y, state, hp, attack, defense)>
    fn get_active_npcs_with_positions_static(
        storage: &HolyMap<SafeString, SafeValue>
    ) -> Vec<(String, f32, f32, i32, f32, f32, f32)> {
        let mut npcs = Vec::new();

        // TODO: Need to implement HolyMap iteration or maintain active NPC list separately
        // For now, this is a placeholder

        npcs
    }

    /// Find combat pairs based on proximity and faction hostility
    /// Returns: Vec<(attacker_ulid, target_ulid, distance)>
    fn find_combat_pairs_static(
        npcs: &[(String, f32, f32, i32, f32, f32, f32)]
    ) -> Vec<(String, String, f32)> {
        let mut pairs = Vec::new();

        for i in 0..npcs.len() {
            let (ulid_a, x_a, y_a, state_a, _, _, _) = &npcs[i];

            // Skip if dead
            if (*state_a & NPCState::DEAD.bits()) != 0 {
                continue;
            }

            for j in (i + 1)..npcs.len() {
                let (ulid_b, x_b, y_b, state_b, _, _, _) = &npcs[j];

                // Skip if dead
                if (*state_b & NPCState::DEAD.bits()) != 0 {
                    continue;
                }

                // Check if hostile factions
                let are_hostile = Self::are_factions_hostile(*state_a, *state_b);
                if !are_hostile {
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
        let ally1 = (state1 & NPCState::ALLY.bits()) != 0;
        let monster1 = (state1 & NPCState::MONSTER.bits()) != 0;
        let passive1 = (state1 & NPCState::PASSIVE.bits()) != 0;

        let ally2 = (state2 & NPCState::ALLY.bits()) != 0;
        let monster2 = (state2 & NPCState::MONSTER.bits()) != 0;
        let passive2 = (state2 & NPCState::PASSIVE.bits()) != 0;

        // Passive never hostile
        if passive1 || passive2 {
            return false;
        }

        // Ally vs Monster = hostile
        (ally1 && monster2) || (monster1 && ally2)
    }

    /// Get attack range based on combat type
    fn get_attack_range(state: i32) -> f32 {
        if (state & NPCState::MELEE.bits()) != 0 {
            50.0 // Melee range
        } else if (state & NPCState::RANGED.bits()) != 0 {
            200.0 // Ranged range
        } else if (state & NPCState::MAGIC.bits()) != 0 {
            150.0 // Magic range
        } else {
            50.0 // Default
        }
    }

    /// Calculate distance between two points
    fn distance(x1: f32, y1: f32, x2: f32, y2: f32) -> f32 {
        let dx = x2 - x1;
        let dy = y2 - y1;
        (dx * dx + dy * dy).sqrt()
    }
}
```

**Compilation Test**:
```bash
cd rust && bash sync.sh
```

---

### Phase 4: Damage Calculation & HP Updates ✅ PRIORITY

**Goal**: Calculate damage, update HP, track cooldowns.

**Changes**:

1. **Add helper methods**:
```rust
impl NPCDataWarehouse {
    /// Check if attacker can attack (cooldown expired)
    fn check_attack_cooldown_static(storage: &HolyMap<SafeString, SafeValue>, ulid: &str) -> Option<bool> {
        let cooldown_key = SafeString(format!("cooldown:{}", ulid));
        if let Some(SafeValue(cooldown_str)) = storage.get(&cooldown_key) {
            if let Ok(last_attack_ms) = cooldown_str.parse::<u64>() {
                let now_ms = Self::get_current_time_ms();
                let cooldown_duration_ms = 1000; // 1 attack per second

                return Some(now_ms >= last_attack_ms + cooldown_duration_ms);
            }
        }
        Some(true) // No cooldown record = can attack
    }

    /// Update attack cooldown
    fn update_cooldown_static(storage: &HolyMap<SafeString, SafeValue>, ulid: &str) {
        let now_ms = Self::get_current_time_ms();
        storage.insert(
            SafeString(format!("cooldown:{}", ulid)),
            SafeValue(now_ms.to_string())
        );
    }

    /// Calculate damage: attacker.attack vs target.defense
    fn calculate_damage_static(storage: &HolyMap<SafeString, SafeValue>, attacker_ulid: &str, target_ulid: &str) -> f32 {
        let attack = Self::get_stat_static(storage, attacker_ulid, "attack").unwrap_or(10.0);
        let defense = Self::get_stat_static(storage, target_ulid, "defense").unwrap_or(5.0);

        // Simple formula: damage = attack - (defense / 2)
        let damage = attack - (defense / 2.0);
        damage.max(1.0) // Minimum 1 damage
    }

    /// Apply damage to target, return new HP
    fn apply_damage_static(storage: &HolyMap<SafeString, SafeValue>, target_ulid: &str, damage: f32) -> f32 {
        let current_hp = Self::get_stat_static(storage, target_ulid, "hp").unwrap_or(100.0);
        let new_hp = (current_hp - damage).max(0.0);

        storage.insert(
            SafeString(format!("hp:{}", target_ulid)),
            SafeValue(new_hp.to_string())
        );

        new_hp
    }

    /// Get a stat value from HolyMap
    fn get_stat_static(storage: &HolyMap<SafeString, SafeValue>, ulid: &str, stat_name: &str) -> Option<f32> {
        let key = SafeString(format!("{}:{}", stat_name, ulid));
        if let Some(SafeValue(value_str)) = storage.get(&key) {
            return value_str.parse::<f32>().ok();
        }
        None
    }

    /// Get position from HolyMap
    fn get_position_static(storage: &HolyMap<SafeString, SafeValue>, ulid: &str) -> Option<(f32, f32)> {
        let key = SafeString(format!("pos:{}", ulid));
        if let Some(SafeValue(pos_str)) = storage.get(&key) {
            let parts: Vec<&str> = pos_str.split(',').collect();
            if parts.len() == 2 {
                if let (Ok(x), Ok(y)) = (parts[0].parse::<f32>(), parts[1].parse::<f32>()) {
                    return Some((x, y));
                }
            }
        }
        None
    }

    /// Mark NPC as dead
    fn mark_dead_static(storage: &HolyMap<SafeString, SafeValue>, ulid: &str) {
        let state_key = SafeString(format!("state:{}", ulid));
        if let Some(SafeValue(state_str)) = storage.get(&state_key) {
            if let Ok(mut state) = state_str.parse::<i32>() {
                state |= NPCState::DEAD.bits();
                storage.insert(state_key, SafeValue(state.to_string()));
            }
        }
    }

    /// Get current time in milliseconds
    fn get_current_time_ms() -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64
    }
}
```

2. **Add public HP getter for GDScript**:
```rust
impl GodotNPCDataWarehouse {
    /// Get NPC current HP
    #[func]
    pub fn get_npc_hp(&self, ulid: GString) -> f32 {
        let ulid_str = ulid.to_string();
        NPCDataWarehouse::get_stat_static(
            &self.warehouse.as_ref().storage,
            &ulid_str,
            "hp"
        ).unwrap_or(0.0)
    }
}
```

**Compilation Test**:
```bash
cd rust && bash sync.sh
```

---

### Phase 5: Active NPC Tracking Solution

**Problem**: HolyMap doesn't provide iteration, so we can't find all "pos:{ulid}" keys.

**Solution**: Maintain a separate `DashMap<String, ()>` of active NPC ULIDs.

**Changes**:

1. **Add active NPC tracking to struct**:
```rust
use dashmap::DashMap;

pub struct NPCDataWarehouse {
    storage: HolyMap<SafeString, SafeValue>,
    active_combat_npcs: DashMap<String, ()>, // Set of active ULID strings

    // ... rest of fields
}
```

2. **Update registration to track active NPCs**:
```rust
pub fn register_npc_for_combat_internal(&self, ulid: &str, ...) {
    // ... existing code ...

    // Add to active set
    self.active_combat_npcs.insert(ulid.to_string(), ());
}

pub fn unregister_npc_from_combat_internal(&self, ulid: &str) {
    // ... existing cleanup code ...

    // Remove from active set
    self.active_combat_npcs.remove(ulid);
}
```

3. **Implement get_active_npcs_with_positions**:
```rust
fn get_active_npcs_with_positions_static(
    storage: &HolyMap<SafeString, SafeValue>,
    active_npcs: &DashMap<String, ()>,
) -> Vec<(String, f32, f32, i32, f32, f32, f32)> {
    let mut npcs = Vec::new();

    for entry in active_npcs.iter() {
        let ulid = entry.key();

        // Get position
        let pos = Self::get_position_static(storage, ulid);
        if pos.is_none() {
            continue; // No position yet
        }
        let (x, y) = pos.unwrap();

        // Get state
        let state = Self::get_stat_static(storage, ulid, "state")
            .unwrap_or(0.0) as i32;

        // Skip if dead
        if (state & NPCState::DEAD.bits()) != 0 {
            continue;
        }

        // Get combat stats
        let hp = Self::get_stat_static(storage, ulid, "hp").unwrap_or(100.0);
        let attack = Self::get_stat_static(storage, ulid, "attack").unwrap_or(10.0);
        let defense = Self::get_stat_static(storage, ulid, "defense").unwrap_or(5.0);

        npcs.push((ulid.clone(), x, y, state, hp, attack, defense));
    }

    npcs
}
```

4. **Update process_combat_tick to pass active_npcs**:
```rust
pub fn start_combat_thread(self: &Arc<Self>) {
    // ... existing setup ...

    let active_npcs = self.active_combat_npcs.clone();

    thread::spawn(move || {
        while running.load(Ordering::Relaxed) {
            thread::sleep(Duration::from_millis(16));

            let events = Self::process_combat_tick_static(&storage, &active_npcs);

            // ... rest of code ...
        }
    });
}

fn process_combat_tick_static(
    storage: &HolyMap<SafeString, SafeValue>,
    active_npcs: &DashMap<String, ()>,
) -> Vec<CombatEvent> {
    let active_npcs_data = Self::get_active_npcs_with_positions_static(storage, active_npcs);
    // ... rest of logic ...
}
```

**Compilation Test**:
```bash
cd rust && bash sync.sh
```

---

## Testing Plan

### Unit Tests (Rust)

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_distance_calculation() {
        assert_eq!(NPCDataWarehouse::distance(0.0, 0.0, 3.0, 4.0), 5.0);
    }

    #[test]
    fn test_faction_hostility() {
        let ally = NPCState::ALLY.bits();
        let monster = NPCState::MONSTER.bits();
        let passive = NPCState::PASSIVE.bits();

        assert!(NPCDataWarehouse::are_factions_hostile(ally, monster));
        assert!(!NPCDataWarehouse::are_factions_hostile(ally, ally));
        assert!(!NPCDataWarehouse::are_factions_hostile(ally, passive));
    }

    #[test]
    fn test_attack_range() {
        assert_eq!(NPCDataWarehouse::get_attack_range(NPCState::MELEE.bits()), 50.0);
        assert_eq!(NPCDataWarehouse::get_attack_range(NPCState::RANGED.bits()), 200.0);
        assert_eq!(NPCDataWarehouse::get_attack_range(NPCState::MAGIC.bits()), 150.0);
    }
}
```

### Integration Tests (GDScript)

```gdscript
# In title.gd or test scene
func test_autonomous_combat():
    print("\n=== Testing Autonomous Combat ===")

    # Start combat system
    NPCDataWarehouse.start_combat_system()

    # Register two hostile NPCs
    var warrior_ulid = "warrior_001"
    var goblin_ulid = "goblin_001"

    NPCDataWarehouse.register_npc_for_combat(
        warrior_ulid,
        NPCState.IDLE | NPCState.MELEE | NPCState.ALLY,
        100.0, # max_hp
        15.0,  # attack
        10.0   # defense
    )

    NPCDataWarehouse.register_npc_for_combat(
        goblin_ulid,
        NPCState.IDLE | NPCState.MELEE | NPCState.MONSTER,
        50.0,  # max_hp
        10.0,  # attack
        5.0    # defense
    )

    # Position them close together (within melee range)
    NPCDataWarehouse.update_npc_position(warrior_ulid, 100.0, 100.0)
    NPCDataWarehouse.update_npc_position(goblin_ulid, 130.0, 100.0) # 30px apart

    # Wait for combat ticks
    await get_tree().create_timer(2.0).timeout

    # Poll events
    var events = NPCDataWarehouse.poll_combat_events()
    print("Combat events received: %d" % events.size())

    for event_json in events:
        var event = JSON.parse_string(event_json)
        print("  Event: %s | Attacker: %s | Target: %s | Amount: %.1f" % [
            event.event_type,
            event.attacker_ulid,
            event.target_ulid,
            event.amount
        ])

    # Check HP decreased
    var goblin_hp = NPCDataWarehouse.get_npc_hp(goblin_ulid)
    print("Goblin HP after combat: %.1f" % goblin_hp)
    assert(goblin_hp < 50.0, "Goblin should have taken damage")

    # Cleanup
    NPCDataWarehouse.unregister_npc_from_combat(warrior_ulid)
    NPCDataWarehouse.unregister_npc_from_combat(goblin_ulid)

    print("✓ Autonomous combat test complete")
```

---

## Compilation Checklist

- [ ] Phase 1: Combat thread infrastructure compiles
- [ ] Phase 2: NPC registration compiles
- [ ] Phase 3: Combat tick logic compiles
- [ ] Phase 4: Damage calculation compiles
- [ ] Phase 5: Active NPC tracking compiles
- [ ] All Rust unit tests pass: `cargo test`
- [ ] GDExtension builds successfully: `bash sync.sh`
- [ ] No warnings or errors in Godot console
- [ ] Integration test runs without panics

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Combat tick time | < 1ms | For 100 active NPCs |
| Event queue latency | < 16ms | One frame delay acceptable |
| Memory overhead | < 1KB per NPC | Lightweight tracking |
| Thread CPU usage | < 5% | Sleeps 16ms between ticks |

---

## Known Limitations & Future Improvements

### Current Limitations:
1. **No spatial partitioning** - O(n²) proximity checks (fine for <100 NPCs)
2. **Fixed attack ranges** - Can't customize per-NPC
3. **Simple damage formula** - No crits, no resistances
4. **No path obstruction** - Ranged attacks ignore walls/terrain

### Future Enhancements:
1. **Spatial hash grid** - O(1) proximity lookups for 1000+ NPCs
2. **Attack range in stats** - Store per-NPC in HolyMap
3. **Advanced combat** - Critical hits, elemental damage, buffs/debuffs
4. **Line-of-sight checks** - Raycast for ranged attacks
5. **Aggro system** - Track threat/aggro per NPC pair
6. **Combat groups** - Multi-target AoE abilities

---

## Design Decisions & Rationale

### Why Thread Instead of Tick-Based?
- **True autonomy**: Combat runs even if GDScript is busy
- **Decoupled timing**: Combat always 60fps, regardless of render FPS
- **Future-proof**: Easy to add more autonomous systems (AI, pathfinding)

### Why HolyMap for Combat Data?
- **Lock-free reads**: Combat thread reads without blocking writes
- **Fast writes**: DashMap for position updates from GDScript
- **Zero-downtime sync**: ArcSwap ensures consistency

### Why Separate Event Queue?
- **Clean separation**: Rust = logic, GDScript = rendering
- **Batch processing**: GDScript can process 10+ events per frame
- **Async-friendly**: Events don't block combat thread

### Why JSON for Events?
- **Flexible**: Easy to add new event fields without recompiling
- **Debuggable**: Can print/log events as human-readable strings
- **Future-proof**: Easy to add new event types

---

## Success Criteria

✅ **Phase 1 Complete**: Combat thread spawns, event queue works, no crashes
✅ **Phase 2 Complete**: NPCs register/unregister, positions tracked in HolyMap
✅ **Phase 3 Complete**: Combat pairs detected based on proximity + faction
✅ **Phase 4 Complete**: Damage calculated, HP updated, events generated
✅ **Phase 5 Complete**: 100+ NPCs fighting autonomously without lag

**Final Validation**:
- Spawn 50 warriors + 50 goblins within combat range
- Confirm combat events generated autonomously
- Confirm HP decreases over time
- Confirm death events when HP reaches 0
- Confirm no crashes or deadlocks after 5 minutes
- Confirm combat thread uses <5% CPU

---

## Timeline Estimate

| Phase | Estimated Time | Dependencies |
|-------|----------------|--------------|
| Phase 1 | 30-45 min | None |
| Phase 2 | 15-20 min | Phase 1 |
| Phase 3 | 45-60 min | Phase 2 |
| Phase 4 | 30-45 min | Phase 3 |
| Phase 5 | 20-30 min | Phase 4 |
| Testing | 30-45 min | All phases |
| **Total** | **3-4 hours** | Sequential |

---

## Next Steps After Rust Implementation

Once all Rust phases compile and tests pass:

1. **GDScript Integration** (documented separately)
   - Update NPCManager to call registration methods
   - Add position sync in NPC `_process()`
   - Add event polling in NPCManager `_process()`
   - Implement event handlers (animations, damage numbers, VFX)

2. **Visual Polish**
   - Add combat state indicators (exclamation marks, targeting lines)
   - Add health bar updates
   - Add damage number popups
   - Add attack projectiles for ranged/magic

3. **Balancing**
   - Tune attack ranges
   - Tune damage formulas
   - Tune cooldown durations
   - Tune faction relationships

---

**Last Updated**: 2025-10-22
**Author**: Claude Code
**Status**: Ready for Implementation ✅
