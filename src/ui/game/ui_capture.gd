extends Node
## Expiring RAM-only model grants; exact preview pixels use separate player storage.
const Png = preload("res://mods/pax_harness/src/images/ui_png.gd")
const Panels = preload("res://mods/pax_harness/src/ui/game/ui_panels.gd")
const Job = preload("res://mods/pax_harness/src/ui/game/ui_capture_job.gd")
const MAX_BYTES := 2*1024*1024
const MAX_IMAGES := 4
const TTL_MSEC := 120000
const MAX_DIMENSION := 1600
var owner_mod: Node
var _images: Dictionary = {}
var _jobs: Array = []
var _clock: Callable = Time.get_ticks_msec
signal player_input
var input_epoch := 0
var _input_window: WeakRef
func watch_viewport(viewport: Viewport) -> void:
	if not viewport is Window: return
	if _input_window!=null and _input_window.get_ref()==viewport: return
	_unwatch_window()
	_input_window=weakref(viewport)
	# Window receives native input before Controls can consume it.
	viewport.window_input.connect(_input)
func _unwatch_window() -> void:
	var window: Variant=_input_window.get_ref() if _input_window!=null else null
	if is_instance_valid(window) and window.is_connected("window_input",_input): window.disconnect("window_input",_input)
	_input_window=null
func _input(event: InputEvent) -> void:
	if (event is InputEventMouse or event is InputEventKey) and event.device!=10071 and not event.get_meta("pax_harness_virtual",false):
		invalidate_input_frames();player_input.emit()
func invalidate_input_frames() -> void: input_epoch+=1
func mark_delivered(handles: Array, selected: Dictionary) -> void:
	for handle: Dictionary in handles:
		var id: String=str(handle.get("id",""))
		if handle.get("source")=="game_viewport" and _images.has(id) and resolve_image(handle,selected).get("ok",false): _images[id]["delivered"]=true
		if _images.has(id) and _images[id].get("delivered",false) and "screen_images" in owner_mod and owner_mod.screen_images!=null:
			owner_mod.screen_images.mark_observed(_images[id].get("preview",{}))
	if "chat_store" in owner_mod and owner_mod.chat_store!=null: owner_mod.chat_store.changed.emit()
func input_frame(id: String, game: RefCounted, selected: Dictionary, consume: bool) -> Dictionary:
	var resolved: Dictionary=resolve_image(id,selected)
	if not resolved.get("ok",false): return resolved
	var entry: Dictionary=_images[id]
	if not entry.get("delivered",false): return {"ok":false,"code":"ui.image_not_observed","result":{"instruction":"Receive and inspect ui.screenshot as an image before virtual input. Text-only or rejected image requests cannot authorize clicks."}}
	if entry.get("consumed",false) or entry.epoch!=input_epoch: return {"ok":false,"code":"ui.image_view_changed"}
	var main: Node=Panels.main_node(game)
	var viewport: Variant=entry.viewport.get_ref() if entry.viewport!=null else null
	if main==null or not is_instance_valid(viewport) or viewport!=main.get_viewport() or viewport.get_visible_rect().size!=entry.size: return {"ok":false,"code":"ui.image_view_changed"}
	if consume:
		for old: Dictionary in _images.values(): old["consumed"]=true
	return {"ok":true,"viewport":viewport,"size":entry.size,"width":entry.descriptor.width,"height":entry.descriptor.height,"epoch":input_epoch}

func setup(owner: Node) -> void:
	owner_mod = owner; name = "HarnessUiCapture"; process_mode = Node.PROCESS_MODE_ALWAYS

func context() -> Dictionary:
	if not is_instance_valid(owner_mod) or not owner_mod.has_method("vision_context"): return {"enabled":false}
	var value: Variant = owner_mod.call("vision_context")
	return value if value is Dictionary else {"enabled":false}

func current(game: RefCounted, expected: Dictionary) -> bool:
	if not is_instance_valid(owner_mod) or not is_instance_valid(game): return false
	if owner_mod.has_method("_game_available") and not owner_mod.call("_game_available",game): return false
	var now: Dictionary = context()
	return bool(now.get("enabled",false)) and identity(now)==identity(expected) and identity(now)!=""

static func identity(value: Dictionary) -> String:
	if not value.get("base") is String or not value.get("model") is String or not value.get("provider_id") is int or not value.get("world_generation") is int: return ""
	if value.base=="" or value.model=="" or value.provider_id<=0: return ""
	return JSON.stringify([value.base,value.model,value.provider_id,value.world_generation])

