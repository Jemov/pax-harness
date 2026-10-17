extends RefCounted
## Explicit player configuration only; model tools can replace one selected prompt string.
const MAX_BYTES := 262144
const MAX_NODES := 256
const SENSITIVE := ["api_key","apikey","authorization","access_token","password","secret","headers","base_url","endpoint"]

static func _data(value: Variant, depth: int, count: Array) -> bool:
	count[0] += 1
	if depth > 12 or count[0] > 32768: return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or key.length() > 160 or key.to_lower() in SENSITIVE or not _data(value[key],depth+1,count): return false
	elif value is Array:
		for item: Variant in value:
			if not _data(item,depth+1,count): return false
	elif value is String:
		if value.length() > 65536: return false
	elif value is float:
		if not is_finite(value): return false
	elif value != null and not value is bool and not value is int: return false
	return true

static func choices(graph: Dictionary) -> Array:
	var result: Array = []
	for id: Variant in graph:
		var node: Variant = graph[id]
		if not id is String or not node is Dictionary or not node.get("inputs") is Dictionary: continue
		for field: Variant in node.inputs:
			if field is String and node.inputs[field] is String and field in ["text","prompt","positive_prompt"]:
				var meta: Variant = node.get("_meta",{})
				var title: String = str(meta.get("title",node.get("class_type",""))) if meta is Dictionary else str(node.get("class_type",""))
				result.append({"node":id,"input":field,"label":id+" · "+title.left(100)+" · "+field})
	return result

static func validate(graph: Dictionary, prompt_node: String = "", prompt_input: String = "text", enabled: bool = true) -> Dictionary:
	if graph.is_empty() or graph.size() > MAX_NODES or not _data(graph,0,[0]) or JSON.stringify(graph).to_utf8_buffer().size() > MAX_BYTES: return {"ok":false,"code":"images.workflow_invalid","message":"Нужен API JSON workflow до 256 узлов и 256 КиБ, без ключей доступа."}
	for id: Variant in graph:
		var node: Variant = graph[id]
		if not id is String or RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,64}$").search(id) == null or not node is Dictionary or not node.get("class_type") is String or node.class_type.is_empty() or node.class_type.length() > 160 or not node.get("inputs") is Dictionary: return {"ok":false,"code":"images.workflow_invalid","message":"Экспортируйте workflow в формате API: узлы с class_type и inputs."}
	var selected: String = prompt_node
	var field: String = prompt_input
	if selected == "":
		var candidates: Array = choices(graph)
		if candidates.size() != 1: return {"ok":false,"code":"images.workflow_prompt_ambiguous","message":"Выберите точный узел и поле положительного описания изображения."}
		selected = candidates[0].node; field = candidates[0].input
	if not graph.has(selected) or not graph[selected].inputs.get(field) is String: return {"ok":false,"code":"images.workflow_prompt_invalid","message":"В выбранном узле нужно существующее строковое поле описания."}
	return {"ok":true,"config":{"enabled":enabled,"graph":graph.duplicate(true),"prompt_node":selected,"prompt_input":field}}

static func with_prompt(config: Dictionary, prompt: String) -> Dictionary:
	var graph: Dictionary = config.graph.duplicate(true)
	graph[config.prompt_node].inputs[config.prompt_input] = prompt
	# Godot's JSON parser materializes all JSON numbers as floats. Comfy output
	# links are [existing_node_id, integer_output_port]; Python uses that port to
	# index a tuple. Restore only these unambiguous structural integer indices.
	# Sampling values, dimensions, weights and arbitrary numeric arrays stay exact.
	for id: String in graph:
		var inputs: Dictionary = graph[id].inputs
		for field: String in inputs: inputs[field] = _wire_links(inputs[field],graph)
	return graph

static func _wire_links(value: Variant, graph: Dictionary) -> Variant:
	if value is Array:
		if value.size() == 2 and value[0] is String and graph.has(value[0]) and value[1] is float and is_finite(value[1]) and value[1] == floorf(value[1]) and value[1] >= 0 and value[1] < 9223372036854775808.0:
			value[1] = int(value[1])
		else:
			for index: int in value.size(): value[index] = _wire_links(value[index],graph)
	elif value is Dictionary:
		for key: Variant in value: value[key] = _wire_links(value[key],graph)
	return value

static func _public_code(value: Variant) -> String:
	return value if value is String and RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,100}$").search(value) != null else ""

static func _value_type(value: Variant) -> String:
	if value == null: return "null"
	if value is bool: return "boolean"
	if value is int or value is float: return "number"
	if value is String: return "string"
	if value is Array: return "array"
	if value is Dictionary: return "object"
	return "unknown"

