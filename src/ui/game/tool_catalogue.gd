extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Labels = preload("res://mods/pax_harness/src/runtime/tools/tool_labels.gd")
const Permissions = preload("res://mods/pax_harness/src/runtime/tools/tool_permissions.gd")
const Partial = preload("res://mods/pax_harness/src/ui/components/partial_checkbox.gd")
const Groups = preload("res://mods/pax_harness/src/runtime/tools/tool_groups.gd")
const TITLES := {"mods":"Сущности и интерфейсы модов","tools":"Выбор инструментов","charts":"Графики и таблицы","maps":"Карты и провинции","analytics":"Аналитика и данные модов","ui":"Интерфейс игры","images":"Генерация изображений","space":"Космос и навигация","economy":"Экономика","world":"Мир и история","chat":"Сохранённые чаты","workspace":"Планы и инструкции","prompts":"Промпты лаборатории","people":"Персонажи","orders":"Приказы","research":"Исследования","diplomacy":"Дипломатия и законы","military":"Армия","time":"Время","creation":"Создание сущностей"}
static func build(owner: Node) -> Control:
	var root:=VBoxContainer.new(); root.name="HarnessToolCatalogue"
	var toggle:=Button.new(); toggle.name="ToolCatalogueToggle"; toggle.text=L.text("Инструменты агента")+" ▸"; toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT; root.add_child(toggle)
	var body:=VBoxContainer.new(); body.hide(); root.add_child(body)
	toggle.pressed.connect(func(): body.visible=not body.visible; toggle.text=L.text("Инструменты агента")+(" ▾" if body.visible else " ▸"))
	var hint:=Label.new(); hint.text=L.text("Галочки управляют доступом агента к инструментам. Квадрат означает частично включённую группу. Отключённые функции нельзя вызвать даже в текущем диалоге. Инструменты загружаются нужными группами по мере необходимости."); hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.add_child(hint)
	var groups: Dictionary={}
	for tool: Dictionary in owner._tool_registry().catalogue(true):
		var id: String=Groups.group_for(tool.name)
		if not groups.has(id): groups[id]=[]
		groups[id].append(tool)
	for id: String in groups:
		var section:=VBoxContainer.new(); body.add_child(section)
		var group_row:=HBoxContainer.new(); section.add_child(group_row)
		var group_check:=Partial.new(); group_check.name="EnableGroup_"+id; group_check.tooltip_text=L.text("Включить или выключить всю группу"); group_row.add_child(group_check)
		var button:=Button.new(); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.name="Tools_"+id; button.text=L.text(TITLES.get(id,id))+" ("+str(groups[id].size())+") ▸"; button.alignment=HORIZONTAL_ALIGNMENT_LEFT; group_row.add_child(button)
		var list:=VBoxContainer.new(); list.hide(); section.add_child(list)
		button.pressed.connect(func(): list.visible=not list.visible; button.text=L.text(TITLES.get(id,id))+" ("+str(groups[id].size())+")"+(" ▾" if list.visible else " ▸"))
		var names: Array=[]; var checks: Dictionary={}
		for tool: Dictionary in groups[id]:
			var tool_row:=HBoxContainer.new(); list.add_child(tool_row)
			var check:=CheckBox.new(); check.name="EnableTool_"+str(tool.name).replace(".","_"); check.tooltip_text=str(tool.name); check.set_pressed_no_signal(Permissions.allowed(owner,tool.name)); tool_row.add_child(check)
			names.append(str(tool.name)); checks[str(tool.name)]=check
			var label:=Label.new(); label.name="ToolDescription_"+str(tool.name).replace(".","_"); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			label.text=str(tool.name)+" — "+L.text(Labels.LABELS.get(tool.name,tool.name))+(L.text(" · недоступно в этой партии") if not tool.available else "")
			tool_row.add_child(label)
			check.toggled.connect(func(enabled: bool): Permissions.set_many(owner,[str(tool.name)],enabled); group_check.set_state(Permissions.state(owner,names)))
		group_check.set_state(Permissions.state(owner,names))
		group_check.toggled.connect(func(enabled: bool):
			var desired: bool=true if group_check.mixed else enabled
			Permissions.set_many(owner,names,desired)
			for key: String in checks: checks[key].set_pressed_no_signal(desired)
			group_check.set_state(Permissions.state(owner,names)))

	root.add_child(_review_button(owner))
	return root
static func _review_button(owner: Node) -> Button:
	var button:=Button.new(); button.text=L.text("Открыть проекты новых сущностей"); button.pressed.connect(func(): owner._creations.open_review()); return button
