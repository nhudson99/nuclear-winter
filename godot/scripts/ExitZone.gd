extends Area3D

## Southern mansion exit. Winning requires the player to enter while holding the item.

signal player_escaped(player: Node3D)

func _ready() -> void:
	add_to_group("exit")
	collision_layer = 0
	collision_mask = 2 # player
	monitoring = true
	monitorable = false
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body == null or not body.is_in_group("player"):
		return
	if body.has_method("has_collected_item") and body.has_collected_item():
		player_escaped.emit(body)
