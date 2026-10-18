extends RefCounted
const L = preload("res://mods/pax_harness/src/localization/localization.gd")
const TYPES := ["gantt","network","sunburst"]
static func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and absf(v) <= 1.0e15
static func text(v: Variant, length: int = 160) -> bool:
	return v is String and not v.strip_edges().is_empty() and v.length() <= length
static func fields(v: Dictionary, allowed: Array) -> bool:
	for key: Variant in v:
		if key not in allowed: return false
	return true
static func acyclic(ids: Dictionary, links: Array) -> bool:
	var degrees: Dictionary = {}; var children: Dictionary = {}
	for id: String in ids: degrees[id] = 0; children[id] = []
	for link: Dictionary in links: degrees[link.target] += 1; children[link.source].append(link.target)
	var queue: Array = []
	for id: String in ids:
		if degrees[id] == 0: queue.append(id)
	var count := 0
	while not queue.is_empty():
		var id: String = queue.pop_front(); count += 1
		for child: String in children[id]:
			degrees[child] -= 1
			if degrees[child] == 0: queue.append(child)
	return count == ids.size()
static func validate(v: Dictionary) -> Dictionary:
	var kind: String = str(v.get("type",""))
	var common: Array = ["type","title","source","basis","unit","x_label","y_label"]
	if not text(v.get("title"),500) or not text(v.get("source"),500) or v.get("basis","observed") not in ["observed","scenario","forecast"]: return {}
	for key: String in ["unit","x_label","y_label"]:
		if not v.get(key,"") is String or v.get(key,"").length() > 80: return {}
	var ids: Dictionary = {}
	match kind:
		"gantt":
			if not fields(v,common+["tasks","dependencies","now"]) or not v.get("tasks") is Array or v.tasks.is_empty() or v.tasks.size() > 64: return {}
			if v.has("now") and not number(v.now): return {}
			for row: Variant in v.tasks:
				if not row is Dictionary or not fields(row,["id","label","start","end","progress","status"]) or not text(row.get("id"),80) or ids.has(row.id) or not text(row.get("label")): return {}
				if not number(row.get("start")) or not number(row.get("end")) or row.end < row.start: return {}
				if row.has("progress") and (not number(row.progress) or row.progress < 0 or row.progress > 1): return {}
				if row.has("status") and row.status not in ["planned","active","blocked","complete"]: return {}
				ids[row.id] = true
			var links: Variant = v.get("dependencies",[])
			if not links is Array or links.size() > 128: return {}
			for link: Variant in links:
				if not link is Dictionary or not fields(link,["source","target"]) or not ids.has(link.get("source")) or not ids.has(link.get("target")) or link.source == link.target: return {}
			if not acyclic(ids,links): return {}
		"network":
			if not fields(v,common+["nodes","links","directed"]) or not v.get("nodes") is Array or v.nodes.is_empty() or v.nodes.size() > 64 or not v.get("links") is Array or v.links.size() > 128 or not v.get("directed",false) is bool: return {}
			for row: Variant in v.nodes:
				if not row is Dictionary or not fields(row,["id","label","value","group"]) or not text(row.get("id"),80) or ids.has(row.id) or not text(row.get("label")): return {}
				if row.has("value") and (not number(row.value) or row.value < 0): return {}
				if row.has("group") and not text(row.group,80): return {}
				ids[row.id] = true
			for link: Variant in v.links:
				if not link is Dictionary or not fields(link,["source","target","value","label"]) or not ids.has(link.get("source")) or not ids.has(link.get("target")) or link.source == link.target: return {}
				if link.has("value") and (not number(link.value) or link.value <= 0): return {}
				if link.has("label") and not text(link.label): return {}
		"sunburst":
			if not fields(v,common+["nodes"]) or not v.get("nodes") is Array or v.nodes.size() < 2 or v.nodes.size() > 128: return {}
			var children: Dictionary = {}; var roots: Array = []
			for row: Variant in v.nodes:
				if not row is Dictionary or not fields(row,["id","label","parent","value"]) or not text(row.get("id"),80) or ids.has(row.id) or not text(row.get("label")): return {}
				if row.has("parent") and not text(row.parent,80): return {}
				ids[row.id] = row; children[row.id] = []
			for row: Dictionary in v.nodes:
				if not row.has("parent"): roots.append(row.id)
				elif not ids.has(row.parent) or row.parent == row.id: return {}
				else: children[row.parent].append(row.id)
			if roots.size() != 1: return {}
			var stack: Array = [[roots[0],0]]; var visited: Dictionary = {}; var sum := 0.0
			while not stack.is_empty():
				var item: Array = stack.pop_back(); var id: String = item[0]
				if visited.has(id) or item[1] > 8: return {}
				visited[id] = true
				if children[id].is_empty():
					if not number(ids[id].get("value")) or ids[id].value < 0: return {}
					sum += ids[id].value
				elif ids[id].has("value"): return {}
				for child: String in children[id]: stack.append([child,item[1]+1])
			if visited.size() != ids.size() or sum <= 0 or not is_finite(sum): return {}
		_: return {}
	return v.duplicate(true)
static func plain(v: Dictionary) -> String:
	var lines: Array = [v.title]
	if v.type == "gantt":
		for task: Dictionary in v.tasks: lines.append(str(task.label)+": "+str(task.start)+" — "+str(task.end)+(" · "+str(task.progress*100)+"%" if task.has("progress") else ""))
	else:
		for row: Dictionary in v.nodes: lines.append(str(row.label)+" ["+str(row.id)+"]"+(" ← "+str(row.parent) if row.has("parent") else "")+(": "+str(row.value) if row.has("value") else ""))
	for link: Dictionary in v.get("links",v.get("dependencies",[])): lines.append(str(link.source)+" → "+str(link.target)+(": "+str(link.value) if link.has("value") else ""))
	lines.append(L.text("Источник: ")+str(v.source))
	return "\n".join(lines)
