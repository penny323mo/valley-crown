extends RefCounted
## Presentation only. Bank is milli-units; never reads world entities or deposits.
const Rules=preload("res://scripts/rules.gd")
const RESOURCES=["food","wood","stone","iron"]
static func describe(cost: Dictionary,bank: Dictionary,population: int,capacity: int,unit: bool,unlocked: bool=true,queued: int=0) -> String:
	var parts: Array[String]=[]
	if not unlocked:parts.append("需城防時代")
	if unit and queued>=5:parts.append("生產隊列已滿")
	if unit and population>=capacity:
		parts.append("人口 %d/%d · %s" % [population,capacity,"已達50人上限" if population>=Rules.POP_LIMIT else "需民居"])
	for resource in RESOURCES:
		var missing=maxi(0,int(cost.get(resource,0))*1000-int(bank.get(resource,0)))
		if missing>0:parts.append("缺"+Rules.RESOURCE_NAMES[resource]+str(ceili(missing/1000.0)))
	return "；".join(parts)
