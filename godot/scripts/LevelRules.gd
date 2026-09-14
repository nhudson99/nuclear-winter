class_name LevelRules
extends RefCounted

## Pure rules for how a play level scales. Kept free of nodes so smokes can
## check the formulas without booting a map.
##
## Monsters cycle easy → moderate → dangerous as the level index grows:
##   n=1 slime, n=2 slime+hare, n=3 slime+hare+tank, n=4 …+tarantula, n=5 …+widow, n=6 …+toad…
## Objectives: one mission item, plus (n-1) keys that each open the next locked
## wing of rooms. The mission item sits in the last locked wing.

const KIND_SLIME := "slime"
const KIND_HARE := "hare"
const KIND_TANK := "tank"
const KIND_TARANTULA := "tarantula"
const KIND_WIDOW := "widow"
const KIND_TOAD := "toad"
const KIND_MISSION := "mission"
const KIND_KEY := "key"

const MONSTER_CYCLE: Array[String] = [
	KIND_SLIME, KIND_HARE, KIND_TANK, KIND_TARANTULA, KIND_WIDOW, KIND_TOAD
]

## Level 1 keeps the current nine-room mansion.
const LEVEL_1_ROOMS := 9
## Start wing on n>1: enough rooms to hide a key away from the exit.
const START_ZONE_ROOMS := 6
## Each extra objective is one more locked wing.
const LOCKED_ZONE_ROOMS := 5
## Higher levels stack wings onto separate floors so only one storey is live.
const MAX_WINGS_PER_FLOOR := 2
const TYPE_STAIR_UP := "stairwell_up"
const TYPE_STAIR_DOWN := "stairwell_down"


static func clamp_level(level: int) -> int:
	return maxi(level, 1)


static func kind_count(kind: String, level: int) -> int:
	var n := clamp_level(level)
	var count := 0
	var cycle_size := MONSTER_CYCLE.size()
	for i in n:
		if MONSTER_CYCLE[i % cycle_size] == kind:
			count += 1
	return count


static func slime_count(level: int) -> int:
	return kind_count(KIND_SLIME, level)


static func hare_count(level: int) -> int:
	return kind_count(KIND_HARE, level)


static func tank_count(level: int) -> int:
	return kind_count(KIND_TANK, level)


static func tarantula_count(level: int) -> int:
	return kind_count(KIND_TARANTULA, level)


static func widow_count(level: int) -> int:
	return kind_count(KIND_WIDOW, level)


static func toad_count(level: int) -> int:
	return kind_count(KIND_TOAD, level)


## One kind per spawned monster, in cycle order: slime, hare, tank, tarantula, widow…
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
		KIND_TARANTULA: tarantula_count(level),
		KIND_WIDOW: widow_count(level),
		KIND_TOAD: toad_count(level),
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


static func floor_count(level: int) -> int:
	return int(ceili(float(zone_count(level)) / float(MAX_WINGS_PER_FLOOR)))


static func floor_for_zone(zone: int) -> int:
	return maxi(zone, 0) / MAX_WINGS_PER_FLOOR


static func zones_on_floor(level: int, floor: int) -> Array[int]:
	var out: Array[int] = []
	var total := zone_count(level)
	var start := floor * MAX_WINGS_PER_FLOOR
	for zone in range(start, mini(start + MAX_WINGS_PER_FLOOR, total)):
		out.append(zone)
	return out


static func floor_has_up_stair(level: int, floor: int) -> bool:
	return floor >= 0 and floor < floor_count(level) - 1


static func floor_has_down_stair(level: int, floor: int) -> bool:
	return floor > 0 and floor < floor_count(level)


## Higher levels scatter the roster instead of parking each kind on a fixed cell.
static func randomize_monster_spawns(level: int) -> bool:
	return clamp_level(level) >= 2


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
	var counted := {
		KIND_SLIME: 0,
		KIND_HARE: 0,
		KIND_TANK: 0,
		KIND_TARANTULA: 0,
		KIND_WIDOW: 0,
		KIND_TOAD: 0,
	}
	for kind in kinds:
		if not counted.has(kind):
			return false
		counted[kind] += 1
	return (
		int(counted[KIND_SLIME]) == slime_count(level)
		and int(counted[KIND_HARE]) == hare_count(level)
		and int(counted[KIND_TANK]) == tank_count(level)
		and int(counted[KIND_TARANTULA]) == tarantula_count(level)
		and int(counted[KIND_WIDOW]) == widow_count(level)
		and int(counted[KIND_TOAD]) == toad_count(level)
		and kinds.size() == clamp_level(level)
	)
