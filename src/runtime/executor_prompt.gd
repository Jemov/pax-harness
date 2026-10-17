extends RefCounted
## Remove only redundant generated tool-schema JSON, never task prose or custom rules.
## Strict equality is intentional: stale or differently granted lab catalogues stay visible.
static func deduplicate(system: String, tools: Array) -> String:
	var known: Dictionary = {}
	var ambiguous: Dictionary = {}
	for tool: Variant in tools:
		if not tool is Dictionary or not tool.get("name") is String: continue
		var name: String = str(tool.name)
		if known.has(name) and known[name] != tool: ambiguous[name] = true
		known[name] = tool
	var kept := PackedStringArray()
	var fence := ""
	for original: String in system.split("\n",true):
		var line: String = original.trim_suffix("\r")
		var trimmed: String = line.strip_edges()
		# Literal code/examples must remain exactly meaningful to the player.
		if trimmed.begins_with("```") or trimmed.begins_with("~~~"):
			var marker: String = trimmed.left(3)
			if fence == "": fence = marker
			elif fence == marker: fence = ""
			kept.append(line)
			continue
		var redundant := false
		if fence == "" and trimmed.begins_with("{") and trimmed.ends_with("}") and trimmed.length() <= 2097152:
			var parser := JSON.new()
			if parser.parse(trimmed) == OK and parser.data is Dictionary:
				var value: Dictionary = parser.data
				if value.size() == 1 and value.get("registered_tools") is Array:
					redundant = true
					for row: Variant in value.registered_tools:
						if not row is Dictionary or not row.get("name") is String or ambiguous.has(row.name) or not known.has(row.name) or known[row.name] != row:
							redundant = false
							break
		if not redundant: kept.append(line)
	return "\n".join(kept)

## Executor owns executable grants and schemas. Laboratory package expansions are
## removed only as an exact native-generated marker/JSON pair, even when stale.
static func without_embedded_catalogues(system: String) -> String:
	var lines: PackedStringArray = system.replace("\r\n","\n").split("\n",true)
	var kept := PackedStringArray()
	var marker := RegEx.create_from_string("^\\[Executable tools\\.[a-z][a-z0-9_]*\\]$")
	var index := 0
	var fence := ""
	while index < lines.size():
		var line: String = lines[index]
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("```") or trimmed.begins_with("~~~"):
			var token: String = trimmed.left(3)
			if fence == "": fence = token
			elif fence == token: fence = ""
			kept.append(line); index += 1
			continue
		if fence == "" and marker.search(line) != null and index+1 < lines.size() and _generated_catalogue(lines[index+1]):
			index += 2
			continue
		kept.append(line); index += 1
	return "\n".join(kept)

static func _generated_catalogue(line: String) -> bool:
	if line.length() > 2097152: return false
	var parser := JSON.new()
	if parser.parse(line) != OK or not parser.data is Dictionary: return false
	var data: Dictionary = parser.data
	if data.size() != 1 or not data.get("registered_tools") is Array: return false
	for tool: Variant in data.registered_tools:
		if not tool is Dictionary or not tool.get("name") is String or not tool.get("arguments_schema") is Dictionary: return false
	return true
