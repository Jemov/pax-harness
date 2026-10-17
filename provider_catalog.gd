extends Node
## Optional same-origin GET metadata. Never gates transport or stores credentials.
const Limits = preload("res://mods/pax_harness/provider_limits.gd")
const MAX_BODY := 4 * 1024 * 1024
const TIMEOUT_MS := 8000
const TTL_MS := 30 * 60 * 1000
const MAX_KEYS := 32
signal completed(provider_instance_id: int)
var _owner: Node
var _cache: Dictionary = {}
var _pending: Dictionary = {}

func setup(owner: Node) -> void:
	_owner = owner

func _now_ms() -> int:
	return Time.get_ticks_msec()

func _identity(provider: Node) -> Dictionary:
	if not is_instance_valid(provider) or provider.is_queued_for_deletion(): return {}
	var properties: Array = provider.get_property_list().map(func(row: Dictionary): return str(row.name))
	for field: String in ["model","base_url","local_window"]:
		if field not in properties: return {}
	var model: String = str(provider.get("model")).strip_edges()
	var base: String = Limits.api_base(str(provider.get("base_url")))
	if base == "" or model == "" or model.length() > 512: return {}
	var id: int = provider.get_instance_id()
	return {"key":JSON.stringify([id,base,model]),"id":id,"base":base,"model":model}

func _clean() -> void:
	var now: int = _now_ms()
	for key: String in _cache.keys():
		if int(_cache[key].expires) <= now: _cache.erase(key)
	for key: String in _pending.keys():
		if now-int(_pending[key].started) >= TIMEOUT_MS:
			_finish(key,HTTPRequest.RESULT_TIMEOUT,0,PackedStringArray(),PackedByteArray())

func ensure(provider: Node, query: Array) -> void:
	_clean()
	var identity: Dictionary = _identity(provider)
	if identity.is_empty(): return
	var key: String = identity.key
	if _cache.has(key) or _pending.has(key): return
	# Only the native ordinary OpenAI-compatible route supplies listing auth.
	if query.size() != 3 or not query[0] is String or not query[2] is Dictionary: return
	if Limits.api_base(str(query[0]).trim_suffix("/chat/completions")) != identity.base or not str(query[0]).ends_with("/chat/completions"): return
	if str(query[2].get("model","")) != identity.model: return
	if not query[1] is Array and not query[1] is PackedStringArray: return
	var headers := PackedStringArray()
	for header: Variant in query[1]:
		if not header is String or "\r" in header or "\n" in header: return
		headers.append(header)
	for old: String in _pending.keys():
		if int(_pending[old].id) == int(identity.id): _cancel(old)
	if _pending.size() >= MAX_KEYS or not is_inside_tree(): return
	var http := _new_http()
	if not is_instance_valid(http): return
	http.timeout = TIMEOUT_MS / 1000.0
	http.body_size_limit = MAX_BODY
	http.max_redirects = 0
	add_child(http)
	var callback: Callable = _http_completed.bind(key)
	http.request_completed.connect(callback,CONNECT_ONE_SHOT)
	_pending[key] = {"id":identity.id,"base":identity.base,"model":identity.model,"http":http,"callback":callback,"started":_now_ms()}
	var error: int = _dispatch(http,identity.base+"/models",headers)
	if error != OK: _finish(key,HTTPRequest.RESULT_CANT_CONNECT,0,PackedStringArray(),PackedByteArray())

func _new_http() -> HTTPRequest:
	return HTTPRequest.new()

func _dispatch(http: HTTPRequest, url: String, headers: PackedStringArray) -> int:
	return http.request(url,headers,HTTPClient.METHOD_GET)

func _http_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, key: String) -> void:
	_finish(key,result,code,headers,body)

