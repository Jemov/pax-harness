extends Node2D
## Presentation only. This node has no Control hitbox and never warps the OS cursor.
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
var at := Vector2.ZERO
var pressed := false
var until := 0
var _pulse := 0
func point(position_: Vector2, down: bool = false) -> void:
	at=position_; pressed=down; until=Time.get_ticks_msec()+8000
	if down: _pulse=Time.get_ticks_msec()+240
	show(); queue_redraw()
func _process(_delta: float) -> void:
	if visible and Time.get_ticks_msec()>until: hide()
	elif visible and _pulse>0:
		queue_redraw()
		if Time.get_ticks_msec()>_pulse: _pulse=0
func _draw() -> void:
	var color:=Color("75d6ff")
	if Time.get_ticks_msec()<_pulse: draw_circle(at,23,Color(0.45,0.84,1,0.3))
	draw_circle(at,16,Color(0.03,0.08,0.12,0.8))
	draw_arc(at,16,0,TAU,32,color,3 if pressed else 1.5,true)
	var arrow:=PackedVector2Array([at,at+Vector2(0,21),at+Vector2(6,15),at+Vector2(11,24),at+Vector2(15,22),at+Vector2(10,13),at+Vector2(19,13)])
	draw_colored_polygon(arrow,color)
	draw_string(ThemeDB.fallback_font,at+Vector2(22,8),"ИИ" if L.language()=="ru" else "AI",HORIZONTAL_ALIGNMENT_LEFT,-1,15,color)
