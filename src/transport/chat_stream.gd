extends Node
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Nonblocking transport for owned text requests (OpenAI SSE or complete Messages).
const Parser = preload("res://mods/pax_harness/src/transport/chat_stream_parser.gd")
const Failure = preload("res://mods/pax_harness/src/core/runtime_error.gd")
const Protocol = preload("res://mods/pax_harness/src/transport/provider_protocol.gd")
const Vision = preload("res://mods/pax_harness/src/transport/vision_payload.gd")
const MAX_RETRIES := 3
const MAX_CAPABILITY_REPAIRS := 4
const CAPABILITY_TTL_MS := 1800000
var owner_mod: Node
var active: Dictionary = {}
var _capabilities: Dictionary = {}
var _serial: int = 0
var received_updates: int = 0
var completed_requests: int = 0

func setup(value: Node) -> void: owner_mod = value

func start(provider: Node, destination: HTTPRequest, query: Array, channel: String, direct: bool) -> bool:
	if not owner_mod._router.stream_owned(channel) or query.size() != 3 or active.has(channel): return false
	if not direct and not provider.has_method("requests"): return false
	var body: Variant = query[2]
	var url: String = str(query[0])
	if not body is Dictionary or not body.get("messages") is Array: return false
	if not url.ends_with("/messages") and not url.ends_with("/chat/completions"): return false
	var parts: Dictionary = endpoint(url)
	if parts.is_empty(): return false
	var cache_key: String = str(provider.get_instance_id())+"|"+url+"|"+str(body.get("model",""))
	var learned: Dictionary = owner_mod._provider_capabilities(provider) if owner_mod.has_method("_provider_capabilities") else {}
	learned.merge(_cached(cache_key),true)
	var base: String = url.trim_suffix("/chat/completions").trim_suffix("/messages")
	var prepared: Array = Protocol.adapt(query,base,str(body.get("model","")),learned)
	var tuned: Dictionary = owner_mod.prepare_generation_query(provider,prepared,channel) if owner_mod.has_method("prepare_generation_query") else {"ok":true,"query":prepared}
	if not tuned.get("ok",false):
		var failure: Dictionary = Failure.make(str(tuned.get("code","manual_generation_settings_invalid")),{"errors":tuned.get("errors",[])})
		failure.message = L.text("Запрос не отправлен: ")+"; ".join(PackedStringArray(tuned.get("errors",[])))
		if owner_mod._router.has_method("stream_failure"): owner_mod._router.stream_failure(channel,failure)
		provider._curl_answer.call_deferred(destination,400,JSON.stringify({"error":{"code":failure.code}}).to_utf8_buffer())
		return true
	prepared = tuned.query
	var timeout_override: float = float(tuned.get("timeout_seconds",0))
	if timeout_override > 0: destination.timeout = timeout_override
	var client := HTTPClient.new()
	_serial += 1
	active[channel] = {"client":client,"provider":provider,"destination":destination,
		"sent":false,"response":false,"sse":false,"code":0,"raw":PackedByteArray(),"parser":Parser.new(),"expected_bytes":-1,"received_bytes":0,
		"direct":direct,"serial":_serial,"native_http":null,"cache_key":cache_key,"capabilities":learned,"capability_repairs":0,
		"protected_fields":tuned.get("protected_fields",[]).duplicate(),"manual_rejection":[],"max_wire_bytes":8388608,
		"attempt":0,"retry_at":0,"retry_after":"","last_activity":Time.get_ticks_msec(),"started":Time.get_ticks_msec(),"timeout":maxf(1 if timeout_override > 0 else 30,destination.timeout)*1000,"last_emit":0,"shown":""}
	if owner_mod.has_method("vision_context"):active[channel]["vision_identity"]=owner_mod.vision_context(provider)
	_set_query(active[channel],prepared)
	var record: Dictionary = active[channel]
	if owner_mod._router.has_method("note_transport_query"):record["usage_request_id"]=owner_mod._router.note_transport_query(channel,provider,prepared)
	if direct:
		var connected: int = client.connect_to_host(str(record.endpoint.host),int(record.endpoint.port),TLSOptions.client() if record.endpoint.tls else null)
		if connected != OK:
			_close(channel)
			return false
	else: _send_native.call_deferred(channel,int(record.serial))
	set_process(true)
	return true

