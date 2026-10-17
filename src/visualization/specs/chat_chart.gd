extends RefCounted
## Bounded declarative data only. No expressions, scripts, external assets or URLs.
const TYPES := ["bar", "line", "area", "stacked_bar", "donut", "pie"]
const Extra = preload("res://mods/pax_harness/src/visualization/specs/chart_extra_spec.gd")
const MAX_LABELS := 60
const MAX_LINE_POINTS := 241
const MAX_SERIES := 4
const MAX_BYTES := 262144

static func parse(text: String) -> Dictionary:
	if text.to_utf8_buffer().size() > MAX_BYTES: return {}
	var json := JSON.new()
	if json.parse(text) != OK: return {}
	return validate(json.data)

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	if value.get("type","") in Extra.TYPES: return Extra.validate(value)
	for key: Variant in value:
		if key not in ["type", "title", "labels", "series", "unit", "source", "x", "curve", "x_label", "y_label", "basis", "breaks"]: return {}
	if not value.get("type") is String or value.type not in TYPES: return {}
	for key: String in ["title", "source"]:
		if not value.get(key) is String or value[key].strip_edges().is_empty() or value[key].length() > 500: return {}
	if not value.get("unit", "") is String or value.get("unit", "").length() > 40: return {}
	for key: String in ["x_label","y_label"]:
		if not value.get(key,"") is String or str(value.get(key,"")).length() > 80: return {}
	if value.get("basis","observed") not in ["observed","scenario","forecast"]: return {}
	if value.get("curve","linear") not in ["linear","smooth"]: return {}
	if value.has("curve") and value.type not in ["line","area"]: return {}
	if not value.get("labels") is Array or value.labels.is_empty() or value.labels.size() > (MAX_LINE_POINTS if value.type in ["line","area"] else MAX_LABELS): return {}
	if value.has("breaks"):
		if value.type not in ["line","area"] or not value.breaks is Array or value.breaks.size() >= value.labels.size(): return {}
		var previous_break := 0
		for index: Variant in value.breaks:
			if not (index is int or index is float) or not is_finite(float(index)) or float(index) != floorf(float(index)) or index <= previous_break or index >= value.labels.size(): return {}
			previous_break = int(index)
	value = value.duplicate(true)
	# Numeric tick labels are safe display data, even when a model omits quotes.
	for index: int in value.labels.size():
		if value.labels[index] is int or value.labels[index] is float:
			if not is_finite(float(value.labels[index])): return {}
			value.labels[index] = str(value.labels[index])
	for label: Variant in value.labels:
		if not label is String or label.is_empty() or label.length() > 160: return {}
	if value.has("x"):
		if value.type not in ["line","area"] or not value.x is Array or value.x.size() != value.labels.size(): return {}
		var previous := -INF
		for point: Variant in value.x:
			if not (point is int or point is float) or not is_finite(float(point)) or absf(float(point)) > 1.0e15 or point <= previous: return {}
			previous = float(point)
	if not value.get("series") is Array or value.series.is_empty() or value.series.size() > MAX_SERIES: return {}
	var positive := false
	for series: Variant in value.series:
		if not series is Dictionary or series.size() != 2 or not series.get("name") is String or series.name.is_empty() or series.name.length() > 160: return {}
		if not series.get("values") is Array or series.values.size() != value.labels.size(): return {}
		for point: Variant in series.values:
			if point == null and value.type in ["line","area"]: continue
			if not (point is int or point is float) or not is_finite(float(point)) or absf(float(point)) > 1.0e15: return {}
			if value.type in ["donut", "pie", "stacked_bar"] and point < 0: return {}
			positive = positive or point > 0
	if value.type in ["donut","pie"] and (value.series.size() != 1 or value.labels.size() > 12 or not positive): return {}
	return value

static func number(value: float) -> String:
	var magnitude := absf(value)
	if magnitude > 0 and magnitude < 0.01: return String.num_scientific(value)
	if magnitude >= 1.0e9: return ("%.2f" % (value / 1.0e9)).trim_suffix("0").trim_suffix("0").trim_suffix(".") + " млрд"
	if magnitude >= 1.0e6: return ("%.2f" % (value / 1.0e6)).trim_suffix("0").trim_suffix("0").trim_suffix(".") + " млн"
	if magnitude >= 10000: return ("%.1f" % (value / 1000.0)).trim_suffix("0").trim_suffix(".") + " тыс."
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func plain(spec: Dictionary) -> String:
	if spec.type in Extra.TYPES: return Extra.plain(spec)
	var lines := PackedStringArray([str(spec.title)])
	if spec.get("basis","observed") != "observed": lines.append("Сценарный расчёт" if spec.basis == "scenario" else "Прогноз")
	if spec.get("x_label","") != "": lines.append("X: "+str(spec.x_label))
	if spec.get("y_label","") != "": lines.append("Y: "+str(spec.y_label))
	if not spec.get("breaks",[]).is_empty(): lines.append("Разрывы кривой: "+str(spec.breaks.size()))
	for index: int in spec.labels.size():
		var values := PackedStringArray()
		for series: Dictionary in spec.series:
			values.append(str(series.name)+": "+("нет данных" if series.values[index] == null else str(series.values[index])+" "+str(spec.get("unit", ""))))
		lines.append(str(spec.labels[index])+" — "+"; ".join(values))
	lines.append("Источник: "+str(spec.source))
	return "\n".join(lines)

static func curve_points(points: PackedVector2Array, mode: String) -> PackedVector2Array:
	if mode != "smooth" or points.size() < 3: return points
	var h: Array[float] = []; var slopes: Array[float] = []; var tangents: Array[float] = []
	for index: int in points.size()-1:
		h.append(maxf(0.000001,points[index+1].x-points[index].x))
		slopes.append((points[index+1].y-points[index].y)/h[-1])
	tangents.append(slopes[0])
	for index: int in range(1,points.size()-1):
		var left: float = slopes[index-1]; var right: float = slopes[index]
		var w1: float = 2*h[index]+h[index-1]; var w2: float = h[index]+2*h[index-1]
		tangents.append(0.0 if left*right <= 0 else (w1+w2)/(w1/left+w2/right))
	tangents.append(slopes[-1])
	var result := PackedVector2Array()
	for index: int in points.size()-1:
		for step: int in 16:
			var t: float = step/16.0; var t2: float = t*t; var t3: float = t2*t
			var y: float = (2*t3-3*t2+1)*points[index].y+(t3-2*t2+t)*h[index]*tangents[index]+(-2*t3+3*t2)*points[index+1].y+(t3-t2)*h[index]*tangents[index+1]
			# Interpolation must never invent an extremum beyond its observations.
			y = clampf(y,minf(points[index].y,points[index+1].y),maxf(points[index].y,points[index+1].y))
			result.append(Vector2(lerpf(points[index].x,points[index+1].x,t),y))
	result.append(points[-1])
	return result
