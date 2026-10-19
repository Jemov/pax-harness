extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Version-bound adapter for the official documented raw Provider handle.
## Native cancellation fallbacks are suppressed only within their captured task.
const Compat = preload("res://mods/pax_harness/src/core/stock_compat.gd")
const Data = preload("res://mods/pax_harness/src/runtime/tools/tool_data.gd")
const Validation = preload("res://mods/pax_harness/src/runtime/response_validation.gd")
const Envelope = preload("res://mods/pax_harness/src/runtime/tool_envelope.gd")
const Limits = preload("res://mods/pax_harness/src/transport/provider_limits.gd")
const Vision = preload("res://mods/pax_harness/src/transport/vision_payload.gd")
const SIGNALS := {"interpreter":"done","event":"event_ready","talk":"interlocutor_answered","person":"person_ready","assistant":"assistant_answered","report":"summary_ready"}
const EFFECTS := {"interpreter":"Prepare the captured native order plan; native simulation remains responsible for its later outcome.",
	"event":"Deliver the captured event narrative to its existing event subscribers.","person":"Create the captured native person record through the existing person callback.",
	"talk":"Deliver the native dialogue response, including that callback's installed relationship/effect fields.",
	"assistant":"Render assistant text only. Native keyword actions and plan submission are disabled; use explicit registered tools.",
	"report":"Deliver the captured native report/news contract to the existing report callback.",
	"preset_edit":"Apply the captured preset-editor edits; the native editor records its own undo snapshot."}
var _owner: Node
var _sequence := 0
var _tasks: Dictionary = {}
var _muted: Dictionary = {}
var _transport: Dictionary = {}
var _rate: Array[int] = []
var _cancelled_analysis: Dictionary = {}
var _usage_pending: Array = []
var _image_channels: Dictionary = {}

func setup(owner_mod: Node) -> void:
	_owner = owner_mod

func invalidate() -> void:
	_cancelled_analysis.clear()
	_usage_pending.clear()
	for key: String in _muted.keys(): _restore(key)
	for record: Dictionary in _transport.values():
		if is_instance_valid(record.provider) and record.provider.is_connected("channel_ready",record.callback):
			record.provider.disconnect("channel_ready",record.callback)
	_transport.clear()
	_tasks.clear()

func cancel_continuation(event: Dictionary) -> bool:
	if event.get("cancel",false): return false
	var channel: String=str(event.get("channel",""))
	if not (channel.begins_with("interpreter_") or channel=="plausible"): return false
	var binding: Dictionary=discover(channel)
	if not binding.get("ok",false) or not binding.get("followup",false): return false
	var key: String="%d:%s"%[binding.provider.get_instance_id(),binding.signal]
	if not _muted.has(key): return false
	var task_id: String=_muted[key].task_id
	if not current(task_id) or not _tasks[task_id].followup: return false
	event.cancel=true
	return true

func discover(channel: String) -> Dictionary:
	var candidates: Array[Node] = []
	_scan(_owner.get_tree().root,candidates)
	var named: Array[Node] = []
	for node: Node in candidates:
		var channels: Variant = node.get("_channels")
		if channels is Dictionary and channels.get(channel) is Dictionary and channels[channel].get("busy",false):
			named.append(node)
	if named.size() == 1:
		var p: Node = named[0]
		return {"ok":true,"provider":p,"signal":"channel_ready","mark":_copy(p.get("_channels")[channel].get("label")),"followup":false}
	if named.size() > 1: return {"ok":false,"reason":"ambiguous_provider"}
	var main_provider: Node = Compat.provider(_owner._game) if _owner._game_available() else null
	if channel in SIGNALS and main_provider != null:
		return {"ok":true,"provider":main_provider,"signal":SIGNALS[channel],"mark":null,"followup":false}
	if channel.begins_with("interpreter_") or channel == "plausible":
		for p: Node in candidates:
			var order: Variant = p.get("_under_review")
			var http: Variant = p.get("http_argument")
			if order is Dictionary and not order.is_empty() and is_instance_valid(http) and str(http.get_meta("channel","")) == channel:
				return {"ok":true,"provider":p,"signal":"done","mark":null,"followup":true,
					"prior":order.duplicate(true),"stage":int(p.get("_check_stage"))}
	return {"ok":false,"reason":"native_sender_unavailable"}

func _scan(node: Node, result: Array[Node]) -> void:
	if node.has_method("ask_own") and node.has_method("channel_name") and node.has_method("answer_schema") and node.has_signal("channel_ready"):
		result.append(node)
	for child: Node in node.get_children(): _scan(child,result)