## Public diagnostics contain only bounded structural identifiers/types. Never
## copy messages, details, received values, headers or response bodies.
static func rejection_diagnostic(status: int, bytes: PackedByteArray) -> Dictionary:
	var result := {"http_status":status,"error_type":"transport_error" if status == 0 else "workflow_rejected","node_errors":[]}
	if bytes.is_empty(): return result
	if bytes.size() > 131072: result.error_type = "response_too_large"; return result
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary: result.error_type = "response_not_json"; return result
	var response: Dictionary = json.data
	var error: Variant = response.get("error")
	if error is Dictionary and _public_code(error.get("type")) != "": result.error_type = _public_code(error.type)
	var nodes: Variant = response.get("node_errors")
	if not nodes is Dictionary: return result
	for id: Variant in nodes:
		if result.node_errors.size() >= 8: break
		var node: Variant = nodes[id]
		if _public_code(id) == "" or not node is Dictionary or not node.get("errors") is Array: continue
		var row := {"node_id":id,"class_type":_public_code(node.get("class_type")),"errors":[]}
		for value: Variant in node.errors.slice(0,4):
			if not value is Dictionary: continue
			var item := {"type":_public_code(value.get("type"))}
			var extra: Variant = value.get("extra_info")
			if extra is Dictionary:
				if _public_code(extra.get("input_name")) != "": item["field"] = _public_code(extra.input_name)
				for key: String in ["expected_type","received_type"]:
					if _public_code(extra.get(key)) != "": item[key] = _public_code(extra[key])
				if extra.has("received_value"): item["received_value_type"] = _value_type(extra.received_value)
				var input_config: Variant = extra.get("input_config")
				if not item.has("expected_type") and input_config is Array and not input_config.is_empty() and _public_code(input_config[0]) != "": item["expected_type"] = _public_code(input_config[0])
			row.errors.append(item)
		result.node_errors.append(row)
	return result

static func generate(generator: Node, native: Dictionary, config: Dictionary, prompt: String) -> Dictionary:
	var base: String = str(native.get("base","")).trim_suffix("/")
	var graph: Dictionary = with_prompt(config,prompt)
	var outcome: Array = await generator._http(base+"/prompt",PackedStringArray(["Content-Type: application/json"]),HTTPClient.METHOD_POST,JSON.stringify({"prompt":graph}))
	var response_json := JSON.new()
	var response: Variant = response_json.data if response_json.parse((outcome[1] as PackedByteArray).get_string_from_utf8()) == OK else null
	if int(outcome[0]) != 200 or not response is Dictionary or not response.get("prompt_id") is String or response.prompt_id.is_empty() or response.prompt_id.length() > 128: return {"ok":false,"code":"workflow_rejected","diagnostic":rejection_diagnostic(int(outcome[0]),outcome[1])}
	var id: String = response.prompt_id
	for _i in 300:
		await generator._pause(2.0)
		var poll: Array = await generator._http(base+"/history/"+id.uri_encode(),PackedStringArray(),HTTPClient.METHOD_GET)
		var history: Variant = JSON.parse_string((poll[1] as PackedByteArray).get_string_from_utf8())
		if not history is Dictionary or not history.get(id) is Dictionary: continue
		var entry: Dictionary = history[id]
		if entry.get("status") is Dictionary and str(entry.status.get("status_str","")) == "error": return {"ok":false,"code":"workflow_failed"}
		var outputs: Variant = entry.get("outputs")
		if not outputs is Dictionary: continue
		for node: Variant in outputs.values():
			if not node is Dictionary or not node.get("images") is Array: continue
			for item: Variant in node.images:
				if not item is Dictionary or not item.get("filename") is String or item.filename.length() > 512 or str(item.get("subfolder","")).length() > 512: continue
				var url: String = base+"/view?filename="+item.filename.uri_encode()+"&subfolder="+str(item.get("subfolder","")).uri_encode()+"&type="+str(item.get("type","output")).uri_encode()
				var downloaded: Array = await generator._http(url,PackedStringArray(),HTTPClient.METHOD_GET)
				if int(downloaded[0]) != 200: return {"ok":false,"code":"workflow_download_failed"}
				var script: Script = generator.get_script()
				var image: Variant = script.call("picture_from_bytes",downloaded[1])
				return {"ok":image is Image and not image.is_empty(),"image":image,"code":"workflow_empty_result"}
	return {"ok":false,"code":"workflow_timeout"}
