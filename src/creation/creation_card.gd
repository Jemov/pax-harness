extends VBoxContainer
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Preview=preload("res://mods/pax_harness/src/creation/voxel_model_view.gd")
const Icons=preload("res://mods/pax_harness/src/creation/creation_icons.gd")
var service: Node
var identity: String
var project:=false
var expanded:=true
var _state: Dictionary={}
var preview: Control
var feedback: Label
var _language: String=""
const KINDS={"object":"Объект","resource":"Ресурс","panel":"Панель","warp_link":"Варп-маршрут","warp_transit":"Перенос корабля","surface":"Искусственная поверхность","resource_style":"Оформление ресурса","object_damage":"Разрушение объекта"}
const STATES={"pending":"Ожидает подтверждения","applied":"Применено","rejected":"Отклонено","superseded":"Заменён новым проектом"}
func setup(value: Node, id: String, is_project: bool, open_details: bool=true) -> void:
	service=value; identity=id; project=is_project; expanded=open_details
	name="CreationCard_"+id.replace(":","_"); size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8); service.changed.connect(refresh); refresh()
func source() -> Dictionary:
	if not is_instance_valid(service): return {}
	if not project: return service.records.get(identity,{})
	for proposal: Dictionary in service.proposals:
		if proposal.id==identity:
			var result: Dictionary=proposal.duplicate(true)
			var object_id: String=str(proposal.definition.get("id",proposal.definition.get("object_id","")))
			if service.records.has(object_id): result["_damage_state"]=service.records[object_id].get("damage",[]).duplicate(true)
			return result
	return {}
func title(data: Dictionary) -> String:
	var definition: Dictionary=data.definition
	var target: String=str(definition.get("resource_id",definition.get("object_id","")))
	if target!="" and service.records.has(target): definition=service.records[target].definition
	return service._title(definition) if definition.has("name") else L.text(KINDS.get(data.kind,"Объект"))
func label(text: String) -> Label:
	var node:=Label.new(); node.text=text; node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; node.size_flags_horizontal=Control.SIZE_EXPAND_FILL; return node
func button(text: String, action: Callable) -> Button:
	var node:=Button.new(); node.text=text; node.pressed.connect(action); return node
func refresh() -> void:
	var data: Dictionary=source()
	var language: String=L.language()
	if data==_state and language==_language: return
	if language==_language and not _state.is_empty() and data.get("definition")==_state.get("definition") and data.get("status")==_state.get("status") and is_instance_valid(preview):
		_state=data.duplicate(true); preview.reload(); return
	_language=language; _state=data.duplicate(true); _build(data)