func capture(event: Dictionary, binding: Dictionary, source: Dictionary, grants: PackedStringArray, generation: int) -> Dictionary:
	if event.get("cancel",false) or not binding.get("ok",false): return {"ok":false,"reason":"request_not_owned"}
	var p: Node = binding.provider
	var muted_key := "%d:%s" % [p.get_instance_id(),binding.signal]
	if _muted.has(muted_key): return {"ok":false,"reason":"native_fallback_already_owned"}
	_sequence += 1
	var task_id := "route:%d:%d" % [generation,_sequence]
	var record: Dictionary = binding.duplicate()
	record.merge({"id":task_id,"channel":str(event.channel),"source":source.duplicate(true),"grants":grants.duplicate(),
		"generation":generation,"game":_owner._game if _owner._game_available() else null,"listeners":p.get_signal_connection_list(binding.signal).duplicate(),"delivered":false,"fallback_seen":false,"target":_target(binding,str(event.channel)),"callback_started":false},true)
	if record.channel=="interpreter" and not record.followup: record["expected_fallback"]=p._offline(str(p.get("_order_text")))
	elif record.followup: record["expected_fallback"]=record.prior.duplicate(true)
	else: record["expected_fallback"]={}
	_tasks[task_id] = record
	_owner._chat_capture(record)
	var proxy: Callable
	if binding.signal == "channel_ready": proxy = _proxy_named.bind(muted_key,task_id)
	elif binding.signal == "event_ready": proxy = _proxy_event.bind(muted_key,task_id)
	else: proxy = _proxy_result.bind(muted_key,task_id)
	_muted[muted_key] = {"provider":p,"signal":binding.signal,"listeners":record.listeners,"proxy":proxy,"task_id":task_id}
	for connection: Dictionary in record.listeners:
		if p.is_connected(binding.signal,connection.callable): p.disconnect(binding.signal,connection.callable)
	p.connect(binding.signal,proxy)
	event.cancel = true
	_launch.call_deferred(task_id,muted_key)
	return {"ok":true,"id":task_id}

func _proxy_named(channel: String, value: Dictionary, mark: Variant, key: String, task_id: String) -> void:
	if _tasks.has(task_id) and channel == _tasks[task_id].channel and _same_id(mark,_tasks[task_id].mark) and value.is_empty():
		_suppressed(key,task_id)
	else: _forward(key,[channel,value,mark])

func _proxy_event(text: String, title: String, key: String, task_id: String) -> void:
	if text == "" and title == "": _suppressed(key,task_id)
	else: _forward(key,[text,title])

func _proxy_result(value: Dictionary, key: String, task_id: String) -> void:
	# A followup cancellation emits its still-current initial plan, not {}.
	if _tasks.has(task_id) and value==_tasks[task_id].expected_fallback:
		_suppressed(key,task_id)
	else: _forward(key,[value])

func _suppressed(key: String, task_id: String) -> void:
	if _tasks.has(task_id): _tasks[task_id].fallback_seen = true
	_restore(key)

func _forward(key: String, args: Array) -> void:
	if not _muted.has(key): return
	var muted: Dictionary = _muted[key]
	for connection: Dictionary in muted.listeners.duplicate():
		if not connection.callable.is_valid(): continue
		if int(connection.flags) & CONNECT_ONE_SHOT:
			muted.listeners.erase(connection)
		if int(connection.flags) & CONNECT_DEFERRED: connection.callable.callv.bind(args).call_deferred()
		else: connection.callable.callv(args)

func _restore(key: String) -> void:
	if not _muted.has(key): return
	var m: Dictionary = _muted[key]
	_muted.erase(key)
	if not is_instance_valid(m.provider): return
	if m.provider.is_connected(m.signal,m.proxy): m.provider.disconnect(m.signal,m.proxy)
	for connection: Dictionary in m.listeners:
		if connection.callable.is_valid() and not m.provider.is_connected(m.signal,connection.callable):
			m.provider.connect(m.signal,connection.callable,int(connection.flags))

func _launch(task_id: String, key: String) -> void:
	if not _tasks.has(task_id): return
	var task: Dictionary = _tasks[task_id]
	if not current(task_id):
		_restore(key)
		_tasks.erase(task_id)
		return
	if not task.fallback_seen:
		_restore(key)
		fail(task_id,"native_cancellation_boundary_unobserved")
		return
	_owner._start_universal_task(task_id,task.source,task.grants)

func current(task_id: String) -> bool:
	if not _tasks.has(task_id) or not is_instance_valid(_owner): return false
	var task: Dictionary = _tasks[task_id]
	if task.generation != _owner._source_generation or not is_instance_valid(task.provider) or task.provider.is_queued_for_deletion(): return false
	if task.game != null and not _owner._game_available(task.game): return false
	if task.channel == "assistant" and task.has("chat_target"): return _owner._chat_current(task)
	return task.target == _target(task,task.channel)

