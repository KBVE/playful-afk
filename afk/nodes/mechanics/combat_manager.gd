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
const WARRIOR_MELEE_RANGE: float = 60.0  # Warriors can attack from close range (accounts for sprite size)
const ARCHER_MIN_RANGE: float = 80.0   # Archers stay at least this far (15-20px visual)
const ARCHER_MAX_RANGE: float = 300.0  # Archers can shoot from this far
const ARCHER_OPTIMAL_RANGE: float = 100.0  # Archers prefer this distance
const ARCHER_HURT_RANGE: float = 150.0  # When hurt, archers keep extra distance
const FACING_THRESHOLD: float = 0.85  # Dot product threshold for "facing" (stricter, ~30 degrees)
const ATTACK_COOLDOWN: float = 1.5  # Seconds between attacks

## Health thresholds for state changes
const HURT_HEALTH_THRESHOLD: float = 0.3  # Below 30% HP triggers HURT state

## NOTE: Enums (Faction, CombatType, NPCState) are defined in NPCManager
## Access them via NPCManager.Faction, NPCManager.CombatType, NPCManager.NPCState

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
		if state_flags & NPCManager.NPCState.ATTACKING:
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
	var distance = attacker.global_position.distance_to(target.global_position)

	# If attacker is VERY close or on top of target, consider them facing
	# (dot product becomes unreliable at very close range)
	if distance < 20.0:
		return true

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

	# NOTE: Sprite flip to face target happens in NPCManager BEFORE can_melee_attack check
	# This ensures proper facing for both the check and the attack animation

	# Create or update combat state
	active_combatants[attacker] = {
		"target": target,
		"type": "melee",
		"npc_type": npc_type,
		"cooldown_timer": ATTACK_COOLDOWN,
		"state_flags": NPCManager.NPCState.COMBAT | NPCManager.NPCState.ATTACKING
	}

	# Set the NPC's current_state to ATTACKING to trigger animation
	# Use bitwise OR to add ATTACKING flag while preserving other flags
	if "current_state" in attacker:
		attacker.current_state |= NPCManager.NPCState.ATTACKING

	combat_started.emit(attacker, target)

	# Execute the melee attack with proper timing
	_execute_melee_attack(attacker, target, npc_type)

	return true


## Execute melee attack with animation timing (async)
func _execute_melee_attack(attacker: Node2D, target: Node2D, npc_type: String) -> void:
	# Delay damage until attack animation reaches the impact frame
	# Warrior attack animation: 5 frames at 10fps = 0.5s total
	# Apply damage at frame 3 (0.3 seconds) when slash connects
	await get_tree().create_timer(0.3).timeout

	# Check if attacker and target are still valid
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	# Calculate and apply damage at the moment of impact
	var damage = calculate_damage(attacker, target)
	apply_damage(attacker, target, damage)

	# Wait for rest of animation to complete (0.5s total - 0.3s already waited = 0.2s remaining)
	await get_tree().create_timer(0.2).timeout

	# Check if attacker is still valid
	if not is_instance_valid(attacker):
		return

	# Mark attack as complete (remove ATTACKING flag from combat state)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker]["state_flags"]
		active_combatants[attacker]["state_flags"] = state_flags & ~NPCManager.NPCState.ATTACKING

	# Remove ATTACKING flag from NPC's current_state
	if "current_state" in attacker:
		attacker.current_state &= ~NPCManager.NPCState.ATTACKING

		# Now set appropriate state based on controller
		if "controller" in attacker and attacker.controller:
			if attacker.controller.is_auto_moving:
				attacker.current_state |= NPCManager.NPCState.WALKING
			else:
				# Remove WALKING flag too if not moving
				attacker.current_state &= ~NPCManager.NPCState.WALKING
		else:
			# Remove WALKING flag and return to idle
			attacker.current_state &= ~NPCManager.NPCState.WALKING


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
		if state_flags & NPCManager.NPCState.ATTACKING:
			return false

	# Check distance (must be in range but not too close)
	var distance = attacker.global_position.distance_to(target.global_position)

	# Archers need to maintain minimum distance and be within max range
	if distance < ARCHER_MIN_RANGE:
		return false  # Too close - need to retreat first

	if distance > ARCHER_MAX_RANGE:
		return false  # Too far - need to pursue

	# MUST be facing target to shoot (just like warriors)
	if not is_facing_target(attacker, target):
		return false

	return true


