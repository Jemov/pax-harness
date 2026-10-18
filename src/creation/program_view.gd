extends VBoxContainer
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
var service: Node
var identity: String
var program: Dictionary
var fields: Dictionary={}
var feedback: Label
var toggle: CheckButton
var actions: Array=[]
var _elapsed:=0.0
func label(text: String) -> Label:
	var item:=Label.new(); item.text=text; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; item.size_flags_horizontal=Control.SIZE_EXPAND_FILL; return item
func text(value: Dictionary) -> String: return str(value.get(L.language(),value.get("en","")))
func field_text(value: Variant) -> String:
	if value is Dictionary and value.get("ru") is String and value.get("en") is String: return text(value)
	return (L.text("Да") if value else L.text("Нет")) if value is bool else (str(int(value)) if value is float and value==floorf(value) else (str(value) if value!=null else "—"))
func setup(value: Node,id: String,source: Dictionary) -> void:
	service=value; identity=id; program=source
	name="EntityProgram_"+id
	add_child(label(L.text("Программа поведения")))
	toggle=CheckButton.new(); toggle.name="ProgramEnabled_"+id; toggle.text=L.text("Выполнять программу"); add_child(toggle)
	toggle.toggled.connect(func(enabled: bool):
		if is_instance_valid(service.programs): service.programs.set_enabled(identity,enabled))
	for row: Dictionary in program.get("ui",{}).get("fields",[]):
		var line:=HBoxContainer.new(); add_child(line); line.add_child(label(text(row.label)))
		var value_label:=label("")
		value_label.autowrap_mode=TextServer.AUTOWRAP_OFF; value_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		value_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; value_label.custom_minimum_size.x=120
		value_label.size_flags_horizontal=Control.SIZE_SHRINK_END; line.add_child(value_label); fields[str(row.path)]=value_label
	var buttons:=HFlowContainer.new(); add_child(buttons)
	for row: Dictionary in program.get("ui",{}).get("buttons",[]):
		var button:=Button.new(); button.text=text(row.label); button.name="ProgramEvent_"+identity+"_"+str(row.event); buttons.add_child(button)
		actions.append(button)
		button.pressed.connect(func():
			if not is_instance_valid(service.programs): return
			var result: Dictionary=service.programs.interact(identity,str(row.event))
			if not result.ok: feedback.text=str(result.get("error",result.get("code",""))))
	feedback=label(""); add_child(feedback); refresh()
func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed<0.2: return
	_elapsed=0.0; refresh()
func refresh() -> void:
	var runtime: Dictionary=service.records.get(identity,{}).get("runtime",{})
	toggle.disabled=runtime.is_empty(); toggle.set_pressed_no_signal(bool(runtime.get("enabled",false)))
	for action: Button in actions: action.disabled=not bool(runtime.get("enabled",false))
	for path: String in fields:
		var value: Variant={"state":runtime.get("state",program.state)}
		for part: String in path.split("."):
			value=value.get(part) if value is Dictionary else null
		fields[path].text=field_text(value)
		fields[path].tooltip_text=fields[path].text
	var error: Dictionary=runtime.get("last_error",{})
	feedback.text=(L.text("Ошибка программы: ")+str(error.get("code",""))+" · "+str(error.get("path",""))+"\n"+L.text("Программа остановлена. Подробности доступны агенту.")) if not error.is_empty() else (L.text("Ожидает применения проекта") if runtime.is_empty() else "")
	feedback.tooltip_text=str(error.get("detail",""))