func completion_current(task_id: String) -> bool:
	# An accepted native callback can legitimately clear or advance its target.
	# Cleanup still belongs to this world generation, never to a replacement world.
	return _tasks.has(task_id) and _live(_tasks[task_id]) and (_tasks[task_id].delivered or current(task_id))

func retire(task_id: String) -> void:
	_tasks.erase(task_id)

func native_contract(task_id: String) -> Dictionary:
	if not _tasks.has(task_id): return {}
	var task: Dictionary = _tasks[task_id]
	return {"metadata":{"name":"native.complete_task","description":EFFECTS.get(task.channel,"Deliver only this captured task's installed domain result to its existing native callback. That callback can apply the native domain effects described by its contract."),
		"arguments_schema":{"type":"object","properties":{"result":task.source.output_contract if task.source.output_contract is Dictionary else {"type":"object"}},"required":["result"],"additionalProperties":false},
		"capability":"native_task_delivery","available":true,"mutates_world":task.channel != "assistant","handler_kind":"captured_native_callback","channels":[task.channel]},
		"validate":validate_native.bind(task_id),"dispatch":deliver.bind(task_id)}

func validate_native(arguments: Dictionary, task_id: String) -> Dictionary:
	if not current(task_id) or arguments.size()!=1 or not arguments.get("result") is Dictionary or not Data.plain(arguments) or _tasks[task_id].delivered:
		return {"ok":false,"errors":["native_invalid_or_stale_task"]}
	var t: Dictionary = _tasks[task_id]
	if t.channel == "assistant" and str(arguments.result.get("action","nothing")) not in ["nothing",""]:
		return {"ok":false,"errors":["assistant_native_actions_disabled_use_registered_tools"]}
	if t.source.output_contract is Dictionary:
		return Validation.validate(JSON.stringify(arguments.result),t.source.output_contract)
	# Some installed channels offer JSON-only, with no readable typed schema.
	return {"ok":true,"errors":[],"schema_available":false}

func deliver(arguments: Dictionary, task_id: String) -> Dictionary:
	var check: Dictionary = validate_native(arguments,task_id)
	if not check.ok: return {"ok":false,"receipt":{"ok":false,"errors":check.errors}}
	var task: Dictionary = _tasks[task_id]
	task.delivered = true
	var native: Dictionary = task.provider.sliders_back(task.provider.from_machine(arguments.result.duplicate(true)))
	if task.followup:
		var merged: Dictionary = task.prior.duplicate(true)
		if task.stage == 2:
			if bool(arguments.result.get("possible",false)):
				merged["plausible"] = true
				merged["why_not"] = ""
		else:
			for field: Variant in native:
				var value: Variant = native[field]
				if _neutral(value): continue
				merged[field] = value
		native = merged
	if task.channel == "assistant":
		_render_assistant(str(native.get("answer","")),task)
	else:
		if task.channel == "interpreter" or task.followup:
			for field: String in ["deltas","needs"]:
				if not native.has(field): native[field] = {}
			if not native.has("magnitude"): native["magnitude"] = 0.3
			if not native.has("plausible"): native["plausible"] = true
		var args: Array = [task.channel,native,task.mark] if task.signal == "channel_ready" else ([str(native.get("text","")),str(native.get("title",""))] if task.signal == "event_ready" else [native])
		_call_listeners(task,args)
	return {"ok":true,"receipt":{"ok":true,"name":"native.complete_task","status":"delivered" if task.callback_started or task.channel=="assistant" else "scheduled_callback","channel":task.channel,"request_id":task_id,"evidence":"Delivered exactly once to the captured native task boundary; domain completion is not inferred."}}

func finish(result: Dictionary, task_id: String) -> void:
	if not _tasks.has(task_id) or not _live(_tasks[task_id]) or (not _tasks[task_id].delivered and not current(task_id)):
		_tasks.erase(task_id)
		return
	var task: Dictionary = _tasks[task_id]
	if not task.delivered:
		if task.channel == "assistant" and result.ok:
			_render_assistant(str(result.message),task)
		else:
			var completion: Dictionary = result.duplicate(true)
			completion["code"] = str(result.code) if not result.ok else "native_completion_tool_not_called"
			completion["ok"] = false
			fail(task_id,completion.code,completion)
			_owner.universal_results[task.channel] = completion.duplicate(true)
			_tasks.erase(task_id)
			return
	_owner._chat_done(task,result)
	_owner.universal_results[task.channel] = result.duplicate(true)
	_tasks.erase(task_id)

func fail(task_id: String, reason: String, completion: Dictionary = {}) -> void:
	if not current(task_id): return
	var task: Dictionary = _tasks[task_id]
	_owner.composition_error = {"channel":task.channel,"errors":PackedStringArray([reason])}
	if task.channel == "assistant":
		_render_assistant(L.text("Помощник: ") + reason,task)
	else:
		_finalize_failure(task,reason)
	_owner._chat_done(task,completion if not completion.is_empty() else {"ok":false,"code":reason})
	task.delivered = true

