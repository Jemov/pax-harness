extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
## Extra statistical chart schemas. Only bounded numbers, text and geometry.
const Extended = preload("res://mods/pax_harness/src/visualization/specs/chart_extended_spec.gd")
const Strategy = preload("res://mods/pax_harness/src/visualization/specs/chart_strategy_spec.gd")
const TYPES := ["column","stacked_column","scatter","bubble","heatmap","sankey","treemap","waterfall","histogram","radar","boxplot","choropleth","cartogram","stacked_area","density","violin","ridgeline","gantt","network","sunburst"] + Extended.TYPES
static func finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and absf(float(value)) <= 1.0e15
static func text(value: Variant, limit: int = 160) -> bool:
	return value is String and not value.strip_edges().is_empty() and value.length() <= limit
static func labels(value: Variant, limit: int = 60) -> bool:
	return value is Array and not value.is_empty() and value.size() <= limit and value.all(func(v: Variant): return text(v))
static func series(value: Dictionary, nonnegative: bool = false) -> bool:
	if not value.get("series") is Array or value.series.is_empty() or value.series.size() > 4: return false
	for row: Variant in value.series:
		if not row is Dictionary or row.size() != 2 or not text(row.get("name")) or not row.get("values") is Array or row.values.size() != value.labels.size(): return false
		for number: Variant in row.values:
			if not finite(number) or (nonnegative and number < 0): return false
	return true
static func validate(value: Dictionary) -> Dictionary:
	var kind: String = str(value.get("type",""))
	if kind in Extended.TYPES: return Extended.validate(value)
	if kind in Strategy.TYPES: return Strategy.validate(value)
	var fields: Array = ["type","title","source","unit","basis","x_label","y_label"]
	match kind:
		"scatter","bubble": fields += ["labels","x","series","sizes","size_label"]
		"heatmap": fields += ["labels","columns","matrix"]
		"sankey": fields += ["nodes","links"]
		"column","stacked_column","treemap","radar","waterfall","stacked_area": fields += ["labels","series","max","total_indices","x"]
		"histogram": fields += ["samples","bins"]
		"density","violin","ridgeline": fields += ["groups","bandwidth"]
		"boxplot": fields += ["boxes"]
		"choropleth","cartogram": fields += ["regions","aspect","body"]
		_: return {}
	for key: Variant in value:
		if key not in fields: return {}
	for key: String in ["title","source"]:
		if not text(value.get(key),500): return {}
	if value.has("body") and not text(value.body,160): return {}
	for key: String in ["unit","x_label","y_label","size_label"]:
		if not value.get(key,"") is String or str(value.get(key,"")).length() > 80: return {}
	if value.get("basis","observed") not in ["observed","scenario","forecast"]: return {}
	match kind:
		"scatter","bubble":
			if not labels(value.get("labels"),241) or not series(value) or not value.get("x") is Array or value.x.size() != value.labels.size() or not value.x.all(finite): return {}
			if kind == "bubble" and (not value.get("sizes") is Array or value.sizes.size() != value.labels.size() or not value.sizes.all(func(v: Variant): return finite(v) and v >= 0) or value.sizes.max() <= 0): return {}
		"column","stacked_column","treemap","radar","waterfall","stacked_area":
			if not labels(value.get("labels"),12 if kind == "radar" else 60) or not series(value,kind in ["treemap","radar","stacked_area","stacked_column"]): return {}
			if kind in ["treemap","waterfall"] and value.series.size() != 1: return {}
			if kind == "stacked_area" and value.labels.size() < 2: return {}
			if kind == "treemap" and value.series[0].values.max() <= 0: return {}
			if kind == "radar":
				if value.labels.size() < 3 or not finite(value.get("max",100)) or value.get("max",100) <= 0: return {}
				for row: Dictionary in value.series:
					if row.values.max() > value.get("max",100): return {}
			if kind == "waterfall":
				if not value.get("total_indices",[]) is Array: return {}
				for i: Variant in value.get("total_indices",[]):
					if not finite(i) or i != floorf(i) or i < 0 or i >= value.labels.size(): return {}
			if kind == "stacked_area" and value.has("x"):
				if not value.x is Array or value.x.size() != value.labels.size(): return {}
				var previous := -INF
				for x: Variant in value.x:
					if not finite(x) or x <= previous: return {}
					previous = x
		"heatmap":
			if not labels(value.get("labels"),24) or not labels(value.get("columns"),24) or not value.get("matrix") is Array or value.matrix.size() != value.labels.size(): return {}
			for row: Variant in value.matrix:
				if not row is Array or row.size() != value.columns.size() or not row.all(func(v: Variant): return v == null or finite(v)): return {}
		"histogram":
			if not value.get("samples") is Array or value.samples.is_empty() or value.samples.size() > 1000 or not value.samples.all(finite): return {}
			if not finite(value.get("bins",10)) or value.get("bins",10) != floorf(value.get("bins",10)) or value.get("bins",10) < 2 or value.get("bins",10) > 40: return {}
		"boxplot":
			if not value.get("boxes") is Array or value.boxes.is_empty() or value.boxes.size() > 24: return {}
			for row: Variant in value.boxes:
				if not row is Dictionary or row.size() != 6 or not text(row.get("label")): return {}
				var previous := -INF
				for key: String in ["min","q1","median","q3","max"]:
					if not finite(row.get(key)) or row[key] < previous: return {}
					previous = row[key]
		"density","violin","ridgeline":
			if not value.get("groups") is Array or value.groups.is_empty() or value.groups.size() > 12: return {}
			if value.has("bandwidth") and (not finite(value.bandwidth) or value.bandwidth <= 0): return {}
			var count := 0
			for group: Variant in value.groups:
				if not group is Dictionary or group.size() != 2 or not text(group.get("name")) or not group.get("samples") is Array or group.samples.size() < 2 or not group.samples.all(finite): return {}
				count += group.samples.size()
			if count > 1000: return {}
		"sankey":
			if not value.get("nodes") is Array or value.nodes.size() < 2 or value.nodes.size() > 32 or not value.get("links") is Array or value.links.is_empty() or value.links.size() > 64: return {}
			var ids: Dictionary = {}; var degrees: Dictionary = {}; var edges: Dictionary = {}
			for row: Variant in value.nodes:
				if not row is Dictionary or row.size() != 2 or not text(row.get("id"),80) or not text(row.get("label")) or ids.has(row.id): return {}
				ids[row.id] = true; degrees[row.id] = 0; edges[row.id] = []
			for row: Variant in value.links:
				if not row is Dictionary or row.size() != 3 or not ids.has(row.get("source")) or not ids.has(row.get("target")) or row.source == row.target or not finite(row.get("value")) or row.value <= 0: return {}
				degrees[row.target] += 1; edges[row.source].append(row.target)
			var queue: Array = []
			for id: String in ids:
				if degrees[id] == 0: queue.append(id)
			var visited := 0
			while not queue.is_empty():
				var id: String = queue.pop_front(); visited += 1
				for target: String in edges[id]:
					degrees[target] -= 1
					if degrees[target] == 0: queue.append(target)
			if visited != ids.size(): return {}
		"choropleth","cartogram":
			if not value.get("regions") is Array or value.regions.is_empty() or value.regions.size() > 64 or not finite(value.get("aspect",1.6)) or value.get("aspect",1.6) <= 0 or value.get("aspect",1.6) > 20: return {}
			var vertices := 0; var ids: Dictionary = {}
			for row: Variant in value.regions:
				if not row is Dictionary or not text(row.get("id"),80) or ids.has(row.id) or not text(row.get("label")) or (row.get("value") != null and not finite(row.value)): return {}
				ids[row.id] = true
				for key: Variant in row:
					if key not in ["id","label","value","polygons","center"]: return {}
				if row.has("center") and (not _point(row.center)): return {}
				if kind == "choropleth" and (not row.get("polygons") is Array or row.polygons.is_empty()): return {}
				for polygon: Variant in row.get("polygons",[]):
					if not polygon is Array or polygon.size() < 3 or polygon.size() > 2048: return {}
					vertices += polygon.size()
					if vertices > 12000 or not polygon.all(_point): return {}
	return value.duplicate(true)

