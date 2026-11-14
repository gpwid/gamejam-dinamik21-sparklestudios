@tool
extends Control
class_name Reticle

@export var dot_radius: float = 2.0:
	set(val):
		dot_radius = val
		queue_redraw()

@export var dot_color: Color = Color(1.0, 1.0, 1.0, 0.9):
	set(val):
		dot_color = val
		queue_redraw()

@export var outline_width: float = 1.0:
	set(val):
		outline_width = val
		queue_redraw()

@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.6):
	set(val):
		outline_color = val
		queue_redraw()

func _draw() -> void:
	if outline_width > 0.0:
		draw_circle(Vector2.ZERO, dot_radius + outline_width, outline_color)
	draw_circle(Vector2.ZERO, dot_radius, dot_color)
