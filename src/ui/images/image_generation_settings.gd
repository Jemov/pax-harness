extends VBoxContainer
const Workflow = preload("res://mods/pax_harness/src/images/image_workflow.gd")
var service: Node
var owner_mod: Node
var editor: TextEdit
var enabled: CheckBox
var prompt_field: OptionButton
var feedback: Label
var _graph: Dictionary = {}
func _label(text: String) -> Label:
	var label := Label.new(); label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; return label
func setup(value: Node, owner: Node) -> void:
	service = value; owner_mod = owner; size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	var status: Dictionary = owner.image_tool("images.status",{},{}).get("result",{}) if owner.has_method("image_tool") else {}
	add_child(_label("Генератор игры: "+str(status.get("service","не настроен"))+" · "+str(status.get("model",""))))
	var native := Button.new(); native.text = "Настроить в игре"
	native.pressed.connect(func():
		if owner_mod.has_method("ui_tool"):
			var chat: Variant = owner_mod.get("chat_ui")
			if chat is Node and chat.has_method("close"): chat.close()
			owner_mod.ui_tool("ui.open",{"panel":"settings.photo"},{}))
	add_child(native)
	add_child(_label("Обычно используется штатный генератор. Для выбранного в игре ComfyUI можно задать свой workflow в формате API JSON."))
	enabled = CheckBox.new(); enabled.text = "Свой workflow ComfyUI"; add_child(enabled)
	add_child(_label("Вставьте экспорт API JSON ниже или выберите JSON из папки workflows мода. Адрес сервера берётся из настроек игры."))
	var files := OptionButton.new(); files.fit_to_longest_item = false; files.clip_text = true
	files.add_item("Выбрать файл из workflows мода…"); files.set_item_disabled(0,true)
	if owner.has_method("list_files"):
		for filename: String in owner.list_files("workflows"):
			if filename == filename.get_file() and filename.get_extension().to_lower() == "json": files.add_item(filename)
	files.item_selected.connect(func(index):
		if index > 0 and owner_mod.has_method("read_text"):
			var raw: String = owner_mod.read_text("workflows/"+files.get_item_text(index))
			if raw.to_utf8_buffer().size() <= Workflow.MAX_BYTES: editor.text = raw; _parse())
	add_child(files)
	editor = TextEdit.new(); editor.custom_minimum_size.y = 220; editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL; editor.placeholder_text = "API JSON workflow"; editor.text_changed.connect(_parse); add_child(editor)
	add_child(_label("Поле положительного описания изображения. При нескольких узлах выберите нужный; отрицательный prompt остаётся из workflow."))
	prompt_field = OptionButton.new(); prompt_field.fit_to_longest_item = false; prompt_field.clip_text = true; add_child(prompt_field)
	var actions := HFlowContainer.new(); add_child(actions)
	var apply := Button.new(); apply.text = "Применить workflow"; apply.pressed.connect(_apply); actions.add_child(apply)
	var reset := Button.new(); reset.text = "Штатный генератор"
	reset.pressed.connect(func(): service.reset_comfy_workflow(); enabled.button_pressed = false; feedback.text = "Используется штатный генератор игры.")
	actions.add_child(reset)
	feedback = _label(""); add_child(feedback)
	var saved: Dictionary = service.comfy_workflow()
	enabled.button_pressed = saved.get("enabled",false)
	editor.text = JSON.stringify(saved.get("graph",{}),"  ")
	_parse()
	for i: int in prompt_field.item_count:
		var selected: Variant = prompt_field.get_item_metadata(i)
		if selected is Dictionary and selected.get("node") == saved.get("prompt_node") and selected.get("input") == saved.get("prompt_input"): prompt_field.select(i)
func _parse() -> void:
	if editor == null or prompt_field == null or feedback == null: return
	var prior: Variant = prompt_field.get_selected_metadata() if prompt_field.selected >= 0 else null
	prompt_field.clear(); _graph = {}
	if editor.text.to_utf8_buffer().size() > Workflow.MAX_BYTES: feedback.text = "Workflow превышает 256 КиБ."; return
	var json := JSON.new()
	if json.parse(editor.text) != OK or not json.data is Dictionary: feedback.text = "Нужен корректный объект API JSON."; return
	_graph = json.data
	var selected: Array = Workflow.choices(_graph)
	for item: Dictionary in selected:
		prompt_field.add_item(item.label); prompt_field.set_item_metadata(prompt_field.item_count-1,item)
	if selected.size() > 1:
		prompt_field.add_item("Выберите поле описания…",0); prompt_field.select(prompt_field.item_count-1)
	if prior is Dictionary:
		for index: int in selected.size():
			if selected[index].node == prior.get("node") and selected[index].input == prior.get("input"): prompt_field.select(index)
	feedback.text = "Узлов: %d. Изменяется только выбранное поле описания." % _graph.size() if selected.size() > 0 else "Не найдено строковое поле text/prompt. Нужен экспорт API workflow."
func _apply() -> void:
	var selected: Variant = prompt_field.get_selected_metadata() if prompt_field.selected >= 0 else null
	if not selected is Dictionary: feedback.text = "Выберите точное поле описания."; return
	var result: Dictionary = service.set_comfy_workflow(_graph,selected.node,selected.input,enabled.button_pressed)
	feedback.text = "Workflow сохранён; применяется только к ComfyUI из настроек игры." if result.ok else str(result.get("result",{}).get("message","Не удалось сохранить workflow."))
