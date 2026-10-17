extends Node
## Native configured image generator; durable artifacts use only this mod's safe data API.
const Panels = preload("res://mods/pax_harness/ui_panels.gd")
const Data = preload("res://mods/pax_harness/runtime_tools/tool_data.gd")
const Png = preload("res://mods/pax_harness/ui_png.gd")
const Artifact = preload("res://mods/pax_harness/image_artifact.gd")
const Job = preload("res://mods/pax_harness/image_generation_job.gd")
const Workflow = preload("res://mods/pax_harness/image_workflow.gd")
const MAX_IMAGES := 128
const MAX_TEXTURES := 8
const MAX_BYTES := 4*1024*1024
const MAX_DIMENSION := 1600
const MANIFEST := "generated_images"
var owner_mod: Node
var _artifacts: Dictionary = {}
var _textures: Dictionary = {}
var _jobs: Array = []

func comfy_workflow() -> Dictionary:
	if not is_instance_valid(owner_mod) or not owner_mod.has_method("get_setting"): return {}
	var saved: Variant = owner_mod.get_setting("image_workflow",{})
	if not saved is Dictionary or not saved.get("graph") is Dictionary: return {}
	var checked: Dictionary = Workflow.validate(saved.graph,str(saved.get("prompt_node","")),str(saved.get("prompt_input","text")),saved.get("enabled",false) == true)
	return checked.config if checked.ok else {}

func set_comfy_workflow(graph: Dictionary, prompt_node: String = "", prompt_input: String = "text", enabled: bool = true) -> Dictionary:
	var checked: Dictionary = Workflow.validate(graph,prompt_node,prompt_input,enabled)
	if not checked.ok: return failure(checked.code,checked.message)
	if not is_instance_valid(owner_mod) or not owner_mod.has_method("set_setting"): return failure("images.settings_unavailable","Недоступно сохранение workflow.")
	owner_mod.set_setting("image_workflow",checked.config)
	return {"ok":true,"result":{"enabled":enabled,"nodes":graph.size(),"prompt_node":checked.config.prompt_node,"prompt_input":checked.config.prompt_input}}

func reset_comfy_workflow() -> void:
	if is_instance_valid(owner_mod) and owner_mod.has_method("set_setting"): owner_mod.set_setting("image_workflow",{})

func settings_panel() -> Control:
	var panel: Control = preload("res://mods/pax_harness/image_generation_settings.gd").new()
	panel.setup(self,owner_mod)
	return panel

func setup(owner: Node) -> void:
	owner_mod = owner; name = "HarnessImageGeneration"; process_mode = Node.PROCESS_MODE_ALWAYS
	if owner.has_method("load_data"):
		var saved: Variant = owner.load_data(MANIFEST,{})
		if saved is Dictionary and saved.get("items") is Array:
			for value: Variant in saved.items.slice(0,MAX_IMAGES):
				var descriptor: Dictionary = validate_descriptor(value)
				if not descriptor.is_empty(): _artifacts[descriptor.id] = descriptor

func current(game: RefCounted) -> bool:
	if not is_instance_valid(owner_mod) or not is_instance_valid(game): return false
	return bool(owner_mod.call("_game_available",game)) if owner_mod.has_method("_game_available") else Panels.main_node(game) != null

func native_artist(game: RefCounted) -> Node:
	var main: Node = Panels.main_node(game)
	var candidate: Variant = Data.property(main,"artist")
	return candidate if candidate is Node and is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.has_method("_make") else null

func native_configuration(artist: Node) -> Dictionary:
	if not is_instance_valid(artist): return {}
	var script: Variant = artist.get_script()
	if not script is Script or not script.has_method("setting"): return {}
	var manual: Variant = Data.property(artist,"manual_settings")
	var settings: Variant = script.call("setting",manual.duplicate(true) if manual is Dictionary else {})
	return settings.duplicate(true) if settings is Dictionary else {}