func execute(game: RefCounted, tool: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	if tool=="ui.panels": return Panels.list_panels(game)
	if tool=="ui.open": return Panels.open_panel(game,str(args.get("panel","")))
	if tool!="ui.screenshot": return {"ok":false,"code":"ui.unknown_tool"}
	if scope.get("analysis_child",false): return {"ok":false,"code":"ui.screenshot_unavailable_in_analysis"}
	var selected: Dictionary = context()
	if not bool(selected.get("enabled",false)): return {"ok":false,"code":"ui.vision_disabled"}
	if not current(game,selected): return {"ok":false,"code":"ui.world_changed"}
	var session: Variant=owner_mod.get("_screen_session") if "_screen_session" in owner_mod else null
	if is_instance_valid(session) and session.paused:return {"ok":false,"code":"ui.screen_view_paused","result":{"instruction":"The player returned to chat and paused screen interaction. Do not reopen it. Finish in text and wait for a new player message."}}
	_jobs = _jobs.filter(func(job):return is_instance_valid(job) and not job.finished)
	if not _jobs.is_empty(): return {"ok":false,"code":"ui.capture_busy"}
	var job: Node = Job.new(); add_child(job); _jobs.append(job)
	job.setup(self,game,selected,scope)
	return {"pending":job}

func _prune() -> void:
	var now: int = _clock.call()
	for id: String in _images.keys():
		if now>=int(_images[id].expires): _images.erase(id)

func retain(image: Image, game: RefCounted, selected: Dictionary) -> Dictionary:
	if not current(game,selected): return {"ok":false,"code":"ui.image_identity_changed"}
	var encoded: Dictionary = encode(image)
	if not encoded.get("ok",false): return encoded
	_prune()
	while _images.size()>=MAX_IMAGES: _images.erase(_images.keys()[0])
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var descriptor := {"id":id,"mime_type":encoded.mime_type,"width":encoded.width,"height":encoded.height,"byte_size":encoded.bytes.size(),"source":"game_viewport"}
	var main: Node=Panels.main_node(game)
	var viewport: Viewport=main.get_viewport() if main!=null and main.is_inside_tree() else null
	if viewport!=null: watch_viewport(viewport)
	_images[id] = {"delivered":false,"consumed":false,"epoch":input_epoch,"viewport":weakref(viewport) if viewport!=null else null,"size":viewport.get_visible_rect().size if viewport!=null else Vector2.ZERO,"bytes":encoded.bytes,"descriptor":descriptor,"identity":identity(selected),"game":weakref(game),"expires":int(_clock.call())+TTL_MSEC}
	var preview: Dictionary={}
	if "screen_images" in owner_mod and owner_mod.screen_images!=null: preview=owner_mod.screen_images.retain(encoded.bytes,encoded.width,encoded.height)
	_images[id]["preview"]=preview
	var observation: Dictionary={"image_attachment":descriptor,"capture_scope":"game_viewport_only","harness_chat_hidden":true,"expires_in_seconds":120,"persistent":false}
	if not preview.is_empty():observation["screenshot_preview"]=preview
	return {"ok":true,"result":observation}

static func encode(image: Image) -> Dictionary:
	if image==null or image.is_empty(): return {"ok":false,"code":"ui.empty_framebuffer"}
	var bounded: Image = image.duplicate()
	bounded.convert(Image.FORMAT_RGB8)
	var maximum: int = maxi(bounded.get_width(),bounded.get_height())
	if maximum>MAX_DIMENSION:
		var factor: float = float(MAX_DIMENSION)/maximum
		bounded.resize(maxi(1,roundi(bounded.get_width()*factor)),maxi(1,roundi(bounded.get_height()*factor)),Image.INTERPOLATE_LANCZOS)
	var bytes: PackedByteArray = Png.encode(bounded)
	# A dense/high-entropy frame may need fewer pixels to fit the wire limit.
	while bytes.size()>MAX_BYTES and maxi(bounded.get_width(),bounded.get_height())>640:
		bounded.resize(maxi(1,roundi(bounded.get_width()*0.8)),maxi(1,roundi(bounded.get_height()*0.8)),Image.INTERPOLATE_LANCZOS)
		bytes=Png.encode(bounded)
	if bytes.is_empty() or bytes.size()>MAX_BYTES: return {"ok":false,"code":"ui.image_size_limit"}
	return {"ok":true,"bytes":bytes,"mime_type":"image/png","width":bounded.get_width(),"height":bounded.get_height()}

func resolve_image(handle: Variant, selected: Dictionary) -> Dictionary:
	if not bool(selected.get("enabled",false)): return {"ok":false,"code":"ui.vision_disabled"}
	var id: String = str(handle.get("id","")) if handle is Dictionary else str(handle) if handle is String else ""
	if not _images.has(id): return {"ok":false,"code":"ui.image_not_found"}
	var entry: Dictionary = _images[id]
	if int(_clock.call())>=int(entry.expires): _images.erase(id); return {"ok":false,"code":"ui.image_expired"}
	if identity(selected)=="" or entry.identity!=identity(selected): return {"ok":false,"code":"ui.image_identity_changed"}
	var live: Dictionary = context()
	if not bool(live.get("enabled",false)): return {"ok":false,"code":"ui.vision_disabled"}
	if identity(live)!=identity(selected): return {"ok":false,"code":"ui.image_identity_changed"}
	var game: Variant = entry.game.get_ref()
	if not game is RefCounted or not current(game,selected): return {"ok":false,"code":"ui.world_changed"}
	return {"ok":true,"bytes":entry.bytes.duplicate(),"mime_type":entry.descriptor.mime_type,"width":entry.descriptor.width,"height":entry.descriptor.height}

func clear() -> void:
	_unwatch_window()
	for job: Variant in _jobs:
		if is_instance_valid(job):
			job.cancel()
			if not job.is_queued_for_deletion(): job.queue_free()
	_jobs.clear(); _images.clear()

func _exit_tree() -> void: clear()
