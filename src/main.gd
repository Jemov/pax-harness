extends PaxMod
## Independent chat/runtime owner. The laboratory is an optional prompt compiler.
const StockCompat = preload("res://mods/pax_harness/src/core/stock_compat.gd")
const RuntimeTools = preload("res://mods/pax_harness/src/runtime/tools/registry.gd")
const UniversalRuntime = preload("res://mods/pax_harness/src/runtime/universal_runtime.gd")
const ProviderRouter = preload("res://mods/pax_harness/src/transport/provider_router.gd")
const Retained = preload("res://mods/pax_harness/src/core/retained_current.gd")
const Migration = preload("res://mods/pax_harness/src/core/state_migration.gd")
const Workspace = preload("res://mods/pax_harness/src/runtime/task_workspace.gd")
const ResourceHistory = preload("res://mods/pax_harness/src/data/resource_history.gd")
const ProviderLimits = preload("res://mods/pax_harness/src/transport/provider_limits.gd")
const Vision = preload("res://mods/pax_harness/src/transport/vision_payload.gd")
var provider_limits: RefCounted = ProviderLimits.new()
var provider_catalog: Node
var analytics_sources: RefCounted = preload("res://mods/pax_harness/src/data/analytics_extensions.gd").new()

var map_sources: RefCounted = preload("res://mods/pax_harness/src/visualization/maps/chart_map_sources.gd").new()
func register_map_source(id: String, title: String, body: String, reader: Callable) -> bool:
	return map_sources.register_source(id,title,body,reader)
func map_provider_tool(name: String, arguments: Dictionary) -> Dictionary:
	if name == "charts.map_sources": return map_sources.describe()
	if str(arguments.get("provider","")) != "": return map_sources.execute(_game,arguments)
	return preload("res://mods/pax_harness/src/visualization/maps/chart_map_data.gd").execute(_game,arguments)

func register_analytics_source(id: String, title: String, description: String, schema: Dictionary, reader: Callable) -> bool:
	if preload("res://mods/pax_harness/src/data/mod_analytics.gd").DEFINITIONS.has(id): return false
	return analytics_sources.register_source(id,title,description,schema,reader)

func analytics_tool(name: String, args: Dictionary) -> Dictionary:
	var adapters: Script = preload("res://mods/pax_harness/src/data/mod_analytics.gd")
	var id: String = str(args.get("source",""))
	if id != "" and adapters.DEFINITIONS.has(id): return adapters.describe(args,Pax) if name == "analytics.sources" else adapters.query(_game,args,Pax)
	if name == "analytics.query": return analytics_sources.query(_game,args)
	var result: Dictionary = analytics_sources.describe(args)
	if id == "": result.result.sources.append_array(adapters.describe({},Pax).result.sources)
	return result

var resource_history: RefCounted
var _game: RefCounted
var _source_generation: int = 0
var _ui_generation: int = 0
var _runtime: RefCounted
var _router: RefCounted
var chat_compactor: RefCounted
var chat_tools: RefCounted
var chat_store: RefCounted
var chat_stream: Node
var chat_ui: Node
var _ui_capture: Node
var _image_generation: Node
var order_archive: RefCounted
var _chat_pending: Dictionary = {}
var _chat_native_watch: Dictionary = {}
var universal_results: Dictionary = {}
var composition_error: Dictionary = {}
var _loaded_state: Dictionary = {}
var _migration_origin: String = ""
var _archive_poll: float = 0.0
var _transport_provider: Node
var _model_defaults: Dictionary = {}
var _lab_used: bool = false

func _mod_loaded() -> void:
	_model_defaults = load_json("config/model_defaults.json",{})
	chat_compactor = load_resource("src/chat/chat_compact.gd").new()
	chat_compactor.setup(self)
	chat_tools = load_resource("src/chat/chat_tools.gd").new()
	chat_tools.setup(self)
	_router = ProviderRouter.new()
	_router.setup(self)
	_runtime = UniversalRuntime.new()
	_ui_capture = load_resource("src/ui/game/ui_capture.gd").new()
	add_child(_ui_capture)
	_ui_capture.setup(self)
	_image_generation = load_resource("src/images/image_generation.gd").new()
	add_child(_image_generation)
	_image_generation.setup(self)
	chat_stream = load_resource("src/transport/chat_stream.gd").new()
	add_child(chat_stream)
	chat_stream.setup(self)
	provider_catalog = load_resource("src/transport/provider_catalog.gd").new()
	add_child(provider_catalog)
	provider_catalog.setup(self)
	provider_catalog.completed.connect(_catalog_completed)
	hook("ai_request",_observe_request)
	hook("ai_answer",_observe_chat_usage)
	Pax.loaded.connect(_mods_loaded)
	Pax.world_closed.connect(_world_closed)
	Pax.register_command("pax_harness",_command,"Pax Harness status; pax_harness open opens chats")
	if Pax.game != null: _world_ready.call_deferred(Pax.game)

