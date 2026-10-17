extends RefCounted
## Read the official record: native YAML headers and biography are separate.
const Data = preload("res://mods/pax_harness/runtime_tools/tool_data.gd")
const FIELDS := ["name","who","temperament","age","чем занят","dream","where","race","guest","died","gone"]

static func read(memory: Object, name: String) -> Dictionary:
	if not is_instance_valid(memory) or not memory.has_method("header"): return {}
	var record: Dictionary = Data.fields(memory.header("person",name),FIELDS)
	if memory.has_method("_read_it") and memory.has_method("_file_name"):
		var text: String = str(memory._read_it(memory._file_name("person",name)))
		if text.begins_with("---"):
			var end: int = text.find("---",3)
			if end >= 0:
				var biography: String = text.substr(end+3).split("## ключевые моменты",true,1)[0].strip_edges()
				if biography.to_utf8_buffer().size() <= 65536: record["lore"] = biography
	return record
