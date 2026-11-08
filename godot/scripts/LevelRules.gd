class_name LevelRules
extends RefCounted

## Pure rules for how a play level scales. Kept free of nodes so smokes can
## check the formulas without booting a map.
##
## Monsters cycle easy → moderate → dangerous as the level index grows:
##   slime → hare → stalker → tank → void → tarantula → widow → toad…
## Objectives: level 1 lists one goal, find the main item and leave. Level n
## after that lists n goals — one sector key per wing lock, then the mission
## item. The first wing's key and LockedDoor live in the library room. The
## steam valve still seals the mission pocket, but it is not a checklist line
## (older notes counted it, which made level n list n+1 goals). Floors grow
## on odd levels (`ceil(n / 2)`).

const KIND_SLIME := "slime"
const KIND_HARE := "hare"
const KIND_STALKER := "stalker"
const KIND_TANK := "tank"
const KIND_VOID := "void"
const KIND_TARANTULA := "tarantula"
const KIND_WIDOW := "widow"
const KIND_TOAD := "toad"
const KIND_MISSION := "mission"
const KIND_KEY := "key"
const KIND_VALVE := "valve"
const KIND_BOOKSHELF := "bookshelf"
const LABEL_FIND_AND_LEAVE := "Find the main item and leave"
const LABEL_MISSION := "Recover the mission item"
## Older checklist copy. Not selected: keys plus the mission item already fill
## level n, and level 1 is find-and-leave only.
const LABEL_VALVE := "Follow the pipes and shut the steam valve"

const MONSTER_CYCLE: Array[String] = [
	KIND_SLIME, KIND_HARE, KIND_STALKER, KIND_TANK, KIND_VOID, KIND_TARANTULA, KIND_WIDOW, KIND_TOAD
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


static func stalker_count(level: int) -> int:
	return kind_count(KIND_STALKER, level)


static func tank_count(level: int) -> int:
	return kind_count(KIND_TANK, level)


static func tarantula_count(level: int) -> int:
	return kind_count(KIND_TARANTULA, level)


static func widow_count(level: int) -> int:
	return kind_count(KIND_WIDOW, level)


static func toad_count(level: int) -> int:
	return kind_count(KIND_TOAD, level)


static func void_count(level: int) -> int:
	return kind_count(KIND_VOID, level)


## One kind per spawned monster, in cycle order: slime, hare, stalker, tank…
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
		KIND_STALKER: stalker_count(level),
		KIND_TANK: tank_count(level),
		KIND_VOID: void_count(level),
		KIND_TARANTULA: tarantula_count(level),
		KIND_WIDOW: widow_count(level),
		KIND_TOAD: toad_count(level),
	}


## Level n lists n objectives. Level 1 is the mission item only.
static func objective_count(level: int) -> int:
	return clamp_level(level)


static func locked_door_count(level: int) -> int:
	return maxi(clamp_level(level) - 1, 0)


## One physical key per locked door (wing or stair).
static func key_count(level: int) -> int:
	return locked_door_count(level)


## Wing stage whose key + LockedDoor are hosted by the library room (0 = none).
## Stage 1 is the first wing gate off the start sector.
static func library_key_stage(level: int) -> int:
	return 1 if locked_door_count(level) > 0 else 0


## Legacy alias — bookshelf unlock is gone; the library hosts a normal key.
static func library_unlock_stage(level: int) -> int:
	return library_key_stage(level)


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


## Every odd level adds another floor: 1→1, 2→1, 3→2, 4→2, …
static func floor_count(level: int) -> int:
	return int(ceili(float(clamp_level(level)) / float(MAX_WINGS_PER_FLOOR)))


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


## Floors adjacent to `floor` (0-based, same index the HUD shows as floor+1).
## Standing on floor 1 preloads floor 2. Standing on floor 2 preloads 1 and 3.
static func neighbor_floors(level: int, floor: int) -> Array[int]:
	var count := floor_count(level)
	if count <= 1:
		return []
	var index := clampi(floor, 0, count - 1)
	var out: Array[int] = []
	if index - 1 >= 0:
		out.append(index - 1)
	if index + 1 < count:
		out.append(index + 1)
	return out


## Higher levels scatter the roster instead of parking each kind on a fixed cell.
static func randomize_monster_spawns(level: int) -> bool:
	return clamp_level(level) >= 2


## Level 1: find the main item and leave.
## Level n > 1: sector keys (library hosts stage 1), then the mission item.
## The steam valve is not selected. Listing it beside the keys and the mission
## item made every level one goal over the count.
static func objectives(level: int) -> Array[Dictionary]:
	var n := clamp_level(level)
	var out: Array[Dictionary] = []
	if n <= 1:
		out.append({
			"kind": KIND_MISSION,
			"stage": 0,
			"label": LABEL_FIND_AND_LEAVE,
		})
		return out
	var keys := key_count(n)
	var library_stage := library_key_stage(n)
	for stage in range(1, keys + 1):
		out.append({
			"kind": KIND_KEY,
			"stage": stage,
			"label": _key_label(stage, keys, library_stage),
		})
	out.append({
		"kind": KIND_MISSION,
		"stage": 0,
		"label": LABEL_MISSION,
	})
	return out


static func _key_label(stage: int, total_keys: int, library_stage: int = 0) -> String:
	if stage == library_stage and library_stage > 0:
		return "Find the sector key in the library"
	if total_keys <= 1:
		return "Find the sector key"
	return "Find sector key %d" % stage


static func counts_match_cycle(level: int) -> bool:
	var kinds := monster_kinds(level)
	var counted := {
		KIND_SLIME: 0,
		KIND_HARE: 0,
		KIND_STALKER: 0,
		KIND_TANK: 0,
		KIND_VOID: 0,
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
		and int(counted[KIND_STALKER]) == stalker_count(level)
		and int(counted[KIND_TANK]) == tank_count(level)
		and int(counted[KIND_VOID]) == void_count(level)
		and int(counted[KIND_TARANTULA]) == tarantula_count(level)
		and int(counted[KIND_WIDOW]) == widow_count(level)
		and int(counted[KIND_TOAD]) == toad_count(level)
		and kinds.size() == clamp_level(level)
	)
