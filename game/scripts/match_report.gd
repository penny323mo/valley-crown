extends RefCounted
## Read-only end-of-match reporting. Hooks run only after authority commits.
## No enemy data, payment, damage, win rule, command or persistence authority.
const Rules=preload("res://scripts/rules.gd")
var trained={}
var completed={}
var unit_losses={}
var building_losses={}
var seen_training={}
var seen_building={}
var seen_loss={}

func reset():
	trained.clear(); completed.clear(); unit_losses.clear(); building_losses.clear()
	seen_training.clear(); seen_building.clear(); seen_loss.clear()

func record_training(unit: Dictionary) -> bool:
	if unit.get("team",-1)!=0 or not unit.get("alive",false) or unit.get("category","")!="unit": return false
	if unit.get("kind","") not in Rules.UNIT_KINDS or unit.get("id",-1)<0 or seen_training.has(unit.id): return false
	seen_training[unit.id]=true
	trained[unit.kind]=trained.get(unit.kind,0)+1
	return true

func record_completion(building: Dictionary) -> bool:
	if building.get("team",-1)!=0 or not building.get("alive",false) or not building.get("built",false) or building.get("category","")!="building": return false
	if building.get("kind","") not in Rules.BUILDABLE_KINDS or building.get("id",-1)<0 or seen_building.has(building.id): return false
	seen_building[building.id]=true
	completed[building.kind]=completed.get(building.kind,0)+1
	return true

func record_settled_loss(victim: Dictionary,damage: float) -> bool:
	# Called after HP settlement but before _kill, never by generic destruction.
	if victim.get("team",-1)!=0 or not victim.get("alive",false) or victim.get("hp",1)>0: return false
	if not is_finite(damage) or damage<=0 or victim.get("id",-1)<0 or seen_loss.has(victim.id): return false
	var kind=victim.get("kind","")
	if victim.get("category","")=="unit" and kind in Rules.UNIT_KINDS:
		unit_losses[kind]=unit_losses.get(kind,0)+1
	elif victim.get("category","")=="building" and (kind=="town_center" or kind in Rules.BUILDABLE_KINDS):
		building_losses[kind]=building_losses.get(kind,0)+1
	else: return false
	seen_loss[victim.id]=true
	return true

func make_report(outcome: String,reason: String,tick: int,age_tick: int,stats: Dictionary,bank: Dictionary) -> Dictionary:
	# Only _check_end calls this once, after final-tick events and deaths.
	return {"build":Rules.BUILD_ID,"outcome":outcome,"reason":reason,"tick":tick,
		"age_tick":age_tick,"economy":stats.duplicate(true),"bank":bank.duplicate(true),
		"trained":trained.duplicate(true),"completed":completed.duplicate(true),
		"unit_losses":unit_losses.duplicate(true),"building_losses":building_losses.duplicate(true)}

static func time_label(tick: int) -> String:
	var seconds=int(maxi(0,tick)/20)
	return "%02d:%02d" % [int(seconds/60),seconds%60]

static func page_text(report: Dictionary,page: String) -> String:
	if report.is_empty(): return "沒有已完成的戰役紀錄。"
	var lines=PackedStringArray()
	if page=="economy":
		lines.append("資源帳目（實際入庫／支出／退款／庫存）")
		for resource in ["food","wood","stone","iron"]:
			var stats=report.economy
			var delivered=int(stats.get("delivered",{}).get(resource,0)/1000)
			var spent=int((stats.get("purchased",{}).get(resource,0)+stats.get("repaired",{}).get(resource,0))/1000)
			var refunded=int(stats.get("refunded",{}).get(resource,0)/1000)
			var remaining=int(report.bank.get(resource,0)/1000)
			lines.append("%s：%d／%d／%d／%d" % [Rules.RESOURCE_NAMES[resource],delivered,spent,refunded,remaining])
		lines.append("支出含維修，未扣退款；負重未入庫不算收入。數值向下取整。")
	elif page=="units":
		lines.append("兵種　訓練完成／戰損")
		for kind in Rules.UNIT_KINDS:
			lines.append("%s　%d／%d" % [Rules.NAMES[kind],report.trained.get(kind,0),report.unit_losses.get(kind,0)])
		lines.append("訓練不含開局單位或未完成隊列；戰損包含開局單位。")
	elif page=="buildings":
		lines.append("建築　本局完工／戰損")
		for kind in ["town_center"]+Rules.BUILDABLE_KINDS:
			lines.append("%s　%d／%d" % [Rules.NAMES[kind],report.completed.get(kind,0),report.building_losses.get(kind,0)])
		lines.append("完工不含開局建築；戰損含遭摧毀的工地，不含取消或自行拆除。")
	else:
		lines.append("戰役歷時　"+time_label(report.tick))
		lines.append("城防時代　"+(time_label(report.age_tick) if report.age_tick>=0 else "未完成研究"))
		var production=0
		for count in report.trained.values(): production+=count
		var construction=0
		for count in report.completed.values(): construction+=count
		lines.append("訓練完成　%d 個單位" % production)
		lines.append("建造完成　%d 座建築" % construction)
		lines.append("選擇分頁回顧經濟、軍隊與建設。")
	return "\n".join(lines)
