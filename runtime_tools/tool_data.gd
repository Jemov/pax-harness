extends RefCounted
const OMIT := ["api_key","access_token","password","credentials","authorization","узел","мат","портрет_файл","кадр_файл","файл","путь"]


static func plain(value: Variant, budget: Dictionary = {}, depth: int = 0) -> bool:
	if budget.is_empty(): budget = {"nodes":8192}
	budget.nodes -= 1
	if depth > 24 or budget.nodes < 0: return false
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not plain(value[key],budget,depth+1): return false
		return true
	if value is Array:
		for row: Variant in value:
			if not plain(row,budget,depth+1): return false
		return true
	return value == null or value is bool or (value is String and value.length() <= 65536) or value is int or (value is float and is_finite(value))


static func clean(value: Variant, depth: int = 0) -> Variant:
	if depth > 24: return null
	if typeof(value) == TYPE_OBJECT or value is Callable: return null
	if value is Vector3: return {"x":value.x,"y":value.y,"z":value.z} if value.is_finite() else null
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			if key is String and key not in OMIT and typeof(value[key]) != TYPE_OBJECT: result[key] = clean(value[key],depth+1)
		return result
	if value is Array or value is PackedStringArray:
		var result: Array = []
		for row: Variant in value:
			if typeof(row) != TYPE_OBJECT: result.append(clean(row,depth+1))
		return result
	if value is float: return value if is_finite(value) else null
	return value if value == null or value is String or value is int or value is bool else null


static func property(object: Variant, name: String) -> Variant:
	if not is_instance_valid(object) or not object is Object: return null
	if not object.get_property_list().any(func(row: Dictionary): return row.name == name): return null
	return object.get(name)


static func number(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value))


static func rows(object: Variant, field: String, keys: Array) -> Array:
	var value: Variant = property(object,field)
	var result: Array = []
	if not value is Array: return result
	for row: Variant in value:
		if row is Dictionary: result.append(fields(row,keys))
	return result


static func fields(row: Dictionary, keys: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: String in keys:
		if row.has(key): result[key] = clean(row[key])
	return result


static func success(result: Variant, before: Variant = {}, after: Variant = {}, submitted: bool = false) -> Dictionary:
	return {"ok":true,"result":clean(result),"before":clean(before),"after":clean(after),"submitted":submitted}


static func failed(code: String, before: Variant = {}, after: Variant = {}) -> Dictionary:
	return {"ok":false,"code":code,"before":clean(before),"after":clean(after),"result":{}}
