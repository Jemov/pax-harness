extends RefCounted
const Spec=preload("res://mods/pax_harness/src/creation/program_spec.gd")
static func merge(source: Dictionary,changes: Variant) -> Dictionary:
	if not changes is Array or changes.is_empty() or changes.size()>16: return failure("program_patch","Expected 1..16 {path,value} replacements")
	var program: Dictionary=source.duplicate(true)
	for index: int in changes.size():
		var change: Variant=changes[index]; var at: String="program_patch."+str(index)
		if not change is Dictionary or not Spec.keys(change,["path","value"],["path","value"]) or not Spec.path(change.path): return failure(at,"Expected a dotted program path and plain replacement value")
		var parts: PackedStringArray=change.path.split(".")
		if parts[0] not in ["ui","handlers","state","events"]: return failure(at,"Only ui, handlers, state and events may be replaced")
		var target: Dictionary=program
		for part: String in parts.slice(0,-1):
			if not target.has(part): target[part]={}
			if not target[part] is Dictionary: return failure(at,"Parent must be a dictionary; replace an entire array instead of indexing it")
			target=target[part]
		target[parts[-1]]=change.value
	var checked: Dictionary=Spec.validate(program)
	return {"ok":true,"program":program} if checked.ok else checked
static func failure(path: String,detail: String) -> Dictionary:
	return {"ok":false,"code":"program.invalid_patch","path":path,"detail":detail,"result":{"path":path,"detail":detail}}
