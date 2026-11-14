extends RefCounted
## Read-only catalogue: base values from current gameplay rules, never live enemy data.
const Rules=preload("res://scripts/rules.gd")
const SECTIONS=["兵種","建築","科技"]
const ROLES={
	"villager":"採集、建造與維修。村民不是主力軍隊；先保持資源入庫，再擴軍。",
	"scout":"探索迷霧與尋找敵軍。速度快、視野廣，但正面戰鬥較弱。",
	"spearman":"近戰防線，對騎兵有額外傷害；小心敵方弓手。",
	"archer":"遠距支援，適合對付長槍兵；保持距離，避免被騎兵近身。",
	"cavalry":"快速突擊，適合追擊弓手；避開長槍兵的反騎兵傷害。",
	"siege":"近距攻城，對所有建築有額外傷害；行動緩慢，需要其他兵種護送。"
}
const BUILDING_ROLES={
	"town_center":"起始主堡，不能另建。接收資源、訓練村民與斥候、研究科技。主堡被毀會落敗。",
	"house":"增加人口空間，供村民與軍隊使用。",
	"barracks":"訓練長槍兵，建立近戰防線。",
	"range":"訓練弓手，提供遠距火力。",
	"storehouse":"資源交付點。靠近採集區建造，可縮短往返路程。",
	"farm":"每田一名村民耕作。選村民後點農田；收成先放入負重，送回主堡／倉庫才入庫。",
	"tower":"自動攻擊可見敵軍的防守建築；不能取代軍隊進攻。",
	"stable":"訓練騎兵，提供快速突擊部隊。",
	"workshop":"製造攻城車，支援對敵方建築的攻擊。"
}
static func entries(section: int) -> Array:
	match posmod(section,3):
		0:return Rules.UNIT_KINDS.duplicate()
		1:return ["town_center"]+Rules.BUILDABLE_KINDS
		_:return ["age2"]+Rules.MILITARY_TECHS
static func producer(kind: String) -> String:
	for building in ["town_center"]+Rules.BUILDABLE_KINDS:
		if kind in Rules.products_for(building):return building
	return ""
static func entry(section: int,index: int) -> Dictionary:
	var ids=entries(section);var kind=ids[posmod(index,ids.size())]
	var lines=PackedStringArray()
	if section==0:
		lines.append(ROLES[kind])
		lines.append("訓練："+Rules.NAMES[producer(kind)]+" · "+str(Rules.TRAIN_TICKS[kind]/20.0)+" 秒")
		lines.append("成本："+Rules.cost_label(kind))
		lines.append("時代："+("城防時代" if kind in Rules.AGE2_KINDS else "聚落時代"))
		lines.append("生命 %d · 護甲 %d · 基礎攻擊 %d" % [Rules.HP[kind],Rules.ARMOR[kind],Rules.DAMAGE[kind]])
		lines.append("射程 %.1f · 攻擊間隔 %.1f 秒" % [Rules.RANGE[kind],Rules.ATTACK_TICKS[kind]/20.0])
		lines.append("移速 %.1f · 視野 %d" % [Rules.SPEED[kind],Rules.SIGHT[kind]])
		for target in Rules.CONTENT.UNIT_COUNTER_BONUSES.get(kind,{}):
			var bonus=Rules.CONTENT.UNIT_COUNTER_BONUSES[kind][target]
			lines.append("對"+Rules.NAMES[target]+"：額外 +%d；未升級每次命中 %d 傷害（已扣護甲）。" % [bonus,Rules.CONTENT.resolve_damage(kind,target).damage])
		if kind=="siege":lines.append("對建築額外 +%d。對主堡未升級每次命中 %d 傷害（已扣護甲）。" % [Rules.CONTENT.SIEGE_BUILDING_BONUS,Rules.CONTENT.resolve_damage(kind,"town_center").damage])
		for tech in Rules.MILITARY_TECHS:
			if kind in Rules.TECH_UNITS[tech]:lines.append("可受益科技："+Rules.NAMES[tech]+"，攻擊 +%d。" % Rules.TECH_BONUS)
		if kind in ["scout","spearman","archer","cavalry"]:lines.append("可回己方主堡旁休整；安全待命 10 秒後，每 2 秒回 1 生命。")
	elif section==1:
		lines.append(BUILDING_ROLES[kind])
		if Rules.COSTS.has(kind):lines.append("建造："+Rules.cost_label(kind)+" · "+str(Rules.BUILD_TIME[kind])+" 秒")
		lines.append("時代："+("城防時代" if kind in Rules.AGE2_KINDS else "聚落時代"))
		lines.append("生命 %d · 護甲 %d · 視野 %d" % [Rules.HP[kind],Rules.ARMOR[kind],Rules.SIGHT[kind]])
		var population=Rules.CONTENT.BUILDINGS[kind].get("population",0)
		if population>0:lines.append("人口空間 +%d；全軍上限 %d。" % [population,Rules.POP_LIMIT])
		var products=PackedStringArray()
		for product in Rules.products_for(kind):products.append(Rules.NAMES[product])
		if not products.is_empty():lines.append("生產："+"、".join(products)+"。完成施工後才可訓練；排隊已付款，完成後才出生。")
		if kind=="tower":lines.append("攻擊 %d · 射程 %.1f · 每隊最多 %d 座。" % [Rules.DAMAGE[kind],Rules.RANGE[kind],Rules.CONTENT.BUILDINGS.tower.limit])
		if kind!="town_center":lines.append("選村民建造；受損的已完成建築可由村民維修。拆除不退資源。")
	else:
		lines.append("研究場所：主堡。與訓練共用隊列，排隊不等於完成。")
		lines.append("成本："+Rules.cost_label(kind))
		lines.append("研究時間："+str(Rules.TRAIN_TICKS[kind]/20.0)+" 秒")
		if kind=="age2":lines.append("升至城防時代，解鎖馬廄、工坊、騎兵、攻城車與軍備科技。")
		else:
			lines.append("需要城防時代；每項只能研究一次。")
			lines.append(Rules.TECH_DETAILS[kind]+"。完成後適用現有及新訓練的指定兵種。")
	lines.append("資料為目前版本基礎值；已研究科技會另加效果。")
	return {"kind":kind,"title":Rules.NAMES[kind],"body":"\n\n".join(lines),"index":posmod(index,ids.size()),"count":ids.size()}