func _cached(key: String) -> Dictionary:
	if not _capabilities.has(key): return {}
	if Time.get_ticks_msec() >= int(_capabilities[key].expires_ms):
		_capabilities.erase(key)
		return {}
	return _capabilities[key].capabilities.duplicate(true)

func clear_capabilities() -> void: _capabilities.clear()

func _set_query(r: Dictionary, query: Array) -> void:
	var request: Dictionary = query[2].duplicate(true)
	var messages_protocol: bool = str(query[0]).ends_with("/messages")
	# Proxy/tunnel traffic uses the game's complete-response transport.
	var streaming: bool = bool(r.direct) and not messages_protocol and r.capabilities.get("stream",true) != false
	if r.capabilities.get("stream",true) == false: request.erase("stream")
	else: request["stream"] = streaming
	if not streaming or r.capabilities.get("stream_options",true) == false: request.erase("stream_options")
	else: request["stream_options"] = {"include_usage":true}
	var headers := PackedStringArray()
	for header: String in query[1]:
		if header.to_lower().begins_with("accept:") or header.to_lower().begins_with("accept-encoding:"): continue
		headers.append(header)
	headers.append("Accept: text/event-stream" if streaming else "Accept: application/json")
	headers.append("Accept-Encoding: identity")
	r.query = [query[0],headers,request]
	r.endpoint = endpoint(str(query[0]))
	r.path = r.endpoint.path
	r.headers = headers
	r.body = JSON.stringify(request)
	r.messages_protocol = messages_protocol
	r.image_request = Vision.contains_images(r.query)

func _vision_gate(channel: String, r: Dictionary) -> bool:
	if not r.get("image_request",false): return true
	var checked: Dictionary = owner_mod._router.validate_images(r.provider,channel,true) if owner_mod._router.has_method("validate_images") else {"ok":false,"code":"vision_image_resolver_unavailable"}
	if checked.get("ok",false): return true
	_fail(channel,str(checked.get("code","vision_input_disabled")),false)
	return false

func _send_native(channel: String, serial: int) -> void:
	if not active.has(channel) or int(active[channel].serial) != serial: return
	var r: Dictionary = active[channel]
	if not is_instance_valid(r.provider) or not is_instance_valid(r.destination):
		_close(channel)
		return
	if not _vision_gate(channel,r): return
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = maxf(1,float(r.timeout)/1000)
	http.set_meta("channel",channel)
	r.native_http = http
	http.request_completed.connect(_native_answer.bind(channel,serial,http),CONNECT_ONE_SHOT)
	r.sent = true
	var sent: bool = r.provider.requests()._dispatch_gigachat(http,r.body,r.headers,str(r.query[0]),channel)
	if not sent: _native_answer.call_deferred(HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray(),channel,serial,http)

func _native_answer(_result: int, code: int, headers: PackedStringArray, bytes: PackedByteArray, channel: String, serial: int, http: HTTPRequest) -> void:
	if not active.has(channel) or int(active[channel].serial) != serial or active[channel].native_http != http:
		if is_instance_valid(http): http.queue_free()
		return
	var r: Dictionary = active[channel]
	r.native_http = null
	if is_instance_valid(http): http.queue_free()
	if bytes.size() > int(r.get("max_wire_bytes",8388608)):
		_fail(channel,"generation_response_too_large",false)
		return
	r.response = code > 0
	r.code = code
	r.raw = bytes
	r.last_activity = Time.get_ticks_msec()
	for header: String in headers:
		if header.to_lower().begins_with("retry-after:"): r.retry_after = header.substr(header.find(":")+1).strip_edges()
	_complete(channel)

