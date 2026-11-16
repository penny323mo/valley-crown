extends RefCounted
const Rules = preload("res://scripts/rules.gd")
## Value-only observation boundary. Hidden static records never consult liveness.
var memory: Dictionary = {}
var current: Dictionary = {}
var tick := 0

static func freeze(value):
	if value is Dictionary:
		var result = {}
		for key in value: result[key] = freeze(value[key])
		result.make_read_only()
		return result
	if value is Array or value is PackedVector3Array or value is PackedByteArray:
		var result = []
		for item in value: result.append(freeze(item))
		result.make_read_only()
		return result
	assert(not value is Object)
	return value

func publish(observed: Dictionary, visible, now: int):
	tick = now
	# Only a legitimate center observation can retire a static memory.
	for id in memory.keys():
		var p = memory[id].pos
		var cell = Vector2i(clampi(floori(p.x+Rules.MAP_HALF),0,Rules.MAP_SIZE-1),clampi(floori(p.z+Rules.MAP_HALF),0,Rules.MAP_SIZE-1))
		if visible[cell.y*Rules.MAP_SIZE+cell.x] and not observed.has(id): memory.erase(id)
	var next = {}
	for id in observed:
		var record = observed[id].duplicate(true)
		record.remembered = false
		record.last_seen_tick = now
		next[id] = freeze(record)
		if record.category in ["building", "resource"] and not record.owned:
			memory[id] = next[id]
	for id in memory:
		if not next.has(id):
			var record = memory[id].duplicate(true)
			record.remembered = true
			next[id] = freeze(record)
	current = freeze(next)

func records(): return current
func get_record(id): return current.get(id, {})
