extends VBoxContainer
## Generic native controls for an approved authored program, without presets.
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const TreeView=preload("res://mods/pax_harness/src/creation/workspace_tree.gd")
var tree_view: RefCounted
var drafts: Dictionary={}
var service: Node
var identity: String
var selections: Dictionary={}
var bindings: Array=[]
var actions: Array=[]
var toggle: CheckButton
var feedback: Label
var _source: Dictionary={}
var _language:=""
var _elapsed:=0.0
signal close_requested
func text(value: Dictionary) -> String: return str(value.get(L.language(),value.get("en","")))
func label(value: String) -> Label:
	var node:=Label.new(); node.text=value; node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; node.size_flags_horizontal=Control.SIZE_EXPAND_FILL; return node
func setup(owner: Node,id: String) -> void:
	if identity!=id: selections.clear()
	service=owner; identity=id; name="ObjectControls_"+id; add_theme_constant_override("separation",12); rebuild()
func rebuild() -> void:
	for node: Node in get_children(): remove_child(node); node.queue_free()
	bindings.clear(); actions.clear(); drafts=selections.duplicate(true); selections.clear()
	_source=service.records.get(identity,{}).get("definition",{}).get("program",{}).get("ui",{}).get("workspace",{}).duplicate(true); _language=L.language()
	if _source.is_empty(): return
	var header:=HBoxContainer.new(); add_child(header)
	var heading:=label(text(_source.title)); heading.add_theme_font_size_override("font_size",22); header.add_child(heading)
	var close:=Button.new(); close.name="WorkspaceClose"; close.text="×"; close.tooltip_text=L.text("Закрыть"); close.custom_minimum_size=Vector2(30,30); header.add_child(close); close.pressed.connect(func(): close_requested.emit())
	if _source.has("subtitle"): add_child(label(text(_source.subtitle)))
	toggle=CheckButton.new(); toggle.text=L.text("Активно"); toggle.name="WorkspaceEnabled"; add_child(toggle)
	toggle.toggled.connect(func(on: bool): service.programs.set_enabled(identity,on))
	if _source.has("layout"):
		var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL; add_child(scroll)
		tree_view=TreeView.new(); tree_view.setup(self); tree_view.build(scroll,_source.layout)
		feedback=label(""); add_child(feedback); refresh(); return
	var columns:=HBoxContainer.new(); columns.add_theme_constant_override("separation",16); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; add_child(columns)
	for column: Array in _source.columns:
		var scroll:=ScrollContainer.new(); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.custom_minimum_size=Vector2(300,420); columns.add_child(scroll)
		var stack:=VBoxContainer.new(); stack.size_flags_horizontal=Control.SIZE_EXPAND_FILL; stack.add_theme_constant_override("separation",16); scroll.add_child(stack)
		for section: Dictionary in column: build_section(stack,section)
	feedback=label(""); add_child(feedback); refresh()
