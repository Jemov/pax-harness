extends RefCounted
## SSE is framed as bytes first, so a network chunk cannot split UTF-8 text.
var pending := PackedByteArray()
var data_lines := PackedStringArray()
var content: String = ""
var usage: Dictionary = {}
var finish_reason: String = ""
var done: bool = false
var error: String = ""

func feed(bytes: PackedByteArray) -> void:
	pending.append_array(bytes)
	while not done and error == "":
		var newline: int = pending.find(10)
		if newline < 0: break
		var line: String = pending.slice(0,newline).get_string_from_utf8().trim_suffix("\r")
		pending = pending.slice(newline+1)
		if line == "": _event()
		elif line.begins_with("data:"): data_lines.append(line.substr(5).trim_prefix(" "))

func end() -> void:
	if not pending.is_empty():
		var line: String = pending.get_string_from_utf8().trim_suffix("\r")
		if line.begins_with("data:"): data_lines.append(line.substr(5).trim_prefix(" "))
		pending.clear()
	_event()

func _event() -> void:
	if data_lines.is_empty() or done: return
	var data: String = "\n".join(data_lines)
	data_lines.clear()
	if data.strip_edges() == "[DONE]":
		done = true
		return
	var value: Variant = JSON.parse_string(data)
	if not value is Dictionary:
		error = "invalid_stream_event"
		return
	if value.has("error"):
		error = "context_length_exceeded" if context_error(JSON.stringify(value.error)) else "provider_stream_error"
		return
	if value.get("usage") is Dictionary: usage = value.usage.duplicate(true)
	var choices: Variant = value.get("choices",[])
	if not choices is Array:
		error = "invalid_stream_choices"
		return
	for choice: Variant in choices:
		if not choice is Dictionary:
			error = "invalid_stream_choice"
			return
		if int(choice.get("index",0)) != 0: continue
		var delta: Variant = choice.get("delta",{})
		if not delta is Dictionary:
			error = "invalid_stream_delta"
			return
		if delta.get("content") is String: content += delta.content
		# Private reasoning is never shown as the public answer.
		if choice.get("finish_reason") is String: finish_reason = choice.finish_reason

static func context_error(value: String) -> bool:
	var text: String = value.to_lower()
	return "context_length_exceeded" in text or "maximum context length" in text or "context window exceeded" in text

static func message_prefix(raw: String) -> String:
	# Read only the root envelope's message string, never nested tool arguments.
	var depth: int = 0
	var i: int = 0
	while i < raw.length():
		var c: String = raw[i]
		if c == "{" or c == "[": depth += 1
		elif c == "}" or c == "]": depth -= 1
		elif c == "\"":
			var token: Dictionary = _string(raw,i+1)
			if not token.complete: return ""
			i = token.end
			if depth == 1 and token.text == "message":
				var j: int = i+1
				while j < raw.length() and raw[j] in [" ","\t","\n","\r"]: j += 1
				if j < raw.length() and raw[j] == ":":
					j += 1
					while j < raw.length() and raw[j] in [" ","\t","\n","\r"]: j += 1
					if j < raw.length() and raw[j] == "\"": return str(_string(raw,j+1).text)
		i += 1
	return ""

static func _string(raw: String, start: int) -> Dictionary:
	var result: String = ""
	var i: int = start
	while i < raw.length():
		var c: String = raw[i]
		if c == "\"": return {"text":result,"end":i,"complete":true}
		if c == "\\":
			i += 1
			if i >= raw.length(): break
			c = raw[i]
			if c == "u":
				if i+4 >= raw.length(): break
				var hex: String = raw.substr(i+1,4)
				if not hex.is_valid_hex_number(): break
				var point: int = hex.hex_to_int()
				i += 4
				if point >= 0xD800 and point <= 0xDBFF:
					if i+6 >= raw.length() or raw.substr(i+1,2) != "\\u": break
					var low_hex: String = raw.substr(i+3,4)
					if not low_hex.is_valid_hex_number(): break
					var low: int = low_hex.hex_to_int()
					if low < 0xDC00 or low > 0xDFFF: break
					point = 0x10000+((point-0xD800)<<10)+(low-0xDC00)
					i += 6
				elif point >= 0xDC00 and point <= 0xDFFF: break
				result += String.chr(point)
			else:
				var escapes: Dictionary = {"n":"\n","r":"\r","t":"\t","b":"\b","f":"\f","/":"/","\\":"\\","\"":"\""}
				if not escapes.has(c): break
				result += str(escapes[c])
		else: result += c
		i += 1
	return {"text":result,"end":i,"complete":false}
