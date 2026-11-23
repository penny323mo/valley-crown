extends RefCounted
## Read-only end-of-match reporting. Hooks run only after authority commits.
## No enemy data, payment, damage, win rule, command or persistence authority.
const Rules=preload("res://scripts/rules.gd")
const MAX_EVENTS=64
var events=[]
var event_serial=0
var omitted_events=0
var trained={}
var completed={}
var unit_losses={}
var building_losses={}
var seen_training={}
var seen_building={}
var seen_loss={}
var _contact_seen=false

func reset():
	trained.clear(); completed.clear(); unit_losses.clear(); building_losses.clear()
	events.clear();event_serial=0;omitted_events=0
	seen_training.clear(); seen_building.clear(); seen_loss.clear(); _contact_seen=false

func record_training(unit: Dictionary,tick: int=0) -> bool:
	if unit.get("team",-1)!=0 or not unit.get("alive",false) or unit.get("category","")!="unit": return false
	if unit.get("kind","") not in Rules.UNIT_KINDS or unit.get("id",-1)<0 or seen_training.has(unit.id): return false
	seen_training[unit.id]=true
	trained[unit.kind]=trained.get(unit.kind,0)+1
	_event("trained",unit.kind,tick)
	return true

func record_completion(building: Dictionary,tick: int=0) -> bool:
	if building.get("team",-1)!=0 or not building.get("alive",false) or not building.get("built",false) or building.get("category","")!="building": return false
	if building.get("kind","") not in Rules.BUILDABLE_KINDS or building.get("id",-1)<0 or seen_building.has(building.id): return false
	seen_building[building.id]=true
	completed[building.kind]=completed.get(building.kind,0)+1
	_event("completed",building.kind,tick)
	return true

func record_settled_loss(victim: Dictionary,damage: float,tick: int=0) -> bool:
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
	_event("lost",kind,tick)
	return true

# Same event keys and checkpoint wire shape; the contact latch is derived
# after restore from the persisted first visible settled damage record.
func record_visible_contact(target: Dictionary, damage: float, visible: bool, tick: int) -> bool:
	if _contact_seen or tick<=0 or not visible or not is_finite(damage) or damage<=0:return false
	if target.get("team",-1)!=1 or not target.get("alive",false):return false
	var kind=target.get("kind","")
	if kind not in Rules.UNIT_KINDS+["town_center"]+Rules.BUILDABLE_KINDS:return false
	_contact_seen=events.any(func(e):return e.get("action","")=="contact")
	if _contact_seen:return false
	_contact_seen=true
	_event("contact",kind,tick)
	return true

# At most four protected indices, all are already actual committed events.
# Scenario-seeded units do not appear in this ordinary-event stream.
static func _milestone_indices(items: Array) -> Dictionary:
	var result={}
	for i in items.size():
		var item=items[i]
		var kind=item.get("kind","")
		match item.get("action",""):
			"completed":
				if not result.has("construction") and kind in Rules.BUILDABLE_KINDS:result.construction=i
			"trained":
				if not result.has("troop") and kind in Rules.UNIT_KINDS and kind not in ["villager","scout"]:result.troop=i
				if not result.has("siege") and kind=="siege":result.siege=i
			"contact":
				if not result.has("combat"):result.combat=i
		if result.size()==4:break
	return result

func _event(action: String,kind: String,tick: int):
	if tick<0:return
	event_serial+=1
	events.append({"action":action,"kind":kind,"tick":tick,"sequence":event_serial})
	if events.size()>MAX_EVENTS:
		var pinned=_milestone_indices(events).values()
		# Retain the earliest achievements and the newest ordinary details.
		# There are always at least 60 non-pinned/tail slots.
		for i in events.size():
			if i in pinned:continue
			events.remove_at(i);omitted_events+=1;break

