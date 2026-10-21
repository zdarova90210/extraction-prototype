@tool
extends Node2D
## Presentation only: the actor's health signal is the source of truth.

@export var bar_width: float = 44.0:
	set(value):
		bar_width = maxf(10.0, value)
		queue_redraw()
@export var bar_height: float = 4.0:
	set(value):
		bar_height = maxf(1.0, value)
		queue_redraw()
@export var fill_color: Color = Color("9ac8ac"):
	set(value):
		fill_color = value
		queue_redraw()
@export var damage_color: Color = Color(0.95, 0.80, 0.58, 0.55)
@export_range(1.0, 1000.0, 1.0) var segment_health: float = 25.0
@export_range(0.0, 2.0, 0.05, "suffix:s") var damage_hold: float = 0.45
@export_range(0.05, 1.0, 0.05, "suffix:s") var damage_catchup: float = 0.3

var current_health: float = 100.0
var maximum_health: float = 100.0
var trail_health: float = 100.0
var _hold_remaining: float = 0.0
var _catchup_elapsed: float = 0.0
var _catchup_from: float = 100.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	var actor := get_parent()
	actor.health_changed.connect(_on_health_changed)
	# Child _ready runs before the actor initializes its exported maximum health.
	actor.ready.connect(reset_from_actor, CONNECT_ONE_SHOT)


func reset_from_actor() -> void:
	var actor := get_parent()
	maximum_health = maxf(1.0, actor.max_health)
	current_health = clampf(actor.health, 0.0, maximum_health)
	trail_health = current_health
	_catchup_from = current_health
	_hold_remaining = 0.0
	_catchup_elapsed = 0.0
	visible = current_health > 0.0
	queue_redraw()


func _on_health_changed(current: float, maximum: float) -> void:
	var previous := current_health
	var maximum_changed := not is_equal_approx(maximum_health, maximum)
	maximum_health = maxf(1.0, maximum)
	current_health = clampf(current, 0.0, maximum_health)
	if current_health < previous and not maximum_changed:
		trail_health = clampf(maxf(trail_health, previous), current_health, maximum_health)
		_catchup_from = trail_health
		_hold_remaining = damage_hold
		_catchup_elapsed = 0.0
	else:
		# Healing and maximum-health changes do not create a false damage trail.
		trail_health = current_health
		_hold_remaining = 0.0
		_catchup_elapsed = 0.0
	visible = current_health > 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if trail_health <= current_health:
		return
	var held := minf(delta, _hold_remaining)
	_hold_remaining -= held
	_catchup_elapsed += delta - held
	if _catchup_elapsed > 0.0:
		var progress := clampf(_catchup_elapsed / damage_catchup, 0.0, 1.0)
		trail_health = lerpf(_catchup_from, current_health, smoothstep(0.0, 1.0, progress))
	queue_redraw()


func _draw() -> void:
	var bar := Rect2(-bar_width * 0.5, 0.0, bar_width, bar_height)
	draw_rect(bar.grow(1.0), Color(0.025, 0.04, 0.04, 0.9))
	draw_rect(bar, Color("172025"))
	var current_width := bar_width * current_health / maximum_health
	var trail_width := bar_width * trail_health / maximum_health
	if trail_width > current_width:
		draw_rect(Rect2(bar.position + Vector2(current_width, 0), Vector2(trail_width - current_width, bar_height)), damage_color)
	draw_rect(Rect2(bar.position, Vector2(current_width, bar_height)), fill_color)
	# Keep HP-based divisions readable even if a future actor has much more HP.
	var max_sections := maxi(2, floori(bar_width / 5.0))
	var step := segment_health * maxf(1.0, ceilf(maximum_health / segment_health / max_sections))
	for index in range(1, ceili(maximum_health / step)):
		var x := bar.position.x + bar_width * index * step / maximum_health
		draw_rect(Rect2(floorf(x), 0, 1.0, bar_height), Color(0.04, 0.07, 0.07, 0.85))
