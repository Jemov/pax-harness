extends VBoxContainer
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## User-requested local disclosure. Never sent to the model automatically.
var input: TextEdit
var note: Label
func setup(original: Dictionary, displayed: Dictionary) -> void:
	name = "ChartDataDisclosure"; visible = false
	note = Label.new(); L.bind(note,"text",["Данные показанного графика. Источник: ",{"value":displayed.get("source",original.get("source",""))}])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.add_theme_font_size_override("font_size",12); add_child(note)
	input = TextEdit.new(); input.editable = false; input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; input.custom_minimum_size.y = 220
	input.text = JSON.stringify({"displayed":displayed,"original":original,"filtered":displayed != original},"  "); add_child(input)
	var copy := Button.new(); copy.text = L.text("Копировать JSON"); copy.pressed.connect(func(): DisplayServer.clipboard_set(input.text)); add_child(copy)