func _game_available(candidate: RefCounted = null) -> bool:
	if candidate == null: candidate = _game
	return candidate != null and candidate == Pax.game and StockCompat.active(candidate)

func _restore_state(state: Dictionary) -> void:
	resource_history = ResourceHistory.new()
	resource_history.restore(state.get("resource_history",{}))
	chat_store = load_resource("src/chat/chat_store.gd").new()
	chat_store.restore(state.get("chat_sessions",{}))
	order_archive = load_resource("src/data/order_archive.gd").new()
	order_archive.restore(state.get("order_archive",{}))
	_migration_origin = str(state.get("imported_from",""))

func _game_loaded(game: PaxGame, state: Dictionary) -> void:
	_reset()
	_loaded_state = state.duplicate(true)
	_restore_state(state)
	_world_ready(game)

func _mods_loaded(game: PaxGame, states: Dictionary) -> void:
	if _loaded_state.has("chat_sessions"): return
	var migrated: Dictionary = Migration.choose(_loaded_state,states)
	if not migrated.has("chat_sessions"): return
	_restore_state(migrated)
	_loaded_state = migrated
	if _game_available(game): order_archive.setup(game)

func _save_state(_facade: PaxGame) -> Dictionary:
	if chat_store == null: return {}
	if resource_history != null and _game_available(): resource_history.capture(_game,true)
	return {"version":1,"chat_sessions":chat_store.snapshot(),"order_archive":order_archive.snapshot() if order_archive != null else {},"resource_history":resource_history.snapshot() if resource_history != null else {},"imported_from":_migration_origin}

func _world_ready(game: PaxGame) -> void:
	if not _game_available(game): return
	_game = game
	if chat_store == null: _restore_state({})
	order_archive.setup(game)
	resource_history.capture(game,true)
	_ui_generation += 1
	_attach_chat.call_deferred(game,_ui_generation)
	_attach_transport.call_deferred()

func _reset() -> void:
	if is_instance_valid(_ui_capture): _ui_capture.clear()
	if is_instance_valid(_image_generation): _image_generation.clear_jobs()
	if is_instance_valid(chat_stream): chat_stream.cancel_all()
	if is_instance_valid(provider_catalog): provider_catalog.cancel_all()
	if chat_compactor != null: chat_compactor.invalidate()
	_source_generation += 1
	_ui_generation += 1
	if _router != null: _router.invalidate()
	if _runtime != null: _runtime.invalidate()
	_chat_pending.clear()
	_chat_native_watch.clear()
	universal_results.clear()
	composition_error.clear()
	if is_instance_valid(chat_ui): chat_ui.detach()
	chat_ui = null
	_detach_transport()

func _world_closed() -> void:
	_reset()
	_game = null
	chat_store = null
	order_archive = null
	resource_history = null
	_loaded_state.clear()

func _days_passed(game: PaxGame, _from_day: int, _days: int) -> void:
	# Capture settled stocks after the simulation step, not an intermediate poll.
	if _game_available(game) and resource_history != null: resource_history.capture(game,true)

func _mod_unloaded() -> void:
	_world_closed()
	if is_instance_valid(_ui_capture): _ui_capture.queue_free()
	_ui_capture = null
	if is_instance_valid(_image_generation): _image_generation.queue_free()
	_image_generation = null
	if Pax.loaded.is_connected(_mods_loaded): Pax.loaded.disconnect(_mods_loaded)
	if Pax.world_closed.is_connected(_world_closed): Pax.world_closed.disconnect(_world_closed)

func _process(delta: float) -> void:
	_archive_poll += delta
	if _archive_poll < 1 or not _game_available(): return
	_archive_poll = 0
	_attach_transport()
	if order_archive != null: order_archive.scan()
	_chat_poll_native()

func failed_orders(arguments: Dictionary = {}) -> Dictionary:
	return order_archive.query(arguments) if order_archive != null else {"error":"archive_unavailable"}

func resource_history_query(arguments: Dictionary) -> Dictionary:
	if arguments.get("scope","country") == "colony" and str(arguments.get("body","")).is_empty(): return {"ok":false,"code":"tools.body_required_for_colony_history"}
	return {"ok":true,"result":resource_history.query(_game,arguments)} if resource_history != null else {"ok":false,"code":"tools.history_source_unavailable"}

func _lab() -> Node:
	var value: Node = Pax.get_mod("prompt_lab_local")
	return value if value != null and value.has_method("harness_prepare_assistant") else null

