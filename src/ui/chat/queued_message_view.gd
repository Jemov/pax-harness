extends PanelContainer
## Compact queue row. Editing holds dispatch; actions retain text and image handles.
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Icons=preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
const Style=preload("res://mods/pax_harness/src/ui/components/chat_style.gd")
const Preferences=preload("res://mods/pax_harness/src/ui/chat/chat_preferences.gd")
var ui: Node
var message: Dictionary={}
var row: HBoxContainer
var summary: Button
var thumbnail: TextureRect
var steer: Button
var trash: Button
var more: Button
var menu: PopupMenu
var editor: ConfirmationDialog
var text_field: TextEdit
var _signature:=""
var _editing:=false
func setup(value: Node) -> void:
	ui=value; name="QueuedMessage"; size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel",Style.box(Color("#25282e"),10,Color.TRANSPARENT,6))
	row=HBoxContainer.new(); row.add_theme_constant_override("separation",6); add_child(row)
	thumbnail=TextureRect.new(); thumbnail.name="QueueThumbnail"; thumbnail.custom_minimum_size=Vector2(32,24); thumbnail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; thumbnail.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; thumbnail.size_flags_vertical=Control.SIZE_SHRINK_CENTER; row.add_child(thumbnail)
	summary=Button.new(); summary.name="QueueSummary"; summary.flat=true; summary.alignment=HORIZONTAL_ALIGNMENT_LEFT; summary.icon=Icons.make("section",ui.QUIET,14); summary.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL; summary.add_theme_font_size_override("font_size",14); summary.pressed.connect(func(): show_text(false)); row.add_child(summary)
	for state: String in ["normal","hover","pressed","focus","disabled"]: summary.add_theme_stylebox_override(state,Style.box(Color("#2c3037") if state in ["hover","focus"] else Color.TRANSPARENT,5,Color.TRANSPARENT,2))
	steer=action("return","QueueSteer",func(): ui.owner_mod.chat_steer_queued(str(message.id)))
	trash=action("trash","QueueRemove",func(): ui.store.remove_queued(str(message.id)))
	more=action("more","QueueMore",show_menu)
	menu=PopupMenu.new(); menu.set_meta("preferred_width",320); add_child(menu)
func action(icon: String,id: String,callback: Callable) -> Button:
	var result: Button=ui.Layout.icon_button(ui,icon,callback,"",28); result.name=id
	for state: String in ["normal","pressed","focus"]: result.add_theme_stylebox_override(state,Style.box(Color.TRANSPARENT,5,Color.TRANSPARENT,0))
	row.add_child(result); return result
func update_message(value: Dictionary) -> void:
	message=value.duplicate(true)
	var signature: String=JSON.stringify([message,L.language()])
	if signature==_signature: return
	_signature=signature
	summary.text=str(message.get("text","")).replace("\n"," ").replace("\r"," ")
	summary.tooltip_text=L.text("Просмотреть сообщение")
	var queued: bool=message.get("status")=="queued"
	steer.visible=queued; trash.visible=queued; more.visible=queued
	if not queued: summary.text=(L.text("Отправка прервана") if message.get("status")=="interrupted" else L.text("Отправка отменена"))+" · "+summary.text
	steer.tooltip_text=L.text("Скорректировать: остановить текущий ответ и отправить это сообщение")
	trash.tooltip_text=L.text("Удалить из очереди"); more.tooltip_text=L.text("Действия с сообщением")
	thumbnail.hide()
	if not message.get("images",[]).is_empty() and ui.owner_mod.get("reference_images")!=null:
		thumbnail.texture=ui.owner_mod.reference_images.texture(message.images[0]); thumbnail.visible=thumbnail.texture!=null
func show_menu() -> void:
	menu.clear()
	menu.add_icon_item(Icons.make("edit"),L.text("Редактировать сообщение"),1)
	menu.add_icon_item(Icons.make("external"),L.text("Открыть в новом чате"),2)
	menu.add_icon_item(Icons.make("section"),L.text("Отключить постановку в очередь") if Preferences.value(ui.owner_mod,"busy_send")=="queue" else L.text("Включить постановку в очередь"),3)
	ui.chat_menu.view.show_menu(menu,_menu_action,{},more.global_position+Vector2(0,more.size.y))
func _menu_action(id: int) -> void:
	match id:
		1: show_text(true)
		2: ui.owner_mod.chat_queued_to_draft(str(message.id))
		3:
			if ui.owner_mod.has_method("set_setting"):
				ui.owner_mod.set_setting("busy_send","interrupt" if Preferences.value(ui.owner_mod,"busy_send")=="queue" else "queue"); ui.apply_preferences()
func show_text(editable: bool) -> void:
	if is_instance_valid(editor): return
	var delivery: Dictionary=ui.store.queued_delivery(str(message.id))
	if editable and delivery.is_empty(): return
	if not delivery.is_empty(): delivery["editing"]=true
	_editing=editable
	editor=ConfirmationDialog.new(); editor.name="QueuedMessageEditor"; editor.theme=ui.surface.theme; editor.exclusive=true
	editor.title=L.text("Редактировать сообщение") if editable else L.text("Сообщение в очереди")
	editor.ok_button_text=L.text("Сохранить") if editable else L.text("Закрыть"); editor.cancel_button_text=L.text("Отмена")
	editor.add_theme_stylebox_override("panel",Style.box(Color("#25282e"),8,Color("#393c43"),16))
	var extent: Vector2=ui.get_viewport().get_visible_rect().size
	text_field=TextEdit.new(); text_field.name="QueuedMessageText"; text_field.text=str(message.get("text","")); text_field.editable=editable; text_field.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; text_field.custom_minimum_size=Vector2(minf(420,maxf(200,extent.x-80)),minf(220,maxf(100,extent.y-160))); editor.add_child(text_field)
	text_field.text_changed.connect(func(): editor.get_ok_button().disabled=_editing and text_field.text.strip_edges().is_empty())
	editor.confirmed.connect(func():
		if _editing: ui.store.edit_queued(str(message.id),text_field.text)
		_release_editor())
	editor.canceled.connect(_release_editor); editor.close_requested.connect(_release_editor)
	ui.add_child(editor); editor.get_cancel_button().visible=editable
	editor.popup_centered(Vector2i(minf(680,extent.x-32),minf(440,extent.y-32)))
	if editable: text_field.grab_focus()
func _release_editor() -> void:
	var delivery: Dictionary=ui.store.queued_delivery(str(message.get("id","")))
	if not delivery.is_empty(): delivery.erase("editing")
	if is_instance_valid(editor): editor.queue_free()
	editor=null
	if is_instance_valid(ui) and ui.owner_mod.has_method("_chat_pump"): ui.owner_mod.call_deferred("_chat_pump")
func _exit_tree() -> void:
	if is_instance_valid(ui): _release_editor()
