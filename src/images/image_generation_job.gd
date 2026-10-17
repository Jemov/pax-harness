extends Node
signal completed
const Workflow = preload("res://mods/pax_harness/src/images/image_workflow.gd")
var service: Node
var game: RefCounted
var prompt := ""
var scope: Dictionary
var result: Dictionary = {}
var finished := false
var _generator: Node
var _deadline := 0

func setup(owner: Node, facade: RefCounted, text: String, context: Dictionary) -> void:
	service = owner; game = facade; prompt = text; scope = context.duplicate()
	process_mode = Node.PROCESS_MODE_ALWAYS; _deadline = Time.get_ticks_msec()+900000
	_run.call_deferred()

func alive() -> bool:
	if finished or not is_instance_valid(service) or not service.current(game): return false
	var current: Variant = scope.get("is_current")
	return bool(current.call()) if current is Callable and current.is_valid() else true

func _run() -> void:
	if not alive(): cancel(); return
	var artist: Node = service.native_artist(game)
	var settings: Dictionary = service.native_configuration(artist)
	if artist == null or settings.is_empty(): _finish(service.failure("images.not_configured","Настройте генератор изображений в Настройки → Нейросеть.")); return
	var script: Variant = artist.get_script()
	var service_id: String = str(settings.get("service",""))
	_generator = script.new(); add_child(_generator)
	# This is the same native generator implementation, with its actual configured
	# service passed opaquely. No keys/routes/models are selected by the tool.
	var image: Variant
	var diagnostic: Dictionary = {}
	var workflow: Dictionary = service.comfy_workflow()
	if service_id == "comfyui" and workflow.get("enabled",false):
		var generated: Dictionary = await Workflow.generate(_generator,settings,workflow,prompt)
		image = generated.get("image")
		diagnostic = generated.get("diagnostic",{})
		if not generated.get("ok",false): _generator.last_error = generated.get("code","workflow_failed")
	else: image = await _generator._make(settings,prompt,false)
	settings.clear()
	if not alive(): cancel(); return
	if not image is Image or image.is_empty():
		var native_error: String = str(_generator.last_error)
		var safe: String = native_error if native_error in ["no_service","no_link","key","money","censorship","model","catalog","workflow_rejected","workflow_failed","workflow_download_failed","workflow_timeout","workflow_empty_result"] else "generation_failed"
		var failed: Dictionary = service.failure("images."+safe,"Генератор изображений вернул ошибку: "+safe+".")
		if not diagnostic.is_empty(): failed.result["diagnostic"] = diagnostic
		_finish(failed); return
	if script.has_method("_account"): script.call("_account",service_id)
	var retained: Dictionary = service.retain(image,prompt)
	_finish(retained)

func _process(_delta: float) -> void:
	if finished: return
	if not alive(): cancel()
	elif Time.get_ticks_msec() >= _deadline: _finish(service.failure("images.timeout","Истекло время ожидания изображения; повтор автоматически не отправлен."))

func cancel() -> void:
	if not finished: _finish({"ok":false,"code":"cancelled","result":{"message":"Генерация изображения остановлена."}})

func _finish(value: Dictionary) -> void:
	if finished: return
	finished = true; result = value; set_process(false)
	if is_instance_valid(_generator): _generator.queue_free()
	completed.emit()