func _tuning() -> Node:
	var value: Node = Pax.get_mod("ai_tuning")
	return value if value != null and value.has_method("apply_query") else null

func vision_context(provider: Node = null) -> Dictionary:
	var context := {"enabled":false,"base":"","model":"","provider_id":0,"world_generation":_source_generation}
	if not _game_available(): return context
	var current: Node = StockCompat.provider(_game)
	if not is_instance_valid(current) or (provider != null and provider != current): return context
	if current.has_method("_reload_if_changed"): current.call("_reload_if_changed")
	context.base = str(current.get("base_url")).strip_edges().trim_suffix("/")
	context.model = str(current.get("model")).strip_edges()
	context.provider_id = current.get_instance_id()
	if context.base == "" or context.model == "": return context
	var tuning: Node = _tuning()
	var profile: Dictionary = {}
	if tuning != null and tuning.has_method("profile_for"):
		profile = tuning.profile_for(context.base,context.model)
	elif current.has_method("generation_profile"):
		var native_profile: Variant = current.call("generation_profile")
		if native_profile is Dictionary: profile = native_profile
	context.enabled = profile.get("enabled") is bool and profile.enabled and profile.get("vision_input") is bool and profile.vision_input
	return context

func vision_input_enabled(provider: Node = null) -> bool:
	return bool(vision_context(provider).enabled)

func resolve_image_attachment(handle: Dictionary, provider: Node) -> Dictionary:
	return _ui_capture.resolve_image(handle,vision_context(provider)) if is_instance_valid(_ui_capture) else {"ok":false,"code":"ui.screenshot_unavailable","errors":["Screenshot expired or no longer available."]}

func resolve_image(handle: Dictionary) -> Dictionary:
	return resolve_image_attachment(handle,StockCompat.provider(_game) if _game_available() else null)

func ui_tool(name: String, arguments: Dictionary, scope: Dictionary) -> Dictionary:
	return _ui_capture.execute(_game,name,arguments,scope) if is_instance_valid(_ui_capture) and _game_available() else {"ok":false,"code":"ui.inactive_world"}

func image_tool(name: String, arguments: Dictionary, scope: Dictionary) -> Dictionary:
	return _image_generation.execute(_game,name,arguments,scope) if is_instance_valid(_image_generation) and _game_available() else {"ok":false,"code":"images.world_unavailable","result":{"message":"Генератор доступен после загрузки партии."}}

func generation_output_limit(fallback: int, small_request: bool = false) -> int:
	var tuning: Node = _tuning()
	var provider: Node = StockCompat.provider(_game) if _game_available() else null
	return int(tuning.output_limit(provider,fallback,small_request)) if tuning != null and provider != null else fallback

func prepare_generation_query(provider: Node, query: Array, channel: String) -> Dictionary:
	var prepared: Array = query.duplicate(true)
	var budget: int = _router.generation_budget(channel,0) if _router != null else 0
	if channel == "mod_pax_harness_chat_compact": budget = generation_output_limit(8192,true)
	# Native ask_ai and provider builders may cap this at 64000 or 8000. Restore
	# the actual allowance already reserved by the runtime before its fit gate.
	if budget > 0 and prepared.size() == 3 and prepared[2] is Dictionary:
		for field: String in ["max_tokens","max_completion_tokens","max_output_tokens"]:
			if prepared[2].has(field): prepared[2][field] = budget
	var tuning: Node = _tuning()
	var tuned: Dictionary = tuning.apply_query(provider,prepared,budget) if tuning != null else {"ok":true,"query":prepared,"errors":[],"protected_fields":[],"timeout_seconds":0}
	if not tuned.get("ok",false) or _router == null: return tuned
	var images: Dictionary = _router.prepare_images(provider,tuned.query,channel)
	if not images.get("ok",false): return images
	tuned.query = images.query
	return tuned

func prompt_tools_available() -> bool:
	var lab: Node = _lab()
	return lab != null and lab.has_method("harness_instruction_tool")

func prompt_tool(name: String, args: Dictionary, scope: Dictionary) -> Dictionary:
	var lab: Node = _lab()
	return lab.harness_instruction_tool(name,args,scope) if prompt_tools_available() else {"ok":false,"code":"prompts.laboratory_unavailable"}

func analysis_delegate(args: Dictionary, scope: Dictionary) -> Node:
	var job: Node = load_resource("src/runtime/analysis_job.gd").new()
	add_child(job)
	job.setup(self,args,scope)
	return job

func workspace_context(chat_id: String) -> Dictionary:
	return Workspace.context(chat_store,chat_id) if chat_store != null else {}

func analysis_context() -> Dictionary:
	return {"date":_game.date_text(),"home_body":_game.home_body(),"country":_game.country()} if _game_available() else {}

