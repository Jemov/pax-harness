extends RefCounted
## Pure protocol adaptation: no provider/model allowlists, credentials, I/O or cache.
const MAX_BUDGET := 10000000
const MAX_ERROR_BYTES := 65536

static func _parts(query: Array) -> bool:
	if query.size() != 3 or not query[0] is String or not query[2] is Dictionary: return false
	if not query[1] is Array and not query[1] is PackedStringArray: return false
	for header: Variant in query[1]:
		if not header is String: return false
	return query[2].get("model") is String and not query[2].model.is_empty() and query[2].model.length() <= 256

static func _base(value: String) -> String:
	var base := value.strip_edges().trim_suffix("/")
	# The exact comparison includes scheme, authority, port and full base path.
	if RegEx.create_from_string("^https?://(?:[A-Za-z0-9.-]+|\\[[A-Fa-f0-9:]+\\])(?::[0-9]{1,5})?(?:/[A-Za-z0-9._~!$&'()*+,;=:%-]+)*$").search(base) == null: return ""
	return base

static func _budget(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= MAX_BUDGET and value == floorf(float(value))

static func _budgets(body: Dictionary) -> bool:
	for field: String in ["max_tokens","max_completion_tokens"]:
		if body.has(field) and not _budget(body[field]): return false
	return true

static func _text_content(content: Variant) -> bool:
	if content is String: return true
	if not content is Array or content.is_empty(): return false
	for block: Variant in content:
		if not block is Dictionary or block.size() != 2 or block.get("type") != "text" or not block.get("text") is String: return false
	return true

static func _image_source(block: Dictionary) -> Dictionary:
	if block.size() != 2 or block.get("type") != "image_url" or not block.get("image_url") is Dictionary: return {}
	var image: Dictionary = block.image_url
	if image.size() != 1 or not image.get("url") is String or image.url.length() > 2800000: return {}
	var found: RegExMatch = RegEx.create_from_string("^data:(image/(?:png|jpeg));base64,([A-Za-z0-9+/]+={0,2})$").search(image.url)
	if found == null: return {}
	return {"type":"base64","media_type":found.get_string(1),"data":found.get_string(2)}

static func _chat_content(content: Variant, allow_images: bool) -> bool:
	if _text_content(content): return true
	if not allow_images or not content is Array or content.is_empty(): return false
	for block: Variant in content:
		if not block is Dictionary: return false
		if block.size() == 2 and block.get("type") == "text" and block.get("text") is String: continue
		if _image_source(block).is_empty(): return false
	return true

static func _text_chat(body: Dictionary) -> bool:
	if not body.get("messages") is Array or body.messages.is_empty() or not _budgets(body): return false
	if body.has("stream") and not body.stream is bool: return false
	for row: Variant in body.messages:
		if not row is Dictionary or row.size() != 2 or row.get("role") not in ["system","user","assistant"] or not _chat_content(row.get("content"),row.get("role") == "user"): return false
	for field: String in ["tools","tool_choice","functions","function_call","audio","modalities","input","contents","system"]:
		if body.has(field): return false
	return true

static func _native_messages(body: Dictionary) -> bool:
	if not body.get("messages") is Array or body.messages.is_empty(): return false
	if body.has("system") and not body.system is String and not body.system is Array: return false
	for row: Variant in body.messages:
		if not row is Dictionary or row.get("role") not in ["user","assistant"] or not (row.get("content") is String or row.get("content") is Array): return false
	return _budgets(body)

static func adapt(query: Array, base_url: String, model: String, capabilities: Dictionary = {}) -> Array:
	if not _parts(query): return query
	var base := _base(base_url)
	if base.is_empty() or query[2].model != model or query[0] not in [base+"/chat/completions",base+"/messages"]: return query
	var body: Dictionary = query[2]
	if query[0] == base+"/messages" and _native_messages(body):
		var native: Array = query.duplicate(true)
		_options(native[2],capabilities,false)
		return native
	if not _text_chat(body): return query
	# An explicit structured schema belongs to its native owner.
	if body.has("response_format") and body.response_format != {"type":"json_object"}: return query
	if query[0] == base+"/messages" or capabilities.get("protocol") == "messages": return _messages(query,base,capabilities)
	var result: Array = query.duplicate(true)
	_options(result[2],capabilities,true)
	return result

static func _options(output: Dictionary, capabilities: Dictionary, auto_json: bool) -> void:
	if capabilities.get("json_mode",true) == false:
		if output.get("response_format") == {"type":"json_object"}: output.erase("response_format")
	elif auto_json and not output.has("response_format"): output["response_format"] = {"type":"json_object"}
	if capabilities.get("omit_temperature",false) == true: output.erase("temperature")
	if capabilities.get("omit_reasoning_effort",false) == true: output.erase("reasoning_effort")
	if capabilities.get("stream",true) == false:
		output.erase("stream"); output.erase("stream_options")
	elif capabilities.get("stream_options",true) == false: output.erase("stream_options")

static func _messages(query: Array, base: String, capabilities: Dictionary) -> Array:
	var source: Dictionary = query[2]
	for key: Variant in source:
		if key not in ["model","messages","max_tokens","max_completion_tokens","temperature","top_p","reasoning_effort","stream","stream_options","stop","response_format"]: return query
	if not source.has("max_tokens") and not source.has("max_completion_tokens"): return query
	if source.has("max_tokens") and source.has("max_completion_tokens") and source.max_tokens != source.max_completion_tokens: return query
	if source.has("reasoning_effort") and source.reasoning_effort != "none" and capabilities.get("omit_reasoning_effort",false) != true: return query
	if source.has("temperature") and capabilities.get("omit_temperature",false) != true:
		if not (source.temperature is int or source.temperature is float) or not is_finite(float(source.temperature)) or source.temperature < 0 or source.temperature > 2: return query
	if source.has("top_p") and (not (source.top_p is int or source.top_p is float) or not is_finite(float(source.top_p)) or source.top_p < 0 or source.top_p > 1): return query
	if source.has("stream_options"):
		if not source.stream_options is Dictionary: return query
		for key: Variant in source.stream_options:
			if key != "include_usage" or not source.stream_options[key] is bool: return query
	var messages: Array = []; var system: Array = []
	for row: Dictionary in source.messages:
		var blocks: Array = [{"type":"text","text":row.content}] if row.content is String else row.content.duplicate(true)
		for index: int in blocks.size():
			if blocks[index].get("type") == "image_url":
				var image: Dictionary = _image_source(blocks[index])
				if image.is_empty(): return query
				blocks[index] = {"type":"image","source":image}
		if row.role == "system":
			if not messages.is_empty(): return query
			system.append_array(blocks)
		else: messages.append({"role":row.role,"content":blocks})
	if messages.is_empty() or messages[0].role != "user": return query
	var body := {"model":source.model,"max_tokens":int(source.get("max_completion_tokens",source.get("max_tokens"))),"messages":messages,"stream":false}
	if capabilities.get("stream",true) == false: body.erase("stream")
	if not system.is_empty(): body["system"] = system
	if source.has("temperature") and capabilities.get("omit_temperature",false) != true: body["temperature"] = source.temperature
	if source.has("top_p"): body["top_p"] = source.top_p
	if source.has("stop") and source.stop != null:
		if not source.stop is String and not source.stop is Array: return query
		var stops: Array = [source.stop] if source.stop is String else source.stop
		if stops.is_empty() or stops.size() > 4: return query
		for stop: Variant in stops:
			if not stop is String or stop.is_empty() or stop.length() > 1000: return query
		body["stop_sequences"] = stops.duplicate()
	var headers: Variant = query[1].duplicate()
	var version_seen := false
	for header: String in headers:
		if header.strip_edges().to_lower().begins_with("anthropic-version:"): version_seen = true
	if not version_seen: headers.append("anthropic-version: 2023-06-01")
	return [base+"/messages",headers,body]

## Read only bounded JSON error fields. Never return the raw diagnostic text.
static func _error_fields(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_ERROR_BYTES: return {}
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary or not parsed.has("error"): return {}
	var raw: Variant = parsed.error
	if raw is String: raw = {"message":raw}
	if not raw is Dictionary: return {}
	return _nested_error(raw,0)

static func _nested_error(raw: Dictionary, depth: int) -> Dictionary:
	var result := {"message":"","param":"","code":"","type":"","block_text":""}
	for field: String in ["message","param","code","type"]:
		if raw.get(field) is String: result[field] = raw[field].left(4096 if field == "message" else 256)
	# Retain outer authentication/context evidence even when its message is a
	# serialized upstream envelope. These internal fields are never returned.
	result.block_text = result.message+" "+result.code+" "+result.type
	var messages: Array = []
	if raw.get("message") is String: messages.append(raw.message)
	var metadata: Variant = raw.get("metadata")
	if metadata is Dictionary and metadata.get("raw") is String: messages.append(metadata.raw)
	# Do not regex-scan embedded JSON fragments in prose as if they were an error.
	if "{" in result.message or "[" in result.message: result.message = ""
	if depth >= 2: return result
	for text: String in messages:
		if text.to_utf8_buffer().size() > 16384: continue
		var parser := JSON.new()
		if parser.parse(text) != OK: continue
		var nested: Variant = parser.data
		if not nested is Dictionary or not nested.get("error") is Dictionary: continue
		var child: Dictionary = _nested_error(nested.error,depth+1)
		result.message = (str(result.message)+"; "+str(child.message)).left(8192)
		result.block_text = (str(result.block_text)+" "+str(child.block_text)).left(24576)
		for field: String in ["code","type"]: result[field] = (str(result[field])+" "+str(child[field])).left(768)
		if not str(child.param).is_empty(): result.param = child.param
	return result

static func _unsupported(error: Dictionary, field: String) -> bool:
	var message: String = str(error.message).to_lower()
	var parameter: String = str(error.param).strip_edges().to_lower()
	var causes := "unsupported|not supported|no longer supported|deprecated|does not support|unknown|unrecognized|not allowed|not permitted|not accepted|unexpected|extra inputs are not permitted"
	if (parameter == field or parameter.begins_with(field+".")) and RegEx.create_from_string(causes).search(message+" "+str(error.code).to_lower()) != null: return true
	if not parameter.is_empty(): return false
	var name := "\\b"+field+"\\b"
	var before := "(?:"+causes+")[^.,;\\n]{0,70}"+name
	var after := name+"[^.,;\\n]{0,70}(?:unsupported|not supported|no longer supported|deprecated|not allowed|not permitted|not accepted|unrecognized|unexpected)"
	return RegEx.create_from_string(before).search(message) != null or RegEx.create_from_string(after).search(message) != null

static func _messages_required(text: String, base: String) -> bool:
	var before := "(?:use|requires?|must|only supports?|only available|only supported|instead|send requests? to)[^.;\\n]{0,100}/messages\\b"
	var after := "/messages\\b[^.;\\n]{0,40}(?:is required|must be used|is the only)"
	var target: String = (base+"/messages").to_lower()
	var relative: String = text.replace(target,"/messages")
	if RegEx.create_from_string(before).search(relative) == null and RegEx.create_from_string(after).search(relative) == null: return false
	var plain: String = text
	for delimiter: String in [char(34),char(39),char(96),"(",")",",",";","\n","\t"]: plain = plain.replace(delimiter," ")
	var tokens: Array = []
	for token: String in plain.split(" ",false): tokens.append(token.trim_suffix(".").trim_suffix(":"))
	if "/messages" not in tokens and target not in tokens: return false
	for token: String in tokens:
		if (token.begins_with("https://") or token.begins_with("http://")) and token != target: return false
	return true

static func recover(query: Array, status: int, bytes: PackedByteArray) -> Dictionary:
	if status not in [400,404,405,415,422] or not _parts(query): return {}
	var suffix: String = "/chat/completions" if query[0].ends_with("/chat/completions") else "/messages" if query[0].ends_with("/messages") else ""
	if suffix.is_empty(): return {}
	var base := _base(str(query[0]).trim_suffix(suffix))
	if base.is_empty() or query[0] != base+suffix: return {}
	var native: bool = suffix == "/messages" and _native_messages(query[2])
	if not native and not _text_chat(query[2]): return {}
	var error := _error_fields(bytes)
	if error.is_empty(): return {}
	var text: String = (str(error.message)+" "+str(error.code)+" "+str(error.type)).to_lower()
	var blocked_text: String = str(error.get("block_text",text)).to_lower()
	for blocked: String in ["unauthorized","authentication","api key","api_key","authorization","permission denied","forbidden","access denied","quota","rate limit","rate_limit","credit","billing","payment","context_length","context length","context window","maximum context","max context","token limit","too many tokens","prompt is too long","input too long","unknown model","model not found","model_not_found","no such model"]:
		if blocked in blocked_text: return {}
	var result: Array = query.duplicate(true)
	var body: Dictionary = result[2]
	var delta: Dictionary = {}; var reasons: Array[String] = []
	if body.get("response_format") == {"type":"json_object"} and _unsupported(error,"response_format"):
		body.erase("response_format"); delta["json_mode"] = false; reasons.append("json_mode_unsupported")
	for field: String in ["temperature","reasoning_effort","stream_options"]:
		if body.has(field) and _unsupported(error,field):
			body.erase(field)
			delta[{"temperature":"omit_temperature","reasoning_effort":"omit_reasoning_effort","stream_options":"stream_options"}[field]] = false if field == "stream_options" else true
			reasons.append(field+"_unsupported")
	if body.has("stream") and _unsupported(error,"stream"):
		body.erase("stream"); body.erase("stream_options"); delta["stream"] = false; reasons.append("stream_unsupported")
	if suffix == "/chat/completions" and _messages_required(text,base):
		var caps: Dictionary = delta.duplicate(); caps["protocol"] = "messages"
		var converted: Array = adapt(result,base,str(body.model),caps)
		if converted[0] == base+"/messages":
			result = converted; delta["protocol"] = "messages"; reasons.append("messages_endpoint_required")
	if delta.is_empty() or result == query: return {}
	return {"query":result,"capabilities":delta,"reason":reasons[0] if reasons.size() == 1 else "multiple_capabilities_unsupported"}