## Check if archer should retreat (enemy too close)
func should_archer_retreat(attacker: Node2D, target: Node2D) -> bool:
	if not attacker or not target:
		return false

	var distance = attacker.global_position.distance_to(target.global_position)

	# If hurt (low health), use extended retreat distance
	if is_hurt(attacker):
		return distance < ARCHER_HURT_RANGE

	# Normal retreat distance
	return distance < ARCHER_MIN_RANGE


## Check if NPC is hurt (low health - below 30%)
func is_hurt(npc: Node2D) -> bool:
	if not npc or not "stats" in npc or not npc.stats:
		return false

	var health_percent = npc.stats.hp / npc.stats.max_hp
	return health_percent <= HURT_HEALTH_THRESHOLD


## Get optimal kiting range based on NPC health state
func get_optimal_kiting_range(npc: Node2D) -> float:
	if is_hurt(npc):
		return ARCHER_HURT_RANGE  # Hurt archers keep extra distance
	return ARCHER_OPTIMAL_RANGE  # Normal kiting range


## Start ranged attack (called by NPCManager after it handles movement)
func start_ranged_attack(attacker: Node2D, target: Node2D, projectile_type: String = "arrow") -> bool:
	if not can_ranged_attack(attacker, target):
		return false

	# CRITICAL: Only RANGED combat type NPCs can fire projectiles
	var attacker_combat_type = _get_npc_combat_type(attacker)
	if attacker_combat_type != NPCManager.CombatType.RANGED:
		return false

	# Get NPC type
	var npc_type = _get_npc_type(attacker)

	# IMPORTANT: Flip archer sprite to face target BEFORE attack animation starts
	# This ensures the bow offset and arrow direction are correct
	if "animated_sprite" in attacker and attacker.animated_sprite:
		var to_target = target.global_position - attacker.global_position
		# Flip sprite if target is to the left
		attacker.animated_sprite.flip_h = to_target.x < 0

	# Create or update combat state
	active_combatants[attacker] = {
		"target": target,
		"type": "ranged",
		"npc_type": npc_type,
		"cooldown_timer": ATTACK_COOLDOWN,
		"state_flags": NPCManager.NPCState.COMBAT | NPCManager.NPCState.ATTACKING
	}

	# Delay arrow firing until attack animation reaches the release point
	# Archer attack animation: 11 frames at 10fps = 1.1s total
	# Fire arrow at frame 7 (0.7 seconds) when bow is fully drawn
	await get_tree().create_timer(0.7).timeout

	# Check if attacker and target are still valid
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return false

	# Fire projectile (handled by ProjectileManager)
	# Note: NPCManager/Controller handles attack animation - we just handle projectile logic
	if ProjectileManager:
		var projectile = ProjectileManager.get_projectile(projectile_type)
		if projectile:
			# Calculate bow position offset based on archer's facing direction
			var bow_offset = _calculate_bow_offset(attacker, target)
			var spawn_position = attacker.global_position + bow_offset

			# Set projectile position (use global_position to handle parallax layers correctly)
			projectile.global_position = spawn_position
			projectile.visible = true

			# Pass attacker reference for damage calculation (use global positions for parallax compatibility)
			if projectile.has_method("fire"):
				projectile.fire(target.global_position, 300.0, attacker)
			# Note: Damage is applied when projectile hits (in arrow.gd's on_hit)

	# Wait for animation to complete (1.1s total - 0.7s already waited = 0.4s remaining)
	await get_tree().create_timer(0.4).timeout

	# Mark attack as complete (animation finished)
	if active_combatants.has(attacker):
		var state_flags = active_combatants[attacker]["state_flags"]
		active_combatants[attacker]["state_flags"] = state_flags & ~NPCManager.NPCState.ATTACKING

	# Update NPC animation state after attack completes
	# Check if NPC should be walking or idle based on controller movement state
	if "current_state" in attacker and is_instance_valid(attacker):
		if "controller" in attacker and attacker.controller:
			if attacker.controller.is_auto_moving:
				attacker.current_state = "Walking"
			else:
				attacker.current_state = "Idle"
		else:
			attacker.current_state = "Idle"

	combat_started.emit(attacker, target)
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
		# Update HURT state based on target's health
		_update_hurt_state(target)

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

		# Skip friendly NPCs (like the cat - should never be targeted)
		if "is_friendly" in target and target.is_friendly:
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
	var faction1 = _get_npc_faction(npc1)
	var faction2 = _get_npc_faction(npc2)

	# NPCs in the same faction don't attack each other
	return faction1 == faction2