func _prepare_source(source: Dictionary) -> Dictionary:
	_lab_used = false
	var prepared: Dictionary = source.duplicate(true)
	prepared.system = read_text("prompts/assistant.md")
	prepared.user = JSON.stringify({"player_asked":source.context.get("player_asked",source.get("request_text","")),"current":source.get("campaign_context",{}).get("current",{}),"history_note":"Full chat history is supplied separately; other archives are read through tools."})
	prepared["options"] = {"temperature":0.2,"max_tokens":8192}
	var grants := PackedStringArray()
	for row: Dictionary in _tool_registry().catalogue():
		if not row.get("available",true): continue
		if row.name not in ["money.add","resources.add","characters.create","bodies.set_parameter","provinces.set_owner","diplomacy.change_relation"]: grants.append(row.name)
	var lab: Node = _lab()
	if lab != null:
		var compiled: Dictionary = lab.harness_prepare_assistant(source.duplicate(true))
		if not compiled.get("ok",false): return {"ok":false,"source":prepared,"grants":grants,"error":str(compiled.get("error","laboratory_compile_failed"))}
		if compiled.get("configured",false):
			prepared.system = compiled.system
			prepared.user = compiled.user
			prepared.options.merge(compiled.get("options",{}),true)
			var default_grants: PackedStringArray = grants.duplicate()
			grants = PackedStringArray(compiled.get("enabled_tools",[]))
			# The laboratory's generated default is built with its own older
			# registry. Keep current Harness capabilities, including opt-in vision.
			# Explicit custom laboratory profiles still retain their exact grants.
			if lab.has_method("selected_profile") and lab.selected_profile() == "local_assistant":
				for name: String in default_grants:
					if name not in grants: grants.append(name)
			_lab_used = true
	prepared.system += "\n"+read_text("prompts/charts.md")
	prepared.system += "\n"+read_text("prompts/interface.md")
	var provider: Node = StockCompat.provider(_game) if _game_available() else null
	if provider != null:
		var limits: Dictionary = _provider_defaults(provider)
		# Reserve the actual output allowance before compaction and native fitting.
		prepared.options["max_tokens"] = maxi(int(prepared.options.get("max_tokens",8192)),int(limits.get("output_tokens",0)))
	prepared.options["max_tokens"] = generation_output_limit(int(prepared.options.get("max_tokens",8192)))
	return {"ok":true,"source":prepared,"grants":grants}

func _observe_request(event: Dictionary) -> void:
	# Native reload/model detection may reset its local window immediately before
	# this hook. Restore only our own metadata, before native fit/compaction.
	if _game_available():
		var provider: Node = StockCompat.provider(_game)
		provider_limits.sync(provider,_provider_metadata(provider))
		var tuning: Node = _tuning()
		if tuning != null: tuning.sync_context(provider)
		_attach_transport()
	chat_compactor.prepare_request(event)
	_router.note_usage_request(event)
	if str(event.get("channel","")) != "assistant" or event.get("cancel",false) or not _game_available(): return
	var binding: Dictionary = _router.discover("assistant")
	if not binding.get("ok",false): return
	if (binding.get("mark") is Dictionary and binding.mark.has("мп_игрок")) or str(binding.get("mark","")).begins_with("мп_ви:"): return
	var source: Dictionary = StockCompat.request(_game,event,Retained.collect(_game,{},false),Pax)
	source.context["conversation"] = []
	var prepared: Dictionary = _prepare_source(source)
	var captured: Dictionary = _router.capture(event,binding,prepared.source,prepared.grants,_source_generation)
	if captured.get("ok",false) and not prepared.ok: _router._tasks[captured.id]["error"] = prepared.error

# Streaming also works without deepseek_limits. Existing custom routes/proxies
# remain their owner's responsibility; the limits adapter calls stream_request.
func _attach_transport() -> void:
	if not _game_available(): return
	var provider: Node = StockCompat.provider(_game)
	if provider == null or not provider.has_method("_build_request") or not provider.has_method("requests"): return
	var route: Callable = provider.get("via_network")
	if route == _network:
		_transport_provider = provider
		provider_limits.sync(provider,_provider_metadata(provider))
		_refresh_catalog(provider)
		return
	if route.is_valid(): return
	_transport_provider = provider
	provider_limits.sync(provider,_provider_metadata(provider))
	_refresh_catalog(provider)
	provider.set("via_network",_network)

func _detach_transport() -> void:
	if is_instance_valid(_transport_provider) and _transport_provider.get("via_network") == _network:
		_transport_provider.set("via_network",Callable())
	provider_limits.detach()
	_transport_provider = null