func status(game: RefCounted) -> Dictionary:
	if not current(game): return failure("images.world_unavailable","Генератор доступен после загрузки партии.")
	var artist: Node = native_artist(game)
	if artist == null: return failure("images.native_generator_unavailable","Игра не предоставила доступный генератор изображений.")
	var settings: Dictionary = native_configuration(artist)
	if settings.is_empty(): return {"ok":true,"result":{"configured":false,"code":"images.not_configured","message":"Настройте генератор изображений в Настройки → Нейросеть.","retained_images":_artifacts.size(),"image_limit":MAX_IMAGES}}
	return {"ok":true,"result":{"configured":true,"service":str(settings.get("service","")).left(80),"model":str(settings.get("model","")).left(160),"custom_workflow":settings.get("service") == "comfyui" and comfy_workflow().get("enabled",false),"retained_images":_artifacts.size(),"image_limit":MAX_IMAGES,"source":"game_configured_generator"}}

func execute(game: RefCounted, tool: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	if tool == "images.status": return status(game)
	if tool != "images.generate": return failure("images.unknown_tool","Неизвестный инструмент изображений.")
	if scope.get("analysis_child",false): return failure("images.analysis_unavailable","Генерация недоступна в дочернем анализе.")
	if args.size() != 1 or not args.get("prompt") is String or str(args.prompt).strip_edges().is_empty() or str(args.prompt).length() > 4000: return failure("images.invalid_prompt","Нужно описание изображения длиной от 1 до 4000 символов.")
	var available: Dictionary = status(game)
	if not available.ok: return available
	if not available.result.configured: return failure("images.not_configured",available.result.message)
	if _artifacts.size() >= MAX_IMAGES: return failure("images.artifact_limit","Достигнут предел сохранённых изображений. Существующие картинки чатов сохранены.")
	_jobs = _jobs.filter(func(job): return is_instance_valid(job) and not job.finished)
	if not _jobs.is_empty(): return failure("images.busy","Предыдущее изображение ещё создаётся.")
	var job: Node = Job.new(); add_child(job); _jobs.append(job)
	job.setup(self,game,str(args.prompt),scope)
	return {"pending":job}

static func failure(code: String, message: String) -> Dictionary:
	return {"ok":false,"code":code,"result":{"message":message}}

static func validate_descriptor(value: Variant) -> Dictionary:
	return Artifact.validate(value)

static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes); return context.finish().hex_encode()