static func _point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and value.all(func(v: Variant): return finite(v) and v >= 0 and v <= 1)

static func plain(spec: Dictionary) -> String:
	if spec.type in Extended.TYPES: return Extended.plain(spec)
	if spec.type in Strategy.TYPES: return Strategy.plain(spec)
	var lines := PackedStringArray([str(spec.title)])
	if spec.get("basis","observed") != "observed": lines.append(L.text("Основа: ")+str(spec.basis))
	for key: String in ["x_label","y_label","size_label"]:
		if spec.get(key,"") != "": lines.append(key+": "+str(spec[key]))
	if spec.has("labels"):
		for index: int in spec.labels.size():
			var values: Array = []
			if spec.has("x"): values.append("x: "+str(spec.x[index]))
			if spec.has("sizes"): values.append(str(spec.get("size_label",L.text("Размер")))+": "+str(spec.sizes[index]))
			for row: Dictionary in spec.get("series",[]): values.append(row.name+": "+str(row.values[index]))
			if spec.has("matrix"): values.append(str(spec.matrix[index]))
			lines.append(str(spec.labels[index])+" — "+", ".join(values))
	if spec.has("links"):
		var names: Dictionary = {}
		for row: Dictionary in spec.nodes: names[row.id] = row.label
		for link: Dictionary in spec.links: lines.append(str(names[link.source])+" → "+str(names[link.target])+": "+str(link.value))
	for row: Dictionary in spec.get("regions",[]): lines.append(str(row.label)+": "+str(row.value))
	for row: Dictionary in spec.get("boxes",[]): lines.append(str(row))
	for row: Dictionary in spec.get("groups",[]): lines.append(str(row.name)+": "+str(row.samples))
	if spec.has("samples"): lines.append(L.text("Наблюдения: ")+str(spec.samples))
	lines.append(L.text("Источник: ")+str(spec.source))
	return "\n".join(lines)
