extends RefCounted
## Deterministic storage-property snapshot, including actual mesh/skin/material resources.
## Animations are verified separately with Contact._snapshot plus scoped track checks.
static func snapshot(scene: Node) -> PackedByteArray:
	return var_to_bytes(_node(scene, scene, {}))
static func _value(value: Variant, scene: Node, resources: Dictionary) -> Variant:
	if value is Resource:
		var id: int = value.get_instance_id()
		if resources.has(id):
			return ["RESOURCE_REFERENCE", resources[id]]
		var index: int = resources.size()
		resources[id] = index
		var properties: Array = []
		for info in value.get_property_list():
			if (int(info.usage) & PROPERTY_USAGE_STORAGE) == 0:
				continue
			properties.append([str(info.name), _value(value.get(info.name), scene, resources)])
		return ["RESOURCE", index, value.get_class(), properties]
	if value is Node:
		return ["NODE_REFERENCE", str(scene.get_path_to(value))]
	if value is Object:
		assert(false, "Unexpected stored object in preservation snapshot")
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_value(item, scene, resources))
		return array
	if value is Dictionary:
		var dictionary: Array = []
		for key in value:
			dictionary.append([_value(key, scene, resources), _value(value[key], scene, resources)])
		return ["DICTIONARY", dictionary]
	return value
static func _node(node: Node, scene: Node, resources: Dictionary) -> Array:
	var properties: Array = []
	for info in node.get_property_list():
		if (int(info.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		properties.append([str(info.name), _value(node.get(info.name), scene, resources)])
	var children: Array = []
	for child in node.get_children():
		children.append(_node(child, scene, resources))
	return [str(node.name), node.get_class(), properties, children]
