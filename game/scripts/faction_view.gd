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
	# Retire a remembered static object only when its remembered physical
	# footprint is inspected and absent. Never inspect hidden current liveness.
	for id in memory.keys():
		if observed.has(id): continue
		var p = memory[id].pos
		var cell = Vector2i(floori(p.x+Rules.MAP_HALF),floori(p.z+Rules.MAP_HALF))
		var width = Rules.FOOTPRINT.get(memory[id].kind,1)
		var low = floori(width/2.0)
		var inspected = false
		for y in range(cell.y-low,cell.y-low+width):
			for x in range(cell.x-low,cell.x-low+width):
				if x>=0 and y>=0 and x<Rules.MAP_SIZE and y<Rules.MAP_SIZE and visible[y*Rules.MAP_SIZE+x]: inspected=true
		if inspected: memory.erase(id)
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
	# Both insertion branches deeply freeze each value before it enters next.
	# Freeze only this fresh outer map; never recopy already-frozen records.
	next.make_read_only()
	current = next

func records(): return current
func get_record(id): return current.get(id, {})
