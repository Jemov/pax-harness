extends RefCounted
## Bounded data widgets; the approved program supplies all object-specific rules.
static func validate(w: Variant,interactions: Array,spec: RefCounted) -> bool:
	if not w is Dictionary or not spec.keys(w,["title","subtitle","columns"],["title","columns"]) or not spec.label(w.title) or (w.has("subtitle") and not spec.label(w.subtitle)): return false
	if not w.columns is Array or w.columns.size()<1 or w.columns.size()>2: return false
	var inputs: Array=[]; var actions: Array=[]; var total:=0
	for column: Variant in w.columns:
		if not column is Array or column.size()>8: return false
		for s: Variant in column:
			total+=1
			if not s is Dictionary or not spec.label(s.get("title")): return false
			match s.get("type"):
				"fields":
					if not spec.keys(s,["type","title","rows"],["type","title","rows"]) or not s.rows is Array or s.rows.size()>12: return false
					for row: Variant in s.rows:
						if not row is Dictionary or not spec.keys(row,["label","path"],["label","path"]) or not spec.label(row.label) or not state_path(row.path,spec): return false
				"choices":
					if not spec.keys(s,["type","title","id","options"],["type","title","id","options"]) or not spec.id(s.id) or s.id in inputs or not s.options is Array or s.options.is_empty() or s.options.size()>12: return false
					inputs.append(s.id); var ids: Array=[]
					for option: Variant in s.options:
						if not option is Dictionary or not spec.keys(option,["id","title","description","value"],["id","title","value"]) or not spec.id(option.id) or option.id in ids or not spec.label(option.title) or (option.has("description") and not spec.label(option.description)) or not option.value is Dictionary or JSON.stringify(option.value).length()>2048: return false
						ids.append(option.id)
				"list":
					if not spec.keys(s,["type","title","paths","empty"],["type","title","paths","empty"]) or not spec.label(s.empty) or not s.paths is Array or s.paths.size()>12: return false
					for path: Variant in s.paths:
						if not state_path(path,spec): return false
				"progress":
					if not spec.keys(s,["type","title","path","max_path"],["type","title","path","max_path"]) or not state_path(s.path,spec) or not state_path(s.max_path,spec): return false
				"actions":
					if not spec.keys(s,["type","title","buttons"],["type","title","buttons"]) or not s.buttons is Array or s.buttons.size()>8: return false
					for button: Variant in s.buttons:
						if not button is Dictionary or not spec.keys(button,["label","event","inputs"],["label","event"]) or not spec.label(button.label) or button.event not in interactions or not button.get("inputs",[]) is Array: return false
						actions.append(button.get("inputs",[]))
				_: return false
	for action: Array in actions:
		if action.size()>4 or action.any(func(key: Variant): return key not in inputs): return false
	return total<=12
static func state_path(value: Variant,spec: RefCounted) -> bool:
	return spec.path(value) and str(value).begins_with("state.")
static func schema() -> Dictionary:
	return {"title":"{ru,en}","subtitle":"optional {ru,en}","columns":"1..2 arrays of sections, at most12 total; native themed window, no CSS/code/paths", "sections":{"fields":"{type:fields,title:{ru,en},rows:[{label:{ru,en},path:state.x}]} (max12)","choices":"{type:choices,title:{ru,en},id:input_name,options:[{id:option_id,title:{ru,en},description?:{ru,en},value:{plain payload}}]} (1..12). First selected by default; selection stays UI-local.","list":"{type:list,title:{ru,en},paths:[state.q1,state.q2,...],empty:{ru,en}}. Live nonempty strings/localized values, max12.","progress":"{type:progress,title:{ru,en},path:state.progress,max_path:state.duration}. Native progress bar, clamped display only.","actions":"{type:actions,title:{ru,en},buttons:[{label:{ru,en},event:interaction_name,inputs?:[input_name]}]}. Click sends selected option.value under event.input.<input_name>. Program must implement actual effects, queueing and resource validation; widgets never produce anything themselves."}}