func _live(task: Dictionary) -> bool:
	return is_instance_valid(_owner) and task.generation==_owner._source_generation and is_instance_valid(task.provider) and not task.provider.is_queued_for_deletion() and (task.game==null or _owner._game_available(task.game))

func _call_listeners(task: Dictionary, args: Array) -> void:
	if not current(task.id): return
	for connection: Dictionary in task.listeners:
		if connection.callable.is_valid():
			if int(connection.flags) & CONNECT_ONE_SHOT and task.provider.is_connected(task.signal,connection.callable): task.provider.disconnect(task.signal,connection.callable)
			if int(connection.flags) & CONNECT_DEFERRED: _deliver_listener.call_deferred(connection,args,task)
			else: _deliver_listener(connection,args,task)

func _deliver_listener(connection: Dictionary,args: Array,task: Dictionary) -> void:
	if not _live(task): return
	if not task.callback_started and task.target!=_target(task,task.channel): return
	task.callback_started=true
	if connection.callable.is_valid(): connection.callable.callv(args)

func _render_assistant(message: String, task: Dictionary) -> void:
	if not current(task.id) or task.game == null: return
	var main: Node = task.game.main
	task["chat_reply"] = message
	var window: Object = main.ui.assistant_window
	window.thinks(false)
	if task.has("chat_target") and _owner.chat_store != null and task.chat_target.chat_id != _owner.chat_store.selected:
		if message != "" and main.model.memory != null: main.model.memory.remember_it("assistant","assistant",main.model.sim.turn,"ответил: " + message,1)
		return
	if message != "":
		var label: String = main.assistant_identity().ai_name()
		window.said(label,message)
		main.assistant_identity().to_history(label,message)
		if main.model.memory != null: main.model.memory.remember_it("assistant","assistant",main.model.sim.turn,"ответил: " + message,1)

func send(packet: Dictionary, done: Callable, task_id: String) -> Dictionary:
	if not current(task_id): return {"ok":false,"error":"stale_task"}
	var now: int = Time.get_ticks_msec()
	while not _rate.is_empty() and now-_rate[0]>=60000: _rate.pop_front()
	if _rate.size()>=12:
		var delay: int = maxi(1,60000-(now-int(_rate[0])))
		_owner._chat_event("network.retry",{"attempt":1,"delay_ms":delay,"failure":{"code":"local_rate_limit","category":"rate_limit","retryable":true}},task_id)
		_owner.get_tree().create_timer(float(delay)/1000).timeout.connect(_send_queued.bind(packet,done,task_id),CONNECT_ONE_SHOT)
		return {"ok":true,"queued":true}
	_rate.append(now)
	_sequence += 1
	var key := "transport:%d" % _sequence
	var slot := 0
	var p: Node = _tasks[task_id].provider
	var attachments: Array = packet.get("request_attachments",[])
	if not attachments.is_empty() and bool(packet.get("analysis_child",false)): return {"ok":false,"error":"vision_not_available_in_analysis_child"}
	for index: int in 8:
		var channel_state: Variant = Data.property(p,"_channels")
		var native_slot: Dictionary = channel_state.get("mod_pax_harness_agent_slot_%d"%index,{}) if channel_state is Dictionary else {}
		if not _transport.values().any(func(record: Dictionary): return record.provider == p and record.slot == index) and not native_slot.get("busy",false) and native_slot.get("queue",[]).is_empty():
			slot = index
			break
		if index == 7: return {"ok":false,"error":"agent_transport_pool_busy"}
	var channel := "mod_pax_harness_agent_slot_%d" % slot
	var callback: Callable = _transport_answer.bind(key,channel)
	_transport[key] = {"provider":p,"callback":callback,"done":done,"task":task_id,"slot":slot,"channel":channel,"analysis_child":bool(packet.get("analysis_child",false)),"analysis_job_id":packet.get("analysis_job_id",0),"output_budget":int(packet.get("options",{}).get("max_tokens",2400))}
	_transport[key]["request_attachments"] = attachments.duplicate(true)
	# Remember only the bounded slot marker if cancellation retires a transport
	# while its native builder is still queued. It must fail, never send text-only.
	if attachments.is_empty(): _image_channels.erase(channel)
	else: _image_channels[channel] = true
	if _tasks[task_id].has("chat_target"):
		var tool_chars: int = clampi(int(packet.get("tool_schema_chars",0)),0,str(packet.system).length())
		_usage_pending.append({"id":key,"channel":channel,"target":_tasks[task_id].chat_target.duplicate(),
			"provider":p,"model":str(p.get("model")),"provider_host":Limits.hostname(str(p.get("base_url"))),
			"generation":_tasks[task_id].generation,"started_ms":Time.get_ticks_msec(),"context_limit":p.context_window(),"parts":{"system":maxi(0,str(packet.system).length()-tool_chars),"tools":tool_chars,"messages":JSON.stringify(packet.data).length()}})
	var options: Dictionary = packet.get("options",{})
	if _tasks[task_id].game!=null and p==Compat.provider(_tasks[task_id].game):
		_transport[key].callback=Callable()
		if not _owner.ask_ai("agent_slot_%d"%slot,str(packet.system),packet.data,_owner._agent_public_answer.bind(key),options):
			_transport.erase(key)
			_usage_pending = _usage_pending.filter(func(row: Dictionary): return row.id != key)
			return {"ok":false,"error":"official_ask_ai_rejected"}
	else:
		p.connect("channel_ready",callback)
		p.ask_own(channel,str(packet.system),packet.data,key,float(options.get("temperature",0.2)),int(options.get("max_tokens",2400)))
	return {"ok":true}

