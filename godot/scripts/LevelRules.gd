class_name LevelRules
extends RefCounted

## Pure rules for how a play level scales. Kept free of nodes so smokes can
## check the formulas without booting a map.
##
## Monsters spawn by difficulty tier (random pick within the tier):
##   Easy: slime, toad
##   Med:  hare, stalker, tarantula
##   Hard: tank, widow, void
## Levels 1–3: one slot per level, cycling easy → med → hard.
## After level 3: total = ceil(n/2), hard = floor(n/3), remaining from the
## easy/med cycle. Objectives: level 1 lists one goal, find the main item and
## leave. Level n after that lists n goals — the library bookcase-lever (opens
## the first wing LockedDoor), then one sector key per later lock, then the
## mission item. The steam valve still seals the mission pocket, but it is not
## a checklist line. Floors grow on odd levels (`ceil(n / 2)`).

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
const LABEL_BOOKSHELF := "Search the library bookcases for the hidden lever"
## Older checklist copy. Not selected: the bookcase lever, keys, and mission
## item already fill level n, and level 1 is find-and-leave only.
const LABEL_VALVE := "Follow the pipes and shut the steam valve"

const TIER_EASY := "easy"
const TIER_MED := "med"
const TIER_HARD := "hard"

## Random pick within each tier. Hare and stalker are distinct med-tier picks.
const MONSTER_TIER_EASY: Array[String] = [KIND_SLIME, KIND_TOAD]
const MONSTER_TIER_MED: Array[String] = [KIND_HARE, KIND_STALKER, KIND_TARANTULA]
const MONSTER_TIER_HARD: Array[String] = [KIND_TANK, KIND_WIDOW, KIND_VOID]

## Early levels / leftover slots walk this difficulty order.
const DIFFICULTY_CYCLE: Array[String] = [TIER_EASY, TIER_MED, TIER_HARD]

## Kept for call-site compatibility; normal generation no longer walks this list.
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


static func monster_count(level: int) -> int:
	var n := clamp_level(level)
	if n <= 3:
		return n
	return int(ceili(float(n) / 2.0))


static func hard_monster_count(level: int) -> int:
	var n := clamp_level(level)
	if n <= 3:
		return 1 if n >= 3 else 0
	return int(floor(float(n) / 3.0))


static func kinds_for_tier(tier: String) -> Array[String]:
	match tier:
		TIER_EASY:
			return MONSTER_TIER_EASY.duplicate()
		TIER_MED:
			return MONSTER_TIER_MED.duplicate()
		TIER_HARD:
			return MONSTER_TIER_HARD.duplicate()
		_:
			return []


static func unique_kinds_for_tier(tier: String) -> Array[String]:
	var out: Array[String] = []
	for kind in kinds_for_tier(tier):
		if not out.has(kind):
			out.append(kind)
	return out


static func kind_in_tier(kind: String, tier: String) -> bool:
	return unique_kinds_for_tier(tier).has(kind)


static func tier_for_kind(kind: String) -> String:
	if kind_in_tier(kind, TIER_EASY):
		return TIER_EASY
	if kind_in_tier(kind, TIER_MED):
		return TIER_MED
	if kind_in_tier(kind, TIER_HARD):
		return TIER_HARD
	return ""


## Deterministic difficulty slots for a level (not the random kind inside a tier).
static func monster_slot_tiers(level: int) -> Array[String]:
	var n := clamp_level(level)
	var tiers: Array[String] = []
	if n <= 3:
		for i in n:
			tiers.append(DIFFICULTY_CYCLE[i % DIFFICULTY_CYCLE.size()])
		return tiers
	var total := monster_count(n)
	var hard_n := hard_monster_count(n)
	var remaining := maxi(total - hard_n, 0)
	for i in remaining:
		# Leftover slots only walk easy → med (hard is reserved by hard_n).
		tiers.append(DIFFICULTY_CYCLE[i % 2])
	for _i in hard_n:
		tiers.append(TIER_HARD)
	return tiers


static func _pick_tier_kind(tier: String, rng: RandomNumberGenerator = null) -> String:
	var pool := unique_kinds_for_tier(tier)
	if pool.is_empty():
		return KIND_SLIME
	if rng == null:
		return pool[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func kind_count(kind: String, level: int) -> int:
	var count := 0
	for entry in monster_kinds(level):
		if entry == kind:
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


## One kind per spawn slot. With `rng`, each slot rolls inside its tier; without
## `rng`, each slot takes the first unique kind in that tier (stable for smokes).
static func monster_kinds(level: int, rng: RandomNumberGenerator = null) -> Array[String]:
	var kinds: Array[String] = []
	for tier in monster_slot_tiers(level):
		kinds.append(_pick_tier_kind(tier, rng))
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


## Physical key pickups. Stage 1's wing lock is opened by the library lever
## instead of a key, so pickups are one fewer than locked doors when n > 1.
static func key_count(level: int) -> int:
	return maxi(clamp_level(level) - 2, 0)


## Wing lock stage unlocked by finding the hidden library lever (0 = none).
## Stage 1 is the first wing gate off the start sector; the library hosts it.
static func library_unlock_stage(level: int) -> int:
	return 1 if locked_door_count(level) > 0 else 0


## Alias kept for map code that pins the library on the stage-1 lock cell.
static func library_key_stage(level: int) -> int:
	return library_unlock_stage(level)


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
## Level n > 1: library bookcase-lever, later sector keys, then the mission item.
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
	var unlock_stage := library_unlock_stage(n)
	if unlock_stage > 0:
		out.append({
			"kind": KIND_BOOKSHELF,
			"stage": unlock_stage,
			"label": LABEL_BOOKSHELF,
		})
	var locked := locked_door_count(n)
	var extra_keys := key_count(n)
	for stage in range(2, locked + 1):
		out.append({
			"kind": KIND_KEY,
			"stage": stage,
			"label": _key_label(stage, extra_keys),
		})
	out.append({
		"kind": KIND_MISSION,
		"stage": 0,
		"label": LABEL_MISSION,
	})
	return out


static func _key_label(stage: int, total_keys: int) -> String:
	if total_keys <= 1:
		return "Find the sector key"
	return "Find sector key %d" % stage


static func counts_match_cycle(level: int) -> bool:
	var tiers := monster_slot_tiers(level)
	var kinds := monster_kinds(level)
	if kinds.size() != tiers.size() or kinds.size() != monster_count(level):
		return false
	var hard_n := 0
	for i in kinds.size():
		var kind: String = kinds[i]
		var tier: String = tiers[i]
		if not kind_in_tier(kind, tier):
			return false
		if tier == TIER_HARD:
			hard_n += 1
	return hard_n == hard_monster_count(level)
