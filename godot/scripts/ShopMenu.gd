extends Control
class_name ShopMenu

## Pip-Boy shop overlay: pistol, speed upgrade, sneak.

signal closed

func _card_specs() -> Array:
	return [
		{
			"item": GameProgress.ShopItem.PISTOL,
			"title": "PISTOL",
			"blurb": "Deal 10 damage. Aim with the flashlight, LMB to fire.",
		},
		{
			"item": GameProgress.ShopItem.SPEED,
			"title": "SPEED UPGRADE",
			"blurb": "+5% move speed. Can be bought more than once.",
		},
		{
			"item": GameProgress.ShopItem.SNEAK,
			"title": "SNEAK",
			"blurb": "Hold Ctrl with the flashlight off to avoid sight detection.",
		},
	]

var _ration_label: Label
var _cards: Array = []
var _status: Label


func _ready() -> void:
	name = "ShopMenu"
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()
	if not GameProgress.rations_changed.is_connected(_on_rations_changed):
		GameProgress.rations_changed.connect(_on_rations_changed)
	if not GameProgress.upgrades_changed.is_connected(_refresh):
		GameProgress.upgrades_changed.connect(_refresh)


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


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.04, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.set_offsets_preset(PRESET_FULL_RECT)

	var title := Label.new()
	title.name = "Title"
	title.text = "BLACK MARKET"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_label(title, 28, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 4)
	add_child(title)
	title.set_anchors_preset(PRESET_TOP_WIDE)
	title.offset_left = 0
	title.offset_top = 36
	title.offset_right = 0
	title.offset_bottom = 80

	_ration_label = Label.new()
	_ration_label.name = "Rations"
	_ration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_label(_ration_label, 20, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	add_child(_ration_label)
	_ration_label.set_anchors_preset(PRESET_TOP_WIDE)
	_ration_label.offset_top = 80
	_ration_label.offset_bottom = 112

	var row := HBoxContainer.new()
	row.name = "Cards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	add_child(row)
	row.anchor_left = 0.06
	row.anchor_right = 0.94
	row.anchor_top = 0.22
	row.anchor_bottom = 0.78
	row.offset_left = 0
	row.offset_right = 0
	row.offset_top = 0
	row.offset_bottom = 0

	for spec in _card_specs():
		row.add_child(_make_card(spec))

	_status = Label.new()
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.text = ""
	UiStyle.apply_label(_status, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	add_child(_status)
	_status.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_status.offset_top = -88
	_status.offset_bottom = -56

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
	add_child(close_btn)
	close_btn.set_anchors_preset(PRESET_BOTTOM_WIDE)
	close_btn.offset_left = 520
	close_btn.offset_right = -520
	close_btn.offset_top = -48
	close_btn.offset_bottom = -12


func _make_card(spec: Dictionary) -> Panel:
	var item: GameProgress.ShopItem = spec["item"]
	var panel := Panel.new()
	panel.name = String(spec["title"]).replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		UiStyle.make_flat(Color(0.02, 0.10, 0.04, 0.96), UiStyle.PIP_GREEN, 2)
	)

	var vbox := VBoxContainer.new()
	vbox.name = "Layout"
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	vbox.set_anchors_preset(PRESET_FULL_RECT)
	vbox.offset_left = 18
	vbox.offset_top = 18
	vbox.offset_right = -18
	vbox.offset_bottom = -18

	var title := Label.new()
	title.name = "Title"
	title.text = String(spec["title"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiStyle.apply_label(title, 22, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
	vbox.add_child(title)

	var cost := Label.new()
	cost.name = "Cost"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiStyle.apply_label(cost, 16, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 2)
	vbox.add_child(cost)

	var blurb := Label.new()
	blurb.name = "Blurb"
	blurb.text = String(spec["blurb"])
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiStyle.apply_label(blurb, 15, Color(0.7, 1.0, 0.7), Color(0.0, 0.08, 0.0), 2)
	vbox.add_child(blurb)

	var buy := Button.new()
	buy.name = "BuyButton"
	buy.text = "BUY"
	buy.focus_mode = Control.FOCUS_ALL
	buy.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UiStyle.apply_button_font(buy, 18, UiStyle.PIP_GREEN, Color(0.0, 0.08, 0.0), 3)
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
	for card in _cards:
		var item: GameProgress.ShopItem = card["item"]
		var cost_label: Label = card["cost"]
		var buy: Button = card["buy"]
		var cost := GameProgress.shop_cost(item)
		var owned := GameProgress.owns_unique(item)
		if item == GameProgress.ShopItem.SPEED and GameProgress.speed_ranks > 0:
			cost_label.text = "%d RATION   (x%d)" % [cost, GameProgress.speed_ranks]
		else:
			cost_label.text = "%d RATION%s" % [cost, "" if cost == 1 else "S"]
		if owned:
			buy.text = "OWNED"
			buy.disabled = true
		elif GameProgress.can_buy(item):
			buy.text = "BUY"
			buy.disabled = false
		else:
			buy.text = "BUY"
			buy.disabled = true
