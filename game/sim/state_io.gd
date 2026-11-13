class_name StateIO
extends RefCounted
## Generic snapshot of plain-data objects by reflection over their script variables, so a field added to
## a state class later is part of the snapshot without touching this file. The result contains only
## values that survive var_to_bytes (no Objects); packed arrays, arrays and dictionaries are deep copies.
## A state class lists variables that are NOT state (computed properties, references to static data) in
## its constant STATE_SKIP.

static var _names_cache := {}  # Script -> Array[String]


static func names_of(obj: Object) -> Array:
	var script: Script = obj.get_script()
	if _names_cache.has(script):
		return _names_cache[script]
	var skip: Array = script.get_script_constant_map().get("STATE_SKIP", [])
	var out: Array = []
	for prop: Dictionary in obj.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and not skip.has(prop["name"]):
			out.append(prop["name"])
	_names_cache[script] = out
	return out


static func dump(obj: Object) -> Dictionary:
	var d := {}
	for n: String in names_of(obj):
		d[n] = to_plain(obj.get(n))
	return d


static func to_plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_OBJECT:
			return dump(v) if v != null else null
		TYPE_ARRAY:
			var out := []
			for e: Variant in v:
				out.append(to_plain(e))
			return out
		TYPE_DICTIONARY:
			var out := {}
			for k: Variant in v:
				out[k] = to_plain(v[k])
			return out
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, \
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, \
		TYPE_PACKED_VECTOR4_ARRAY:
			return v.duplicate()
	return v


## Writes `d` into `obj` in place. Nested objects and typed object arrays keep their existing instances
## where the counts match (the view and the HUD may hold references to them).
static func restore(obj: Object, d: Dictionary) -> void:
	for n: String in names_of(obj):
		if not d.has(n):
			continue
		var cur: Variant = obj.get(n)
		var src: Variant = d[n]
		if typeof(cur) == TYPE_OBJECT and cur != null and src is Dictionary:
			restore(cur, src)
		elif cur is Array and src is Array:
			_restore_array(cur, src)
		else:
			obj.set(n, to_plain(src))


static func _restore_array(arr: Array, src: Array) -> void:
	if arr.is_typed() and arr.get_typed_builtin() == TYPE_OBJECT:
		var script: Script = arr.get_typed_script()
		arr.resize(src.size())
		for i in src.size():
			if arr[i] == null:
				arr[i] = script.new()
			restore(arr[i], src[i])
	else:
		arr.clear()
		for e: Variant in src:
			arr.append(to_plain(e))
