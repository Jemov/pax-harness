extends RefCounted
## Structural diagnostics only. No handlers, ownership checks or world effects.

const MAX_RAW_CHARACTERS = 2097152
const MAX_SCHEMA_CHARACTERS = 131072
const MAX_DATA_NODES = 16384
const MAX_CHECK_STEPS = 32768

const KEYS = ["type", "properties", "required", "additionalProperties", "items", "enum", "const", "anyOf", "minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems", "description", "title", "default", "$schema"]


static func validate(raw: String, contract: Variant) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	if raw.length() > MAX_RAW_CHARACTERS:
		issue(diagnostics, "response_size_limit", "response", "Response exceeds the local structural-validation size limit.")
		return {"ok": false, "parse_ok": false, "schema_available": false, "parsed": null, "diagnostics": diagnostics, "errors": _codes(diagnostics)}
	var parser := JSON.new()
	var parsed_ok: bool = parser.parse(raw) == OK
	if not parsed_ok:
		issue(diagnostics, "invalid_json", "response", "Response is not a complete strict JSON value.")
	var schema_result: Dictionary = validate_schema(contract)
	diagnostics.append_array(schema_result.diagnostics)
	if parsed_ok and not _plain_data(parser.data, {"nodes": MAX_DATA_NODES}, 0):
		issue(diagnostics, "response_complexity_limit", "response", "Response exceeds supported JSON depth, size or numeric limits.")
	elif parsed_ok and schema_result.ok:
		_check(parser.data, contract, "response", diagnostics, {"steps": MAX_CHECK_STEPS})
	return {"ok": diagnostics.is_empty(), "parse_ok": parsed_ok, "schema_available": schema_result.ok,
		"parsed": parser.data if parsed_ok else null, "diagnostics": diagnostics, "errors": _codes(diagnostics)}


static func validate_schema(contract: Variant) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	if not contract is Dictionary:
		issue(diagnostics, "schema_unavailable", "output_contract", "This response contract has no supported machine-readable schema.")
	elif not _plain_data(contract, {"nodes": MAX_DATA_NODES}, 0) or JSON.stringify(contract).length() > MAX_SCHEMA_CHARACTERS:
		issue(diagnostics, "invalid_schema", "output_contract", "Schema exceeds supported JSON depth, size or numeric limits.")
	else:
		var definition_error: String = _definition_error(contract)
		if definition_error != "":
			issue(diagnostics, definition_error, "output_contract", "Schema contains an unsupported keyword." if definition_error == "schema_unavailable" else "Schema definition has invalid types, lengths or contradictory bounds.")
	return {"ok": diagnostics.is_empty(), "diagnostics": diagnostics, "errors": _codes(diagnostics)}


static func _plain_data(value: Variant, budget: Dictionary, depth: int) -> bool:
	budget.nodes -= 1
	if depth > 48 or budget.nodes < 0:
		return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _plain_data(value[key], budget, depth + 1):
				return false
		return true
	if value is Array:
		for item: Variant in value:
			if not _plain_data(item, budget, depth + 1):
				return false
		return true
	return value == null or value is String or value is bool or _number(value)


static func issue(diagnostics: Array, code: String, path: String, message: String) -> void:
	diagnostics.append({"code": code, "path": path, "message": message, "severity": "error"})


static func _codes(diagnostics: Array[Dictionary]) -> PackedStringArray:
	var codes: PackedStringArray = []
	for item: Dictionary in diagnostics:
		codes.append(item.code + ":" + item.path)
	return codes


