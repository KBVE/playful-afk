extends Node

## CombatManager - Centralized Combat System
## Handles both melee and ranged combat for all NPCs
## Communicates with NPCManager for object pooling and NPC access

## Signals
signal combat_started(attacker: Node2D, target: Node2D)
signal combat_ended(attacker: Node2D, target: Node2D)
signal damage_dealt(attacker: Node2D, target: Node2D, damage: float)
signal target_killed(attacker: Node2D, target: Node2D)

## Combat configuration
const WARRIOR_MELEE_RANGE: float = 50.0  # Warriors need to be close (~3px visual distance)
const ARCHER_MIN_RANGE: float = 80.0   # Archers stay at least this far (15-20px visual)
const ARCHER_MAX_RANGE: float = 300.0  # Archers can shoot from this far
const ARCHER_OPTIMAL_RANGE: float = 100.0  # Archers prefer this distance
const FACING_THRESHOLD: float = 0.85  # Dot product threshold for "facing" (stricter, ~30 degrees)
const ATTACK_COOLDOWN: float = 1.5  # Seconds between attacks

## NPC State enum (using bitwise flags for easy combinations)
## Can combine states: e.g., WALKING | COMBAT | PURSUING
enum NPCState {
	IDLE = 1 << 0,        # 1:   Idle (not moving, not attacking)
	WALKING = 1 << 1,     # 2:   Walking/moving
	ATTACKING = 1 << 2,   # 4:   Currently attacking (animation playing)
	WANDERING = 1 << 3,   # 8:   Normal wandering/idle behavior (no combat)
	COMBAT = 1 << 4,      # 16:  Engaged in combat
	RETREATING = 1 << 5,  # 32:  Retreating from enemy (archer kiting)
	PURSUING = 1 << 6     # 64:  Moving towards enemy
}

## Active combat tracking
var active_combatants: Dictionary = {}  # Key: attacker Node2D, Value: combat state

## Combat state structure:
## {
##   "target": Node2D,
##   "type": "melee" or "ranged",
##   "npc_type": "warrior", "archer", etc.
##   "cooldown_timer": float,
##   "state_flags": int (bitwise NPCState flags)
## }


func _ready() -> void:
	# Wait for scene tree to be ready
	await get_tree().process_frame
	print("CombatManager initialized")


func _process(delta: float) -> void:
	# Update cooldown timers for all active combatants
	for attacker in active_combatants.keys():
		var combat_state = active_combatants[attacker]
		if combat_state["cooldown_timer"] > 0.0:
			combat_state["cooldown_timer"] -= delta


## ===== MELEE COMBAT =====

## Check if attacker can perform melee attack on target
func can_melee_attack(attacker: Node2D, target: Node2D) -> bool:
	if not attacker or not target:
		return false

	# Check if attacker is passive (can't attack)
	if attacker.has_method("is_passive") and attacker.is_passive():
		return false

	# Check if target is alive
	if target.has_method("is_alive"):
		if "stats" in target and target.stats:
			if not target.stats.is_alive():
				return false

	# Check if on cooldown
	if active_combatants.has(attacker):
		if active_combatants[attacker]["cooldown_timer"] > 0.0:
			return false

	# Check if currently attacking (can't attack while animation playing)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker].get("state_flags", 0)
		if state_flags & NPCState.ATTACKING:
			return false

	# Get NPC type for range checking
	var npc_type = _get_npc_type(attacker)
	var required_range = WARRIOR_MELEE_RANGE

	# Check proximity based on NPC type
	var distance = attacker.global_position.distance_to(target.global_position)
	if distance > required_range:
		return false

	# MUST be facing target for melee (strict requirement)
	if not is_facing_target(attacker, target):
		return false

	return true


## Check if attacker is facing target
func is_facing_target(attacker: Node2D, target: Node2D) -> bool:
	var to_target = (target.global_position - attacker.global_position).normalized()

	# Determine attacker's facing direction
	var facing_dir = Vector2.RIGHT  # Default facing right

	# Check if attacker has a sprite that's flipped
	if "animated_sprite" in attacker and attacker.animated_sprite:
		if attacker.animated_sprite.flip_h:
			facing_dir = Vector2.LEFT

	# Check if attacker has a scale-based flip
	if attacker.scale.x < 0:
		facing_dir = Vector2.LEFT

	# Calculate dot product (1.0 = same direction, -1.0 = opposite)
	var dot = facing_dir.dot(to_target)

	return dot >= FACING_THRESHOLD