func generation_budget(channel: String, fallback: int = 0) -> int:
	for record: Dictionary in _transport.values():
		if record.get("channel") == channel and current(str(record.task)):
			return int(record.get("output_budget",fallback))
	return fallback

func _image_record(channel: String) -> Dictionary:
	for record: Dictionary in _transport.values():
		if record.get("channel") == channel and current(str(record.task)): return record
	return {}

func validate_images(provider: Node, channel: String, required: bool = false) -> Dictionary:
	if "vision_support" in _owner and is_instance_valid(_owner.vision_support) and _owner.vision_support.is_probe_channel(channel): return _owner.vision_support.validate(provider,channel)
	var record: Dictionary = _image_record(channel)
	if required and record.is_empty(): return {"ok":false,"code":"vision_request_expired","errors":["vision_request_expired"]}
	if record.get("request_attachments",[]).is_empty(): return {"ok":true}
	if record.get("provider") != provider or record.get("analysis_child",false): return {"ok":false,"code":"vision_provider_changed","errors":["vision_provider_changed"]}
	if not _owner.has_method("vision_input_enabled") or not _owner.vision_input_enabled(provider): return {"ok":false,"code":"vision_input_disabled","errors":["vision_input_disabled"]}
	if not _owner.has_method("resolve_image_attachment"): return {"ok":false,"code":"vision_image_resolver_unavailable","errors":["vision_image_resolver_unavailable"]}
	for handle: Dictionary in record.request_attachments:
		var resolved: Dictionary = _owner.resolve_image_attachment(handle,provider)
		if not resolved.get("ok",false): return {"ok":false,"code":str(resolved.get("code","vision_image_unavailable")),"errors":[str(resolved.get("code","vision_image_unavailable"))]}
	return {"ok":true}

func prepare_images(provider: Node, query: Array, channel: String) -> Dictionary:
	if "vision_support" in _owner and is_instance_valid(_owner.vision_support) and _owner.vision_support.is_probe_channel(channel): return _owner.vision_support.prepare(provider,query,channel)
	var record: Dictionary = _image_record(channel)
	if record.is_empty() and _image_channels.has(channel): return {"ok":false,"code":"vision_request_expired","errors":["vision_request_expired"]}
	if record.get("request_attachments",[]).is_empty(): return {"ok":true,"query":query}
	var checked: Dictionary = validate_images(provider,channel)
	if not checked.ok: return checked
	var resolver: Callable = func(handle: Dictionary) -> Dictionary: return _owner.resolve_image_attachment(handle,provider)
	return Vision.apply(query,record.request_attachments,resolver,true,str(provider.get("model")))

func _send_queued(packet: Dictionary, done: Callable, task_id: String) -> void:
	if not current(task_id) or _cancelled_analysis.has(int(packet.get("analysis_job_id",0))): return
	var accepted: Dictionary = send(packet,done,task_id)
	if not accepted.get("ok",false) and done.is_valid(): done.call({"error":accepted.get("error","agent_transport_rejected")})

func _transport_answer(channel: String, response: Dictionary, mark: Variant, key: String, expected: String) -> void:
	if channel != expected or mark != key or not _transport.has(key): return
	var record: Dictionary = _transport[key]
	_transport.erase(key)
	if is_instance_valid(record.provider) and record.provider.is_connected("channel_ready",record.callback): record.provider.disconnect("channel_ready",record.callback)
	if record.has("stream_error"): response = {"error":record.stream_error,"failure":record.get("stream_failure",{})}
	_mark_images_seen(record,response)
	if record.done.is_valid(): record.done.call(response.duplicate(true))

