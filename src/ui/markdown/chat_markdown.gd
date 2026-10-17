extends RefCounted
## Native BBCode presentation of a safe Markdown subset; never load remote assets.
const Chart = preload("res://mods/pax_harness/src/visualization/specs/chat_chart.gd")
const ChartResponse = preload("res://mods/pax_harness/src/visualization/chart_response.gd")
const Table = preload("res://mods/pax_harness/src/ui/markdown/table_spec.gd")
static func escape(text: String) -> String: return text.replace("[","[lb]")

static func plain_inline(text: String) -> String:
	var value: String = RegEx.create_from_string("\\[([^\\]]+)\\]\\((https://[^\\s)]+)\\)").sub(text,"$1 ($2)",true)
	return value.replace("**","").replace("__","").replace("`","").replace("~~","")

static func inline(text: String) -> String:
	var tokens: Array = []
	# Protect inline code and links from the emphasis pass and escape raw BBCode.
	var pattern := RegEx.create_from_string("`([^`]+)`|\\[([^\\]]+)\\]\\((https://[^\\s)]+)\\)")
	var result: String = ""
	var cursor := 0
	for found: RegExMatch in pattern.search_all(text):
		result += escape(text.substr(cursor,found.get_start()-cursor))
		var replacement: String
		if found.get_string(1) != "": replacement = "[bgcolor=#292b30][code]"+escape(found.get_string(1))+"[/code][/bgcolor]"
		else:
			var url: String = found.get_string(3).replace("[","%5B").replace("]","%5D").replace('"',"%22")
			replacement = "[url="+url+"][color=#8fcaff]"+escape(found.get_string(2))+"[/color][/url]"
		tokens.append(replacement)
		result += "\uE000"+str(tokens.size()-1)+"\uE001"
		cursor = found.get_end()
	result += escape(text.substr(cursor))
	result = RegEx.create_from_string("\\*\\*([^*\\n]+)\\*\\*").sub(result,"[b]$1[/b]",true)
	result = RegEx.create_from_string("~~([^~\\n]+)~~").sub(result,"[s]$1[/s]",true)
	result = RegEx.create_from_string("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)").sub(result,"[i]$1[/i]",true)
	for index: int in tokens.size(): result = result.replace("\uE000"+str(index)+"\uE001",tokens[index])
	return result

static func cells(line: String) -> Array:
	var text: String = line.strip_edges().trim_prefix("|").trim_suffix("|")
	var result: Array = []
	for cell: String in text.replace("\\|","\uE002").split("|"): result.append(cell.strip_edges().replace("\uE002","|"))
	return result

static func separator(line: String) -> bool:
	if "|" not in line: return false
	for cell: String in cells(line):
		if RegEx.create_from_string("^:?-{3,}:?$").search(cell) == null: return false
	return true

static func parse_reference(text: String, events: Array) -> Dictionary:
	if text.to_utf8_buffer().size() > 512: return {}
	var json := JSON.new()
	return chart_reference(json.data,events) if json.parse(text) == OK else {}

static func chart_reference(value: Variant, events: Array) -> Dictionary:
	if not value is Dictionary or value.size() != 1 or not value.get("tool_call_id") is String: return {}
	var id: String = value.tool_call_id
	if RegEx.create_from_string("^[A-Za-z0-9_.:-]{1,128}$").search(id) == null: return {}
	for event: Dictionary in events:
		if event.get("kind") == "tool" and event.get("id") == id and event.get("status") == "complete" and event.get("name") in ["charts.function","charts.map","datasets.chart"]:
			return Chart.validate(event.get("result",{}).get("chart",{}))
	return {}

static func generated_images(events: Array) -> Array:
	var images: Array = []; var seen: Dictionary = {}
	for value: Variant in events:
		if not value is Dictionary or value.get("kind") != "tool" or value.get("name") != "images.generate" or value.get("status") != "complete": continue
		var result: Variant = value.get("result",{})
		var descriptor: Variant = result.get("generated_image") if result is Dictionary else null
		if not descriptor is Dictionary or not descriptor.get("id") is String or RegEx.create_from_string("^[a-f0-9]{32}$").search(descriptor.id) == null or seen.has(descriptor.id): continue
		seen[descriptor.id] = true; images.append(descriptor.duplicate(true))
	return images

static func blocks(markdown: String, events: Array = [], complete: bool = false) -> Array:
	var lines: PackedStringArray = markdown.replace("\r\n","\n").split("\n")
	var result: Array = []
	var buffer := PackedStringArray()
	var fenced := false
	var i := 0
	while i < lines.size():
		if not fenced and lines[i].strip_edges() == "```pax-chart":
			var end := i+1
			while end < lines.size() and lines[end].strip_edges() != "```": end += 1
			if end < lines.size():
				var json: String = "\n".join(lines.slice(i+1,end))
				var checked: Dictionary = ChartResponse.inspect(json,events)
				if not buffer.is_empty(): result.append({"kind":"text","text":"\n".join(buffer)}); buffer.clear()
				if checked.ok: result.append({"kind":"chart","spec":checked.spec})
				else: result.append({"kind":"chart_error","raw":json,"reason":checked.reason,"code":checked.code})
				i = end+1
				continue
			elif complete:
				if not buffer.is_empty(): result.append({"kind":"text","text":"\n".join(buffer)}); buffer.clear()
				result.append({"kind":"chart_error","raw":"\n".join(lines.slice(i+1)),"reason":"Ответ оборвался: блок диаграммы не завершён.","code":"charts.unclosed_fence"})
				break
		if not fenced and lines[i].strip_edges().begins_with("```"): fenced = true
		elif fenced and lines[i].strip_edges() == "```": fenced = false
		if not fenced and i+1 < lines.size() and "|" in lines[i] and separator(lines[i+1]):
			if not buffer.is_empty(): result.append({"kind":"text","text":"\n".join(buffer)}); buffer.clear()
			var alignments: Array = []
			for cell: String in cells(lines[i+1]):
				alignments.append("center" if cell.begins_with(":") and cell.ends_with(":") else "right" if cell.ends_with(":") else "left" if cell.begins_with(":") else "auto")
			var table: Dictionary = {"kind":"table","headers":cells(lines[i]),"rows":[],"alignments":alignments}
			i += 2
			while i < lines.size() and "|" in lines[i] and not lines[i].strip_edges().is_empty():
				table.rows.append(cells(lines[i]))
				i += 1
			var normalized: Dictionary = Table.normalize(table)
			normalized["kind"] = "table"
			result.append(normalized)
			continue
		buffer.append(lines[i])
		i += 1
	if not buffer.is_empty(): result.append({"kind":"text","text":"\n".join(buffer)})
	return result