static func _definition_error(schema: Dictionary, depth: int = 0) -> String:
	if depth > 24:
		return "invalid_schema"
	for key: Variant in schema:
		if key not in KEYS:
			return "schema_unavailable"
	var types: Variant = schema.get("type", [])
	types = [types] if types is String else types
	if not types is Array:
		return "invalid_schema"
	for type: Variant in types:
		if type not in ["object", "array", "string", "number", "integer", "boolean", "null"]:
			return "invalid_schema"
	var nested: Array = []
	if schema.has("properties"):
		if not schema.properties is Dictionary:
			return "invalid_schema"
		for key: Variant in schema.properties:
			if not key is String or not schema.properties[key] is Dictionary:
				return "invalid_schema"
			nested.append(schema.properties[key])
	if schema.has("required") and (not schema.required is Array or not schema.required.all(func(key: Variant): return key is String)):
		return "invalid_schema"
	if schema.has("items"):
		if not schema.items is Dictionary:
			return "invalid_schema"
		nested.append(schema.items)
	if schema.has("additionalProperties"):
		if schema.additionalProperties is Dictionary:
			nested.append(schema.additionalProperties)
		elif not schema.additionalProperties is bool:
			return "invalid_schema"
	if schema.has("anyOf"):
		if not schema.anyOf is Array or schema.anyOf.is_empty() or schema.anyOf.size() > 16:
			return "invalid_schema"
		for branch: Variant in schema.anyOf:
			if not branch is Dictionary:
				return "invalid_schema"
			nested.append(branch)
	if schema.has("enum") and (not schema.enum is Array or schema.enum.is_empty()):
		return "invalid_schema"
	for key: String in ["minimum", "maximum", "minLength", "maxLength", "minItems", "maxItems"]:
		if schema.has(key) and not _number(schema[key]):
			return "invalid_schema"
		if schema.has(key) and key in ["minLength", "maxLength", "minItems", "maxItems"] and (float(schema[key]) < 0 or float(schema[key]) != floor(float(schema[key]))):
			return "invalid_schema"
	for pair: Array in [["minimum", "maximum"], ["minLength", "maxLength"], ["minItems", "maxItems"]]:
		if schema.has(pair[0]) and schema.has(pair[1]) and schema[pair[0]] > schema[pair[1]]:
			return "invalid_schema"
	for child: Dictionary in nested:
		var error: String = _definition_error(child, depth + 1)
		if error != "":
			return error
	return ""


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _type(value: Variant, kind: String) -> bool:
	match kind:
		"object": return value is Dictionary
		"array": return value is Array
		"string": return value is String
		"number": return _number(value)
		"integer": return _number(value) and float(value) == floor(float(value))
		"boolean": return value is bool
		"null": return value == null
	return false


static func _equal(a: Variant, b: Variant) -> bool:
	if _number(a) and _number(b):
		return float(a) == float(b)
	if typeof(a) != typeof(b):
		return false
	return a == b


static func _check(value: Variant, schema: Dictionary, path: String, diagnostics: Array[Dictionary], budget: Dictionary) -> void:
	budget.steps -= 1
	if budget.steps < 0:
		if not diagnostics.any(func(item: Dictionary): return item.code == "validation_complexity_limit"):
			issue(diagnostics, "validation_complexity_limit", path, "Schema evaluation exceeded its local operation limit.")
		return
	if value is float and not is_finite(value):
		issue(diagnostics, "nonfinite_number", path, "Response contains a nonfinite number.")
		return
	if schema.has("anyOf"):
		var matched := false
		for branch: Dictionary in schema.anyOf:
			var branch_errors: Array[Dictionary] = []
			_check(value, branch, path, branch_errors, budget)
			matched = matched or branch_errors.is_empty()
		if not matched:
			issue(diagnostics, "schema_anyOf", path, "Value does not match any declared schema alternative.")
	var types: Variant = schema.get("type", [])
	types = [types] if types is String else types
	if not types.is_empty() and not types.any(func(kind: String): return _type(value, kind)):
		issue(diagnostics, "schema_type", path, "Value does not match the declared JSON type.")
		return
	if schema.has("enum") and not schema.enum.any(func(item: Variant): return _equal(value, item)):
		issue(diagnostics, "schema_enum", path, "Value is outside the declared enum.")
	if schema.has("const") and not _equal(value, schema["const"]):
		issue(diagnostics, "schema_const", path, "Value differs from the declared constant.")
	if value is Dictionary:
		for key: String in schema.get("required", []):
			if not value.has(key):
				issue(diagnostics, "schema_required", path + "." + key, "A required field is missing.")
		for key: String in value:
			if schema.get("properties", {}).has(key):
				_check(value[key], schema.properties[key], path + "." + key, diagnostics, budget)
			else:
				var extra: Variant = schema.get("additionalProperties", true)
				if extra is Dictionary:
					_check(value[key], extra, path + "." + key, diagnostics, budget)
				elif extra == false:
					issue(diagnostics, "schema_extra_field", path + "." + key, "The contract does not allow this field.")
	elif value is Array:
		for bound: String in ["minItems", "maxItems"]:
			if schema.has(bound) and (value.size() < schema[bound] if bound == "minItems" else value.size() > schema[bound]):
				issue(diagnostics, "schema_" + bound, path, "Array length is outside the declared bound.")
		if schema.has("items"):
			for index: int in value.size():
				_check(value[index], schema.items, path + "[%d]" % index, diagnostics, budget)
	elif value is String:
		for bound: String in ["minLength", "maxLength"]:
			if schema.has(bound) and (value.length() < schema[bound] if bound == "minLength" else value.length() > schema[bound]):
				issue(diagnostics, "schema_" + bound, path, "Text length is outside the declared bound.")
	elif _number(value):
		for bound: String in ["minimum", "maximum"]:
			if schema.has(bound) and (value < schema[bound] if bound == "minimum" else value > schema[bound]):
				issue(diagnostics, "schema_" + bound, path, "Number is outside the declared bound.")