func public_answer(response: Dictionary,key: String) -> void:
	if not _transport.has(key): return
	var record: Dictionary=_transport[key]
	if record.has("stream_error"): response = {"error":record.stream_error,"failure":record.get("stream_failure",{})}
	_transport.erase(key)
	_mark_images_seen(record,response)
	if record.done.is_valid(): record.done.call(response.duplicate(true))

func _mark_images_seen(record: Dictionary, response: Dictionary) -> void:
	if response.has("error") or response.has("failure") or record.has("stream_error"): return
	if is_instance_valid(_owner) and _owner.has_method("mark_game_images_delivered"):
		_owner.call("mark_game_images_delivered",record.get("request_attachments",[]),record.provider)

static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value


func _target(binding: Dictionary, channel: String) -> Dictionary:
	var result: Dictionary = {}
	if _owner._game_available():
		var main: Variant = _owner._game.main
		if channel == "assistant": return {"question":str(main.player._assistant_question),"history_size":main.player.assistant_history.size()}
		var fields: Array = []
		match channel:
			"interpreter","interpreter_land","interpreter_military","interpreter_diplomacy","interpreter_space": fields=["being_weighed"]
			"assistant": fields=["_assistant_question"]
			"talk": fields=["talking_with","conversation_now"]
			"person": fields=["waiting_person_on","_waiting_special"]
			"report": fields=["summary_waiting"]
		for field: String in fields:
			if main.get_property_list().any(func(row: Dictionary): return row.name == field): result[field]=Data.clean(main.get(field))
		if result.has("being_weighed"):
			var orders: Variant = Data.property(main,"orders")
			if orders is Array:
				for order: Variant in orders:
					if order is Dictionary and _same_id(order.get("id"),result["being_weighed"]):
						result["order_identity"]=Data.fields(order,["id","text","body","place","reassess"]).duplicate(true)
		if channel in ["law","research","order_story","plausible"] and not binding.get("followup",false):
			var field: String = "законы" if channel=="law" else ("orders" if channel=="order_story" else "разработки")
			var rows: Variant = Data.property(main,field)
			if rows is Array:
				for row: Variant in rows:
					if row is Dictionary and _same_id(row.get("id"),binding.get("mark")):
						result["native_item"]=Data.fields(row,["id","text","what","status","canceled"]).duplicate(true)
	if channel=="preset_edit":
		for listener: Dictionary in binding.get("listeners",binding.provider.get_signal_connection_list(binding.signal)):
			var consumer: Object = listener.callable.get_object()
			if is_instance_valid(consumer) and consumer.get_property_list().any(func(row: Dictionary): return row.name=="_последний"):
				result["preset_input"] = Data.clean(consumer.get("_последний"))
	return result


func _finalize_failure(task: Dictionary, reason: String) -> void:
	# Error finalization never calls a native domain callback: several callbacks
	# turn empty answers into successful fallback world mutations.
	var main: Variant = task.game.main if task.game != null else null
	if is_instance_valid(main):
		match task.channel:
			"interpreter","interpreter_land","interpreter_military","interpreter_diplomacy","interpreter_space":
				var orders: Variant = Data.property(main,"orders")
				if orders is Array:
					for order: Variant in orders:
						if order is Dictionary and _same_id(order.get("id"),task.target.get("being_weighed")):
							order["request"]={"understood":str(order.get("text","")),"plausible":false,"why_not":"prompt_lab: "+reason,"deltas":{},"needs":{}}
							order["status"]="невыполним"
				if Data.property(main,"being_weighed")!=null: main.set("being_weighed",-1)
				if main.has_method("_обновить_приказы"): main._обновить_приказы()
				if main.has_method("_оценить_следующий"): main._оценить_следующий.call_deferred()
			"talk":
				_set_existing(main,"провайдер_ждёт_ответа",false)
				_window_stop(main,"окно_человека")
			"person":
				_set_existing(main,"не_до_людей",false)
				_set_existing(main,"waiting_person_on","")
				_set_existing(main,"_waiting_special",{})
			"report":
				# Preserve the pending report until the native failure callback
				# consumes it and closes the jump. Clearing it first also disables
				# Main's own watchdog, leaving the loading overlay forever.
				if main.has_method("_итоги_готовы"):
					_set_existing(main,"_сбой_итогов",true)
					main._итоги_готовы({})
				else:
					_set_existing(main,"summary_waiting",{})
			"epoch": _set_existing(main,"_ждём_эпоху",false)
			"consequences": _set_existing(main,"_ждём_последствий",false)
			"council":
				var count: Variant = Data.property(main,"_совет_ждём")
				if count!=null:
					main.set("_совет_ждём",maxi(0,int(count)-1))
					if int(count)<=1 and main.has_method("_продолжить_скачок"): main._продолжить_скачок.call_deferred()
			"faction":
				var waiting: Variant = Data.property(main,"_ждём_фракцию")
				if waiting is Dictionary and task.mark is Dictionary: waiting.erase(str(task.mark.get("фракция","")))
				_window_stop(main,"окно_входящих")
			"surroundings":
				var waiting: Variant = Data.property(main,"_осматриваемся")
				if waiting is Dictionary and task.mark is String: waiting.erase(task.mark)
			"law","research","plausible":
				var rows: Variant = Data.property(main,"законы" if task.channel=="law" else "разработки")
				if rows is Array:
					for row: Variant in rows:
						if row is Dictionary and _same_id(row.get("id"),task.mark):
							row["status"]="невозможен" if task.channel=="law" else "провалилось"
							row["why"]="prompt_lab: "+reason
		if main.has_method("_печать"): main._печать(L.text("Помощник: ")+reason)
	if task.channel=="preset_edit":
		for listener: Dictionary in task.listeners:
			var consumer: Object = listener.callable.get_object()
			if not is_instance_valid(consumer): continue
			_set_existing(consumer,"_ждём",false)
			var button: Variant = Data.property(consumer,"кнопка")
			if is_instance_valid(button) and button is BaseButton: button.disabled=false
			var status: Variant = Data.property(consumer,"status")
			if is_instance_valid(status) and status is Label: status.text=L.text("Помощник: ")+reason


