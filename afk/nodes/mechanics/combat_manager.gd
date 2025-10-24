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
## NOTE: Combat ranges are now decentralized - each NPC defines its own attack_range property
## - NPC base class: default 60.0 (melee allies like warriors)
## - Monster base class: default 50.0 (melee monsters)
## - Individual NPCs override as needed (e.g., Archer: 150.0 for ranged attacks)
const FACING_THRESHOLD: float = 0.85  # Dot product threshold for "facing" (stricter, ~30 degrees)
const ATTACK_COOLDOWN: float = 1.5  # Seconds between attacks

## Health thresholds for state changes (SIMPLIFIED - no more HURT state)

## NOTE: NPCState bitwise flags are defined in NPCManager
## Includes behavioral states, combat types, and factions - all unified in NPCState enum
## Access via NPCManager.NPCState (e.g., NPCState.MELEE, NPCState.ALLY, NPCState.WALKING)

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

	# Connect to EventManager for bidirectional communication
	if EventManager:
		# Listen to combat events from EventManager (debounced pathway)
		EventManager.combat_started.connect(_on_event_combat_started)
		EventManager.combat_ended.connect(_on_event_combat_ended)

	# Connect to NPCManager for bidirectional communication
	if NPCManager:
		# Listen to NPC state changes that might affect combat
		NPCManager.request_state_change.connect(_on_npc_state_change_requested)


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
	# Use bitwise check for PASSIVE flag
	var attacker_state := Bitwise._ensure_int_prop(attacker, "current_state")
	if Bitwise.has_flag(attacker_state, NPCManager.NPCStaticState.PASSIVE):
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

	# Get attack range from NPC property (decentralized)
	var required_range = attacker.attack_range if "attack_range" in attacker else 60.0

	# Check proximity - must be within attack range
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
	var current_state := Bitwise._ensure_int_prop(attacker, "current_state")
	Bitwise._set_int_prop(attacker, "current_state", Bitwise.add_flag(current_state, NPCManager.NPCState.ATTACKING))

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
	var current_state := Bitwise._ensure_int_prop(attacker, "current_state")
	current_state = Bitwise.remove_flag(current_state, NPCManager.NPCState.ATTACKING)

	# Now set appropriate state based on controller
	if "controller" in attacker and attacker.controller:
		if attacker.controller.is_auto_moving:
			current_state = Bitwise.add_flag(current_state, NPCManager.NPCState.WALKING)
		else:
			# Remove WALKING flag too if not moving
			current_state = Bitwise.remove_flag(current_state, NPCManager.NPCState.WALKING)
	else:
		# Remove WALKING flag and return to idle
		current_state = Bitwise.remove_flag(current_state, NPCManager.NPCState.WALKING)

	Bitwise._set_int_prop(attacker, "current_state", current_state)


## ===== RANGED COMBAT =====

## Check if attacker can perform ranged attack on target
func can_ranged_attack(attacker: Node2D, target: Node2D) -> bool:
	if not attacker or not target:
		return false

	# Check if attacker is passive (can't attack)
	# Use bitwise check for PASSIVE flag
	var attacker_state := Bitwise._ensure_int_prop(attacker, "current_state")
	if Bitwise.has_flag(attacker_state, NPCManager.NPCStaticState.PASSIVE):
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

	# Get archer's attack range (optimal distance)
	var optimal_range = attacker.attack_range if "attack_range" in attacker else 150.0
	var min_range = optimal_range * 0.5  # Half optimal = minimum kiting distance
	var max_range = optimal_range * 2.0  # Double optimal = maximum shooting distance

	# Archers need to maintain minimum distance and be within max range
	if distance < min_range:
		return false  # Too close - need to retreat first

	if distance > max_range:
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
	var optimal_range = attacker.attack_range if "attack_range" in attacker else 150.0
	var min_range = optimal_range * 0.5  # Minimum kiting distance

	# If hurt (low health), use extended retreat distance
	if is_hurt(attacker):
		return distance < optimal_range  # Retreat to full optimal range when hurt

	# Normal retreat distance
	return distance < min_range


## Check if NPC is hurt (low health - DEPRECATED, kept for compatibility)
func is_hurt(npc: Node2D) -> bool:
	# SIMPLIFIED: No longer using HURT state flag
	return false


## Get optimal kiting range based on NPC health state
func get_optimal_kiting_range(npc: Node2D) -> float:
	var optimal_range = npc.attack_range if "attack_range" in npc else 150.0

	if is_hurt(npc):
		return optimal_range  # Hurt archers keep at optimal range
	return optimal_range  # Normal kiting range is also optimal