func _provider_defaults(provider: Node) -> Dictionary:
	if not is_instance_valid(provider): return {}
	return ProviderLimits.resolve(str(provider.base_url),str(provider.model),_provider_metadata(provider))

func _provider_metadata(provider: Node) -> Dictionary:
	var metadata: Dictionary = _model_defaults.duplicate(true)
	if is_instance_valid(provider_catalog) and is_instance_valid(provider): metadata.merge(provider_catalog.snapshot(provider),true)
	return metadata

func _provider_capabilities(provider: Node) -> Dictionary:
	return provider_catalog.capabilities(provider) if is_instance_valid(provider_catalog) else {}

func _catalog_completed(provider_instance_id: int) -> void:
	if not _game_available(): return
	var provider: Node = StockCompat.provider(_game)
	if provider != null and provider.get_instance_id() == provider_instance_id:
		provider_limits.sync(provider,_provider_metadata(provider))

func _refresh_catalog(provider: Node) -> void:
	if not is_instance_valid(provider_catalog) or not is_instance_valid(provider) or not _game_available(): return
	if provider.has_method("why_offline") and str(provider.why_offline()) != "": return
	if StockCompat.native_auth_transport(provider): return
	# Optional metadata GET must not bypass the user's native tunnel/proxy.
	var settings: Dictionary = _game.main.ui.menu_node.settings
	if str(settings.get("proxy",{}).get("mode","off")) != "off": return
	provider_catalog.ensure(provider,provider._build_request("JSON","JSON","",0.2,256,"mod_pax_harness_catalog",true))

func _current_provider() -> Node:
	if not _game_available(): return null
	var provider: Node = StockCompat.provider(_game)
	if provider == null: return null
	# Read the game's saved selection before capability checks and compaction,
	# not only later inside the native request dispatcher. Never pin a model.
	if provider.has_method("_reload_if_changed"): provider.call("_reload_if_changed")
	# Discovery is independent of who owns via_network: another mod can release
	# that route only during the first ai_request hook after a model switch.
	_refresh_catalog(provider)
	provider_limits.sync(provider,_provider_metadata(provider))
	var tuning: Node = _tuning()
	if tuning != null: tuning.sync_context(provider)
	_attach_transport()
	return provider

func _network(destination: HTTPRequest, packet: Dictionary) -> void:
	if not is_instance_valid(_transport_provider): return
	var provider: Node = _transport_provider
	var tuning: Node = _tuning()
	if tuning != null and tuning.has_method("prepare_native_packet"):
		var restored: Dictionary = tuning.prepare_native_packet(provider,packet)
		if not restored.get("ok",false):
			provider._curl_answer.call_deferred(destination,400,JSON.stringify({"error":{"code":restored.get("code","ai_tuning_context_source_unavailable"),"message":"; ".join(PackedStringArray(restored.get("errors",[])))}}).to_utf8_buffer())
			return
		packet = restored.packet
	var channel: String = str(packet.get("к",""))
	var system: String = str(packet.get("с",""))
	var user: String = str(packet.get("п",""))
	var dossier: String = str(packet.get("д",""))
	var heat: float = float(packet.get("ж",0.2))
	var limit: int = int(packet.get("pr",8192))
	var small: bool = bool(packet.get("corr",false))
	var query: Array = provider._build_request(system,user,dossier,heat,limit,channel,small)
	if channel.begins_with("mod_pax_harness_"):
		var limits: Dictionary = _provider_defaults(provider)
		# This is the allowance already reserved by runtime/compaction. Raising it
		# here would silently invalidate that budget, especially for child readers.
		for key: String in ["max_tokens","max_output_tokens","max_completion_tokens"]:
			if query[2].has(key): query[2][key] = mini(int(query[2][key]),limit)
		destination.timeout = maxf(destination.timeout,float(limits.get("timeout_seconds",destination.timeout)))
	_router.note_transport_identity({"channel":channel,"system":system,"user":user,"dossier":dossier},str(query[2].get("model","")),ProviderLimits.hostname(str(query[0])))
	destination.set_meta("retry_args",[system,user,dossier,heat,limit,channel,small])
	destination.set_meta("sent_head",user.left(300))
	destination.set_meta("sent_at",Time.get_ticks_msec())
	destination.set_meta("chars",system.length()+user.length()+dossier.length())
	# Honour the native opt-in request log, which does not include auth headers.
	if str(provider.get("dump_folder")) != "": provider._to_dump(destination,str(query[0]),JSON.stringify(query[2]))
	if stream_request(provider,destination,query,channel): return
	var tuned: Dictionary = prepare_generation_query(provider,query,channel)
	if not tuned.get("ok",false):
		provider._curl_answer.call_deferred(destination,400,JSON.stringify({"error":{"code":tuned.get("code","manual_generation_settings_invalid"),"message":"; ".join(PackedStringArray(tuned.get("errors",[])))}}).to_utf8_buffer())
		return
	query = tuned.query
	if float(tuned.get("timeout_seconds",0)) > 0: destination.timeout = float(tuned.timeout_seconds)
	var image_check: Dictionary = _router.validate_images(provider,channel,Vision.contains_images(query))
	if not image_check.get("ok",false):
		provider._curl_answer.call_deferred(destination,400,JSON.stringify({"error":{"code":image_check.get("code","vision_input_unavailable"),"message":"; ".join(PackedStringArray(image_check.get("errors",[])))}}).to_utf8_buffer())
		return
	var sent: bool = provider.requests()._dispatch_gigachat(destination,JSON.stringify(query[2]),query[1],query[0],channel)
	if not sent: provider._curl_answer.call_deferred(destination,0,PackedByteArray())

