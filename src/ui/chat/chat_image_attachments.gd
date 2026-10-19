extends Node
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const MAX_USER_IMAGES=2
var ui: Node
var row: HFlowContainer
var notice: Label
var _signature:=""
func setup(value: Node,fields: VBoxContainer,actions: HBoxContainer) -> void:
	ui=value
	row=HFlowContainer.new(); row.name="ReferenceImages"; fields.add_child(row); fields.move_child(row,0)
	notice=Label.new(); notice.name="ReferenceImageNotice"; notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; notice.add_theme_color_override("font_color",ui.QUIET); fields.add_child(notice); fields.move_child(notice,1)
	var attach: Button=ui.Layout.icon_button(ui,"attachment",paste_image,L.text("Вставить изображение из буфера · Ctrl+V"),28)
	attach.name="AttachReferenceImage"; actions.add_child(attach); actions.move_child(attach,0)
	ui.input.gui_input.connect(_paste_key)
	ui.store.changed.connect(sync); sync()
func images() -> Array: return ui.store.current().get("draft_images",[]).duplicate(true)
func paste_image() -> void:
	var image: Image=DisplayServer.clipboard_get_image() if DisplayServer.has_method("clipboard_get_image") else null
	if image==null or image.is_empty(): notice.text=L.text("Скопируйте изображение в буфер и нажмите Ctrl+V. Можно также взять картинку из галереи генератора."); notice.show(); return
	add_image(image,L.text("Изображение из буфера"))
func _paste_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode!=KEY_V or not (event.ctrl_pressed or event.meta_pressed): return
	if not DisplayServer.has_method("clipboard_get_image"): return
	var image: Image=DisplayServer.clipboard_get_image()
	if image!=null and not image.is_empty(): add_image(image,L.text("Изображение из буфера")); ui.input.accept_event()
func add_image(image: Image,title: String="image") -> bool:
	if ui.store.current().is_empty(): return false
	if images().size()>=MAX_USER_IMAGES: notice.text=L.text("Можно прикрепить до двух изображений."); notice.show(); return false
	var result: Dictionary=ui.owner_mod.reference_images.import_image(image,title)
	if not result.ok: notice.text=L.text("Не удалось прикрепить изображение: ")+str(result.code); notice.show(); return false
	return add_reference(result.attachment)
func add_reference(handle: Dictionary) -> bool:
	if images().size()>=MAX_USER_IMAGES or not ui.owner_mod.reference_images.resolve(handle).get("ok",false): return false
	var draft: Dictionary=ui.store.current()
	if not draft.has("draft_images"): draft["draft_images"]=[]
	if not draft.draft_images.any(func(image: Dictionary): return image.id==handle.id): draft.draft_images.append(handle.duplicate(true))
	ui.store.changed.emit(); ui._update_send_state(); return true
func sync() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(row): return
	var refs: Array=images(); var enabled: bool=ui.owner_mod.vision_input_enabled()
	var signature: String=JSON.stringify([refs,enabled,L.language()])
	if signature==_signature: return
	_signature=signature
	for child: Node in row.get_children(): row.remove_child(child); child.queue_free()
	for handle: Dictionary in refs:
		var chip:=HBoxContainer.new(); row.add_child(chip)
		var thumbnail:=TextureRect.new(); thumbnail.texture=ui.owner_mod.reference_images.texture(handle); thumbnail.custom_minimum_size=Vector2(64,48); thumbnail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; thumbnail.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; chip.add_child(thumbnail)
		var remove: Button=ui._button("×",func(): ui.store.current().get("draft_images",[]).erase(handle); ui.store.changed.emit(); ui._update_send_state())
		remove.tooltip_text=L.text("Убрать изображение"); chip.add_child(remove)
	row.visible=not refs.is_empty()
	notice.text=L.text("Ввод изображений у выбранной модели выключен или не поддерживается. Текст будет отправлен, модель получит уведомление о вложении.") if not enabled else ""
	notice.visible=not refs.is_empty() and not enabled
func _process(_delta: float) -> void:
	if is_instance_valid(ui) and ui.surface.visible: sync()

static func message_preview(ui: Node,parent: Node,images_: Array,warning: String) -> void:
	for handle: Dictionary in images_:
		var texture: Texture2D=ui.owner_mod.reference_images.texture(handle)
		if texture==null: continue
		var image:=TextureRect.new(); image.name="AttachedReferenceImage"; image.texture=texture; image.custom_minimum_size=Vector2(240,135); image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; parent.add_child(image)
		image.tooltip_text=str(handle.get("name","image"))
		image.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
		image.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:preload("res://mods/pax_harness/src/ui/images/image_viewer.gd").open(ui,texture,str(handle.get("name","image"))))
	if warning!="":
		var label:=Label.new(); label.name="ImageInputWarning"; label.text=warning; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.add_theme_color_override("font_color",ui.QUIET); parent.add_child(label)
