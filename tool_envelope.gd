extends RefCounted
## Convert the observed DeepSeek text tool grammar, never arbitrary prose/XML.
## Permissions and argument validation remain in the existing runtime registry.
const TAG := "｜｜DSML｜｜ "

static func normalize(raw: String, request_id: String) -> String:
	var input: String = raw.strip_edges()
	var start: String = "<"+TAG+"calls>"
	var end: String = "</"+TAG+"calls>"
	if not input.begins_with(start) or not input.ends_with(end): return raw
	var source: String = input.substr(start.length(),input.length()-start.length()-end.length()).strip_edges()
	var invoke := RegEx.create_from_string('^<'+TAG+'invoke name="([A-Za-z_][A-Za-z0-9_.:-]*)">')
	var parameter := RegEx.create_from_string('^<'+TAG+'parameter name="([A-Za-z_][A-Za-z0-9_]*)" string="(true|false)">')
	var calls: Array = []
	while source != "":
		if calls.size() >= 8: return raw
		var head: RegExMatch = invoke.search(source)
		if head == null: return raw
		var name: String = head.get_string(1)
		source = source.substr(head.get_end()).strip_edges()
		var args: Dictionary = {}
		var close: String = "</"+TAG+"invoke>"
		while not source.begins_with(close):
			var field: RegExMatch = parameter.search(source)
			if field == null or args.has(field.get_string(1)): return raw
			var field_end: String = "</"+TAG+"parameter>"
			var offset: int = source.find(field_end,field.get_end())
			if offset < 0: return raw
			var value: String = source.substr(field.get_end(),offset-field.get_end())
			if value.contains("<"+TAG) or value.contains("</"+TAG): return raw
			if field.get_string(2) == "true": args[field.get_string(1)] = value
			else:
				var json := JSON.new()
				if json.parse(value) != OK: return raw
				args[field.get_string(1)] = json.data
			source = source.substr(offset+field_end.length()).strip_edges()
		calls.append({"id":"dsml:"+request_id+":"+str(calls.size()),"name":name,"arguments":args})
		source = source.substr(close.length()).strip_edges()
	if calls.is_empty(): return raw
	return JSON.stringify({"message":"","tool_calls":calls,"result":null})

static func response(bytes: PackedByteArray, request_id: String) -> PackedByteArray:
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary: return bytes
	var body: Dictionary = json.data
	if not body.get("choices") is Array: return bytes
	var changed: bool = false
	for choice: Variant in body.choices:
		if not choice is Dictionary or int(choice.get("index",0)) != 0 or not choice.get("message") is Dictionary: continue
		var message: Dictionary = choice.message
		if not message.get("content") is String: continue
		var content: String = normalize(message.content,request_id)
		if content != message.content:
			message.content = content
			changed = true
	return JSON.stringify(body).to_utf8_buffer() if changed else bytes