func _command(args: PackedStringArray) -> String:
	if not args.is_empty() and args[0] == "open" and is_instance_valid(chat_ui): chat_ui.open()
	return JSON.stringify({"independent":true,"laboratory_available":_lab()!=null,"laboratory_used_for_last_request":_lab_used,"chats":chat_store.chats.size() if chat_store != null else 0,"imported_from":_migration_origin,"native_stream_route":is_instance_valid(_transport_provider),"busy":chat_busy()})

func _attach_chat(game: RefCounted, generation: int) -> void:
	if generation != _ui_generation or not _game_available(game) or is_instance_valid(chat_ui): return
	var main: Node = game.main
	if not is_instance_valid(main.ui.assistant_window): return
	chat_store.import_native(main.player.assistant_history,game.date_text())
	main.player.assistant_history = chat_store.context()
	chat_ui = load_resource("src/ui/chat/chat_ui.gd").new()
	chat_ui.setup(self,main)

func chat_busy() -> bool:
	return chat_store != null and (chat_store.running() or (chat_compactor != null and chat_compactor.busy()))

func chat_new() -> void:
	if chat_store == null: return
	chat_store.create()
	_game.main.player.assistant_history = chat_store.context()

func chat_select(chat_id: String) -> void:
	if chat_store == null or not chat_store.select(chat_id): return
	_game.main.player.assistant_history = chat_store.context()

func chat_delete(chat_id: String) -> void:
	if chat_store != null and chat_store.remove(chat_id): _game.main.player.assistant_history = chat_store.context()

func chat_send(text: String) -> bool:
	return chat_send_with_refs(text,[])

func chat_send_with_refs(text: String, refs: Array) -> bool:
	if text.strip_edges().get_slice(" ",0) == "/compact":
		if not _game_available() or chat_busy(): return false
		_current_provider()
		var compacted: Dictionary = chat_compactor.manual(chat_store.selected,text.strip_edges().trim_prefix("/compact").strip_edges())
		if not compacted.ok and is_instance_valid(chat_ui): chat_ui.status.text = "Пока нечего сжимать." if compacted.code == "nothing_to_compact" else "Сжатие недоступно: "+str(compacted.code)
		return compacted.ok
	return _chat_send_to(chat_store.selected if chat_store != null else "",text,refs)

func _chat_send_to(chat_id: String, text: String, refs: Array = [], origin: Dictionary = {}, existing_user: String = "") -> bool:
	if not _game_available() or chat_store == null or chat_busy() or text.strip_edges().is_empty() or chat_store.find(chat_id).is_empty(): return false
	var provider: Node = _current_provider()
	var main: Node = _game.main
	main.player.assistant_history = chat_store.context(chat_id)
	_chat_pending = chat_store.begin(text,_game.date_text(),chat_id,refs,origin,existing_user)
	if provider != null and provider.has_method("why_offline") and str(provider.why_offline()) == "off":
		chat_store.finish(_chat_pending,"ИИ отключён правилами сценария или модом. Для работы чата включите ИИ в настройках отключившего его мода.",false,"ai_disabled_by_world")
		_chat_pending.clear()
		main.player.assistant_history = chat_store.context()
		return true
	if provider != null and not _provider_defaults(provider).get("chat_supported",true):
		chat_store.finish(_chat_pending,"Эта модель отвечает только вероятностями на типизированные вопросы. Она не поддерживает чат, текстовые ответы и инструменты построения графиков. Выберите разговорную модель.",false,"provider_not_chat_model")
		_chat_pending.clear()
		main.player.assistant_history = chat_store.context()
		return true
	_chat_send_ready.call_deferred(text,_chat_pending.duplicate(),_source_generation)
	return true