## Get NPC's faction
func _get_npc_faction(npc: Node2D) -> NPCManager.Faction:
	# Check if NPC explicitly defines faction
	if "faction" in npc:
		return npc.faction

	# Check if marked as friendly (cat, companions, etc.)
	if "is_friendly" in npc and npc.is_friendly:
		return NPCManager.Faction.ALLY

	# Otherwise, determine by type
	var npc_type = _get_npc_type(npc)

	match npc_type:
		"warrior", "archer", "cat":
			return NPCManager.Faction.ALLY
		"chicken":
			return NPCManager.Faction.MONSTER
		_:
			return NPCManager.Faction.NEUTRAL


## ===== COMBAT STATE MANAGEMENT =====

## End combat for attacker
func end_combat(attacker: Node2D) -> void:
	if active_combatants.has(attacker):
		var target = active_combatants[attacker]["target"]
		active_combatants.erase(attacker)
		combat_ended.emit(attacker, target)


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
		return active_combatants[attacker].get("state_flags", NPCManager.NPCState.WANDERING)
	return NPCManager.NPCState.WANDERING


## Check if NPC has specific state flag
func has_state(attacker: Node2D, state_flag: int) -> bool:
	var current_state = get_npc_state(attacker)
	return (current_state & state_flag) != 0


## ===== EVENT HANDLERS =====

## Called when target is killed
func _on_target_killed(attacker: Node2D, target: Node2D) -> void:
	target_killed.emit(attacker, target)

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


## Get NPC's combat type
func _get_npc_combat_type(npc: Node2D) -> NPCManager.CombatType:
	# Check if NPC explicitly defines combat_type
	if "combat_type" in npc:
		return npc.combat_type

	# Otherwise, determine by type for backward compatibility
	var npc_type = _get_npc_type(npc)

	match npc_type:
		"warrior":
			return NPCManager.CombatType.MELEE
		"archer":
			return NPCManager.CombatType.RANGED
		"cat", "chicken":
			return NPCManager.CombatType.NONE
		_:
			return NPCManager.CombatType.NONE


## Update HURT state flag based on NPC health
func _update_hurt_state(npc: Node2D) -> void:
	if not npc or not "stats" in npc or not npc.stats:
		return

	# Check if NPC is hurt (low health)
	if is_hurt(npc):
		# Add HURT flag to combat state if in active_combatants
		if active_combatants.has(npc):
			active_combatants[npc]["state_flags"] |= NPCManager.NPCState.HURT
	else:
		# Remove HURT flag if health recovered
		if active_combatants.has(npc):
			active_combatants[npc]["state_flags"] &= ~NPCManager.NPCState.HURT


## Calculate bow offset position based on archer's facing direction
func _calculate_bow_offset(attacker: Node2D, target: Node2D) -> Vector2:
	# Determine which direction the archer is facing
	var to_target = (target.global_position - attacker.global_position).normalized()

	# Bow offset from center of sprite
	# The bow is held to the side and slightly forward
	var bow_horizontal_offset = 40.0  # Distance from center to bow
	var bow_vertical_offset = -10.0   # Slightly above center (bow is held up)

	# Check if archer is facing left or right based on sprite flip
	var facing_left = false
	if "animated_sprite" in attacker:
		var sprite = attacker.animated_sprite
		if sprite and sprite.flip_h:
			facing_left = true

	# If we can't determine from sprite flip, use target direction
	if not "animated_sprite" in attacker or not attacker.animated_sprite:
		facing_left = to_target.x < 0

	# Calculate offset based on facing direction
	var horizontal_offset = bow_horizontal_offset if not facing_left else -bow_horizontal_offset

	return Vector2(horizontal_offset, bow_vertical_offset)


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
	if state & NPCManager.NPCState.ATTACKING:
		return "Attacking"
	# Walking animation (used for WALKING, RETREATING, PURSUING)
	elif state & NPCManager.NPCState.WALKING:
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
