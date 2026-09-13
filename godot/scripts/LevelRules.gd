class_name LevelRules
extends RefCounted

## Pure rules for how a play level scales. Kept free of nodes so smokes can
## check the formulas without booting a map.
##
## Monsters cycle easy → moderate → dangerous as the level index grows:
##   n=1 slime, n=2 slime+hare, n=3 slime+hare+tank, n=4 two slimes + hare + tank…
## Objectives: one mission item, plus (n-1) keys that each open the next locked
## wing of rooms. The mission item sits in the last locked wing.

const KIND_SLIME := "slime"
const KIND_HARE := "hare"
const KIND_TANK := "tank"
const KIND_MISSION := "mission"
const KIND_KEY := "key"

const MONSTER_CYCLE: Array[String] = [KIND_SLIME, KIND_HARE, KIND_TANK]

## Level 1 keeps the current nine-room mansion.
const LEVEL_1_ROOMS := 9
## Start wing on n>1: enough rooms to hide a key away from the exit.
const START_ZONE_ROOMS := 6
## Each extra objective is one more locked wing.
const LOCKED_ZONE_ROOMS := 5


static func clamp_level(level: int) -> int:
	return maxi(level, 1)


static func slime_count(level: int) -> int:
	var n := clamp_level(level)
	return int(ceili(float(n) / 3.0))


static func hare_count(level: int) -> int:
	var n := clamp_level(level)
	if n < 2:
		return 0
	return int(ceili(float(n - 1) / 3.0))


static func tank_count(level: int) -> int:
	var n := clamp_level(level)
	if n < 3:
		return 0
	return int(ceili(float(n - 2) / 3.0))


## One kind per spawned monster, in cycle order: slime, hare, tank, slime…
static func monster_kinds(level: int) -> Array[String]:
	var n := clamp_level(level)
	var kinds: Array[String] = []
	for i in n:
		kinds.append(MONSTER_CYCLE[i % MONSTER_CYCLE.size()])
	return kinds


static func monster_counts(level: int) -> Dictionary:
	return {
		KIND_SLIME: slime_count(level),
		KIND_HARE: hare_count(level),
		KIND_TANK: tank_count(level),
	}


static func objective_count(level: int) -> int:
	return clamp_level(level)


static func locked_door_count(level: int) -> int:
	return maxi(clamp_level(level) - 1, 0)


static func key_count(level: int) -> int:
	return locked_door_count(level)


static func zone_count(level: int) -> int:
	return 1 + locked_door_count(level)


static func room_count(level: int) -> int:
	var n := clamp_level(level)
	if n <= 1:
		return LEVEL_1_ROOMS
	return START_ZONE_ROOMS + LOCKED_ZONE_ROOMS * (n - 1)


static func zone_room_counts(level: int) -> Array[int]:
	var n := clamp_level(level)
	var zones: Array[int] = []
	if n <= 1:
		zones.append(LEVEL_1_ROOMS)
		return zones
	zones.append(START_ZONE_ROOMS)
	for _i in range(n - 1):
		zones.append(LOCKED_ZONE_ROOMS)
	return zones


## n objectives: key 1..n-1 (if any), then the mission item.
static func objectives(level: int) -> Array[Dictionary]:
	var n := clamp_level(level)
	var out: Array[Dictionary] = []
	for stage in range(1, n):
		out.append({
			"kind": KIND_KEY,
			"stage": stage,
			"label": _key_label(stage, n - 1),
		})
	out.append({
		"kind": KIND_MISSION,
		"stage": 0,
		"label": "Recover the mission item",
	})
	return out


static func _key_label(stage: int, total_keys: int) -> String:
	if total_keys <= 1:
		return "Find the sector key"
	return "Find sector key %d" % stage


static func counts_match_cycle(level: int) -> bool:
	var kinds := monster_kinds(level)
	var slimes := 0
	var hares := 0
	var tanks := 0
	for kind in kinds:
		match kind:
			KIND_SLIME:
				slimes += 1
			KIND_HARE:
				hares += 1
			KIND_TANK:
				tanks += 1
			_:
				return false
	return (
		slimes == slime_count(level)
		and hares == hare_count(level)
		and tanks == tank_count(level)
		and kinds.size() == clamp_level(level)
	)
