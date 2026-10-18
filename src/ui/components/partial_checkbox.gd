extends CheckBox
## Reuse the native checkbox; only its mixed-state mark needs an extra draw.
var mixed := false
func set_state(state: int) -> void:
	mixed=state==1
	if mixed: add_theme_icon_override("checked",get_theme_icon("unchecked"))
	else: remove_theme_icon_override("checked")
	set_pressed_no_signal(state!=0); queue_redraw()
func _draw() -> void:
	if not mixed: return
	var icon: Texture2D=get_theme_icon("unchecked")
	var p:=Vector2(get_theme_stylebox("normal").get_margin(SIDE_LEFT),(size.y-icon.get_height())*0.5+get_theme_constant("check_v_offset"))
	var span: Vector2=icon.get_size()
	draw_rect(Rect2((p+span*0.30).round(),(span*0.40).round()),get_theme_color("font_color"))
