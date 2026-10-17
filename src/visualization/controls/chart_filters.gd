extends RefCounted
## Pure projections: the saved chart and model data are never changed by a filter.
static func subset(values: Array, indices: Array) -> Array:
	var out: Array = []
	for i: int in indices: out.append(values[i])
	return out
static func selected(text: String, query: String) -> bool: return query == "" or query in text.to_lower()
static func apply(original: Dictionary, query: String = "", hidden_series: Array = [], minimum: float = 0) -> Dictionary:
	var v: Dictionary = original.duplicate(true)
	query = query.to_lower().strip_edges()
	if v.has("series"):
		v.series = v.series.filter(func(row: Dictionary): return row.name not in hidden_series)
		if v.series.is_empty(): return {}
	if v.type in ["symbol_map","flow_map"]:
		var keep: Dictionary = {}
		for row: Dictionary in v.nodes:
			if selected(str(row.label),query): keep[row.id] = true
		if v.type == "flow_map":
			var matches: Dictionary = keep.duplicate()
			for edge: Dictionary in v.get("links",[]):
				if matches.has(edge.source): keep[edge.target] = true
				if matches.has(edge.target): keep[edge.source] = true
			v.links = v.links.filter(func(e: Dictionary): return keep.has(e.source) and keep.has(e.target) and float(e.value) >= minimum)
		v.nodes = v.nodes.filter(func(n: Dictionary): return keep.has(n.id))
		if v.nodes.is_empty(): return {}
	elif v.type == "calendar_heatmap":
		v.days = v.days.filter(func(day: Dictionary): return selected(str(day.date),query))
		if v.days.is_empty(): return {}
	elif v.type == "parallel":
		v.rows = v.rows.filter(func(row: Dictionary): return selected(str(row.label),query) and row.label not in hidden_series)
		if v.rows.is_empty(): return {}
	elif v.type == "small_multiples":
		v.panels = v.panels.filter(func(row: Dictionary): return selected(str(row.title),query))
		if v.panels.is_empty(): return {}
	elif v.type in ["sankey","network"]:
		var keep: Dictionary = {}; var matches: Dictionary = {}
		for row: Dictionary in v.nodes:
			if selected(str(row.label),query): keep[row.id] = true; matches[row.id] = true
		if query != "":
			for edge: Dictionary in v.links:
				if matches.has(edge.source): keep[edge.target] = true
				if matches.has(edge.target): keep[edge.source] = true
		v.links = v.links.filter(func(e: Dictionary): return keep.has(e.source) and keep.has(e.target) and float(e.get("value",1)) >= minimum)
		if v.type == "sankey":
			keep.clear()
			for edge: Dictionary in v.links: keep[edge.source] = true; keep[edge.target] = true
		v.nodes = v.nodes.filter(func(n: Dictionary): return keep.has(n.id))
		if v.nodes.is_empty() or (v.type == "sankey" and v.links.is_empty()): return {}
	elif v.type in ["sunburst","tree","icicle"]:
		var keep: Dictionary = {}; var parents: Dictionary = {}; var children: Dictionary = {}
		for row: Dictionary in v.nodes:
			parents[row.id] = str(row.get("parent","")); children[row.id] = []
		for row: Dictionary in v.nodes:
			if parents[row.id] != "": children[parents[row.id]].append(row.id)
		for row: Dictionary in v.nodes:
			if not selected(str(row.label),query): continue
			var id: String = row.id
			while id != "": keep[id] = true; id = parents[id]
			var queue: Array = [row.id]
			while not queue.is_empty():
				id = queue.pop_front(); keep[id] = true; queue.append_array(children[id])
		v.nodes = v.nodes.filter(func(n: Dictionary): return keep.has(n.id))
		if v.nodes.size() < 2: return {}
	elif v.type == "gantt":
		v.tasks = v.tasks.filter(func(t: Dictionary): return selected(str(t.label),query) and str(t.get("status","")) not in hidden_series)
		if v.tasks.is_empty(): return {}
		var keep: Dictionary = {}
		for task: Dictionary in v.tasks: keep[task.id] = true
		v.dependencies = v.get("dependencies",[]).filter(func(e: Dictionary): return keep.has(e.source) and keep.has(e.target))
	elif v.has("groups"):
		v.groups = v.groups.filter(func(g: Dictionary): return selected(str(g.name),query) and g.name not in hidden_series)
		if v.groups.is_empty(): return {}
	elif v.has("regions"):
		v.regions = v.regions.filter(func(r: Dictionary): return selected(str(r.label),query))
		if v.regions.is_empty(): return {}
	elif v.has("boxes"):
		v.boxes = v.boxes.filter(func(b: Dictionary): return selected(str(b.label),query))
		if v.boxes.is_empty(): return {}
	elif v.has("labels"):
		var indices: Array = []
		for i: int in v.labels.size():
			if selected(str(v.labels[i]),query): indices.append(i)
		if indices.is_empty(): return {}
		v.labels = subset(v.labels,indices)
		for key: String in ["x","sizes","matrix"]:
			if v.has(key): v[key] = subset(v[key],indices)
		for row: Dictionary in v.get("series",[]):
			for key: String in ["values","lower","upper"]:
				if row.has(key): row[key] = subset(row[key],indices)
		if v.type in ["line","area"]:
			var breaks: Array = []
			for i: int in range(1,indices.size()):
				if indices[i] != indices[i-1]+1 or indices[i] in v.get("breaks",[]): breaks.append(i)
			v.breaks = breaks
		if v.type == "waterfall" and query != "": return {} # Signed deltas cannot be removed without changing subsequent totals.
		if v.has("total_indices"):
			var totals: Array = []
			for i: int in indices.size():
				if indices[i] in v.total_indices: totals.append(i)
			v.total_indices = totals
	return v