static func endpoint(url: String) -> Dictionary:
	var tls: bool = url.begins_with("https://")
	# Plain HTTP is restricted to deterministic loopback transport tests.
	if not tls and not url.begins_with("http://127.0.0.1:"): return {}
	var rest: String = url.substr(8 if tls else 7)
	var slash: int = rest.find("/")
	if slash < 1: return {}
	var host: String = rest.left(slash)
	if "@" in host or "#" in url: return {}
	var port: int = 443 if tls else 80
	var colon: int = host.rfind(":")
	if colon >= 0:
		port = host.substr(colon+1).to_int()
		host = host.left(colon)
	if host.is_empty() or port < 1 or port > 65535: return {}
	return {"host":host,"port":port,"path":rest.substr(slash),"tls":tls}

static func idle_budget(timeout_ms: int, messages_protocol: bool) -> int:
	# Complete Messages generation need not send any chunks before its JSON body.
	# The independent started deadline still bounds the entire request/retries.
	return timeout_ms if messages_protocol else mini(90000,timeout_ms)

func _process(_delta: float) -> void:
	for channel: String in active.keys():
		if not active.has(channel): continue
		var r: Dictionary = active[channel]
		var c: HTTPClient = r.client
		if not is_instance_valid(r.destination) or not is_instance_valid(r.provider):
			_close(channel)
			continue
		if Time.get_ticks_msec()-int(r.started) > int(r.timeout):
			_fail(channel,"stream_timeout",false)
			continue
		if int(r.retry_at) > 0:
			if Time.get_ticks_msec() < int(r.retry_at): continue
			r.retry_at = 0
			r.last_activity = Time.get_ticks_msec()
			if not r.direct:
				_send_native(channel,int(r.serial))
				continue
			var connected: int = c.connect_to_host(str(r.endpoint.host),int(r.endpoint.port),TLSOptions.client() if r.endpoint.tls else null)
			if connected != OK: _fail(channel,"stream_connection_error")
			continue
		if not r.direct: continue
		if Time.get_ticks_msec()-int(r.last_activity) > idle_budget(int(r.timeout),bool(r.get("messages_protocol",false))):
			_fail(channel,"stream_timeout")
			continue
		var err: int = c.poll()
		if err != OK:
			if r.response and c.get_status() == HTTPClient.STATUS_DISCONNECTED: _complete(channel)
			else: _fail(channel,"stream_connection_error")
			continue
		var state: int = c.get_status()
		if state == HTTPClient.STATUS_CONNECTED and not r.sent:
			if not _vision_gate(channel,r): continue
			var sent: int = c.request(HTTPClient.METHOD_POST,str(r.path),r.headers,str(r.body))
			r.sent = true
			if sent != OK: _fail(channel,"stream_request_error")
			continue
		if c.has_response() and not r.response:
			r.response = true
			r.code = c.get_response_code()
			r.expected_bytes = c.get_response_body_length()
			for header: String in c.get_response_headers():
				if header.to_lower().begins_with("content-type:") and "text/event-stream" in header.to_lower(): r.sse = true
				if header.to_lower().begins_with("retry-after:"): r.retry_after = header.substr(header.find(":")+1).strip_edges()
			if int(r.code) >= 400: r.sse = false
		if state == HTTPClient.STATUS_BODY:
			for _part: int in 16:
				if c.get_status() != HTTPClient.STATUS_BODY: break
				var chunk: PackedByteArray = c.read_response_body_chunk()
				if chunk.is_empty(): break
				r.received_bytes += chunk.size()
				if int(r.received_bytes) > int(r.max_wire_bytes):
					_fail(channel,"generation_response_too_large",false)
					break
				r.last_activity = Time.get_ticks_msec()
				if r.sse: r.parser.feed(chunk)
				else:
					var raw: PackedByteArray = r.raw
					raw.append_array(chunk)
					r.raw = raw
			if not active.has(channel): continue
			if r.sse:
				_publish(channel,r)
				if r.parser.error != "": _fail(channel,str(r.parser.error))
				elif r.parser.done: _complete(channel)
			if active.has(channel) and r.response and c.get_status() in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]: _complete(channel)
		elif r.sent and state in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]:
			_complete(channel)
		elif state in [HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
			_fail(channel,"stream_connection_error")
	if active.is_empty(): set_process(false)

func _publish(channel: String, r: Dictionary, force: bool = false) -> void:
	if not force and Time.get_ticks_msec()-int(r.last_emit) < 90: return
	var text: String = Parser.message_prefix(r.parser.content)
	if text == str(r.shown): return
	r.shown = text
	r.last_emit = Time.get_ticks_msec()
	received_updates += 1
	owner_mod._router.stream_text(channel,text)

func _complete(channel: String) -> void:
	if not active.has(channel): return
	var r: Dictionary = active[channel]
	if r.direct and not r.sse and int(r.expected_bytes) >= 0 and int(r.received_bytes) != int(r.expected_bytes):
		_fail(channel,"stream_incomplete")
		return
	if int(r.code) >= 400:
		if Parser.context_error(r.raw.get_string_from_utf8()):
			_report_error(channel,Failure.make("context_length_exceeded",{},int(r.code)))
			_deliver(channel,int(r.code),r.raw)
			return
		if _capability_retry(channel): return
		if _retry(channel,Failure.make("http_"+str(r.code),{},int(r.code))): return
		_report_error(channel,Failure.make("http_"+str(r.code),{},int(r.code)))
		_deliver(channel,int(r.code),r.raw)
		return
	if not r.response:
		_fail(channel,"stream_empty_response")
		return
	if not r.sse:
		var whole: Variant = JSON.parse_string(r.raw.get_string_from_utf8())
		if whole is Dictionary:
			if whole.get("stop_reason","") in ["max_tokens","refusal"]:
				_fail(channel,"generation_truncated",false)
				return
			if whole.get("choices") is Array:
				for choice: Variant in whole.choices:
					if choice is Dictionary and choice.get("finish_reason","") in ["length","content_filter"]:
						_fail(channel,"generation_truncated",false)
						return
		_deliver(channel,int(r.code),r.raw)
		return
	r.parser.end()
	if r.parser.finish_reason in ["length","content_filter"]:
		_fail(channel,"generation_truncated",false)
		return
	if r.parser.error != "" or not r.parser.done or r.parser.content.is_empty():
		_fail(channel,"stream_incomplete")
		return
	_publish(channel,r,true)
	var result: Dictionary = {"choices":[{"index":0,"message":{"role":"assistant","content":r.parser.content},"finish_reason":r.parser.finish_reason}],"usage":r.parser.usage}
	_deliver(channel,int(r.code),JSON.stringify(result).to_utf8_buffer())

func _capability_retry(channel: String) -> bool:
	var r: Dictionary = active[channel]
	if int(r.capability_repairs) >= MAX_CAPABILITY_REPAIRS: return false
	var recovered: Dictionary = Protocol.recover(r.query,int(r.code),r.raw)
	if recovered.is_empty(): return false
	var rejected: Array = []
	for capability: String in recovered.capabilities:
		var field: String = {"omit_temperature":"temperature","omit_reasoning_effort":"reasoning_effort","json_mode":"response_format","stream_options":"stream_options","stream":"stream"}.get(capability,"")
		if field != "" and field in r.protected_fields: rejected.append(field)
	if not rejected.is_empty():
		r.manual_rejection = rejected
		return false
	# Only errors rejected before generation are eligible; a successful/partial
	# response is never replayed by this path, and the original deadline remains.
	if Time.get_ticks_msec()+1 >= int(r.started)+int(r.timeout): return false
	r.capabilities.merge(recovered.capabilities,true)
	if _capabilities.size() >= 64 and not _capabilities.has(r.cache_key): _capabilities.erase(_capabilities.keys()[0])
	_capabilities[r.cache_key] = {"capabilities":r.capabilities.duplicate(true),"expires_ms":Time.get_ticks_msec()+CAPABILITY_TTL_MS}
	r.capability_repairs += 1
	r.client.close()
	_set_query(r,recovered.query)
	r.retry_at = Time.get_ticks_msec()+1
	r.sent = false; r.response = false; r.sse = false; r.code = 0; r.retry_after = ""
	r.raw = PackedByteArray(); r.parser = Parser.new(); r.expected_bytes = -1; r.received_bytes = 0
	if owner_mod._router.has_method("stream_retry"):
		owner_mod._router.stream_retry(channel,{"attempt":r.capability_repairs,"delay_ms":0,"failure":{"code":"api_capability_adjustment","category":"compatibility","retryable":true},"adjustment":str(recovered.reason)})
	return true

func _fail(channel: String, reason: String, allow_retry: bool = true) -> void:
	# An explicit failure cannot pass a partial JSON command to the tool runner.
	var failure: Dictionary = Failure.make(reason)
	if allow_retry and _retry(channel,failure): return
	_report_error(channel,failure)
	_deliver(channel,502,JSON.stringify({"error":{"message":reason}}).to_utf8_buffer())

func _report_error(channel: String, failure: Dictionary) -> void:
	if "vision_support" in owner_mod and is_instance_valid(owner_mod.vision_support):
		var r: Dictionary=active.get(channel,{})
		var usage: Dictionary=r.parser.usage if r.get("sse",false) else {}
		owner_mod.vision_support.transport_failure(channel,str(failure.code),usage)
	if active.has(channel):
		failure.details = {"retries":active[channel].attempt,"capability_repairs":active[channel].get("capability_repairs",0),"elapsed_ms":Time.get_ticks_msec()-int(active[channel].started)}
		if not active[channel].get("manual_rejection",[]).is_empty():
			failure.details["manual_parameters_rejected"] = active[channel].manual_rejection.duplicate()
			failure.message = L.text("API отклонил заданные вручную параметры: ")+", ".join(PackedStringArray(active[channel].manual_rejection))+L.text(". Измените их в «Тонкой настройке». Ручные значения не удалены автоматически.")
	if owner_mod._router.has_method("stream_failure"): owner_mod._router.stream_failure(channel,failure)
	else: owner_mod._router.stream_error(channel,str(failure.code))

func _retry(channel: String, failure: Dictionary) -> bool:
	if not active.has(channel): return false
	var r: Dictionary = active[channel]
	if not failure.retryable or int(r.attempt) >= MAX_RETRIES: return false
	var delay: int = Failure.delay_ms(int(r.attempt)+1,str(r.retry_after))
	if Time.get_ticks_msec()+delay >= int(r.started)+int(r.timeout): return false
	r.client.close()
	r.attempt += 1
	r.retry_at = Time.get_ticks_msec()+delay
	r.sent = false; r.response = false; r.sse = false; r.code = 0; r.retry_after = ""
	r.raw = PackedByteArray(); r.parser = Parser.new(); r.shown = ""; r.expected_bytes = -1; r.received_bytes = 0
	owner_mod._router.stream_text(channel,"")
	if owner_mod._router.has_method("stream_retry"): owner_mod._router.stream_retry(channel,{"attempt":r.attempt,"delay_ms":delay,"failure":failure})
	return true

func _deliver(channel: String, code: int, bytes: PackedByteArray) -> void:
	if not active.has(channel): return
	var r: Dictionary = active[channel]
	if code >= 200 and code < 300 and owner_mod._router.has_method("normalize_response"): bytes = owner_mod._router.normalize_response(channel,bytes)
	if owner_mod._router.has_method("record_transport_usage"):owner_mod._router.record_transport_usage(str(r.get("usage_request_id","")),code,bytes)
	if "vision_support" in owner_mod and is_instance_valid(owner_mod.vision_support):owner_mod.vision_support.response(channel,code,bytes,r.get("vision_identity",{}) if r.get("image_request",false) else {})
	_close(channel)
	completed_requests += 1
	if is_instance_valid(r.provider) and is_instance_valid(r.destination): r.provider.call_deferred("_curl_answer",r.destination,code,bytes)

func _close(channel: String) -> void:
	if not active.has(channel): return
	active[channel].client.close()
	var http: Variant = active[channel].get("native_http")
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	active.erase(channel)

func cancel(channel: String) -> void:
	if active.has(channel):
		_report_error(channel,Failure.make("cancelled"))
		_deliver(channel,499,JSON.stringify({"error":{"message":"cancelled"}}).to_utf8_buffer())

func cancel_all() -> void:
	for channel: String in active.keys(): cancel(channel)

func status() -> Dictionary:
	return {"active":active.size(),"text_updates":received_updates,"completed":completed_requests}
