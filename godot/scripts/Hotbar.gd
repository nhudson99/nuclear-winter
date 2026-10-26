extends Control
class_name Hotbar

## Three Minecraft-style slots along the bottom. A slot exists only once that
## gun is owned: 1 pistol, 2 shotgun, 3 AK.

const SLOT_SIZE := Vector2(84, 72)


func _ready() -> void:
	name = "Hotbar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not GameProgress.upgrades_changed.is_connected(refresh):
		GameProgress.upgrades_changed.connect(refresh)
	if not GameProgress.ammo_changed.is_connected(refresh):
		GameProgress.ammo_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for child in get_children():
		child.free()
	var owned := GameProgress.owned_weapons()
	visible = not owned.is_empty()
	if owned.is_empty():
		return
	var gap := 8.0
	var width := float(owned.size()) * SLOT_SIZE.x + float(owned.size() - 1) * gap
	var height := SLOT_SIZE.y + 22.0
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -(height + 16.0)
	offset_bottom = -16.0
	var row := HBoxContainer.new()
	row.name = "Slots"
	row.add_theme_constant_override("separation", int(gap))
	row.position = Vector2.ZERO
	row.size = Vector2(width, SLOT_SIZE.y)
	add_child(row)
	for weapon in owned:
		row.add_child(_make_slot(weapon))
	var hint := Label.new()
	hint.name = "ReloadHint"
	hint.text = "R  RELOAD"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, SLOT_SIZE.y + 2.0)
	hint.size = Vector2(width, 18)
	UiStyle.apply_label(hint, 12, Color(0.85, 0.82, 0.7), Color(0, 0, 0), 3)
	add_child(hint)


func slot_count() -> int:
	var slots := get_node_or_null("Slots")
	return slots.get_child_count() if slots else 0


func slot_node(weapon: GameProgress.WeaponId) -> Panel:
	var slots := get_node_or_null("Slots")
	if slots == null:
		return null
	var slot := slots.get_node_or_null("Slot%d" % GameProgress.weapon_slot(weapon))
	return slot as Panel


func is_slot_selected(weapon: GameProgress.WeaponId) -> bool:
	var slot := slot_node(weapon)
	return slot != null and bool(slot.get_meta("selected", false))


func ammo_text(weapon: GameProgress.WeaponId) -> String:
	var slot := slot_node(weapon)
	if slot == null:
		return ""
	var label := slot.get_node_or_null("Ammo") as Label
	return label.text if label else ""


func _make_slot(weapon: GameProgress.WeaponId) -> Panel:
	var selected := GameProgress.selected_weapon == weapon
	var panel := Panel.new()
	panel.name = "Slot%d" % GameProgress.weapon_slot(weapon)
	panel.custom_minimum_size = SLOT_SIZE
	panel.size = SLOT_SIZE
	panel.set_meta("selected", selected)
	panel.set_meta("weapon", weapon)
	var border := Color(0.96, 0.86, 0.42) if selected else Color(0.22, 0.22, 0.24)
	var box := UiStyle.make_flat(Color(0.07, 0.07, 0.08, 0.94), border, 4 if selected else 2)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", box)

	var index := Label.new()
	index.name = "Index"
	index.text = str(GameProgress.weapon_slot(weapon))
	index.position = Vector2(6, 2)
	index.size = Vector2(20, 16)
	UiStyle.apply_label(index, 12, Color(0.95, 0.92, 0.8), Color(0, 0, 0), 3)
	panel.add_child(index)

	var title := Label.new()
	title.name = "Name"
	title.text = GameProgress.weapon_name(weapon)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(2, 18)
	title.size = Vector2(SLOT_SIZE.x - 4, 28)
	UiStyle.apply_label(title, 13, Color(0.93, 0.9, 0.82), Color(0, 0, 0), 3)
	panel.add_child(title)

	var ammo := Label.new()
	ammo.name = "Ammo"
	ammo.text = "%d/%d" % [GameProgress.loaded_ammo(weapon), GameProgress.reserve_ammo(weapon)]
	ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo.position = Vector2(2, 48)
	ammo.size = Vector2(SLOT_SIZE.x - 4, 18)
	UiStyle.apply_label(ammo, 13, Color(0.98, 0.84, 0.35), Color(0, 0, 0), 3)
	panel.add_child(ammo)
	return panel