func make_report(outcome: String,reason: String,tick: int,age_tick: int,stats: Dictionary,bank: Dictionary) -> Dictionary:
	# Only _check_end calls this once, after final-tick events and deaths.
	return {"build":Rules.BUILD_ID,"outcome":outcome,"reason":reason,"tick":tick,
		"age_tick":age_tick,"economy":stats.duplicate(true),"bank":bank.duplicate(true),
		"trained":trained.duplicate(true),"completed":completed.duplicate(true),
		"unit_losses":unit_losses.duplicate(true),"building_losses":building_losses.duplicate(true),
		"events":events.duplicate(true),"omitted_events":omitted_events}

static func time_label(tick: int) -> String:
	var seconds=int(maxi(0,tick)/20)
	return "%02d:%02d" % [int(seconds/60),seconds%60]

# Preserve the exact checkpoint keys/format; bound their event rows and
# accept only the same factual types that can be produced by this observer.
static func valid_checkpoint_events(state: Dictionary,tick: int) -> bool:
	var items=state.get("events",[])
	var serial=state.get("event_serial",-1)
	var omitted=state.get("omitted_events",-1)
	if not items is Array or items.size()>MAX_EVENTS or not serial is int or not omitted is int or omitted<0 or serial!=items.size()+omitted:return false
	var previous=0
	var contact=false
	for item in items:
		if not item is Dictionary or item.size()!=4 or not item.has_all(["action","kind","tick","sequence"]):return false
		if not item.kind is String or not item.action is String or not item.tick is int or not item.sequence is int:return false
		if item.tick<0 or item.tick>tick or item.sequence<=previous or item.sequence>serial:return false
		previous=item.sequence
		var build_or_unit=item.kind in Rules.BUILDABLE_KINDS+Rules.UNIT_KINDS+["town_center"]
		match item.action:
			"trained":
				if item.kind not in Rules.UNIT_KINDS:return false
			"completed":
				if item.kind not in Rules.BUILDABLE_KINDS:return false
			"lost":
				if not build_or_unit:return false
			"contact":
				if contact or item.tick<=0 or not build_or_unit:return false
				contact=true
			_:return false
	return true

static func _milestone_lines(report: Dictionary) -> Array[String]:
	var lines:Array[String]=["本局階段紀錄"]
	var items=report.get("events",[])
	var indices=_milestone_indices(items)
	var labels={"construction":"首次完工","troop":"首次出兵","siege":"首次攻城車出兵","combat":"首次擊中敵方目標"}
	var timeline=[]
	for key in ["construction","troop","siege","combat"]:
		if not indices.has(key):continue
		var item=items[indices[key]]
		# A first army birth may already be the first siege. Show it once.
		if key=="siege" and indices.get("troop",-1)==indices[key]:continue
		var text=labels[key]
		if key in ["construction","troop"]:text+=" · "+Rules.NAMES.get(item.kind,item.kind)
		timeline.append({"tick":item.tick,"sequence":item.sequence,"text":text})
	var age_tick=report.get("age_tick",-1)
	if age_tick>=0 and report.get("skirmish_mode","") not in ["battle","fortress","survival","breach"]:
		timeline.append({"tick":age_tick,"sequence":0,"text":"完成研究 · 城防時代"})
	timeline.sort_custom(func(a,b):return a.tick<b.tick if a.tick!=b.tick else a.sequence<b.sequence)
	for row in timeline:lines.append(time_label(row.tick)+" · "+row.text)
	if timeline.is_empty():lines.append("本局沒有已完成的階段紀錄。")
	lines.append(time_label(report.tick)+" · "+{"victory":"勝利","defeat":"失敗","draw":"和局"}.get(report.outcome,"戰役結束"))
	return lines