## Start melee attack (called by NPCManager after it handles movement)
func start_melee_attack(attacker: Node2D, target: Node2D) -> bool:
	if not can_melee_attack(attacker, target):
		return false

	# Get NPC type
	var npc_type = _get_npc_type(attacker)

	# Create or update combat state
	active_combatants[attacker] = {
		"target": target,
		"type": "melee",
		"npc_type": npc_type,
		"cooldown_timer": ATTACK_COOLDOWN,
		"state_flags": NPCState.COMBAT | NPCState.ATTACKING
	}

	# Calculate and apply damage
	# Note: NPCManager/Controller handles attack animation - we just handle damage logic
	var damage = calculate_damage(attacker, target)
	apply_damage(attacker, target, damage)

	# Mark attack as complete (remove ATTACKING flag)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker]["state_flags"]
		active_combatants[attacker]["state_flags"] = state_flags & ~NPCState.ATTACKING

	combat_started.emit(attacker, target)

	print("CombatManager: %s melee attacked %s" % [_get_npc_name(attacker), _get_npc_name(target)])

	return true


## ===== RANGED COMBAT =====

## Check if attacker can perform ranged attack on target
func can_ranged_attack(attacker: Node2D, target: Node2D) -> bool:
	if not attacker or not target:
		return false

	# Check if attacker is passive (can't attack)
	if attacker.has_method("is_passive") and attacker.is_passive():
		return false

	# Check if target is alive
	if target.has_method("is_alive"):
		if "stats" in target and target.stats:
			if not target.stats.is_alive():
				return false

	# Check if on cooldown
	if active_combatants.has(attacker):
		if active_combatants[attacker]["cooldown_timer"] > 0.0:
			return false

	# Check if currently attacking (can't attack while animation playing)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker].get("state_flags", 0)
		if state_flags & NPCState.ATTACKING:
			return false

	# Check distance (must be in range but not too close)
	var distance = attacker.global_position.distance_to(target.global_position)

	# Archers need to maintain minimum distance and be within max range
	if distance < ARCHER_MIN_RANGE:
		return false  # Too close - need to retreat first

	if distance > ARCHER_MAX_RANGE:
		return false  # Too far - need to pursue

	return true


## Check if archer should retreat (enemy too close)
func should_archer_retreat(attacker: Node2D, target: Node2D) -> bool:
	if not attacker or not target:
		return false

	var distance = attacker.global_position.distance_to(target.global_position)
	return distance < ARCHER_MIN_RANGE


## Start ranged attack (called by NPCManager after it handles movement)
func start_ranged_attack(attacker: Node2D, target: Node2D, projectile_type: String = "arrow") -> bool:
	if not can_ranged_attack(attacker, target):
		return false

	# Get NPC type
	var npc_type = _get_npc_type(attacker)

	# Create or update combat state
	active_combatants[attacker] = {
		"target": target,
		"type": "ranged",
		"npc_type": npc_type,
		"cooldown_timer": ATTACK_COOLDOWN,
		"state_flags": NPCState.COMBAT | NPCState.ATTACKING
	}

	# Fire projectile (handled by ProjectileManager)
	# Note: NPCManager/Controller handles attack animation - we just handle projectile logic
	if ProjectileManager:
		var projectile = ProjectileManager.get_projectile(projectile_type)
		if projectile:
			# Set projectile position and make visible
			projectile.position = attacker.global_position
			projectile.visible = true

			# Pass attacker reference for damage calculation
			if projectile.has_method("fire"):
				projectile.fire(target.global_position, 300.0, attacker)
			# Note: Damage is applied when projectile hits (in arrow.gd's on_hit)

	# Mark attack as complete (projectile fired)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker]["state_flags"]
		active_combatants[attacker]["state_flags"] = state_flags & ~NPCState.ATTACKING

	combat_started.emit(attacker, target)

	print("CombatManager: %s ranged attacked %s" % [_get_npc_name(attacker), _get_npc_name(target)])

	return true


