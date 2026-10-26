extends Control
class_name ShopMenu

## Pip-Boy shop. Each visit sells the full catalog for this level: unowned guns,
## ammo for owned guns, health, speed, and sneak.

signal closed

var _ration_label: Label
var _cards: Array = []
var _status: Label
var _view := Vector2(1280, 720)


func _ready() -> void:
	name = "ShopMenu"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var view := get_viewport_rect().size
	if view.x < 64.0:
		view = Vector2(1280, 720)
	_view = view
	_build_chrome(view)
	_refresh()
	if not GameProgress.rations_changed.is_connected(_on_rations_changed):
		GameProgress.rations_changed.connect(_on_rations_changed)
	if not GameProgress.upgrades_changed.is_connected(_refresh):
		GameProgress.upgrades_changed.connect(_refresh)
	if not GameProgress.ammo_changed.is_connected(_refresh):
		GameProgress.ammo_changed.connect(_refresh)
	if not GameProgress.shop_refreshed.is_connected(_on_shop_refreshed):
		GameProgress.shop_refreshed.connect(_on_shop_refreshed)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_shop()
		get_viewport().set_input_as_handled()


func close_shop() -> void:
	closed.emit()
	queue_free()


func get_card(item: GameProgress.ShopItem) -> Dictionary:
	for card in _cards:
		if int(card["item"]) == int(item):
			return card
	return {}


func get_buy_button(item: GameProgress.ShopItem) -> Button:
	var card := get_card(item)
	return card.get("buy") as Button if not card.is_empty() else null


func _on_rations_changed(_amount: int) -> void:
	_refresh()


func _on_shop_refreshed(_generation: int) -> void:
	_refresh()


