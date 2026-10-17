extends RefCounted

const BG = Color("#07090e")
const SURFACE = Color("#10131a")
const HOVER = Color("#171b23")
const EDGE = Color("#2d333e")
const TEXT = Color("#e6edf5")
const MUTED = Color("#8594ad")
const GOLD = Color("#e8b85c")
const BLUE = Color("#e8b85c")
const MINT = Color("#a8b8a9")


static func box(color: Color, radius: int = 6, border: Color = Color.TRANSPARENT, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(mini(radius, 6))
	style.set_border_width_all(1 if border.a > 0.0 else 0)
	style.border_color = border
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


static func theme() -> Theme:
	var result = Theme.new()
	result.default_font_size = 14
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Menlo","Consolas","DejaVu Sans Mono","monospace"])
	result.set_font("font","TextEdit",mono)
	result.set_font("mono_font","RichTextLabel",mono)
	for type: String in ["Label", "Button", "OptionButton", "LineEdit", "TextEdit", "RichTextLabel"]:
		result.set_color("font_color", type, TEXT)
	for type: String in ["Button", "OptionButton"]:
		result.set_stylebox("normal", type, box(SURFACE, 4, EDGE, 10))
		result.set_stylebox("hover", type, box(HOVER, 4, EDGE, 10))
		result.set_stylebox("pressed", type, box(HOVER, 4, GOLD, 10))
		result.set_stylebox("focus", type, box(Color.TRANSPARENT, 4, GOLD, 10))
		result.set_color("font_hover_color", type, Color.WHITE)
		result.set_color("font_pressed_color", type, GOLD)
		result.set_color("font_disabled_color", type, MUTED)
	for type: String in ["LineEdit", "TextEdit"]:
		result.set_stylebox("normal", type, box(Color("#0d1016"), 4, EDGE, 12))
		result.set_stylebox("focus", type, box(Color.TRANSPARENT, 10, BLUE, 12))
		result.set_color("font_placeholder_color", type, MUTED)
		result.set_color("caret_color", type, GOLD)
		result.set_color("selection_color", type, Color("#4a4232"))
	for type: String in ["LineEdit", "TextEdit"]:
		result.set_stylebox("read_only", type, box(Color("#0d1016"), 4, EDGE, 12))
	result.set_stylebox("panel", "PopupMenu", box(SURFACE, 10, EDGE, 8))
	result.set_color("font_color", "PopupMenu", TEXT)
	result.set_stylebox("hover", "PopupMenu", box(HOVER, 6, Color.TRANSPARENT, 8))
	result.set_stylebox("scroll", "VScrollBar", box(BG, 5, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber", "VScrollBar", box(EDGE, 5, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_highlight", "VScrollBar", box(MUTED, 5, Color.TRANSPARENT, 3))
	return result


static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func tab(button: Button, selected: bool) -> void:
	var style := box(HOVER if selected else Color.TRANSPARENT, 4, Color.TRANSPARENT, 9)
	style.border_width_bottom = 2 if selected else 0
	style.border_color = GOLD
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state,style)
	button.add_theme_stylebox_override("focus",box(Color.TRANSPARENT,4,Color.TRANSPARENT,9))
	button.add_theme_color_override("font_color",GOLD if selected else MUTED)


static func link(button: Button) -> void:
	for state: String in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,box(Color.TRANSPARENT,0,Color.TRANSPARENT,3))
	button.add_theme_color_override("font_color",GOLD)
	button.add_theme_color_override("font_hover_color",TEXT)
	button.add_theme_font_size_override("font_size",13)
