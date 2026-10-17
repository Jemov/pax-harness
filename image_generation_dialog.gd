extends Control
const Style = preload("res://mods/pax_harness/chat_style.gd")
var ui: Node
var panel: PanelContainer
func setup(value: Node) -> void:
	ui = value; name = "ImageGenerationDialog"; theme = ui.surface.theme; mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(self)
	var dim := ColorRect.new(); dim.color = Color(0,0,0,0.55); dim.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(dim); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new(); panel.add_theme_stylebox_override("panel",Style.box(ui.BG,6,Color("#35383f"),20)); add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",12); panel.add_child(column)
	column.add_child(ui._label("Генератор изображений",18,ui.TEXT))
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(scroll)
	var generator: Variant = ui.owner_mod.get("_image_generation")
	if generator is Node and generator.has_method("settings_panel"): scroll.add_child(generator.settings_panel())
	var close_button: Button = ui._button("Закрыть",queue_free); column.add_child(close_button)
	get_viewport().size_changed.connect(_layout); _layout()
func _layout() -> void:
	var area: Rect2 = ui.get_viewport().get_visible_rect(); position = area.position; size = area.size
	panel.size = Vector2(minf(820,maxf(300,size.x-32)),minf(760,maxf(280,size.y-32))); panel.position = (size-panel.size)/2
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE: get_viewport().set_input_as_handled(); queue_free()
