extends VBoxContainer
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
const Icons=preload("res://mods/pax_harness/src/ui/components/chat_icons.gd")
const Viewer=preload("res://mods/pax_harness/src/ui/images/image_viewer.gd")
var _cards: Dictionary={}
var _toggle: Button
var _scroll: ScrollContainer
var _row: HBoxContainer
func _ensure() -> void:
	if _toggle!=null: return
	_toggle=Button.new();_toggle.name="ScreenImagesToggle";_toggle.flat=true;_toggle.icon=Icons.make("image",Color("949ba7"),16);_toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT;add_child(_toggle)
	_scroll=ScrollContainer.new();_scroll.name="ScreenImagesStrip";_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(_scroll)
	_row=HBoxContainer.new();_row.add_theme_constant_override("separation",8);_scroll.add_child(_row)
	_toggle.pressed.connect(func():_scroll.visible=not _scroll.visible)
func update_images(ui: Node, events: Array) -> void:
	_ensure()
	var store: Variant=ui.owner_mod.get("screen_images")
	var keep: Dictionary={};var count:=0;var observed:=0
	for event: Dictionary in events:
		var descriptor: Variant=event.get("result",{}).get("screenshot_preview") if event.get("kind")=="tool" and event.get("result") is Dictionary else null
		if not descriptor is Dictionary or keep.has(descriptor.get("id","")): continue
		var id: String=str(descriptor.get("id",""));keep[id]=true;count+=1
		var result: Dictionary=({"ok":true,"descriptor":store.items.get(id,descriptor)} if _cards.has(id) else store.resolve(descriptor)) if store!=null else {"ok":false}
		if not result.get("ok",false): continue
		if result.descriptor.get("observed",false): observed+=1
		if not _cards.has(id):
			var card:=TextureButton.new();card.name="ScreenPreview_"+id;var thumb: Image=result.texture.get_image();var scale_: float=minf(160.0/thumb.get_width(),90.0/thumb.get_height());thumb.resize(maxi(1,roundi(thumb.get_width()*scale_)),maxi(1,roundi(thumb.get_height()*scale_)),Image.INTERPOLATE_LANCZOS);card.texture_normal=ImageTexture.create_from_image(thumb);card.ignore_texture_size=true;card.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_CENTERED;card.custom_minimum_size=Vector2(160,90);card.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
			card.pressed.connect(func():
				var full: Dictionary=store.resolve(descriptor)
				if full.get("ok",false):Viewer.open(ui,full.texture,"",["Игровой снимок",{"value":" · "+str(int(descriptor.width))+" × "+str(int(descriptor.height))}]))
			_row.add_child(card);_cards[id]=card
		L.bind(_cards[id],"tooltip_text",["Просмотрено изображение" if result.descriptor.get("observed",false) else "Снимок ещё не получен моделью",{"value":" · "+str(int(descriptor.width))+" × "+str(int(descriptor.height))+" · "},"Нажмите, чтобы развернуть"])
	for id: String in _cards.keys():
		if not keep.has(id):_cards[id].queue_free();_cards.erase(id)
	L.bind(_toggle,"text",["Просмотренные изображения" if observed==count else "Снимки экрана",{"value":" · "+str(observed if observed==count else count)}])
	visible=count>0