static func _set_existing(object: Object, field: String, value: Variant) -> void:
	if object.get_property_list().any(func(row: Dictionary): return row.name==field): object.set(field,value)

static func _same_id(left: Variant,right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return float(left)==float(right)
	return typeof(left)==typeof(right) and left==right

static func _neutral(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL: return true
		TYPE_STRING: return value.is_empty()
		TYPE_BOOL: return not value
		TYPE_INT,TYPE_FLOAT: return float(value)==0.0
		TYPE_ARRAY: return value.is_empty()
		TYPE_DICTIONARY: return str(value.get("deed","x"))==""
	return false


static func _window_stop(main: Object, field: String) -> void:
	var window: Variant = Data.property(main,field)
	if is_instance_valid(window) and window.has_method("думает"): window.думает(false)


func note_usage_request(event: Dictionary) -> void:
	var channel: String = str(event.get("channel",""))
	for record: Dictionary in _usage_pending:
		if record.channel != channel or record.has("fingerprint"): continue
		record["fingerprint"] = _usage_fingerprint(event)
		var provider: Node = record.get("provider")
		if is_instance_valid(provider):
			record["model"] = str(provider.get("model"))
			record["provider_host"] = Limits.hostname(str(provider.get("base_url")))
		record.parts.system = maxi(0,str(event.get("system","")).length()-int(record.parts.tools))
		record.parts.messages = str(event.get("user","")).length()+str(event.get("dossier","")).length()
		return

func transport_request_id(channel: String, provider: Node=null) -> String:
	# Slots have one live transport. Capture this ID before a native callback can
	# retire the task or reuse the slot; never attribute a response by channel alone.
	for key: String in _transport:
		var record: Dictionary=_transport[key]
		if record.channel==channel and (provider==null or record.provider==provider) and current(str(record.task)):return key
	return ""

func note_final_usage_request(event: Dictionary) -> void:
	var key: String=transport_request_id(str(event.get("channel","")))
	for record: Dictionary in _usage_pending:
		if record.id!=key:continue
		record["fingerprint"]=_usage_fingerprint(event)
		_set_usage_parts(record,str(event.get("system","")).length(),str(event.get("user","")).length()+str(event.get("dossier","")).length())
		return

func _set_usage_parts(record: Dictionary, system_chars: int, message_chars: int) -> void:
	var tools: int=clampi(int(record.parts.get("tools",0)),0,system_chars)
	record.parts={"system":system_chars-tools,"tools":tools,"messages":message_chars}

func note_transport_identity(event: Dictionary, model: String, provider_host: String) -> void:
	var fingerprint: String = _usage_fingerprint(event)
	var key: String=transport_request_id(str(event.get("channel","")))
	for record: Dictionary in _usage_pending:
		if record.channel != str(event.get("channel","")):continue
		if (key!="" and record.id!=key) or (key=="" and record.get("fingerprint",fingerprint)!=fingerprint):continue
		record["fingerprint"]=fingerprint
		record["model"] = model
		record["provider_host"] = provider_host
		_set_usage_parts(record,str(event.get("system","")).length(),str(event.get("user","")).length()+str(event.get("dossier","")).length())
		return

func note_transport_query(channel: String, provider: Node, query: Array) -> String:
	var key: String=transport_request_id(channel,provider)
	if key=="" or query.size()!=3 or not query[2] is Dictionary:return key
	for record: Dictionary in _usage_pending:
		if record.id!=key:continue
		record["model"]=str(query[2].get("model",record.get("model","")))
		record["provider_host"]=Limits.hostname(str(query[0]))
		var system_chars: int=_usage_text_chars(query[2].get("system",""));var message_chars:=0
		for message: Dictionary in query[2].get("messages",[]):
			var count: int=_usage_text_chars(message.get("content",""))
			if message.get("role") in ["system","developer"]:system_chars+=count
			else:message_chars+=count
		_set_usage_parts(record,system_chars,message_chars)
		break
	return key

static func _usage_text_chars(content: Variant) -> int:
	if content is String:return content.length()
	var count:=0
	if content is Array:
		for block: Variant in content:
			if block is Dictionary and block.get("type")=="text" and block.get("text") is String:count+=block.text.length()
	return count

func record_transport_usage(key: String, code: int, bytes: PackedByteArray) -> void:
	if key=="" or code<200 or code>=300:return
	var body: Variant=JSON.parse_string(bytes.get_string_from_utf8())
	if not body is Dictionary:return
	for record: Dictionary in _usage_pending:
		if record.id==key:
			_commit_usage(record,body.get("usage",{}) if body.get("usage") is Dictionary else {})
			return

func _commit_usage(record: Dictionary, usage: Dictionary) -> void:
	_usage_pending.erase(record)
	if record.generation != _owner._source_generation:return
	_owner._chat_usage(record.target,{"id":record.id,"elapsed_ms":maxi(0,Time.get_ticks_msec()-int(record.started_ms)),"usage":usage,"context_limit":record.context_limit,"parts":record.parts,"model":str(record.get("model","")),"provider_host":str(record.get("provider_host",""))})

func _usage_fingerprint(event: Dictionary) -> String:
	return (str(event.get("system",""))+"\n"+str(event.get("user",""))+"\n"+str(event.get("dossier",""))).sha256_text()

func record_usage(event: Dictionary) -> void:
	var fingerprint: String = _usage_fingerprint(event)
	for record: Dictionary in _usage_pending:
		if record.channel != str(event.get("channel","")) or record.get("fingerprint",fingerprint) != fingerprint: continue
		_commit_usage(record,event.get("usage",{}) if event.get("usage") is Dictionary else {})
		return

func stream_owned(channel: String) -> bool:
	if "vision_support" in _owner and is_instance_valid(_owner.vision_support) and _owner.vision_support.is_probe_channel(channel): return true
	if channel == "mod_pax_harness_chat_compact" and _owner.chat_compactor != null and _owner.chat_compactor.busy(): return true
	for record: Dictionary in _transport.values():
		if record.get("channel") != channel or not current(str(record.task)): continue
		return _tasks[record.task].has("chat_target")
	return false

func stream_text(channel: String, text: String) -> void:
	for key: String in _transport:
		var record: Dictionary = _transport[key]
		if record.get("channel") != channel or not current(str(record.task)): continue
		var task: Dictionary = _tasks[record.task]
		if record.get("analysis_child",false): return
		if task.has("chat_target"): _owner._chat_stream_text(task.chat_target,key,text)
		return

func stream_error(channel: String, code: String) -> void:
	for record: Dictionary in _transport.values():
		if record.get("channel") == channel: record["stream_error"] = code

func stream_failure(channel: String, failure: Dictionary) -> void:
	if channel == "mod_pax_harness_chat_compact" and _owner.chat_compactor != null: _owner.chat_compactor.transport_failure = failure.duplicate(true)
	for record: Dictionary in _transport.values():
		if record.get("channel") == channel:
			record["stream_error"] = str(failure.code)
			record["stream_failure"] = failure.duplicate(true)

func stream_retry(channel: String, payload: Dictionary) -> void:
	if channel == "mod_pax_harness_chat_compact" and _owner.chat_compactor != null:
		for job: Dictionary in _owner.chat_compactor.jobs.values(): job.store.record(job.target,"network.retry",payload)
	for record: Dictionary in _transport.values():
		if record.get("channel") == channel and current(str(record.task)):
			_owner._chat_event("network.retry",payload,str(record.task))

func cancel_analysis(job_id: int) -> void:
	_cancelled_analysis[job_id] = true
	for key: String in _transport.keys():
		var record: Dictionary = _transport[key]
		if int(record.get("analysis_job_id",0)) != job_id: continue
		_transport.erase(key)
		if is_instance_valid(record.provider) and record.callback.is_valid() and record.provider.is_connected("channel_ready",record.callback): record.provider.disconnect("channel_ready",record.callback)
		if is_instance_valid(_owner.chat_stream): _owner.chat_stream.cancel(str(record.channel))

func normalize_response(channel: String, bytes: PackedByteArray) -> PackedByteArray:
	for key: String in _transport:
		var record: Dictionary = _transport[key]
		if record.get("channel") == channel and current(str(record.task)):
			return Envelope.response(bytes,key)
	return bytes
