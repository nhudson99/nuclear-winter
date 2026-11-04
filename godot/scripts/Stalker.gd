extends "res://scripts/Monster.gd"

## Radiation-mask stalker. Indestructible, no health bar. Freezes completely
## while the flashlight is on it — no movement, no attacks — and only creeps
## when the beam leaves.

func _ready() -> void:
	super._ready()
	add_to_group("stalker")
	indestructible = true
	show_health_bar = false
	if _health_bar:
		_health_bar.visible = false
		_health_bar.queue_free()
		_health_bar = null


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	if is_breaching_hide():
		super._physics_process(delta)
		return
	var lit := _lit_by_flashlight()
	if lit:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity(delta)
		move_and_slide()
		_animate_walk(_walk_phase, 0.0)
		_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
		return
	super._physics_process(delta)


func _allows_attack() -> bool:
	return not _lit_by_flashlight()


func take_damage(_amount: float) -> void:
	# Indestructible: beam and bullets do not hurt it, but light still freezes it.
	pass
