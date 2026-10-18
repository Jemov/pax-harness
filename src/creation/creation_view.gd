extends Node
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const Icons = preload("res://mods/pax_harness/src/creation/creation_icons.gd")
var service: Node
var window: PanelContainer
var content: VBoxContainer
var feedback: Label
func setup(value: Node) -> void:
	service=value
	var body:=VBoxContainer.new(); body.name="HarnessCreations"
	var heading:=_label(L.text("Новые сущности")); body.add_child(heading)
	var hint:=_label(L.text("Агент готовит проект. Только кнопка «Применить» добавляет его в эту партию. Модель и иконка не означают исследование или постройку за ресурсы.")); body.add_child(hint)
	feedback=_label(""); body.add_child(feedback)
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(560,360); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(scroll)
	content=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",12); scroll.add_child(content)
	window=service.game.add_window(L.text("Новые сущности"),body,Vector2(620,460))
	window.name="HarnessCreationWindow"; window.hide()
	service.changed.connect(refresh); refresh()
func _label(text: String) -> Label:
	var label:=Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; return label
func _button(text: String, action: Callable) -> Button:
	var button:=Button.new(); button.text=text; button.pressed.connect(action); return button
func open() -> void:
	if is_instance_valid(service.owner_mod.chat_ui): service.owner_mod.chat_ui.close()
	window.show(); refresh()