## Start ranged attack (called by NPCManager after it handles movement)
func start_ranged_attack(attacker: Node2D, target: Node2D, projectile_type: String = "arrow") -> bool:
	if not can_ranged_attack(attacker, target):
		return false

	# CRITICAL: Only RANGED combat type NPCs can fire projectiles
	var attacker_combat_type = _get_npc_combat_type(attacker)
	if attacker_combat_type != NPCManager.NPCStaticState.RANGED:
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
	if is_instance_valid(attacker):
		var current_state := Bitwise._ensure_int_prop(attacker, "current_state")
		if "controller" in attacker and attacker.controller:
			if attacker.controller.is_auto_moving:
				current_state = Bitwise.add_flag(current_state, NPCManager.NPCState.WALKING)
			else:
				# Remove WALKING flag - return to idle
				current_state = Bitwise.remove_flag(current_state, NPCManager.NPCState.WALKING)
		else:
			# Remove WALKING flag - return to idle
			current_state = Bitwise.remove_flag(current_state, NPCManager.NPCState.WALKING)
		Bitwise._set_int_prop(attacker, "current_state", current_state)

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
		target.take_damage(damage, attacker)  # Pass attacker for counter-attack
		damage_dealt.emit(attacker, target, damage)

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

		# Skip if target is same faction as attacker (don't attack allies)
		# Extract faction bits and compare directly (ALLY, MONSTER, or PASSIVE)
		var faction_mask := NPCManager.NPCStaticState.ALLY | NPCManager.NPCStaticState.MONSTER | NPCManager.NPCStaticState.PASSIVE
		var attacker_faction := Bitwise.extract_bits(Bitwise._ensure_int_prop(attacker, "current_state"), faction_mask)
		var target_faction := Bitwise.extract_bits(Bitwise._ensure_int_prop(target, "current_state"), faction_mask)
		if attacker_faction == target_faction and attacker_faction != 0:
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


## Find all valid targets within range (for multi-enemy awareness)
func find_all_valid_targets(attacker: Node2D, max_range: float = 500.0) -> Array[Node2D]:
	var valid_targets: Array[Node2D] = []

	if not attacker:
		return valid_targets

	# Check if attacker is passive (can't attack)
	if attacker.has_method("is_passive") and attacker.is_passive():
		return valid_targets

	# Get all NPCs from NPCManager pools
	var potential_targets = _get_all_npcs()

	for target in potential_targets:
		# Skip self
		if target == attacker:
			continue

		# Skip friendly NPCs (like the cat - should never be targeted)
		if "is_friendly" in target and target.is_friendly:
			continue

		# Skip if target is same faction as attacker (don't attack allies)
		# Extract faction bits and compare directly (ALLY, MONSTER, or PASSIVE)
		var faction_mask := NPCManager.NPCStaticState.ALLY | NPCManager.NPCStaticState.MONSTER | NPCManager.NPCStaticState.PASSIVE
		var attacker_faction := Bitwise.extract_bits(Bitwise._ensure_int_prop(attacker, "current_state"), faction_mask)
		var target_faction := Bitwise.extract_bits(Bitwise._ensure_int_prop(target, "current_state"), faction_mask)
		if attacker_faction == target_faction and attacker_faction != 0:
			continue

		# Skip if target is dead
		if "stats" in target and target.stats:
			if not target.stats.is_alive():
				continue

		# Check distance
		var distance = attacker.global_position.distance_to(target.global_position)
		if distance <= max_range:
			valid_targets.append(target)

	return valid_targets


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
		return active_combatants[attacker].get("state_flags", NPCManager.NPCState.IDLE)
	return NPCManager.NPCState.IDLE


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


## Get NPC's combat type from bitwise state flags
func _get_npc_combat_type(npc: Node2D) -> int:
	var state := Bitwise._ensure_int_prop(npc, "current_state")

	# Check bitwise flags for combat type
	if Bitwise.has_flag(state, NPCManager.NPCStaticState.MELEE):
		return NPCManager.NPCStaticState.MELEE
	elif Bitwise.has_flag(state, NPCManager.NPCStaticState.RANGED):
		return NPCManager.NPCStaticState.RANGED
	elif Bitwise.has_flag(state, NPCManager.NPCStaticState.MAGIC):
		return NPCManager.NPCStaticState.MAGIC
	elif Bitwise.has_flag(state, NPCManager.NPCStaticState.HEALER):
		return NPCManager.NPCStaticState.HEALER

	return 0  # No combat type (passive)


## Update HURT state flag based on NPC health (DEPRECATED - no longer used)
func _update_hurt_state(npc: Node2D) -> void:
	# SIMPLIFIED: HURT state removed, this is now a no-op
	pass


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
## Note: COMBAT doesn't map to animations - it's a behavioral state
func get_animation_state_string(npc: Node2D) -> String:
	var state = get_npc_state(npc)

	# Attack animation takes priority
	if state & NPCManager.NPCState.ATTACKING:
		return "Attacking"
	# Walking animation
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


## ===== BIDIRECTIONAL SIGNAL HANDLERS =====

## Handle combat started events from EventManager (debounced pathway)
func _on_event_combat_started(attacker: Node2D, target: Node2D) -> void:
	# EventManager is broadcasting combat start - can react if needed
	pass


## Handle combat ended events from EventManager (debounced pathway)
func _on_event_combat_ended(attacker: Node2D, target: Node2D) -> void:
	# EventManager is broadcasting combat end - can react if needed
	pass


## Handle NPC state change requests from NPCManager
func _on_npc_state_change_requested(npc: Node2D, new_state: int, reason: String) -> void:
	# NPCManager is requesting a state change - can react if it affects combat
	# For example, if NPC enters DEAD state, end all combat involving this NPC
	if new_state & NPCManager.NPCState.DEAD:
		if is_in_combat(npc):
			end_combat(npc)
