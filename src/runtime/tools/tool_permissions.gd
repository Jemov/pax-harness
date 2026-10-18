extends RefCounted
## Player preferences narrow tool grants. They never override native capability checks.
const OFF_BY_DEFAULT := ["money.add","resources.add","characters.create","bodies.set_parameter","provinces.set_owner","diplomacy.change_relation"]
static func allowed(owner: Node, name: String) -> bool:
	if not is_instance_valid(owner) or not owner.has_method("get_setting"): return true
	var overrides: Variant=owner.get_setting("tool_permissions",{}) if is_instance_valid(owner) and owner.has_method("get_setting") else {}
	return bool(overrides[name]) if overrides is Dictionary and overrides.get(name) is bool else name not in OFF_BY_DEFAULT
static func set_many(owner: Node, names: Array, enabled: bool) -> void:
	var stored: Variant=owner.get_setting("tool_permissions",{})
	var overrides: Dictionary=stored.duplicate(true) if stored is Dictionary else {}
	for name: String in names: overrides[name]=enabled
	owner.set_setting("tool_permissions",overrides)
static func state(owner: Node, names: Array) -> int:
	var count:=0
	for name: String in names:
		if allowed(owner,name): count+=1
	return 0 if count==0 else 2 if count==names.size() else 1