func retain(image: Image, prompt: String) -> Dictionary:
	if image == null or image.is_empty(): return failure("images.empty_result","Генератор вернул пустое изображение.")
	if _artifacts.size() >= MAX_IMAGES: return failure("images.artifact_limit","Достигнут предел сохранённых изображений.")
	if not is_instance_valid(owner_mod) or not owner_mod.has_method("save_data") or not owner_mod.has_method("load_data"): return failure("images.persistence_unavailable","Недоступно сохранение изображений мода.")
	var copy: Image = image.duplicate(); copy.convert(Image.FORMAT_RGB8)
	var maximum: int = maxi(copy.get_width(),copy.get_height())
	if maximum > MAX_DIMENSION:
		var factor: float = float(MAX_DIMENSION)/maximum
		copy.resize(maxi(1,roundi(copy.get_width()*factor)),maxi(1,roundi(copy.get_height()*factor)),Image.INTERPOLATE_LANCZOS)
	var bytes: PackedByteArray = Png.encode(copy)
	while bytes.size() > MAX_BYTES and maxi(copy.get_width(),copy.get_height()) > 512:
		copy.resize(maxi(1,roundi(copy.get_width()*0.8)),maxi(1,roundi(copy.get_height()*0.8)),Image.INTERPOLATE_LANCZOS); bytes = Png.encode(copy)
	if bytes.size() < 16 or bytes.size() > MAX_BYTES: return failure("images.result_size_limit","Изображение превышает допустимый размер сохранения.")
	var id: String = Crypto.new().generate_random_bytes(16).hex_encode()
	var descriptor := {"id":id,"mime_type":"image/png","width":copy.get_width(),"height":copy.get_height(),"byte_size":bytes.size(),"sha256":digest(bytes),"title":prompt.replace("\n"," ").left(160),"source":"game_configured_generator","persistent":true}
	owner_mod.save_data("generated_image_"+id,{"version":1,"descriptor":descriptor,"png_base64":Marshalls.raw_to_base64(bytes)})
	var persisted: Variant = owner_mod.load_data("generated_image_"+id,{})
	if not persisted is Dictionary or validate_descriptor(persisted.get("descriptor")) != descriptor or not persisted.get("png_base64") is String or persisted.png_base64 != Marshalls.raw_to_base64(bytes): return failure("images.persist_failed","Не удалось сохранить изображение. Повторная генерация автоматически не запускается.")
	var items: Array = _artifacts.values().duplicate(true); items.append(descriptor)
	owner_mod.save_data(MANIFEST,{"version":1,"items":items})
	var manifest: Variant = owner_mod.load_data(MANIFEST,{})
	var persisted_items: Array = []
	if manifest is Dictionary and manifest.get("items") is Array:
		for item: Variant in manifest.items: persisted_items.append(validate_descriptor(item))
	if persisted_items != items: return failure("images.persist_failed","Не удалось сохранить запись изображения.")
	_artifacts[id] = descriptor; _cache_texture(id,ImageTexture.create_from_image(copy))
	return {"ok":true,"result":{"generated_image":descriptor.duplicate(true),"message":"Изображение создано и сохранено.","basis":"generated"}}

func resolve_image(value: Variant) -> Dictionary:
	var id: String = str(value.get("id","")) if value is Dictionary else str(value) if value is String else ""
	if not _artifacts.has(id): return failure("images.artifact_not_found","Сохранённое изображение не найдено.")
	var descriptor: Dictionary = _artifacts[id]
	if not _textures.has(id):
		var record: Variant = owner_mod.load_data("generated_image_"+id,{})
		if not record is Dictionary or validate_descriptor(record.get("descriptor")) != descriptor or not record.get("png_base64") is String or record.png_base64.length() > ceili(MAX_BYTES*4.0/3.0)+4: return failure("images.artifact_invalid","Запись изображения повреждена.")
		var bytes: PackedByteArray = Marshalls.base64_to_raw(record.png_base64)
		if bytes.size() != descriptor.byte_size or digest(bytes) != descriptor.sha256: return failure("images.artifact_invalid","Данные изображения повреждены.")
		if bytes.size() < 33 or bytes.slice(0,8) != PackedByteArray([137,80,78,71,13,10,26,10]): return failure("images.artifact_invalid","Неверный формат изображения.")
		var width: int = (int(bytes[16])<<24)|(int(bytes[17])<<16)|(int(bytes[18])<<8)|int(bytes[19])
		var height: int = (int(bytes[20])<<24)|(int(bytes[21])<<16)|(int(bytes[22])<<8)|int(bytes[23])
		if width != descriptor.width or height != descriptor.height: return failure("images.artifact_invalid","Размер изображения не совпадает с сохранённой записью.")
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK or image.get_width() != descriptor.width or image.get_height() != descriptor.height: return failure("images.artifact_invalid","Изображение не удалось открыть.")
		_cache_texture(id,ImageTexture.create_from_image(image))
	return {"ok":true,"texture":_textures[id],"descriptor":descriptor.duplicate(true)}

func _cache_texture(id: String, texture: Texture2D) -> void:
	if not _textures.has(id) and _textures.size() >= MAX_TEXTURES: _textures.erase(_textures.keys()[0])
	_textures[id] = texture

func clear_jobs() -> void:
	for job: Variant in _jobs:
		if is_instance_valid(job): job.cancel()
	_jobs.clear()

func _exit_tree() -> void: clear_jobs()
