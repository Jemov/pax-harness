extends SceneTree
const Store=preload("res://mods/pax_harness/src/images/screen_images.gd")
const Capture=preload("res://mods/pax_harness/src/ui/game/ui_capture.gd")
const Session=preload("res://mods/pax_harness/src/ui/game/screen_session.gd")
const Gallery=preload("res://mods/pax_harness/src/ui/images/screen_image_gallery.gd")
const Viewer=preload("res://mods/pax_harness/src/ui/images/image_viewer.gd")
const L=preload("res://mods/pax_harness/src/localization/localization.gd")
class Game extends RefCounted:
	var main: Node
	func scene_root() -> Node:return main
class Chat extends CanvasLayer:
	var native: Control
	func open() -> void:show()
class Owner extends Node:
	var records: Dictionary={}
	var screen_images: RefCounted
	var _screen_session: Node
	var chat_ui: CanvasLayer
	var game: RefCounted
	var busy:=true
	func save_data(key: String, value: Variant) -> void:records[key]=value.duplicate(true)
	func load_data(key: String, fallback: Variant) -> Variant:return records.get(key,fallback).duplicate(true)
	func vision_context() -> Dictionary:return {"enabled":true,"base":"https://fixture.invalid/v1","model":"Vision","provider_id":1,"world_generation":1}
	func _game_available(candidate: RefCounted) -> bool:return candidate==game
	func chat_busy() -> bool:return busy
	func chat_stop() -> void:busy=false;_screen_session.end()
	func invalidate_game_input_frames() -> void:pass
class Ui extends Node:
	var owner_mod: Node