static func render(markdown: String) -> String:
	var lines: PackedStringArray = markdown.replace("\r\n","\n").split("\n")
	var output := PackedStringArray()
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		if line.strip_edges().begins_with("```"):
			var code := PackedStringArray()
			i += 1
			while i < lines.size() and not lines[i].strip_edges().begins_with("```"):
				code.append(escape(lines[i]))
				i += 1
			output.append("[bgcolor=#202226][code]"+"\n".join(code)+"[/code][/bgcolor]")
		elif i+1 < lines.size() and "|" in line and separator(lines[i+1]):
			var raw: Dictionary = {"headers":cells(line),"rows":[]}
			i += 2
			while i < lines.size() and "|" in lines[i] and not lines[i].strip_edges().is_empty():
				raw.rows.append(cells(lines[i])); i += 1
			var normalized: Dictionary = Table.normalize(raw)
			var table: String = "[table="+str(normalized.headers.size())+"]"
			for header: String in normalized.headers: table += "[cell expand=1 border=#36393e bg=#24262b padding=10,8,10,8][b]"+inline(header)+"[/b][/cell]"
			for row: Array in normalized.rows:
				for value: Variant in row: table += "[cell expand=1 border=#303238 padding=10,8,10,8]"+inline(str(value))+"[/cell]"
			output.append(table+"[/table]")
			continue
		else:
			var heading: RegExMatch = RegEx.create_from_string("^(#{1,6})\\s+(.+)$").search(line)
			var bullet: RegExMatch = RegEx.create_from_string("^(\\s*)[-*+]\\s+(.+)$").search(line)
			if heading != null: output.append("[font_size="+str(maxi(16,26-heading.get_string(1).length()*2))+"][b]"+inline(heading.get_string(2))+"[/b][/font_size]")
			elif bullet != null: output.append(bullet.get_string(1)+"•  "+inline(bullet.get_string(2)))
			elif line.strip_edges().begins_with("> "): output.append("[color=#a7adb7]▎ "+inline(line.strip_edges().substr(2))+"[/color]")
			elif line.strip_edges() in ["---","***","___"]: output.append("[color=#45494f]────────────────────────────────────────[/color]")
			else: output.append(inline(line))
		i += 1
	return "\n".join(output)

static func expand_chart_references(markdown: String, events: Array) -> String:
	# Exports are standalone: include saved data rather than a local receipt pointer.
	var regex := RegEx.create_from_string("(?ms)^```pax-chart\\s*\\n(.*?)\\n```[ \\t]*$")
	var output: String = markdown
	var matches: Array = regex.search_all(markdown)
	matches.reverse()
	for found: RegExMatch in matches:
		var spec: Dictionary = parse_reference(found.get_string(1),events)
		if not spec.is_empty(): output = output.left(found.get_start())+"```pax-chart\n"+JSON.stringify(spec)+"\n```"+output.substr(found.get_end())
	return output

static func plain_text(markdown: String, events: Array = []) -> String:
	var pieces: Array = blocks(markdown,events)
	if pieces.any(func(block: Dictionary): return block.kind in ["chart","chart_error"]):
		var sections := PackedStringArray()
		for block: Dictionary in pieces:
			if block.kind == "chart": sections.append(Chart.plain(block.spec))
			elif block.kind == "text": sections.append(plain_text(block.text))
			elif block.kind == "chart_error": sections.append("Диаграмма не построена: "+str(block.reason)+"\n"+str(block.raw))
			else:
				sections.append(" | ".join(block.headers))
				for row: Array in block.rows: sections.append(" | ".join(row))
		return "\n\n".join(sections)
	var out := PackedStringArray()
	var fenced: bool = false
	for line: String in markdown.replace("\r\n","\n").split("\n"):
		if line.strip_edges().begins_with("```"):
			fenced = not fenced
			continue
		if fenced:
			out.append(line)
			continue
		if separator(line): continue
		line = RegEx.create_from_string("^#{1,6}\\s+").sub(line,"")
		line = RegEx.create_from_string("^(\\s*)[-*+]\\s+").sub(line,"$1• ")
		line = line.trim_prefix("> ")
		line = plain_inline(line)
		line = RegEx.create_from_string("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)").sub(line,"$1",true)
		line = RegEx.create_from_string("(?<!_)_([^_\\n]+)_(?!_)").sub(line,"$1",true)
		out.append(line)
	return "\n".join(out)
