extends Node

## Session-wide run state: rations, shop loadout, and which aristocrat line to show.
## Owned guns, ammo, and upgrades stay on this autoload, so a new floor keeps them.

enum AristocratMode { BRIEFING, VICTORY, DEFEAT }
enum WeaponId { NONE, PISTOL, SHOTGUN, AK }
enum ShopItem {
	PISTOL,
	SPEED,
	SNEAK,
	SHOTGUN,
	AK,
	PISTOL_AMMO,
	SHOTGUN_AMMO,
	AK_AMMO,
	HEALTH,
}

const PISTOL_COST := 5
const SHOTGUN_COST := 10
const AK_COST := 25
const PISTOL_AMMO_COST := 1
const SHOTGUN_AMMO_COST := 5
const AK_AMMO_COST := 10
const SPEED_COST := 1
const HEALTH_COST := 1
const SNEAK_COST := 3

const PISTOL_MAG := 10
const SHOTGUN_MAG := 8
const AK_MAG := 30
const PISTOL_CAP := 50
const SHOTGUN_CAP := 16
const AK_CAP := 60

const PISTOL_DAMAGE := 10
const SHOTGUN_PELLETS := 10
const SHOTGUN_PELLET_DAMAGE := 10
const AK_DAMAGE := 25

const SPEED_BONUS := 0.05
const HEALTH_PER_RANK := 10
const BASE_MAX_HEALTH := 100
const MAX_UPGRADE_RANKS := 5
const LEVEL_RATION_REWARD := 5

const VICTORY_LINE := "Well, you survived. Good for you. Here is your ration reward"
const BRIEFING_LINE := "You want to eat? Then get to work"
const DEFEAT_LINE := "Finally, you are no longer a drain on the motherland"

signal rations_changed(amount: int)
signal upgrades_changed
signal ammo_changed
signal shop_refreshed(generation: int)

var rations: int = 0
var has_pistol: bool = false
var has_shotgun: bool = false
var has_ak: bool = false
var pistol_loaded: int = 0
var pistol_reserve: int = 0
var shotgun_loaded: int = 0
var shotgun_reserve: int = 0
var ak_loaded: int = 0
var ak_reserve: int = 0
var selected_weapon: WeaponId = WeaponId.NONE
var speed_ranks: int = 0
var health_ranks: int = 0
var has_sneak: bool = false
var aristocrat_mode: AristocratMode = AristocratMode.BRIEFING
var current_level: int = 1
## Bumps when the level changes so the next map visit stocks the full catalog again.
var shop_generation: int = 0


func speed_bonus() -> float:
	return SPEED_BONUS * float(speed_ranks)


func speed_multiplier() -> float:
	return 1.0 + speed_bonus()


func health_bonus() -> int:
	return HEALTH_PER_RANK * health_ranks


func max_health() -> int:
	return BASE_MAX_HEALTH + health_bonus()


func shop_cost(item: ShopItem) -> int:
	match item:
		ShopItem.PISTOL:
			return PISTOL_COST
		ShopItem.SHOTGUN:
			return SHOTGUN_COST
		ShopItem.AK:
			return AK_COST
		ShopItem.PISTOL_AMMO:
			return PISTOL_AMMO_COST
		ShopItem.SHOTGUN_AMMO:
			return SHOTGUN_AMMO_COST
		ShopItem.AK_AMMO:
			return AK_AMMO_COST
		ShopItem.HEALTH:
			return HEALTH_COST
		ShopItem.SPEED:
			return SPEED_COST
		ShopItem.SNEAK:
			return SNEAK_COST
		_:
			return 0


func owns_unique(item: ShopItem) -> bool:
	match item:
		ShopItem.PISTOL:
			return has_pistol
		ShopItem.SHOTGUN:
			return has_shotgun
		ShopItem.AK:
			return has_ak
		ShopItem.SNEAK:
			return has_sneak
		ShopItem.SPEED, ShopItem.HEALTH, ShopItem.PISTOL_AMMO, ShopItem.SHOTGUN_AMMO, ShopItem.AK_AMMO:
			return false
		_:
			return false


func can_buy(item: ShopItem) -> bool:
	if not _shop_item_available(item):
		return false
	return rations >= shop_cost(item)