func _build(data: Dictionary) -> void:
	for node: Node in get_children(): remove_child(node); node.queue_free()
	preview=null
	if data.is_empty(): return
	var d: Dictionary=data.definition
	var model_definition: Dictionary=d if data.kind=="object" else service.records.get(str(d.get("object_id","")),{}).get("definition",{})
	var status: String=str(data.get("status","applied"))
	var row:=HBoxContainer.new(); add_child(row)
	var icon:=TextureRect.new(); icon.name="CreationIcon"; icon.texture=Icons.make(d.get("icon","panel")); icon.custom_minimum_size=Vector2(22,22)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER; row.add_child(icon)
	var heading:=button(("▾ " if expanded else "▸ ")+title(data),func(): expanded=not expanded; _build(source()))
	heading.alignment=HORIZONTAL_ALIGNMENT_LEFT; heading.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; heading.tooltip_text=title(data); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(heading)
	var body_name: String=str(d.get("body",""))
	if body_name!="" and service.has_method("body_title"): body_name=service.body_title(body_name)
	add_child(label(L.text(KINDS.get(data.kind,"Объект"))+" · "+L.text(STATES.get(status,status))+(" · "+body_name if body_name!="" else "")))
	if not expanded: return
	if data.kind in ["object","object_damage"] and not model_definition.is_empty() and service.api!=null and service.api.get("voxel")!=null:
		preview=Preview.new(); add_child(preview); preview.setup(service,model_definition)
		add_child(label(L.text("Перетаскивание — вращение · колесо — масштаб")))
		if model_definition.get("destructible",false):
			if not service.capabilities().destructible_objects: add_child(label(L.text("Компонент Voxel Tools не установлен. Разрушение недоступно; обычные модели работают без него.")))
			var damage:=CheckButton.new(); damage.name="CarveObject"; damage.text=L.text("Разрушение: нажмите на модель")
			damage.disabled=status!="applied" or not service.records.has(model_definition.id) or not service.capabilities().destructible_objects
			damage.toggled.connect(func(enabled: bool): preview.carving=enabled); add_child(damage)
			preview.carved.connect(func(result: Dictionary): feedback.text=L.text("Изменение применено.") if result.ok else L.text("Не удалось применить проект: ")+str(result.get("code","")))
		add_child(label(L.text("Высота над телом, км: ")+str(model_definition.altitude_km)+L.text(" · размер, км: ")+str(model_definition.size_km)))
	if data.kind=="surface": add_child(label(L.text("Территорий: ")+str(int(d.provinces_count))))
	if data.kind=="resource": add_child(label(L.text("Начальный запас, потребление и производство: 0. Ресурс появится в штатном окне ресурсов.")))
	if data.kind=="panel":
		for field: Dictionary in d.rows:
			var value: String=str(field.get("value",""))
			if field.has("resource_id") and service.records.has(field.resource_id): value=str(service.game.resources(field.body).get(service.records[field.resource_id].resource_key,0))
			add_child(label(str(field.label.get(L.language(),field.label.en))+": "+value))
	if data.kind=="warp_link": add_child(label(str(d.from_id)+" → "+str(d.to_id)+L.text(" · дней: ")+str(d.days)))
	var actions:=HFlowContainer.new(); add_child(actions)
	if project and status=="pending":
		var apply:=button(L.text("Применить"),func(): service.view._apply(identity)); apply.name="Apply_"+identity.replace(":","_"); actions.add_child(apply)
		actions.add_child(button(L.text("Отклонить"),func(): service.reject_from_player(identity)))
	elif data.kind in ["object","object_damage"] and not model_definition.is_empty() and service.records.has(model_definition.id):
		var focus:=button(L.text("Перейти к объекту"),func():
			var result: Dictionary=service.focus_object(str(model_definition.id))
			if not result.ok: feedback.text=L.text("Не удалось перейти к объекту: ")+str(result.get("code","")))
		focus.name="FocusObject_"+str(model_definition.id); actions.add_child(focus)
	elif data.kind=="surface":
		actions.add_child(button(L.text("Открыть карту поверхности"),func(): service.view.window.hide(); service.game.scene_root().galaxy_view().open_body_map(Array(service.game.body_names()).find("harness_surface_"+str(d.id)))))
	if project:
		var details:=TextEdit.new(); details.editable=false; details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; details.custom_minimum_size.y=180; details.text=JSON.stringify(d,"  "); details.hide(); add_child(details)
		actions.add_child(button(L.text("Данные проекта"),func(): details.visible=not details.visible))
	if not project and data.kind=="warp_link":
		var pick:=OptionButton.new(); var ids: Array=[]
		for ship: Dictionary in service.game.ships():
			if ship.get("origin")==service.records[d.from_id].definition.body:
				ids.append(int(ship.id)); pick.add_item(L.text("Корабль №")+str(ship.id)+" → "+str(ship.get("where_to","")))
		add_child(pick)
		var transfer:=button(L.text("Подготовить перенос"),func():
			if pick.selected<0 or pick.selected>=ids.size(): return
			service.propose("warp_transit",{"link_id":identity,"ship_id":ids[pick.selected]},L.text("Перенос выбранного корабля через варп-маршрут из окна управления.")))
		transfer.disabled=ids.is_empty(); add_child(transfer)
	feedback=label(error_text(str(data.error)) if data.has("error") else ""); add_child(feedback)
func error_text(code: String) -> String:
	if code=="creation.voxel_component_required": return L.text("Компонент Voxel Tools не установлен. Разрушение недоступно; обычные модели работают без него.")
	return L.text("Проект не применён: ")+code