func refresh() -> void:
	if not is_instance_valid(content): return
	for node: Node in content.get_children(): content.remove_child(node); node.queue_free()
	content.add_child(_label(L.text("Проекты на подтверждение")))
	var count:=0
	for p: Dictionary in service.proposals:
		if p.status!="pending": continue
		count+=1
		var box:=VBoxContainer.new(); content.add_child(box)
		var title: String=service._title(service.records[p.definition.resource_id].definition) if p.kind=="resource_style" else service._title(p.definition)
		box.add_child(_label(title+" · "+L.text({"object":"Объект","resource":"Ресурс","panel":"Панель","warp_link":"Варп-маршрут","warp_transit":"Перенос корабля","surface":"Искусственная поверхность","resource_style":"Оформление ресурса"}[p.kind])))
		box.add_child(_label(L.text("Ваш запрос: ")+str(p.request)))
		if p.kind=="object": box.add_child(_label(str(p.definition.body)+L.text(" · высота, км: ")+str(p.definition.altitude_km)+L.text(" · размер, км: ")+str(p.definition.size_km)))
		if p.kind=="surface": box.add_child(_label(str(p.definition.body)+L.text(" · высота оболочки, км: ")+str(p.definition.altitude_km)+L.text(" · территорий: ")+str(int(p.definition.provinces_count))+"\n"+L.text("Исходное тело сохраняется. Население, колония и ресурсы не добавляются.")))
		if p.kind=="resource_style": box.add_child(_label(str(p.definition.resource_id)+L.text(" · цвет текста: ")+str(p.definition.text_color if p.definition.text_color!=null else L.text("Штатный"))))
		if p.kind=="resource": box.add_child(_label(L.text("Начальный запас, потребление и производство: 0. Ресурс появится в штатном окне ресурсов.")))
		if p.kind=="warp_link": box.add_child(_label(str(p.definition.from_id)+" → "+str(p.definition.to_id)+L.text(" · дней: ")+str(p.definition.days)))
		if p.kind=="warp_transit": box.add_child(_label(L.text("Корабль №")+str(p.definition.ship_id)+L.text(" · маршрут: ")+str(p.definition.link_id)))
		var row:=HFlowContainer.new(); box.add_child(row)
		var apply:=_button(L.text("Применить"),_apply.bind(str(p.id))); apply.name="Apply_"+str(p.id).replace(":","_"); row.add_child(apply)
		row.add_child(_button(L.text("Отклонить"),func(): service.reject_from_player(p.id)))
		var details:=TextEdit.new(); details.editable=false; details.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; details.custom_minimum_size.y=200; details.text=JSON.stringify(p.definition,"  "); details.hide(); box.add_child(details)
		row.add_child(_button(L.text("Данные проекта"),func(): details.visible=not details.visible))
		if p.kind=="object": row.add_child(_button(L.text("Предпросмотр модели"),func(): _preview(box,p.definition)))
		if p.has("error"): box.add_child(_label(L.text("Проект не применён: данные изменились или недоступны. Проверьте проект заново.")+" ["+str(p.error)+"]"))
	if count==0: content.add_child(_label(L.text("Нет проектов на подтверждение.")))
	content.add_child(HSeparator.new()); content.add_child(_label(L.text("Добавлено в партию")))
	for id: String in service.records:
		var record: Dictionary=service.records[id]; var d: Dictionary=record.definition
		var box:=VBoxContainer.new(); content.add_child(box)
		var row:=HBoxContainer.new(); box.add_child(row)
		var icon:=TextureRect.new(); icon.texture=Icons.make(d.get("icon","panel")); icon.custom_minimum_size=Vector2(24,24); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; row.add_child(icon)
		row.add_child(_label(service._title(d)))
		if record.kind=="surface":
			box.add_child(_label(str(d.body)+L.text(" · территорий: ")+str(int(d.provinces_count))))
			box.add_child(_button(L.text("Открыть карту поверхности"),func(): window.hide(); service.game.scene_root().galaxy_view().open_body_map(Array(service.game.body_names()).find("harness_surface_"+str(d.id)))))
		if record.kind=="object":
			box.add_child(_button(L.text("Предпросмотр модели"),func(): _preview(box,d)))
			box.add_child(_label(str(d.body)+" · "+str(d.longitude)+"°, "+str(d.latitude)+"°"))
			box.add_child(_button(L.text("Перейти к телу"),func(): service.owner_mod.chat_ui.close(); window.hide(); service.game.focus(d.body,true)))
		if record.kind=="panel":
			for field: Dictionary in d.rows:
				var value: String=str(field.get("value",""))
				if field.has("resource_id"): value=str(service.game.resources(field.body).get(service.records[field.resource_id].resource_key,0))
				box.add_child(_label(str(field.label.get(L.language(),field.label.en))+": "+value))
		if record.kind=="warp_link":
			box.add_child(_label(str(d.from_id)+" → "+str(d.to_id)+L.text(" · дней: ")+str(d.days)))
			var pick:=OptionButton.new(); var ids: Array=[]
			for ship: Dictionary in service.game.ships():
				if ship.get("origin")==service.records[d.from_id].definition.body:
					ids.append(int(ship.id)); pick.add_item(L.text("Корабль №")+str(ship.id)+" → "+str(ship.get("where_to","")))
			box.add_child(pick)
			var transfer:=_button(L.text("Подготовить перенос"),func():
				if pick.selected<0 or pick.selected>=ids.size(): return
				service.propose("warp_transit",{"link_id":id,"ship_id":ids[pick.selected]},L.text("Перенос выбранного корабля через варп-маршрут из окна управления.")))
			transfer.disabled=ids.is_empty(); box.add_child(transfer)
func _apply(id: String) -> void:
	var result: Dictionary=service.apply_from_player(id)
	feedback.text=L.text("Изменение применено.") if result.ok else L.text("Не удалось применить проект: ")+str(result.get("code",""))
func _preview(box: Control, d: Dictionary) -> void:
	if box.get_node_or_null("ModelPreview")!=null: return
	var container:=SubViewportContainer.new(); container.name="ModelPreview"; container.custom_minimum_size=Vector2(320,220); container.stretch=true; box.add_child(container)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(480,300); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE; container.add_child(viewport)
	var mesh: MeshInstance3D=service.api.voxel.model(d.model); viewport.add_child(mesh)
	var center: Vector3=mesh.get_aabb().get_center(); var span: float=maxf(4,mesh.get_aabb().size.length())
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=center+Vector3(0.8,0.6,1)*span; camera.look_at(center); camera.current=true
	var light:=DirectionalLight3D.new(); viewport.add_child(light); light.rotation_degrees=Vector3(-45,-35,0); light.light_energy=1.8
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color("#151a20"); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=0.5; viewport.add_child(environment)
func dispose() -> void:
	if is_instance_valid(window): window.queue_free()
	window=null