func buy(item: ShopItem) -> bool:
	if not can_buy(item):
		return false
	rations -= shop_cost(item)
	match item:
		ShopItem.PISTOL:
			_grant_weapon(WeaponId.PISTOL)
		ShopItem.SHOTGUN:
			_grant_weapon(WeaponId.SHOTGUN)
		ShopItem.AK:
			_grant_weapon(WeaponId.AK)
		ShopItem.PISTOL_AMMO:
			pistol_reserve += PISTOL_MAG
		ShopItem.SHOTGUN_AMMO:
			shotgun_reserve += SHOTGUN_MAG
		ShopItem.AK_AMMO:
			ak_reserve += AK_MAG
		ShopItem.HEALTH:
			health_ranks += 1
		ShopItem.SPEED:
			speed_ranks += 1
		ShopItem.SNEAK:
			has_sneak = true
		_:
			rations += shop_cost(item)
			return false
	rations_changed.emit(rations)
	ammo_changed.emit()
	upgrades_changed.emit()
	return true


## Every visit offers the full current catalog: guns you do not own yet, a
## magazine for each gun you do, and the three upgrades.
func shop_catalog() -> Array[ShopItem]:
	var items: Array[ShopItem] = []
	if not has_pistol:
		items.append(ShopItem.PISTOL)
	if not has_shotgun:
		items.append(ShopItem.SHOTGUN)
	if not has_ak:
		items.append(ShopItem.AK)
	if has_pistol:
		items.append(ShopItem.PISTOL_AMMO)
	if has_shotgun:
		items.append(ShopItem.SHOTGUN_AMMO)
	if has_ak:
		items.append(ShopItem.AK_AMMO)
	items.append(ShopItem.HEALTH)
	items.append(ShopItem.SPEED)
	items.append(ShopItem.SNEAK)
	return items


func owns_weapon(weapon: WeaponId) -> bool:
	match weapon:
		WeaponId.PISTOL:
			return has_pistol
		WeaponId.SHOTGUN:
			return has_shotgun
		WeaponId.AK:
			return has_ak
		WeaponId.NONE:
			return false
		_:
			return false


func owned_weapons() -> Array[WeaponId]:
	var owned: Array[WeaponId] = []
	for weapon in [WeaponId.PISTOL, WeaponId.SHOTGUN, WeaponId.AK]:
		if owns_weapon(weapon):
			owned.append(weapon)
	return owned


func weapon_slot(weapon: WeaponId) -> int:
	match weapon:
		WeaponId.PISTOL:
			return 1
		WeaponId.SHOTGUN:
			return 2
		WeaponId.AK:
			return 3
		WeaponId.NONE:
			return 0
		_:
			return 0


func weapon_name(weapon: WeaponId) -> String:
	match weapon:
		WeaponId.PISTOL:
			return "PISTOL"
		WeaponId.SHOTGUN:
			return "SHOTGUN"
		WeaponId.AK:
			return "AK"
		WeaponId.NONE:
			return ""
		_:
			return ""


func magazine_size(weapon: WeaponId) -> int:
	match weapon:
		WeaponId.PISTOL:
			return PISTOL_MAG
		WeaponId.SHOTGUN:
			return SHOTGUN_MAG
		WeaponId.AK:
			return AK_MAG
		WeaponId.NONE:
			return 0
		_:
			return 0


func ammo_cap(weapon: WeaponId) -> int:
	match weapon:
		WeaponId.PISTOL:
			return PISTOL_CAP
		WeaponId.SHOTGUN:
			return SHOTGUN_CAP
		WeaponId.AK:
			return AK_CAP
		WeaponId.NONE:
			return 0
		_:
			return 0


func loaded_ammo(weapon: WeaponId) -> int:
	match weapon:
		WeaponId.PISTOL:
			return pistol_loaded
		WeaponId.SHOTGUN:
			return shotgun_loaded
		WeaponId.AK:
			return ak_loaded
		WeaponId.NONE:
			return 0
		_:
			return 0


func reserve_ammo(weapon: WeaponId) -> int:
	match weapon:
		WeaponId.PISTOL:
			return pistol_reserve
		WeaponId.SHOTGUN:
			return shotgun_reserve
		WeaponId.AK:
			return ak_reserve
		WeaponId.NONE:
			return 0
		_:
			return 0


func total_ammo(weapon: WeaponId) -> int:
	return loaded_ammo(weapon) + reserve_ammo(weapon)


func can_accept_pack(weapon: WeaponId) -> bool:
	if not owns_weapon(weapon):
		return false
	return total_ammo(weapon) + magazine_size(weapon) <= ammo_cap(weapon)


func select_weapon(weapon: WeaponId) -> bool:
	if weapon != WeaponId.NONE and not owns_weapon(weapon):
		return false
	if selected_weapon == weapon:
		return true
	selected_weapon = weapon
	upgrades_changed.emit()
	return true


