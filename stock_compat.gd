extends RefCounted
## Read-only adapter for the official documented UNSTABLE PaxGame.main handle.
## Stock ai_request exposes only channel/SYSTEM/USER, not native task metadata.


## Native dispatch may own an OAuth exchange beyond the built request headers.
## Ask its own predicate; never infer authentication from provider/model names.
static func native_auth_transport(value: Node) -> bool:
	if not is_instance_valid(value) or value.is_queued_for_deletion(): return false
	var base: Variant = null
	for property: Dictionary in value.get_property_list():
		if property.get("name") == "base_url": base = value.get("base_url"); break
	if not base is String: return false
	var callable_requests := false
	for method: Dictionary in value.get_method_list():
		if method.get("name") == "requests":
			callable_requests = method.get("args",[]).size() <= method.get("default_args",[]).size()
			break
	if not callable_requests: return false
	var requests: Variant = value.call("requests")
	if not (requests is Object) or not is_instance_valid(requests): return false
	var script: Variant = requests.get_script()
	if not script is Script: return false
	var native: Variant = script.get_script_constant_map().get("RussianProvidersScript")
	if not native is Script: return false
	for method: Dictionary in native.get_script_method_list():
		if method.get("name") != "gigachat": continue
		var args: Array = method.get("args",[])
		var required: int = args.size()-method.get("default_args",[]).size()
		if (int(method.get("flags",0)) & METHOD_FLAG_STATIC) == 0 or args.size() < 1 or required > 1: return false
		if int(args[0].get("type",TYPE_NIL)) not in [TYPE_NIL,TYPE_STRING]: return false
		var answer: Variant = native.call("gigachat",base)
		return answer is bool and answer
	return false


static func active(game: RefCounted) -> bool:
	if game == null:
		return false
	var main: Variant = game.get("main")
	return is_instance_valid(main) and main is Node and not main.is_queued_for_deletion()


static func provider(game: RefCounted) -> Node:
	if not active(game):
		return null
	var value: Variant = game.main.get("provider")
	return value if is_instance_valid(value) and value is Node and not value.is_queued_for_deletion() else null


static func variant(game: RefCounted, channel: String = "") -> String:
	var value: Node = provider(game)
	if value == null or not value.has_method("small") or not value.small():
		return "full"
	# Stock falls back to the full template when this channel has no small one.
	return "small" if channel != "" and value.has_method("small_prompt") and not str(value.small_prompt(channel)).is_empty() else "full"


static func contract(game: RefCounted, channel: String, request_variant: String, api: Node = null) -> Variant:
	var value: Node = provider(game)
	if value == null or not value.has_method("answer_schema"):
		return "json"
	if not contract_safe(channel,request_variant,api):
		return "json"
	return detached(value.answer_schema(channel, request_variant == "small"))


static func contract_safe(channel: String, request_variant: String, api: Node) -> bool:
	if api == null:
		return false
	if request_variant == "small":
		var schemas: Variant = api.json("res://data/prompt_small/schemas.json")
		if schemas is Dictionary and schemas.has(channel):
			return true
	# Some installed full templates contain illustrative, non-JSON notation.
	# Stock's schema reader logs an engine error when it tries that notation.
	# Preflight each candidate with the non-logging parser. A failed preflight
	# reports JSON-only/unavailable, never an invented response schema.
	var text: String = api.text("res://data/prompt_" + channel + ".txt")
	var tags := RegEx.create_from_string("Return ONLY JSON|Reply with JSON|Answer ONLY JSON|Strict JSON|WHAT YOU RETURN")
	var markers: Array[RegExMatch] = tags.search_all(text)
	if markers.is_empty():
		return false
	for marker: RegExMatch in markers:
		var cursor: int = text.find("{",marker.get_end())
		if cursor < 0:
			continue
		var start: int = cursor
		var nesting := 0
		while cursor < text.length():
			var character: String = text[cursor]
			if character == "{": nesting += 1
			if character == "}": nesting -= 1
			cursor += 1
			if nesting == 0:
				var json := JSON.new()
				if json.parse(text.substr(start,cursor-start)) != OK or not json.data is Dictionary:
					return false
				break
		if nesting != 0:
			return false
	return true


static func settings(game: RefCounted) -> Dictionary:
	var value: Node = provider(game)
	var result := {"temperature":0.2,"max_tokens":2400}
	if value != null and value.get("model") is String:
		result["model"] = value.get("model")
	return result


