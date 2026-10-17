extends RefCounted
const Style = preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
static func make(control: Control, text: String) -> Control:
	if text.strip_edges().is_empty(): return null
	var available: float = control.get_viewport_rect().size.x-48
	var natural: float = 0
	for line: String in text.split("\n"):
		natural = maxf(natural,control.get_theme_default_font().get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x+2)
	var width: float = minf(maxf(1,available),clampf(natural,80,620))
	var label := Label.new()
	label.name = "FullTextTooltip"
	label.theme = control.theme
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = width
	# Godot already puts this content in its themed TooltipPanel.
	label.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	label.clip_text = false; label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.max_lines_visible = -1
	label.add_theme_font_override("font",control.get_theme_default_font())
	label.add_theme_font_size_override("font_size",13)
	label.add_theme_color_override("font_color",Color("#e0e8f4"))
	return label