func build_section(parent: Node,s: Dictionary) -> void:
	var panel:=PanelContainer.new(); parent.add_child(panel)
	var margin:=MarginContainer.new(); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",8); margin.add_child(box)
	var title:=label(text(s.title)); title.add_theme_font_size_override("font_size",18); box.add_child(title)
	match s.type:
		"choices":
			var group:=ButtonGroup.new()
			for index: int in s.options.size():
				var option: Dictionary=s.options[index]
				var button:=Button.new(); button.name="WorkspaceChoice_"+s.id+"_"+option.id; button.text=text(option.title); button.alignment=HORIZONTAL_ALIGNMENT_LEFT; button.toggle_mode=true; button.button_group=group; button.custom_minimum_size.y=36; box.add_child(button)
				if option.has("description"): box.add_child(label(text(option.description)))
				button.pressed.connect(func(): selections[s.id]=option.value.duplicate(true); refresh())
				if index==0: button.set_pressed_no_signal(true); selections[s.id]=option.value.duplicate(true)
		"fields":
			for row: Dictionary in s.rows:
				var line:=HBoxContainer.new(); line.add_theme_constant_override("separation",12); box.add_child(line); line.add_child(label(text(row.label)))
				var value:=label(""); value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; line.add_child(value); bindings.append({"type":"field","node":value,"path":row.path})
		"list":
			var empty:=label(text(s.empty)); box.add_child(empty)
			var rows: Array=[]
			for path: String in s.paths:
				var value:=label(""); box.add_child(value); rows.append({"node":value,"path":path})
			bindings.append({"type":"list","rows":rows,"empty":empty})
		"progress":
			var progress:=ProgressBar.new(); progress.custom_minimum_size.y=24; box.add_child(progress); bindings.append({"type":"progress","node":progress,"path":s.path,"max_path":s.max_path})
		"actions":
			for row: Dictionary in s.buttons:
				var button:=Button.new(); button.name="WorkspaceAction_"+identity+"_"+row.event; button.text=text(row.label); button.custom_minimum_size.y=36; box.add_child(button); actions.append({"node":button,"inputs":row.get("inputs",[])})
				button.pressed.connect(func(): send(row.event,row.get("inputs",[])))
func send(event: String,input_ids: Array,payload: Dictionary={}) -> void:
	var input: Dictionary=payload.duplicate(true)
	for key: String in input_ids:
		if not selections.has(key): return
		var value: Variant=selections[key]; input[key]=value.duplicate(true) if value is Dictionary or value is Array else value
	var result: Dictionary=service.programs.interact(identity,event,input)
	feedback.text="" if result.ok else str(result.get("error",result.get("code",""))); refresh()
func state_value(path: String) -> Variant:
	var value: Variant={"state":service.records.get(identity,{}).get("runtime",{}).get("state",{})}
	for key: String in path.split("."):
		if value is Dictionary: value=value.get(key)
		elif value is Array and key.is_valid_int() and int(key)>=0 and int(key)<value.size(): value=value[int(key)]
		else: value=null
	return value
func display(value: Variant) -> String:
	if value is Dictionary and value.has_all(["ru","en"]): return text(value)
	if value is bool: return L.text("Да") if value else L.text("Нет")
	if value==null: return "—"
	return str(int(value)) if value is float and value==floorf(value) else str(value)
func refresh() -> void:
	if not is_instance_valid(toggle): return
	var runtime: Dictionary=service.records.get(identity,{}).get("runtime",{})
	var enabled: bool=runtime.get("enabled",false); toggle.set_pressed_no_signal(enabled)
	for action: Dictionary in actions: action.node.disabled=not enabled or action.inputs.any(func(key: String): return not selections.has(key)) or action.get("enabled_paths",[]).any(func(p: String): return not bool(state_value(p)))
	for binding: Dictionary in bindings:
		match binding.type:
			"field": binding.node.text=display(state_value(binding.path))
			"progress":
				var maximum: Variant=state_value(binding.max_path); var value: Variant=state_value(binding.path)
				binding.node.max_value=maxf(1,float(maximum)) if maximum is float or maximum is int else 1
				binding.node.value=float(value) if value is float or value is int else 0
			"list":
				var count:=0
				for row: Dictionary in binding.rows:
					var value: Variant=state_value(row.path); row.node.visible=value!=null and (not value is String or not value.is_empty())
					if row.node.visible: count+=1; row.node.text=str(count)+". "+display(value)
				binding.empty.visible=count==0
			_: if tree_view!=null: tree_view.refresh(binding,enabled)
	if not runtime.get("last_error",{}).is_empty(): feedback.text=L.text("Ошибка программы: ")+str(runtime.last_error)
func _process(delta: float) -> void:
	_elapsed+=delta
	if _elapsed<0.2: return
	_elapsed=0
	var current: Dictionary=service.records.get(identity,{}).get("definition",{}).get("program",{}).get("ui",{}).get("workspace",{})
	if current!=_source or _language!=L.language(): rebuild()
	else: refresh()