static func request(game: RefCounted, event: Dictionary, retained: Dictionary = {}, api: Node = null) -> Dictionary:
	var channel: String = str(event.get("channel", ""))
	var request_variant: String = variant(game,channel)
	var system: String = str(event.get("system", ""))
	var user: String = str(event.get("user", ""))
	# The full USER remains exact data; no attempt to guess JSON boundaries or
	# recover a player order from a side summary. Unknown original text is empty.
	var data: Dictionary = {"channel":channel,"variant":request_variant,"system":system,"user":user,
		"dossier":str(event.get("dossier", "")),"output_contract":contract(game,channel,request_variant,api),
		"context_available":true,"context":_task_input(game, channel, user),
		"dossier_context":{},"request_prefix":"","request_text":str(game.main.player._assistant_question) if channel == "assistant" and active(game) else "",
		"world_instructions":system,"generation_settings":settings(game),
		"stock_scope":{"fields":["system","user"],"variant_source":"current_provider_strength_and_installed_small_template",
			"task_context_available":false,"original_order_available":false,"dossier_available":false,
			"shared_instructions_separated":false,"generation_settings_captured":false,
			"unavailable_sources":["request.text","request.prefix","cache.dossier","context.dossier"]}}
	if retained.get("campaign_context") is Dictionary:
		data["campaign_context"] = retained.campaign_context.duplicate(true)
	return data


static func validate_test_settings(overrides: Dictionary) -> Dictionary:
	for key: String in overrides:
		if key not in ["temperature","max_tokens"]:
			return {"ok":false,"error":"stock_generation_unsupported:" + key}
		var value: Variant = overrides[key]
		if not (value is int or value is float) or not is_finite(float(value)):
			return {"ok":false,"error":"stock_generation_invalid:" + key}
		if key == "temperature" and (float(value) < 0 or float(value) > 2):
			return {"ok":false,"error":"stock_generation_invalid:" + key}
		if key == "max_tokens" and (float(value) != floor(float(value)) or float(value) < 1 or float(value) > 10000000):
			return {"ok":false,"error":"stock_generation_invalid:" + key}
	return {"ok":true,"error":""}


static func packet(request_value: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_test_settings(request_value.get("generation_overrides",{}))
	if not checked.ok:
		return checked
	var effective: Dictionary = request_value.get("generation_settings",{}).duplicate(true)
	effective.merge(request_value.get("generation_overrides",{}),true)
	var numeric: Dictionary = {}
	for key: String in ["temperature","max_tokens"]:
		if effective.has(key): numeric[key] = effective[key]
	checked = validate_test_settings(numeric)
	if not checked.ok:
		return checked
	var prompt: String = str(request_value.get("system", ""))
	prompt += "\n\n## Isolated mod test transport\nThe following USER data contains the compiled request to test. Do not apply any game action. Produce the requested response as JSON text inside result_json. This wrapper is the transport contract; the compiled response contract remains unchanged. Return ONLY this outer JSON object:\n{\"result_json\":\"JSON text of the requested response\"}"
	return {"ok":true,"prompt":prompt,"data":{"compiled_user":str(request_value.get("user","")),
		"compiled_dossier":str(request_value.get("dossier","")),"response_contract":detached(request_value.get("output_contract","json"))},
		"options":{"temperature":effective.get("temperature",0.2),"max_tokens":effective.get("max_tokens",2400)}}


static func answer(response: Dictionary) -> Dictionary:
	if not response.get("result_json") is String:
		return {"ok":false,"state":"failed","error":"stock_ai_empty_or_invalid_envelope","raw":"","parsed":null,
			"parse_ok":false,"raw_available":false,"diagnostics":[],"transport":"official_ask_ai_parsed"}
	var raw: String = response.result_json
	var json := JSON.new()
	var parsed_ok: bool = json.parse(raw) == OK
	return {"ok":parsed_ok,"state":"complete" if parsed_ok else "failed","error":"" if parsed_ok else "invalid_json",
		"raw":raw,"parsed":json.data if parsed_ok else null,"parse_ok":parsed_ok,"raw_available":false,
		"raw_source":"model_result_json_field","exact_wire_replay":false,"diagnostics":[],"transport":"official_ask_ai_parsed"}


static func detached(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if key is String:
				result[key] = detached(value[key])
		return result
	if value is Array:
		return value.map(func(item: Variant): return detached(item))
	if value is float:
		return value if is_finite(value) else null
	return value if value == null or value is String or value is int or value is bool else null


static func _task_input(game: RefCounted, channel: String, user: String) -> Dictionary:
	if channel == "assistant" and active(game):
		return {"player_asked":game.main.player._assistant_question,"conversation":game.main.player.assistant_history.slice(-6),"source":"live_assistant_request"}
	return {"native_user":user,"source":"stock_ai_request"}