## ===== DAMAGE CALCULATION =====

## Calculate damage based on attacker's attack and target's defense
func calculate_damage(attacker: Node2D, target: Node2D) -> float:
	var base_damage = 10.0  # Default damage

	# Get attacker's attack stat
	if "stats" in attacker and attacker.stats:
		base_damage = attacker.stats.attack

	# Get target's defense stat
	var defense = 0.0
	if "stats" in target and target.stats:
		defense = target.stats.defense

	# Calculate final damage: attack - (defense * 0.5)
	# Defense reduces damage by 50% of its value
	var final_damage = base_damage - (defense * 0.5)

	# Minimum damage is 1 (can't deal 0 or negative damage)
	final_damage = max(1.0, final_damage)

	return final_damage


## Apply damage to target
func apply_damage(attacker: Node2D, target: Node2D, damage: float) -> void:
	if not target or not is_instance_valid(target):
		return

	# Apply damage to target
	if target.has_method("take_damage"):
		target.take_damage(damage)
		damage_dealt.emit(attacker, target, damage)

		print("CombatManager: %s dealt %.1f damage to %s" % [_get_npc_name(attacker), damage, _get_npc_name(target)])

		# Check if target died
		if "stats" in target and target.stats:
			if not target.stats.is_alive():
				_on_target_killed(attacker, target)


## ===== TARGET ACQUISITION =====

