extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity: float = 20.0

func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	input.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")

	# Camera-relative isometric movement (camera looks from +X/-Z-ish).
	# Map WASD onto the ground plane using fixed isometric axes.
	var forward := Vector3(-1, 0, -1).normalized()
	var right := Vector3(1, 0, -1).normalized()
	var direction := (right * input.x) + (forward * -input.y)
	if direction.length() > 1.0:
		direction = direction.normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