func _chat_send_ready(text: String, target: Dictionary, generation: int) -> void:
	var deadline: int = Time.get_ticks_msec()+8500
	while is_instance_valid(provider_catalog) and _game_available() and generation == _source_generation:
		var provider: Node = _current_provider()
		if provider == null or not provider_catalog.pending(provider) or Time.get_ticks_msec() >= deadline: break
		if _chat_pending != target: return
		await get_tree().create_timer(0.1).timeout
	if not _game_available() or generation != _source_generation or _chat_pending != target: return
	# Completion can arrive after _current_provider() but before pending() turns
	# false. Apply the completed metadata before the native initial request fits.
	var ready_provider: Node = StockCompat.provider(_game)
	provider_limits.sync(ready_provider,_provider_metadata(ready_provider))
	var main: Node = _game.main
	main.player.assistant_history = chat_store.context(str(target.chat_id))
	main.assistant_questions().ask(text)
	# A stock/offline profile can answer without the tool runtime.
	if not _chat_pending.is_empty():
		_chat_native_watch = _chat_pending.duplicate()
		_chat_pending.clear()
		_chat_poll_native()
	main.player.assistant_history = chat_store.context()

func _chat_pump() -> void:
	if not _game_available() or chat_store == null or chat_busy(): return
	for delivery: Dictionary in chat_store.deliveries:
		if delivery.get("status") != "queued": continue
		if chat_store.find(str(delivery.target_id)).is_empty():
			delivery.status = "interrupted"
			continue
		if _chat_send_to(str(delivery.target_id),str(delivery.text),[],delivery.origin,str(delivery.user_message_id)):
			delivery.status = "running"
			chat_store.changed.emit()
		return

func chat_context_limit() -> int:
	var provider: Node = _current_provider()
	return int(provider.context_window()) if provider != null else 1000000

func chat_tool(name: String, arguments: Dictionary, scope: Dictionary) -> Dictionary:
	return chat_tools.execute(name,arguments,scope)

func chat_stop() -> void:
	if chat_compactor != null: chat_compactor.cancel()
	if not _chat_pending.is_empty() and chat_store != null:
		chat_store.finish(_chat_pending,"Ответ остановлен.",false,"cancelled")
		_chat_pending.clear()
	for task_id: String in _router._tasks.keys():
		var task: Dictionary = _router._tasks[task_id]
		if task.channel == "assistant" and task.has("runtime_token"):
			var channels := PackedStringArray()
			for transport: Dictionary in _router._transport.values():
				if transport.task == task_id: channels.append(str(transport.get("channel","")))
			chat_store.cancel_deliveries(str(task.get("chat_target",{}).get("message_id","")))
			_runtime.cancel(str(task.runtime_token))
			for channel: String in channels: chat_stream.cancel(channel)

func _chat_capture(task: Dictionary) -> void:
	if task.channel != "assistant" or chat_store == null: return
	task["chat_target"] = _chat_pending.duplicate() if not _chat_pending.is_empty() else chat_store.begin(str(_game.main.player._assistant_question),_game.date_text())
	task.source["chat_references"] = task.chat_target.get("references",[]).duplicate(true)
	task.source["chat_origin"] = task.chat_target.get("origin",{}).duplicate(true)
	if chat_store.needs_title(str(task.chat_target.chat_id)):
		task.source.system = str(task.source.get("system",""))+"\nChat naming: when finishing this conversation's first successful answer with an empty tool_calls list, set the outer result to {\"chat_title\":\"short topic title\"}. Use the player's language, 2–6 words, at most 48 characters. Summarize the topic; do not copy the question or include instructions, quotes or a heading. Keep the answer in message. This is display metadata, not a tool or world action."
	_chat_pending.clear()

func _chat_current(task: Dictionary) -> bool:
	return chat_store != null and not chat_store.message(task.get("chat_target",{})).is_empty()

func _chat_event(kind: String, payload: Dictionary, task_id: String) -> void:
	if chat_store == null or not _router._tasks.has(task_id): return
	var task: Dictionary = _router._tasks[task_id]
	if task.channel == "assistant" and task.has("chat_target"): chat_store.record(task.chat_target,kind,payload)