func _build_chrome(view: Vector2) -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.04, 0.0, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.position = Vector2.ZERO
	dim.size = view
	add_child(dim)

	var title := Label.new()
	title.name = "Title"
	title.text = "BLACK MARKET"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 18)
	title.size = Vector2(view.x, 36)
	UiStyle.apply_label(title, 28, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 4)
	add_child(title)

	_ration_label = Label.new()
	_ration_label.name = "Rations"
	_ration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ration_label.position = Vector2(0, 56)
	_ration_label.size = Vector2(view.x, 28)
	UiStyle.apply_label(_ration_label, 20, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	add_child(_ration_label)

	var row := Control.new()
	row.name = "Cards"
	add_child(row)

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text = ""
	_status.position = Vector2(0, view.y - 92)
	_status.size = Vector2(view.x, 28)
	UiStyle.apply_label(_status, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	add_child(_status)

	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "CLOSE"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.apply_button_font(close_btn, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	close_btn.add_theme_stylebox_override("normal", UiStyle.make_flat(Color(0.02, 0.12, 0.04, 0.92), UiStyle.PIP_GREEN, 2))
	close_btn.add_theme_stylebox_override("hover", UiStyle.make_flat(Color(0.06, 0.28, 0.10, 0.96), Color(0.7, 1.0, 0.7), 2))
	close_btn.add_theme_stylebox_override("pressed", UiStyle.make_flat(Color(0.10, 0.40, 0.14, 1.0), Color.WHITE, 2))
	close_btn.pressed.connect(close_shop)
	close_btn.position = Vector2(view.x * 0.5 - 90.0, view.y - 56.0)
	close_btn.size = Vector2(180, 40)
	add_child(close_btn)


func _spec_for(item: GameProgress.ShopItem) -> Dictionary:
	match item:
		GameProgress.ShopItem.PISTOL:
			return {
				"item": item,
				"title": "PISTOL",
				"blurb": "10 damage, magazine of 10. Buying it loads one magazine.",
			}
		GameProgress.ShopItem.SHOTGUN:
			return {
				"item": item,
				"title": "SHOTGUN",
				"blurb": "8 shells. 10 pellets of 10 damage inside the flashlight cone.",
			}
		GameProgress.ShopItem.AK:
			return {
				"item": item,
				"title": "AK",
				"blurb": "25 damage, magazine of 30. Buying it loads one magazine.",
			}
		GameProgress.ShopItem.PISTOL_AMMO:
			return {
				"item": item,
				"title": "PISTOL AMMO",
				"blurb": "One pistol magazine, 10 rounds. Cannot pass the cap of 50.",
			}
		GameProgress.ShopItem.SHOTGUN_AMMO:
			return {
				"item": item,
				"title": "SHOTGUN AMMO",
				"blurb": "8 shotgun shells. Cannot pass the cap of 16.",
			}
		GameProgress.ShopItem.AK_AMMO:
			return {
				"item": item,
				"title": "AK AMMO",
				"blurb": "One AK magazine, 30 rounds. Cannot pass the cap of 60.",
			}
		GameProgress.ShopItem.HEALTH:
			return {
				"item": item,
				"title": "HEALTH",
				"blurb": "+10 max HP per rank. Stacks up to 5.",
			}
		GameProgress.ShopItem.SPEED:
			return {
				"item": item,
				"title": "SPEED UPGRADE",
				"blurb": "+5% move speed per rank. Stacks up to 5.",
			}
		GameProgress.ShopItem.SNEAK:
			return {
				"item": item,
				"title": "SNEAK",
				"blurb": "Hold Ctrl with the flashlight off to avoid sight detection.",
			}
		_:
			return {"item": item, "title": "ITEM", "blurb": ""}


func _make_card(spec: Dictionary, card_size: Vector2) -> Panel:
	var item: GameProgress.ShopItem = spec["item"]
	var panel := Panel.new()
	panel.name = String(spec["title"]).replace(" ", "")
	panel.size = card_size
	panel.custom_minimum_size = card_size
	panel.add_theme_stylebox_override(
		"panel",
		UiStyle.make_flat(Color(0.02, 0.10, 0.04, 0.96), UiStyle.PIP_GREEN, 2)
	)

	var vbox := VBoxContainer.new()
	vbox.name = "Layout"
	vbox.add_theme_constant_override("separation", 6)
	vbox.position = Vector2(14, 12)
	vbox.size = card_size - Vector2(28, 20)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = String(spec["title"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.apply_label(title, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	vbox.add_child(title)

	var cost := Label.new()
	cost.name = "Cost"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_label(cost, 15, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 2)
	vbox.add_child(cost)

	var blurb := Label.new()
	blurb.name = "Blurb"
	blurb.text = String(spec["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.apply_label(blurb, 13, Color(0.7, 1.0, 0.7), Color(0.0, 0.08, 0.0), 2)
	vbox.add_child(blurb)

	var buy := Button.new()
	buy.name = "BuyButton"
	buy.text = "BUY"
	buy.focus_mode = Control.FOCUS_ALL
	buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	buy.custom_minimum_size = Vector2(0, 36)
	UiStyle.apply_button_font(buy, 16, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	buy.add_theme_stylebox_override("normal", UiStyle.make_flat(Color(0.04, 0.18, 0.08, 0.95), UiStyle.PIP_GREEN, 2))
	buy.add_theme_stylebox_override("hover", UiStyle.make_flat(Color(0.08, 0.32, 0.12, 0.98), Color(0.7, 1.0, 0.7), 2))
	buy.add_theme_stylebox_override("pressed", UiStyle.make_flat(Color(0.12, 0.42, 0.16, 1.0), Color.WHITE, 2))
	buy.add_theme_stylebox_override("disabled", UiStyle.make_flat(Color(0.05, 0.08, 0.05, 0.9), UiStyle.PIP_GREEN_DIM, 2))
	buy.pressed.connect(_on_buy_pressed.bind(item))
	vbox.add_child(buy)

	_cards.append({
		"item": item,
		"panel": panel,
		"cost": cost,
		"buy": buy,
	})
	return panel


func _on_buy_pressed(item: GameProgress.ShopItem) -> void:
	if GameProgress.buy(item):
		_status.text = "PURCHASED"
	else:
		_status.text = "NOT ENOUGH RATIONS"
	_refresh()


func _refresh() -> void:
	if _ration_label:
		_ration_label.text = "RATIONS  %d" % GameProgress.rations
	var row := get_node_or_null("Cards")
	if row == null:
		return
	for child in row.get_children():
		child.free()
	_cards.clear()
	var specs: Array[Dictionary] = []
	for item in GameProgress.shop_catalog():
		specs.append(_spec_for(item))
	var columns := 3
	var gap := 16.0
	var card_w := minf(340.0, (_view.x - 48.0 - gap * float(columns - 1)) / float(columns))
	var card_h := 210.0
	var rows := int(ceili(float(specs.size()) / float(columns))) if specs.size() > 0 else 1
	var total_w := float(columns) * card_w + gap * float(columns - 1)
	var total_h := float(rows) * card_h + gap * float(maxi(rows - 1, 0))
	row.position = Vector2((_view.x - total_w) * 0.5, 96.0)
	row.size = Vector2(total_w, total_h)
	for i in specs.size():
		var panel := _make_card(specs[i], Vector2(card_w, card_h))
		var col := i % columns
		var line := int(i / columns)
		panel.position = Vector2(float(col) * (card_w + gap), float(line) * (card_h + gap))
		row.add_child(panel)
	for card in _cards:
		var item: GameProgress.ShopItem = card["item"]
		var cost_label: Label = card["cost"]
		var buy: Button = card["buy"]
		var cost := GameProgress.shop_cost(item)
		var owned := GameProgress.owns_unique(item)
		var rank := 0
		if item == GameProgress.ShopItem.SPEED:
			rank = GameProgress.speed_ranks
		elif item == GameProgress.ShopItem.HEALTH:
			rank = GameProgress.health_ranks
		if rank > 0:
			cost_label.text = "%d RATION   (x%d)" % [cost, rank]
		else:
			cost_label.text = "%d RATION%s" % [cost, "" if cost == 1 else "S"]
		if owned:
			buy.text = "OWNED"
			buy.disabled = true
		elif item == GameProgress.ShopItem.SPEED and GameProgress.speed_ranks >= GameProgress.MAX_UPGRADE_RANKS:
			buy.text = "MAX"
			buy.disabled = true
		elif item == GameProgress.ShopItem.HEALTH and GameProgress.health_ranks >= GameProgress.MAX_UPGRADE_RANKS:
			buy.text = "MAX"
			buy.disabled = true
		elif _ammo_is_full(item):
			buy.text = "FULL"
			buy.disabled = true
		elif GameProgress.can_buy(item):
			buy.text = "BUY"
			buy.disabled = false
		else:
			buy.text = "BUY"
			buy.disabled = true


func _ammo_is_full(item: GameProgress.ShopItem) -> bool:
	match item:
		GameProgress.ShopItem.PISTOL_AMMO:
			return GameProgress.has_pistol and not GameProgress.can_accept_pack(GameProgress.WeaponId.PISTOL)
		GameProgress.ShopItem.SHOTGUN_AMMO:
			return GameProgress.has_shotgun and not GameProgress.can_accept_pack(GameProgress.WeaponId.SHOTGUN)
		GameProgress.ShopItem.AK_AMMO:
			return GameProgress.has_ak and not GameProgress.can_accept_pack(GameProgress.WeaponId.AK)
		_:
			return false
