extends RefCounted
## Pure table operations. Every input cell survives normalization and CSV export.
const PAGE_SIZE := 50

static func normalize(block: Dictionary) -> Dictionary:
	var headers: Array = block.get("headers",[]).duplicate(true)
	var rows: Array = []
	var width: int = headers.size()
	for input: Variant in block.get("rows",[]):
		if input is Array:
			rows.append(input.duplicate(true)); width = maxi(width,input.size())
	width = maxi(1,width)
	var extra: int = maxi(int(block.get("extra_columns",0)),maxi(0,width-headers.size()))
	while headers.size() < width: headers.append("Столбец "+str(headers.size()+1))
	for column: int in width:
		if str(headers[column]).strip_edges().is_empty(): headers[column] = "Столбец "+str(column+1)
	for row: Array in rows:
		while row.size() < width: row.append("")
	var align: Array = block.get("alignments",[]).duplicate()
	while align.size() < width: align.append("auto")
	var numeric: Array = []
	for column: int in width:
		var count := 0; var all_numbers := true
		for row: Array in rows:
			if missing(row[column]): continue
			count += 1
			if number(row[column]) == null: all_numbers = false; break
		numeric.append(all_numbers and count > 0)
		if align[column] not in ["left","center","right"]: align[column] = "right" if numeric[column] else "left"
	return {"headers":headers,"rows":rows,"alignments":align,"numeric":numeric,"extra_columns":extra,"title":str(block.get("title","")),"source":str(block.get("source",""))}

static func missing(value: Variant) -> bool:
	return value == null or str(value).strip_edges().to_lower() in ["","—","–","-","n/a","null","нет данных"]

static func number(value: Variant) -> Variant:
	if value is int or value is float: return float(value) if is_finite(float(value)) else null
	var text: String = str(value).strip_edges().replace("\u00a0"," ").replace("\u202f"," ")
	if RegEx.create_from_string("^[+-]?(?:[0-9]{1,3}(?: [0-9]{3})+|[0-9]+)(?:[.,][0-9]+)?(?:[eE][+-]?[0-9]+)?%?$").search(text) == null: return null
	text = text.replace(" ","").replace(",",".").trim_suffix("%")
	var result: float = text.to_float()
	return result if is_finite(result) else null

static func indices(spec: Dictionary, query: String = "", column: int = -1, descending: bool = false) -> Array:
	var found: Array = []
	var needle: String = query.strip_edges().to_lower()
	for index: int in spec.rows.size():
		if needle.is_empty() or needle in " ".join(spec.rows[index].map(func(value: Variant): return str(value))).to_lower(): found.append(index)
	if column >= 0 and column < spec.headers.size():
		found.sort_custom(func(a: int,b: int):
			var av: Variant = spec.rows[a][column]; var bv: Variant = spec.rows[b][column]
			var am: bool = missing(av); var bm: bool = missing(bv)
			if am or bm: return a < b if am == bm else not am
			var va: Variant = number(av) if spec.numeric[column] else str(av).to_lower()
			var vb: Variant = number(bv) if spec.numeric[column] else str(bv).to_lower()
			if va == vb: return a < b
			return va > vb if descending else va < vb)
	return found

static func csv(spec: Dictionary, order: Array = []) -> String:
	var lines := PackedStringArray()
	lines.append(csv_row(spec.headers))
	for index: int in order: lines.append(csv_row(spec.rows[index]))
	return "\r\n".join(lines)+"\r\n"

static func csv_row(row: Array) -> String:
	var cells := PackedStringArray()
	for value: Variant in row:
		var text: String = "" if value == null else str(value)
		# RFC 4180 quoting; preserve the exact data, including formula-like strings.
		if "," in text or '"' in text or "\n" in text or "\r" in text: text = '"'+text.replace('"','""')+'"'
		cells.append(text)
	return ",".join(cells)