func _finish(key: String, result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _pending.has(key): return
	var record: Dictionary = _pending[key]
	_pending.erase(key)
	_dispose(record)
	var entry: Dictionary = {}
	var caps: Dictionary = {}
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and body.size() <= MAX_BODY:
		var metadata: Dictionary = parse_metadata(body,str(record.model),str(record.base))
		entry = metadata.get("context",{})
		caps = metadata.get("capabilities",{})
	if _cache.size() >= MAX_KEYS and not _cache.has(key):
		var oldest: String = str(_cache.keys()[0])
		for candidate: String in _cache:
			if int(_cache[candidate].used) < int(_cache[oldest].used): oldest = candidate
		_cache.erase(oldest)
	_cache[key] = {"entry":entry,"capabilities":caps,"expires":_now_ms()+TTL_MS,"used":_now_ms()}
	completed.emit(int(record.id))

static func _integer(value: Variant) -> int:
	if not (value is int or value is float) or value is bool: return 0
	if not is_finite(float(value)) or value <= 0 or value > 10000000 or float(value) != floorf(float(value)): return 0
	return int(value)

static func parse_metadata(bytes: PackedByteArray, model: String, base: String) -> Dictionary:
	if bytes.size() > MAX_BODY or Limits.api_base(base) == "": return {}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return {}
	var value: Variant = parser.data
	var rows: Variant = value.get("data",value.get("models",[])) if value is Dictionary else value
	if not rows is Array: return {}
	var selected: Dictionary = {}
	var found := false
	for row: Variant in rows:
		if not row is Dictionary or row.get("id") != model: continue
		if found: return {} # Ambiguous duplicated IDs are not reliable capabilities.
		found = true
		selected = row
	if not found: return {}
	var tokens := 0
	for field: String in ["context_length","context_window","max_input_tokens","context_size"]:
		var amount: int = _integer(selected.get(field))
		if amount > 0: tokens = amount if tokens == 0 else mini(tokens,amount)
	for container: String in ["limits","metadata","capabilities","config","model"]:
		var nested: Variant = selected.get(container)
		if nested is Dictionary:
			var amount: int = _integer(nested.get("context_size"))
			if amount > 0: tokens = amount if tokens == 0 else mini(tokens,amount)
	var caps: Dictionary = {}
	var endpoints: Variant = selected.get("supported_endpoints")
	if endpoints is Array and endpoints.all(func(item: Variant): return item is String):
		if "/messages" in endpoints and "/chat/completions" not in endpoints: caps["protocol"] = "messages"
	var parameters: Variant = selected.get("supported_parameters")
	if parameters is Array and parameters.all(func(item: Variant): return item is String):
		caps["json_mode"] = "response_format" in parameters
	return {"context":{"context_tokens":tokens,"api_base":Limits.api_base(base)} if tokens > 0 else {},"capabilities":caps}

static func parse_entry(bytes: PackedByteArray, model: String, base: String) -> Dictionary:
	return parse_metadata(bytes,model,base).get("context",{})

func snapshot(provider: Node) -> Dictionary:
	_clean()
	var identity: Dictionary = _identity(provider)
	if identity.is_empty() or not _cache.has(identity.key): return {}
	var record: Dictionary = _cache[identity.key]
	record.used = _now_ms()
	return {identity.model:record.entry.duplicate(true)} if not record.entry.is_empty() else {}

func pending(provider: Node) -> bool:
	_clean()
	var identity: Dictionary = _identity(provider)
	return not identity.is_empty() and _pending.has(identity.key)

func capabilities(provider: Node) -> Dictionary:
	_clean()
	var identity: Dictionary = _identity(provider)
	if identity.is_empty() or not _cache.has(identity.key): return {}
	var record: Dictionary = _cache[identity.key]
	record.used = _now_ms()
	return record.capabilities.duplicate(true)

func _dispose(record: Dictionary) -> void:
	var http: HTTPRequest = record.http
	if not is_instance_valid(http): return
	if http.request_completed.is_connected(record.callback): http.request_completed.disconnect(record.callback)
	http.cancel_request()
	http.queue_free()

func _cancel(key: String) -> void:
	if not _pending.has(key): return
	var record: Dictionary = _pending[key]
	_pending.erase(key)
	_dispose(record)

func cancel_all() -> void:
	for key: String in _pending.keys(): _cancel(key)

func _exit_tree() -> void:
	cancel_all()