func _chat_done(task: Dictionary, result: Dictionary) -> void:
	if chat_store == null or not task.has("chat_target"): return
	var ok: bool = bool(result.get("ok",false))
	var code: String = str(result.get("code",""))
	var text: String = str(task.get("chat_reply",result.get("message",""))) if ok else str(result.get("failure",{}).get("message",_chat_error(code)))
	if not ok and code == "charts.invalid_response" and str(result.get("rejected_chart_message","")) != "":
		# Keep the failed block for the diagnostic card, including non-stream providers.
		chat_store.message(task.chat_target).erase("stream")
		text = str(result.rejected_chart_message)+"\n\n"+text
	chat_store.finish(task.chat_target,text,ok,code)
	if ok and result.get("proposed_result") is Dictionary:
		chat_store.apply_title(str(task.chat_target.chat_id),result.proposed_result.get("chat_title"))
	if not ok: chat_store.cancel_deliveries(str(task.chat_target.message_id))
	chat_compactor.retire(str(task.get("id","")))
	var delivery_id: String = str(task.chat_target.get("origin",{}).get("delivery_id",""))
	for delivery: Dictionary in chat_store.deliveries:
		if delivery.id == delivery_id: delivery.status = "complete" if ok else "interrupted"
	_chat_pump.call_deferred()
	if task.chat_target.chat_id == chat_store.selected and _game_available(): _game.main.player.assistant_history = chat_store.context()

func _chat_error(code: String) -> String:
	if code == "cancelled": return "Ответ остановлен."
	if code == "agent_round_limit" or code == "agent_call_limit": return "Достигнут предел шагов за один ответ. Посмотрите выполненные действия выше; продолжить можно следующим сообщением."
	return str(load_resource("src/core/runtime_error.gd").make(code).message)+" Выполненные шаги сохранены в чате."

func _chat_poll_native() -> void:
	if _chat_native_watch.is_empty() or not _game_available() or chat_store == null: return
	var main: Node = _game.main
	if main.ui.assistant_window._thinking: return
	var history: Array = main.player.assistant_history
	var reply: String = str(history.back().get("what","")) if not history.is_empty() and history.back().get("who") != "player" else "Ответ не получен."
	chat_store.finish(_chat_native_watch,reply)
	_chat_native_watch.clear()

func chat_history(arguments: Dictionary, chat_id: String) -> Dictionary:
	return chat_store.history(chat_id,arguments) if chat_store != null else {"error":"chat_unavailable"}

func _observe_chat_usage(data: Dictionary) -> void:
	if chat_compactor != null: chat_compactor.record_usage(data)
	if _router != null: _router.record_usage(data)

func _chat_usage(target: Dictionary, request: Dictionary) -> void:
	if chat_store != null: chat_store.record_usage(target,request)

func stream_request(provider: Node, destination: HTTPRequest, query: Array, channel: String) -> bool:
	if not is_instance_valid(chat_stream) or not _game_available(): return false
	# Preserve native proxy/tunnel routing whenever it is configured.
	var settings: Dictionary = _game.main.ui.menu_node.settings
	var direct: bool = str(settings.get("proxy",{}).get("mode","off")) == "off"
	if StockCompat.native_auth_transport(provider): direct = false
	return chat_stream.start(provider,destination,query,channel,direct)

func _chat_stream_text(target: Dictionary, request_id: String, text: String) -> void:
	if chat_store != null: chat_store.stream_update(target,request_id,text)

func _chat_compact_answer(response: Dictionary, token: String) -> void:
	if chat_compactor != null: chat_compactor._answer(response,token)

func _start_universal_task(task_id: String, source: Dictionary, grants: PackedStringArray) -> void:
	if not _router.current(task_id): return
	var task: Dictionary = _router._tasks[task_id]
	if task.get("error","")!="":
		_router.finish({"ok":false,"code":task.error,"message":"","receipts":[],"native_delivered":false},task_id)
		return
	var scope := {"game":task.game,"world_generation":task.generation,"request_id":task_id,"channel":task.channel,"enabled_tools":grants,
		"chat_id":task.get("chat_target",{}).get("chat_id",""),"message_id":task.get("chat_target",{}).get("message_id",""),"forward_depth":int(task.get("chat_target",{}).get("origin",{}).get("depth",0)),"trace":_chat_event.bind(task_id),"is_current":_router.current.bind(task_id),"completion_current":_router.completion_current.bind(task_id),"retire":_router.retire.bind(task_id)}
	scope["context_limit"] = chat_context_limit
	if task.has("chat_target"):
		scope["workspace"] = workspace_context.bind(str(task.chat_target.chat_id))
		scope["chat_context"] = chat_compactor.context_for.bind(str(task.chat_target.chat_id))
		scope["compact_packet"] = chat_compactor.prepare
	var token: String = _runtime.start(source,scope,_tool_registry(),_router.send.bind(task_id),_router.finish.bind(task_id),_router.native_contract(task_id))
	if _router._tasks.has(task_id): _router._tasks[task_id]["runtime_token"] = token


func _agent_public_answer(response: Dictionary, key: String) -> void:
	if _router != null: _router.public_answer(response,key)


func _tool_registry() -> RefCounted:
	var registered: RefCounted = RuntimeTools.new()
	registered.setup(_game if _game_available() else null,self,_source_generation)
	return registered

