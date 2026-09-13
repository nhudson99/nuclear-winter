extends Node

## Session-wide run state: rations, shop loadout, and which aristocrat line to show.

enum AristocratMode { BRIEFING, VICTORY }
enum ShopItem { PISTOL, SPEED, SNEAK }

const PISTOL_COST := 5
const SPEED_COST := 1
const SNEAK_COST := 3
const SPEED_BONUS := 0.05
const LEVEL_RATION_REWARD := 5

const VICTORY_LINE := "Well, you survived. Good for you. Here is your ration reward"
const BRIEFING_LINE := "You want to eat? Then get to work"

signal rations_changed(amount: int)
signal upgrades_changed

var rations: int = 0
var has_pistol: bool = false
var speed_ranks: int = 0
var has_sneak: bool = false
var aristocrat_mode: AristocratMode = AristocratMode.BRIEFING
var current_level: int = 1


func speed_bonus() -> float:
	return SPEED_BONUS * float(speed_ranks)


func speed_multiplier() -> float:
	return 1.0 + speed_bonus()


func shop_cost(item: ShopItem) -> int:
	match item:
		ShopItem.PISTOL:
			return PISTOL_COST
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
		ShopItem.SNEAK:
			return has_sneak
		ShopItem.SPEED:
			return false
		_:
			return false


func can_buy(item: ShopItem) -> bool:
	if owns_unique(item):
		return false
	return rations >= shop_cost(item)


func buy(item: ShopItem) -> bool:
	if not can_buy(item):
		return false
	rations -= shop_cost(item)
	match item:
		ShopItem.PISTOL:
			has_pistol = true
		ShopItem.SPEED:
			speed_ranks += 1
		ShopItem.SNEAK:
			has_sneak = true
		_:
			rations += shop_cost(item)
			return false
	rations_changed.emit(rations)
	upgrades_changed.emit()
	return true


func award_escape() -> void:
	rations += LEVEL_RATION_REWARD
	rations_changed.emit(rations)


func advance_level() -> void:
	current_level = LevelRules.clamp_level(current_level + 1)


func dialogue_line() -> String:
	if aristocrat_mode == AristocratMode.VICTORY:
		return VICTORY_LINE
	return BRIEFING_LINE


func reset_for_tests() -> void:
	rations = 0
	has_pistol = false
	speed_ranks = 0
	has_sneak = false
	aristocrat_mode = AristocratMode.BRIEFING
	current_level = 1
	rations_changed.emit(rations)
	upgrades_changed.emit()