func cycle_weapon(step: int) -> void:
	var owned := owned_weapons()
	if owned.is_empty():
		selected_weapon = WeaponId.NONE
		upgrades_changed.emit()
		return
	var index := owned.find(selected_weapon)
	if index < 0:
		index = 0 if step >= 0 else owned.size() - 1
	else:
		index = posmod(index + step, owned.size())
	if selected_weapon == owned[index]:
		return
	selected_weapon = owned[index]
	upgrades_changed.emit()


func consume_round(weapon: WeaponId) -> bool:
	if not owns_weapon(weapon) or loaded_ammo(weapon) <= 0:
		return false
	_set_loaded(weapon, loaded_ammo(weapon) - 1)
	ammo_changed.emit()
	return true


func reload_weapon(weapon: WeaponId) -> bool:
	if not owns_weapon(weapon):
		return false
	var room := magazine_size(weapon) - loaded_ammo(weapon)
	var reserve := reserve_ammo(weapon)
	if room <= 0 or reserve <= 0:
		return false
	var moved := mini(room, reserve)
	_set_loaded(weapon, loaded_ammo(weapon) + moved)
	_set_reserve(weapon, reserve - moved)
	ammo_changed.emit()
	return true


func award_escape() -> void:
	rations += LEVEL_RATION_REWARD
	rations_changed.emit(rations)


func advance_level() -> void:
	current_level = LevelRules.clamp_level(current_level + 1)
	shop_generation += 1
	shop_refreshed.emit(shop_generation)


func dialogue_line() -> String:
	match aristocrat_mode:
		AristocratMode.VICTORY:
			return VICTORY_LINE
		AristocratMode.DEFEAT:
			return DEFEAT_LINE
		AristocratMode.BRIEFING:
			return BRIEFING_LINE
		_:
			return BRIEFING_LINE


func reset_for_tests() -> void:
	rations = 0
	has_pistol = false
	has_shotgun = false
	has_ak = false
	pistol_loaded = 0
	pistol_reserve = 0
	shotgun_loaded = 0
	shotgun_reserve = 0
	ak_loaded = 0
	ak_reserve = 0
	selected_weapon = WeaponId.NONE
	speed_ranks = 0
	health_ranks = 0
	has_sneak = false
	aristocrat_mode = AristocratMode.BRIEFING
	current_level = 1
	shop_generation = 0
	rations_changed.emit(rations)
	ammo_changed.emit()
	upgrades_changed.emit()


func _shop_item_available(item: ShopItem) -> bool:
	if owns_unique(item):
		return false
	match item:
		ShopItem.PISTOL, ShopItem.SHOTGUN, ShopItem.AK, ShopItem.SNEAK:
			return true
		ShopItem.SPEED:
			return speed_ranks < MAX_UPGRADE_RANKS
		ShopItem.HEALTH:
			return health_ranks < MAX_UPGRADE_RANKS
		ShopItem.PISTOL_AMMO:
			return can_accept_pack(WeaponId.PISTOL)
		ShopItem.SHOTGUN_AMMO:
			return can_accept_pack(WeaponId.SHOTGUN)
		ShopItem.AK_AMMO:
			return can_accept_pack(WeaponId.AK)
		_:
			return false


func _grant_weapon(weapon: WeaponId) -> void:
	match weapon:
		WeaponId.PISTOL:
			has_pistol = true
		WeaponId.SHOTGUN:
			has_shotgun = true
		WeaponId.AK:
			has_ak = true
		WeaponId.NONE:
			return
		_:
			return
	# The purchase includes one loaded magazine and nothing in reserve.
	_set_loaded(weapon, magazine_size(weapon))
	_set_reserve(weapon, 0)
	if selected_weapon == WeaponId.NONE:
		selected_weapon = weapon


func _set_loaded(weapon: WeaponId, amount: int) -> void:
	var stored := maxi(amount, 0)
	match weapon:
		WeaponId.PISTOL:
			pistol_loaded = stored
		WeaponId.SHOTGUN:
			shotgun_loaded = stored
		WeaponId.AK:
			ak_loaded = stored
		WeaponId.NONE:
			pass
		_:
			pass


func _set_reserve(weapon: WeaponId, amount: int) -> void:
	var stored := maxi(amount, 0)
	match weapon:
		WeaponId.PISTOL:
			pistol_reserve = stored
		WeaponId.SHOTGUN:
			shotgun_reserve = stored
		WeaponId.AK:
			ak_reserve = stored
		WeaponId.NONE:
			pass
		_:
			pass
