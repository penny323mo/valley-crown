extends RefCounted
## Public victory objective, based only on committed delivery statistics.
const FOOD=600000
const WOOD=400000
static func progress(stats: Dictionary) -> Dictionary:
	var delivered=stats.get("delivered",{})
	return {"food":clampi(int(delivered.get("food",0)),0,FOOD),"wood":clampi(int(delivered.get("wood",0)),0,WOOD)}
static func complete(stats: Dictionary) -> bool:
	var p=progress(stats);return p.food>=FOOD and p.wood>=WOOD
static func caption(stats: Dictionary) -> String:
	var p=progress(stats);return "糧 %d/600 · 木 %d/400" % [p.food/1000,p.wood/1000]
