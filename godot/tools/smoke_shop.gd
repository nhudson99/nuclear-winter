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
	var cards_ok: bool = shop != null and cards != null and int(cards.get_child_count()) == 3
	var titles_ok: bool = false
	if cards_ok:
		var names := PackedStringArray()
		for child in cards.get_children():
			names.append(String(child.name))
		titles_ok = names.has("PISTOL") and names.has("SPEEDUPGRADE") and names.has("SNEAK")
	print("shop_open_ok=", map.is_shop_open() and cards_ok, " titles_ok=", titles_ok)

	var pistol_item := 0
	var speed_item := 1
	var sneak_item := 2
	var pistol_btn = shop.get_buy_button(pistol_item) if shop else null
	var broke_ok: bool = pistol_btn != null and bool(pistol_btn.disabled) and not gp.can_buy(pistol_item)
	print("cannot_buy_pistol_broke_ok=", broke_ok)

	gp.rations = 5
	gp.rations_changed.emit(5)
	await process_frame
	var pistol_buy_ok: bool = gp.buy(pistol_item)
	var pistol_owned_ok: bool = gp.has_pistol and gp.rations == 0
	print("pistol_buy_ok=", pistol_buy_ok and pistol_owned_ok, " rations=", gp.rations)

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

	var costs_ok: bool = (
		gp.shop_cost(pistol_item) == 5
		and gp.shop_cost(speed_item) == 1
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
		and speed_ok
		and sneak_buy_ok
		and unique_locked
		and speed_stack
		and costs_ok
	)
	print("shop_smoke_ok=", all_ok)
	quit(0 if all_ok else 1)