## Find nearest valid target for attacker
func find_nearest_target(attacker: Node2D, max_range: float = 500.0) -> Node2D:
	if not attacker:
		return null

	# Check if attacker is passive (can't attack)
	if attacker.has_method("is_passive") and attacker.is_passive():
		return null

	var nearest_target: Node2D = null
	var nearest_distance: float = max_range

	# Get all NPCs from NPCManager pools
	var potential_targets = _get_all_npcs()

	for target in potential_targets:
		# Skip self
		if target == attacker:
			continue

		# Skip if target is same type as attacker (don't attack allies)
		if _is_same_faction(attacker, target):
			continue

		# Skip if target is dead
		if "stats" in target and target.stats:
			if not target.stats.is_alive():
				continue

		# Check distance
		var distance = attacker.global_position.distance_to(target.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_target = target

	return nearest_target


## Check if two NPCs are in the same faction (don't attack each other)
func _is_same_faction(npc1: Node2D, npc2: Node2D) -> bool:
	# For now, warriors and archers are allies (both humanoids)
	# Chickens and monsters are separate

	var type1 = _get_npc_type(npc1)
	var type2 = _get_npc_type(npc2)

	# Humanoid faction (warriors, archers)
	var humanoid_faction = ["warrior", "archer"]
	# Monster faction (chicken, etc.)
	var monster_faction = ["chicken"]

	if type1 in humanoid_faction and type2 in humanoid_faction:
		return true

	if type1 in monster_faction and type2 in monster_faction:
		return true

	return false


## ===== COMBAT STATE MANAGEMENT =====

## End combat for attacker
func end_combat(attacker: Node2D) -> void:
	if active_combatants.has(attacker):
		var target = active_combatants[attacker]["target"]
		active_combatants.erase(attacker)
		combat_ended.emit(attacker, target)
		print("CombatManager: Combat ended for %s" % _get_npc_name(attacker))


## Get current target for attacker
func get_current_target(attacker: Node2D) -> Node2D:
	if active_combatants.has(attacker):
		return active_combatants[attacker]["target"]
	return null


## Check if attacker is in combat
func is_in_combat(attacker: Node2D) -> bool:
	return active_combatants.has(attacker)


## Get NPC combat state flags (from active_combatants)
func get_combat_state(attacker: Node2D) -> int:
	if active_combatants.has(attacker):
		return active_combatants[attacker].get("state_flags", CombatManager.NPCState.WANDERING)
	return CombatManager.NPCState.WANDERING


## Check if NPC has specific state flag
func has_state(attacker: Node2D, state_flag: int) -> bool:
	var current_state = get_npc_state(attacker)
	return (current_state & state_flag) != 0


## ===== EVENT HANDLERS =====

## Called when target is killed
func _on_target_killed(attacker: Node2D, target: Node2D) -> void:
	target_killed.emit(attacker, target)

	print("CombatManager: %s killed %s!" % [_get_npc_name(attacker), _get_npc_name(target)])

	# End combat for attacker
	end_combat(attacker)

	# TODO: Handle loot, experience, etc.


## ===== HELPER FUNCTIONS =====

## Get all NPCs from NPCManager pools
func _get_all_npcs() -> Array[Node2D]:
	var npcs: Array[Node2D] = []

	if not NPCManager:
		return npcs

	# Get from persistent pool
	for slot in NPCManager.persistent_pool:
		if slot["is_active"] and slot["character"] != null:
			npcs.append(slot["character"])

	# Get from generic pool
	for slot in NPCManager.generic_pool:
		if slot["is_active"] and slot["character"] != null:
			npcs.append(slot["character"])

	# Add cat if active
	if NPCManager.cat:
		npcs.append(NPCManager.cat)

	return npcs


## Get NPC type
func _get_npc_type(npc: Node2D) -> String:
	if NPCManager and NPCManager.has_method("get_npc_type"):
		return NPCManager.get_npc_type(npc)

	# Fallback to class name
	return npc.get_class()


## Get NPC name for debug output
func _get_npc_name(npc: Node2D) -> String:
	if not npc:
		return "Unknown"

	if "stats" in npc and npc.stats:
		return npc.stats.npc_name

	return npc.name


## ===== NPC STATE MANAGEMENT (Animation States) =====

## Global NPC state tracking (maps NPC -> bitwise state flags)
## This tracks ALL NPCs, not just combatants
var npc_states: Dictionary = {}  # Key: NPC Node2D, Value: int (bitwise NPCState flags)


## Set NPC state flags (replaces current state)
func set_npc_state(npc: Node2D, state_flags: int) -> void:
	npc_states[npc] = state_flags


## Add state flag(s) to NPC (bitwise OR)
func add_npc_state(npc: Node2D, state_flags: int) -> void:
	if not npc_states.has(npc):
		npc_states[npc] = 0
	npc_states[npc] |= state_flags


## Remove state flag(s) from NPC (bitwise AND NOT)
func remove_npc_state(npc: Node2D, state_flags: int) -> void:
	if npc_states.has(npc):
		npc_states[npc] &= ~state_flags


## Check if NPC has ALL of the specified state flags
func has_npc_state(npc: Node2D, state_flags: int) -> bool:
	if not npc_states.has(npc):
		return false
	return (npc_states[npc] & state_flags) == state_flags


## Check if NPC has ANY of the specified state flags
func has_any_npc_state(npc: Node2D, state_flags: int) -> bool:
	if not npc_states.has(npc):
		return false
	return (npc_states[npc] & state_flags) != 0


## Get NPC state flags
func get_npc_state(npc: Node2D) -> int:
	return npc_states.get(npc, 0)


## Get animation state string from NPCState flags (for setting npc.current_state)
## Priority: ATTACKING > WALKING > IDLE
## Note: COMBAT, WANDERING, RETREATING, PURSUING don't map to animations - they're behavioral states
func get_animation_state_string(npc: Node2D) -> String:
	var state = get_npc_state(npc)

	# Attack animation takes priority
	if state & NPCState.ATTACKING:
		return "Attacking"
	# Walking animation (used for WALKING, RETREATING, PURSUING)
	elif state & NPCState.WALKING:
		return "Walking"
	# Default to idle
	else:
		return "Idle"


## ===== DEBUG =====

## Print all active combatants
func print_combat_status() -> void:
	print("=== CombatManager Status ===")
	print("  Active Combatants: %d" % active_combatants.size())
	for attacker in active_combatants.keys():
		var state = active_combatants[attacker]
		print("    %s -> %s (%s, cooldown: %.1fs)" % [
			_get_npc_name(attacker),
			_get_npc_name(state["target"]),
			state["type"],
			state["cooldown_timer"]
		])