var checks:=0
var failures: Array=[]
var changes:=0
func check(value: bool, label_: String) -> void:
	checks+=1
	if not value:failures.append(label_);print("FAIL: "+label_)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	L.configure(JSON.parse_string(FileAccess.get_file_as_string("res://mods/pax_harness/data/lang/ru.json")),JSON.parse_string(FileAccess.get_file_as_string("res://mods/pax_harness/data/lang/en.json")));L.forced_language="ru"
	root.size=Vector2i(800,600)
	var main:=Control.new();root.add_child(main);main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var owner:=Owner.new();root.add_child(owner);owner.game=Game.new();owner.game.main=main
	var store:=Store.new();store.setup(owner);owner.screen_images=store
	var original:=Image.create(320,180,false,Image.FORMAT_RGB8);original.fill(Color.CORNFLOWER_BLUE);original.set_pixel(0,0,Color.RED);original.set_pixel(319,179,Color.GREEN)
	var bytes: PackedByteArray=Capture.encode(original).bytes
	var first: Dictionary=store.retain(bytes,320,180)
	check(not first.is_empty() and not first.observed,"capture is not falsely labelled viewed before model acceptance")
	var resolved: Dictionary=store.resolve(first)
	check(resolved.ok and resolved.texture.get_image().get_pixel(0,0)==Color.RED and resolved.texture.get_image().get_pixel(319,179)==Color.GREEN,"exact sent pixels retained without cropping/re-encoding")
	store.mark_observed(first)
	var second: Dictionary=store.retain(bytes,320,180)
	check(first.id!=second.id and not second.observed,"identical later screenshot has independent delivery status")
	owner.records=JSON.parse_string(JSON.stringify(owner.records))
	var restored:=Store.new();restored.setup(owner)
	check(restored.resolve(first).descriptor.observed and restored.resolve(first).texture.get_width()==320,"previews and delivery status survive store reload")
	check(not restored.resolve({"id":"../../settings"}).ok,"image viewer cannot resolve a path selected by model")
	var ui:=Ui.new();owner.add_child(ui);ui.owner_mod=owner
	var gallery:=Gallery.new();ui.add_child(gallery);gallery.position=Vector2(10,10);gallery.size=Vector2(760,140)
	var other:=Image.create(160,160,false,Image.FORMAT_RGB8);other.fill(Color.GREEN)
	var third: Dictionary=store.retain(Capture.encode(other).bytes,160,160)
	var events: Array=[{"kind":"tool","result":{"screenshot_preview":first}},{"kind":"tool","result":{"screenshot_preview":second}},{"kind":"tool","result":{"screenshot_preview":third}}]
	gallery.update_images(ui,events);await process_frame
	check(gallery.visible and gallery._cards.size()==3 and gallery._toggle.text.contains("3"),"all actual frames have compact transcript thumbnails")
	check(gallery._cards[first.id].texture_normal.get_width()==160 and gallery._cards[first.id].texture_normal.get_height()==90,"thumbnail texture is bounded and preserves aspect")
	gallery._cards[first.id].pressed.emit();await process_frame
	var views: Array=Viewer.open_views();check(views.size()==1,"thumbnail click opens full-window viewer")
	var viewer: Node=views[0]
	check(viewer.image.texture.get_width()==320 and viewer.image.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"full viewer uses exact full-size image without edge cropping")
	var locale:=L.new();root.add_child(locale);locale.setup(func():return [gallery]+Viewer.open_views())
	L.forced_language="en";locale.refresh(true)
	check(gallery._toggle.text=="Screenshots · 3" and viewer.image.get_parent().get_child(0).get_child(0).text=="Game screenshot · 320 × 180" and gallery._cards[first.id].tooltip_text.contains("Click to expand"),"viewer, thumbnail count and tooltip switch to English together")
	L.forced_language="ru";locale.refresh(true)
	check(gallery._toggle.text=="Снимки экрана · 3" and viewer.image.get_parent().get_child(0).get_child(0).text=="Игровой снимок · 320 × 180" and not gallery._cards[first.id].tooltip_text.contains("Click"),"switching back restores all Russian screenshot labels")
	L.forced_language="de";locale.refresh(true)
	check(gallery._toggle.text=="Screenshots · 3","unsupported game language uses English screenshot UI")
	L.forced_language="ru";locale.refresh(true);locale.queue_free()
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;viewer._input(escape);await process_frame
	check(Viewer.open_views().is_empty(),"Esc closes expanded image")
	owner.chat_ui=Chat.new();owner.add_child(owner.chat_ui);owner.chat_ui.native=PanelContainer.new();main.add_child(owner.chat_ui.native)
	owner.chat_ui.visibility_changed.connect(func():changes+=1)
	var session:=Session.new();owner.add_child(session);session.setup(owner);owner._screen_session=session
	var capture:=Capture.new();owner.add_child(capture);capture.setup(owner)
	var handles: Array=[]
	for i: int in 2:
		var pending: Dictionary=capture.execute(owner.game,"ui.screenshot",{},{})
		if not pending.pending.finished:await pending.pending.completed
		check(pending.pending.result.ok and not owner.chat_ui.visible and session.active,"chat stays hidden throughout screen session")
		handles.append(pending.pending.result.result.image_attachment)
		check(pending.pending.result.result.has("screenshot_preview"),"actual capture receipt links a saved preview")
		pending.pending.queue_free();await process_frame
	check(changes==1,"two captures do not repeatedly hide/show chat")
	var controls: Control=session.chrome.get_node("Controls/ScreenSessionControls")
	check(session.owns_point(root,controls.get_global_rect().get_center()),"agent cannot click its own stop/chat controls")
	capture.mark_delivered([handles[-1]],owner.vision_context())
	var last: Dictionary=capture._images[handles[-1].id].preview
	check(store.resolve(last).descriptor.observed,"model delivery marks saved transcript image as viewed")
	capture.clear()
	check(store.resolve(last).ok,"expiring input grants do not erase transcript previews")
	session.end();check(owner.chat_ui.visible and changes==2,"chat restores once at end of whole session")
	check(session.begin(),"next screen session starts")
	session.end(false);check(not owner.chat_ui.visible,"player takeover does not force chat back over gameplay")
	owner.chat_ui.open();session.begin();session._return_to_chat()
	check(owner.busy and session.paused and owner.chat_ui.visible,"return pauses screen work without cancelling the answer")
	check(capture.execute(owner.game,"ui.screenshot",{},{}).code=="ui.screen_view_paused","paused session cannot start flashing again on next screenshot")
	session.resume_for_player_task();check(session.begin(),"new player task can resume screen view")
	var interrupted: Dictionary=capture.execute(owner.game,"ui.screenshot",{},{})
	session._return_to_chat()
	if not interrupted.pending.finished:await interrupted.pending.completed
	check(not interrupted.pending.result.ok and owner.chat_ui.visible,"return during pending capture cannot capture/reopen chat")
	interrupted.pending.queue_free()
	session.resume_for_player_task();session.begin()
	session._stop();check(not owner.busy and not session.active and owner.chat_ui.visible,"stop cancels answer and restores chat")
	owner.queue_free();main.queue_free();await process_frame
	print("SCREEN_PRESENTATION_TESTS "+("PASS" if failures.is_empty() else str(failures))+"; "+str(checks)+" checks")
	quit(0 if failures.is_empty() else 1)
