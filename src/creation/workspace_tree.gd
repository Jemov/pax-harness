extends RefCounted
## Renderer for the agent's layout tree; effects stay in approved handlers.
var view: VBoxContainer
func setup(owner: VBoxContainer) -> void: view=owner
func build(parent: Node,s: Dictionary,enabled_paths: Array=[]) -> Control:
	var paths: Array=enabled_paths.duplicate()
	if s.has("enabled_path"): paths.append(s.enabled_path)
	var control: Control
	match s.type:
		"row": control=HBoxContainer.new()
		"grid": control=GridContainer.new(); control.columns=int(s.get("columns",2))
		"tabs": control=TabContainer.new(); control.custom_minimum_size.y=320
		"scroll": control=ScrollContainer.new(); control.custom_minimum_size.y=160; control.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
		_: control=VBoxContainer.new()
	control.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(control)
	if s.has("visible_path"): view.bindings.append({"type":"visible","node":control,"path":s.visible_path})
	if s.type in ["row","grid","column","tabs","panel","scroll"]:
		var target: Control=control
		if s.type=="panel":
			if s.has("title"): control.add_child(view.label(view.text(s.title)))
			var panel:=PanelContainer.new(); control.add_child(panel)
			var margin:=MarginContainer.new(); panel.add_child(margin)
			for side: String in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,12)
			target=VBoxContainer.new(); margin.add_child(target)
		elif s.type=="scroll": target=VBoxContainer.new(); target.size_flags_horizontal=Control.SIZE_EXPAND_FILL; control.add_child(target)
		for child: Dictionary in s.children:
			var rendered: Control=build(target,child,paths)
			if s.type=="tabs": control.set_tab_title(control.get_tab_count()-1,view.text(child.title)); rendered.size_flags_vertical=Control.SIZE_EXPAND_FILL
		return control
	if s.has("title") and s.type!="button" and not (s.type=="input" and s.kind=="toggle"): control.add_child(view.label(view.text(s.title)))
	match s.type:
		"text": control.add_child(view.label(view.text(s.text)))
		"value":
			var value: Label=view.label(""); control.add_child(value); view.bindings.append({"type":"field","node":value,"path":s.path})
		"separator": control.add_child(HSeparator.new())
		"progress":
			var bar:=ProgressBar.new(); bar.custom_minimum_size.y=24; control.add_child(bar); view.bindings.append({"type":"progress","node":bar,"path":s.path,"max_path":s.max_path})
		"table":
			var table:=Tree.new(); table.hide_root=true; table.columns=s.columns.size(); table.column_titles_visible=true; table.custom_minimum_size=Vector2(260,180); table.size_flags_horizontal=Control.SIZE_EXPAND_FILL; control.add_child(table)
			for i: int in s.columns.size(): table.set_column_title(i,view.text(s.columns[i].title))
			view.bindings.append({"type":"table","node":table,"path":s.path,"columns":s.columns,"empty":s.empty,"previous":null})
		"input": build_input(control,s,paths)
		"button":
			var button:=Button.new(); button.name="WorkspaceButton_"+s.id; button.text=view.text(s.title); button.custom_minimum_size.y=36; button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; control.add_child(button)
			view.actions.append({"node":button,"inputs":s.get("inputs",[]),"enabled_paths":paths})
			button.pressed.connect(func(): view.send(s.event,s.get("inputs",[]),s.get("payload",{})))
	return control
func build_input(parent: Control,s: Dictionary,paths: Array) -> void:
	var value: Variant=view.drafts.get(s.id,view.state_value(s.initial_path) if s.has("initial_path") else s.get("default"))
	var input: Control
	match s.kind:
		"text":
			var edit:=LineEdit.new(); edit.max_length=int(s.get("max_length",2048)); edit.text=(value if value is String else "").left(edit.max_length); value=edit.text; input=edit
			edit.text_changed.connect(func(v: String): view.selections[s.id]=v)
		"textarea":
			var edit:=TextEdit.new(); edit.custom_minimum_size.y=100; edit.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; edit.text=(value if value is String else "").left(int(s.get("max_length",2048))); value=edit.text; input=edit
			edit.text_changed.connect(func():
				var caret: Vector2i=Vector2i(edit.get_caret_column(),edit.get_caret_line())
				if edit.text.length()>int(s.get("max_length",2048)): edit.text=edit.text.left(int(s.get("max_length",2048))); edit.set_caret_line(caret.y); edit.set_caret_column(caret.x)
				view.selections[s.id]=edit.text)
		"number","slider":
			var numeric: Range=SpinBox.new() if s.kind=="number" else HSlider.new(); numeric.min_value=float(s.get("min",0)); numeric.max_value=float(s.get("max",100)); numeric.step=float(s.get("step",1)); numeric.value=float(value) if value is int or value is float else numeric.min_value; value=numeric.value; input=numeric
			numeric.value_changed.connect(func(v: float): view.selections[s.id]=v)
			if s.kind=="slider":
				var line:=HBoxContainer.new(); parent.add_child(line); parent=line
				var readout: Label=view.label(view.display(numeric.value)); readout.size_flags_horizontal=0; readout.custom_minimum_size.x=48; line.add_child(readout)
				numeric.value_changed.connect(func(v: float): readout.text=view.display(v))
		"toggle":
			var flag:=CheckButton.new(); flag.text=view.text(s.title); flag.button_pressed=value if value is bool else false; value=flag.button_pressed; input=flag
			flag.toggled.connect(func(v: bool): view.selections[s.id]=v)
		"select":
			var select:=OptionButton.new(); var selected:=0
			for i: int in s.options.size():
				select.add_item(view.text(s.options[i].title))
				if preload("res://mods/pax_harness/src/creation/workspace_tree_spec.gd").same_scalar(value,s.options[i].value): selected=i
			select.select(selected); value=s.options[selected].value; input=select
			select.item_selected.connect(func(i: int): view.selections[s.id]=s.options[i].value)
	view.selections[s.id]=value; input.name="WorkspaceInput_"+s.id; input.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(input)
	view.bindings.append({"type":"input_enabled","node":input,"enabled_paths":paths})
func refresh(binding: Dictionary,enabled: bool) -> void:
	match binding.type:
		"visible": binding.node.visible=bool(view.state_value(binding.path))
		"input_enabled":
			var active: bool=enabled and binding.enabled_paths.all(func(p: String): return bool(view.state_value(p)))
			var input: Control=binding.node
			if input is BaseButton: input.disabled=not active
			elif input is SpinBox: input.editable=active
			elif input is LineEdit or input is TextEdit: input.editable=active
			elif input is Slider: input.editable=active
		"table":
			var value: Variant=view.state_value(binding.path)
			if binding.get("drawn",false) and typeof(binding.previous)==typeof(value) and binding.previous==value: return
			binding.drawn=true
			binding.previous=value.duplicate(true) if value is Array or value is Dictionary else value
			var table: Tree=binding.node; table.clear(); var root: TreeItem=table.create_item(); var count:=0
			if value is Array:
				for data: Variant in value.slice(0,64):
					if not data is Dictionary: continue
					var row: TreeItem=table.create_item(root); count+=1
					for i: int in binding.columns.size(): row.set_text(i,view.display(data.get(binding.columns[i].key)))
			if count==0: table.create_item(root).set_text(0,view.text(binding.empty))
