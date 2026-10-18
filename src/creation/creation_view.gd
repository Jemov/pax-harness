extends Node
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Card=preload("res://mods/pax_harness/src/creation/creation_card.gd")
const PAGE_SIZE:=10
var service: Node
var window: PanelContainer
var content: VBoxContainer
var feedback: Label
var search: LineEdit
var filter: OptionButton
var page_label: Label
var previous: Button
var next: Button
var page:=0
var _cards: Dictionary={}
func setup(value: Node) -> void:
	service=value
	var body:=VBoxContainer.new(); body.name="HarnessCreations"
	var heading:=Label.new(); heading.text=L.text("Новые сущности"); heading.add_theme_font_size_override("font_size",18); body.add_child(heading)
	feedback=Label.new(); feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.add_child(feedback)
	search=LineEdit.new(); search.name="CreationSearch"; search.placeholder_text=L.text("Поиск по названию, телу или типу"); body.add_child(search)
	filter=OptionButton.new(); filter.name="CreationFilter"
	for caption: String in ["Проекты и объекты","На подтверждении","Добавлено в партию","История"]: filter.add_item(L.text(caption))
	body.add_child(filter)
	search.text_changed.connect(func(_text: String): page=0; refresh())
	filter.item_selected.connect(func(_index: int): page=0; refresh())
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(560,360); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(scroll)
	content=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",12); scroll.add_child(content)
	var pages:=HBoxContainer.new(); body.add_child(pages)
	previous=Button.new(); previous.text="‹"; previous.name="PreviousPage"; previous.pressed.connect(func(): page=maxi(0,page-1); refresh()); pages.add_child(previous)
	page_label=Label.new(); page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; pages.add_child(page_label)
	next=Button.new(); next.text="›"; next.name="NextPage"; next.pressed.connect(func(): page+=1; refresh()); pages.add_child(next)
	window=service.game.add_window(L.text("Новые сущности"),body,Vector2(680,540)); window.name="HarnessCreationWindow"; window.hide()
	service.changed.connect(refresh); refresh()
func open() -> void:
	if is_instance_valid(service.owner_mod.chat_ui): service.owner_mod.chat_ui.close()
	window.show(); refresh()
func refresh() -> void:
	if not is_instance_valid(content): return
	var rows: Array=[]
	if filter.selected in [0,1,3]:
		for p: Dictionary in service.proposals:
			if (filter.selected==3) == (p.status!="pending"): rows.append({"id":p.id,"project":true,"data":p})
	if filter.selected in [0,2]:
		for id: String in service.records: rows.append({"id":id,"project":false,"data":service.records[id]})
	var query: String=search.text.strip_edges().to_lower()
	rows=rows.filter(func(row: Dictionary): return _matches(row,query))
	var pages: int=maxi(1,ceili(float(rows.size())/PAGE_SIZE)); page=clampi(page,0,pages-1)
	page_label.text=str(page+1)+" / "+str(pages)+" · "+str(rows.size()); previous.disabled=page==0; next.disabled=page==pages-1
	var visible_rows: Array=rows.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE)
	var keys: Array=[]
	for row: Dictionary in visible_rows: keys.append(("p:" if row.project else "r:")+str(row.id))
	for key: String in _cards.keys():
		if key not in keys:
			var old: Node=_cards[key]; content.remove_child(old); old.queue_free(); _cards.erase(key)
	for index: int in visible_rows.size():
		var row: Dictionary=visible_rows[index]; var key: String=keys[index]
		if not _cards.has(key):
			var card:=Card.new(); content.add_child(card); _cards[key]=card; card.setup(service,row.id,row.project,false)
		content.move_child(_cards[key],index); _cards[key].refresh()
func _matches(row: Dictionary, query: String) -> bool:
	if query=="": return true
	var d: Dictionary=row.data.definition
	var target: String=str(d.get("resource_id",d.get("object_id","")))
	if service.records.has(target): d=service.records[target].definition
	var body: String=str(d.get("body",""))
	var display_body: String=service.body_title(body) if service.has_method("body_title") and body!="" else body
	return (service._title(d)+" "+str(d.get("id",target))+" "+body+" "+display_body+" "+L.text(Card.KINDS.get(row.data.kind,"Объект"))+" "+str(row.id)).to_lower().contains(query)
func _apply(id: String) -> void:
	var result: Dictionary=service.apply_from_player(id)
	feedback.text=L.text("Изменение применено.") if result.ok else L.text("Не удалось применить проект: ")+str(result.get("code",""))
func dispose() -> void:
	if is_instance_valid(window): window.queue_free()
	window=null
