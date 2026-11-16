extends RefCounted
const Rules=preload("res://scripts/rules.gd")
static func plan(building: Dictionary,bank: Dictionary,free_population: int,commands: Array,unlocked: bool) -> Dictionary:
	var result={"kind":"","count":0,"cost":{},"reason":"生產建築已失效"}
	if not building.get("owned",false) or not building.get("alive",false) or building.get("remembered",false) or building.get("team",-1)!=0 or building.get("category","")!="building" or not building.get("built",false): return result
	if building.get("kind","") not in ["barracks","range","stable","workshop"]: return result
	var kind=Rules.PRODUCES[building.kind];result.kind=kind
	if not unlocked: result.reason="需要城防時代";return result
	for command in commands:
		if command.get("team",-1)==0:result.reason="指令處理中";return result
	var slots=5-building.get("queue",[]).size()
	if slots<=0:result.reason="生產隊列已滿";return result
	if free_population<=0:result.reason="人口已滿，先建民居";return result
	var count=mini(3,mini(slots,free_population))
	for resource in Rules.COSTS[kind]:count=mini(count,int(bank.get(resource,0)/(Rules.COSTS[kind][resource]*1000)))
	if count<=0:result.reason="資源不足";return result
	result.count=count;result.reason=""
	for resource in Rules.COSTS[kind]:result.cost[resource]=Rules.COSTS[kind][resource]*count
	return result
