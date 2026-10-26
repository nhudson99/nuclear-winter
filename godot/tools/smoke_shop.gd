extends SceneTree

## Headless smoke: map SHOP button, three-card menu, ration purchases.

func _initialize() -> void:
	call_deferred("_run")


func _progress() -> Node:
	return root.get_node("GameProgress")


func _run() -> void:
	var gp := _progress()
	gp.reset_for_tests()

	var packed: PackedScene = load("res://scenes/GameMap.tscn")
	if packed == null:
		push_error("Missing GameMap.tscn")
		quit(1)
		return
	var map: Control = packed.instantiate()
	root.add_child(map)
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame

	var shop_btn: Button = map.get_shop_button() if map.has_method("get_shop_button") else null
	var rations_label: Label = map.get_rations_label() if map.has_method("get_rations_label") else null
	var button_ok := shop_btn != null and shop_btn.text == "SHOP"
	var corner_ok := shop_btn != null and is_equal_approx(shop_btn.anchor_left, 1.0) and is_equal_approx(shop_btn.anchor_top, 0.0)
	var rations_ok := rations_label != null and rations_label.text.contains("0")
	print(
		"shop_button_ok=", button_ok,
		" top_right_ok=", corner_ok,
		" rations_label_ok=", rations_ok,
		" text=", shop_btn.text if shop_btn else ""
	)

	if not map.has_method("open_shop"):
		push_error("GameMap missing open_shop")
		quit(1)
		return
	map.open_shop()
	await process_frame
	var shop = map.get_shop_menu() if map.has_method("get_shop_menu") else null
	var cards = shop.get_node_or_null("Cards") if shop else null
	var names := _card_names(cards)
	var cards_ok: bool = shop != null and cards != null and names.size() == 6
	var titles_ok: bool = (
		names.has("PISTOL")
		and names.has("SHOTGUN")
		and names.has("AK")
		and names.has("HEALTH")
		and names.has("SPEEDUPGRADE")
		and names.has("SNEAK")
		and not names.has("PISTOLAMMO")
	)
	print("shop_open_ok=", map.is_shop_open() and cards_ok, " titles_ok=", titles_ok, " cards=", names)

	var pistol_item := GameProgress.ShopItem.PISTOL
	var shotgun_item := GameProgress.ShopItem.SHOTGUN
	var ak_item := GameProgress.ShopItem.AK
	var speed_item := GameProgress.ShopItem.SPEED
	var sneak_item := GameProgress.ShopItem.SNEAK
	var health_item := GameProgress.ShopItem.HEALTH
	var pistol_ammo := GameProgress.ShopItem.PISTOL_AMMO
	var shotgun_ammo := GameProgress.ShopItem.SHOTGUN_AMMO
	var ak_ammo := GameProgress.ShopItem.AK_AMMO
	var pistol_btn = shop.get_buy_button(pistol_item) if shop else null
	var broke_ok: bool = pistol_btn != null and bool(pistol_btn.disabled) and not gp.can_buy(pistol_item)
	print("cannot_buy_pistol_broke_ok=", broke_ok)

	gp.rations = 5
	gp.rations_changed.emit(5)
	await process_frame
	var pistol_buy_ok: bool = gp.buy(pistol_item)
	var pistol_owned_ok: bool = (
		gp.has_pistol
		and gp.rations == 0
		and gp.pistol_loaded == GameProgress.PISTOL_MAG
		and gp.pistol_reserve == 0
		and gp.selected_weapon == GameProgress.WeaponId.PISTOL
	)
	await process_frame
	var after_pistol := _card_names(shop.get_node_or_null("Cards"))
	var ammo_listed: bool = after_pistol.has("PISTOLAMMO") and not after_pistol.has("PISTOL")
	print(
		"pistol_buy_ok=", pistol_buy_ok and pistol_owned_ok and ammo_listed,
		" rations=", gp.rations,
		" loaded=", gp.pistol_loaded,
		" cards=", after_pistol
	)

	gp.rations = 1
	var speed_buy_ok: bool = gp.buy(speed_item)
	var speed_ok: bool = speed_buy_ok and is_equal_approx(gp.speed_multiplier(), 1.05)
	print("speed_buy_ok=", speed_ok, " ranks=", gp.speed_ranks)

	gp.rations = 3
	var sneak_buy_ok: bool = gp.buy(sneak_item) and gp.has_sneak
	print("sneak_buy_ok=", sneak_buy_ok)

	gp.rations = 10
	var unique_locked: bool = not gp.buy(pistol_item) and not gp.buy(sneak_item)
	var speed_stack: bool = gp.buy(speed_item) and gp.speed_ranks == 2
	print("unique_locked_ok=", unique_locked, " speed_stack_ok=", speed_stack)

	gp.rations = 20
	var speed_cap_ok := true
	while gp.speed_ranks < GameProgress.MAX_UPGRADE_RANKS:
		if not gp.buy(speed_item):
			speed_cap_ok = false
			break
	var speed_stopped: bool = speed_cap_ok and gp.speed_ranks == 5 and not gp.buy(speed_item)
	var speed_btn = shop.get_buy_button(speed_item)
	await process_frame
	var speed_max_label: bool = speed_btn != null and speed_btn.text == "MAX" and bool(speed_btn.disabled)
	print("speed_cap_ok=", speed_stopped and speed_max_label, " ranks=", gp.speed_ranks)

	gp.rations = 10
	var health_ok := true
	for _rank in GameProgress.MAX_UPGRADE_RANKS:
		if not gp.buy(health_item):
			health_ok = false
			break
	var health_cap_ok: bool = (
		health_ok
		and gp.health_ranks == 5
		and gp.max_health() == 150
		and not gp.buy(health_item)
	)
	print("health_cap_ok=", health_cap_ok, " ranks=", gp.health_ranks, " max=", gp.max_health())

	gp.rations = 10
	var pistol_packs := 0
	while gp.buy(pistol_ammo):
		pistol_packs += 1
	var pistol_ammo_ok: bool = (
		pistol_packs == 4
		and gp.total_ammo(GameProgress.WeaponId.PISTOL) == GameProgress.PISTOL_CAP
		and not gp.can_buy(pistol_ammo)
	)
	var ammo_btn = shop.get_buy_button(pistol_ammo)
	await process_frame
	var ammo_full_label: bool = ammo_btn != null and ammo_btn.text == "FULL"
	print("pistol_ammo_ok=", pistol_ammo_ok and ammo_full_label, " packs=", pistol_packs, " total=", gp.total_ammo(GameProgress.WeaponId.PISTOL))

	gp.rations = 40
	var shotgun_buy_ok: bool = (
		gp.buy(shotgun_item)
		and gp.has_shotgun
		and gp.shotgun_loaded == GameProgress.SHOTGUN_MAG
		and gp.shotgun_reserve == 0
	)
	var shotgun_pack_ok: bool = gp.buy(shotgun_ammo) and gp.total_ammo(GameProgress.WeaponId.SHOTGUN) == GameProgress.SHOTGUN_CAP
	var shotgun_cap_ok: bool = shotgun_pack_ok and not gp.buy(shotgun_ammo)
	print("shotgun_ammo_ok=", shotgun_buy_ok and shotgun_cap_ok, " total=", gp.total_ammo(GameProgress.WeaponId.SHOTGUN))

	gp.rations = 40
	var ak_buy_ok: bool = (
		gp.buy(ak_item)
		and gp.has_ak
		and gp.ak_loaded == GameProgress.AK_MAG
		and gp.ak_reserve == 0
	)
	var ak_pack_ok: bool = gp.buy(ak_ammo) and gp.total_ammo(GameProgress.WeaponId.AK) == GameProgress.AK_CAP
	var ak_cap_ok: bool = ak_pack_ok and not gp.buy(ak_ammo)
	print("ak_ammo_ok=", ak_buy_ok and ak_cap_ok, " total=", gp.total_ammo(GameProgress.WeaponId.AK))

	var full_names := _card_names(shop.get_node_or_null("Cards"))
	var full_catalog: bool = (
		not full_names.has("PISTOL")
		and not full_names.has("SHOTGUN")
		and not full_names.has("AK")
		and full_names.has("PISTOLAMMO")
		and full_names.has("SHOTGUNAMMO")
		and full_names.has("AKAMMO")
		and full_names.has("HEALTH")
		and full_names.has("SPEEDUPGRADE")
		and full_names.has("SNEAK")
	)
	print("full_catalog_ok=", full_catalog, " cards=", full_names)

	var generation_before: int = gp.shop_generation
	var loaded_before: int = gp.pistol_loaded
	var reserve_before: int = gp.pistol_reserve
	gp.advance_level()
	var persisted: bool = (
		gp.shop_generation == generation_before + 1
		and gp.has_pistol
		and gp.has_shotgun
		and gp.has_ak
		and gp.has_sneak
		and gp.pistol_loaded == loaded_before
		and gp.pistol_reserve == reserve_before
		and gp.speed_ranks == 5
		and gp.health_ranks == 5
		and gp.current_level == 2
	)
	await process_frame
	var refreshed_names := _card_names(shop.get_node_or_null("Cards"))
	var refreshed: bool = refreshed_names.size() == full_names.size() and full_catalog
	print("persist_ok=", persisted, " shop_refresh_ok=", refreshed, " generation=", gp.shop_generation)

	var costs_ok: bool = (
		gp.shop_cost(pistol_item) == 5
		and gp.shop_cost(shotgun_item) == 10
		and gp.shop_cost(ak_item) == 25
		and gp.shop_cost(pistol_ammo) == 1
		and gp.shop_cost(shotgun_ammo) == 5
		and gp.shop_cost(ak_ammo) == 10
		and gp.shop_cost(speed_item) == 1
		and gp.shop_cost(health_item) == 1
		and gp.shop_cost(sneak_item) == 3
	)
	print("costs_ok=", costs_ok)

	var all_ok: bool = (
		button_ok
		and corner_ok
		and rations_ok
		and cards_ok
		and titles_ok
		and broke_ok
		and pistol_buy_ok
		and pistol_owned_ok
		and ammo_listed
		and speed_ok
		and sneak_buy_ok
		and unique_locked
		and speed_stack
		and speed_stopped
		and speed_max_label
		and health_cap_ok
		and pistol_ammo_ok
		and ammo_full_label
		and shotgun_buy_ok
		and shotgun_cap_ok
		and ak_buy_ok
		and ak_cap_ok
		and full_catalog
		and persisted
		and refreshed
		and costs_ok
	)
	print("shop_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)


func _card_names(cards: Node) -> PackedStringArray:
	var names := PackedStringArray()
	if cards == null:
		return names
	for child in cards.get_children():
		names.append(String(child.name))
	return names