static func page_text(report: Dictionary,page: String,compact_overview=false) -> String:
	if report.is_empty(): return "沒有已完成的戰役紀錄。"
	var lines=PackedStringArray()
	# Only the compact live summary requests this order; saved history and
	# larger views keep the original complete report and layout.
	if compact_overview and page=="overview":
		lines.append_array(_milestone_lines(report))
		lines.append("")
	if report.has("layout_title"):lines.append("戰場："+str(report.layout_title))
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
		if report.get("victory_mode","conquest")=="control":
			lines.append("戰役模式　中央據點爭奪")
			var scores=report.get("control_ticks",[0,0])
			lines.append("控制時間　我方 %d / 敵方 %d 秒（180 秒勝利）" % [scores[0]/20,scores[1]/20])
		elif report.get("victory_mode","conquest")=="supply":
			lines.append("戰役模式　資源爭奪戰")
			var supplies=report.get("supply_progress",[{"food":0,"wood":0},{"food":0,"wood":0}])
			for team in 2:lines.append(("我方" if team==0 else "敵方")+"送抵　糧 %d/600 · 木 %d/400" % [supplies[team].food/1000,supplies[team].wood/1000])
		else:
			lines.append("戰役模式　"+preload("res://scripts/skirmish_policy.gd").title(report.get("skirmish_mode","standard")))
		if report.has("escort"):
			var escort=report.escort
			lines.append("護送階段　%d/3 · 村民存活 %d/3" % [mini(int(escort.get("stage",0)),3),int(escort.get("villagers_alive",0))])
			var phases=["抵達前哨","前哨建成","反攻擊退"]
			for index in mini(escort.get("stage_ticks",[]).size(),3):
				lines.append("%s  %s" % [time_label(escort.stage_ticks[index]),phases[index]])
		if report.has("forward_depot"):
			var supply=report.forward_depot
			lines.append("前線倉庫交付　木 %d · 糧 %d · %d 次" % [int(supply.get("wood_milli",0)/1000),int(supply.get("food_milli",0)/1000),int(supply.get("deliveries",0))])
		if report.has("expedition"):
			var mission=report.expedition
			lines.append("遠征階段　%d/5" % mini(int(mission.get("stage",0)),5))
			for index in mission.get("stage_ticks",[]).size():
				lines.append("%s  %s" % [time_label(mission.stage_ticks[index]),preload("res://scripts/frontier_expedition.gd").TITLES[index]])
		if not compact_overview:
			lines.append("")
			lines.append_array(_milestone_lines(report))
		lines.append("")
		lines.append("戰役歷時　"+time_label(report.tick))
		lines.append("城防時代　"+("開局已有" if report.get("skirmish_mode","") in ["battle","fortress","survival","breach"] else (time_label(report.age_tick) if report.age_tick>=0 else "未完成研究")))
		var production=0
		for count in report.trained.values(): production+=count
		var construction=0
		for count in report.completed.values(): construction+=count
		lines.append("訓練完成　%d 個單位" % production)
		lines.append("建造完成　%d 座建築" % construction)
		lines.append("選擇分頁回顧經濟、軍隊與建設。")
		lines.append("")
		lines.append("我方戰役紀錄（最近 12 項）")
		var history=report.get("events",[]).duplicate(true)
		if report.get("age_tick",-1)>=0 and report.get("skirmish_mode","") not in ["battle","fortress","survival","breach"]:history.append({"action":"research","kind":"age2","tick":report.age_tick,"sequence":-1})
		history.sort_custom(func(a,b):return a.tick<b.tick if a.tick!=b.tick else a.sequence<b.sequence)
		var hidden=int(report.get("omitted_events",0))+maxi(0,history.size()-12)
		if hidden>0:lines.append("較早 %d 項未列出；總數仍完整。" % hidden)
		if history.is_empty():lines.append("尚無建造、出兵或戰損紀錄。")
		for event in history.slice(maxi(0,history.size()-12)):
			var action={"trained":"出兵","completed":"完工","lost":"戰損","research":"研究","contact":"交戰"}.get(event.action,"")
			lines.append("%s  %s · %s" % [time_label(event.tick),action,Rules.NAMES.get(event.kind,event.kind)])
	return "\n".join(lines)
