extends RefCounted
## Recruitment recommendation from sanitized faction records only.
## No authority lookup, future knowledge, spawn, payment or combat changes.
const Rules=preload("res://scripts/rules.gd")
const ORDER=["spearman","archer","cavalry","siege"]
const BASE={"spearman":5,"archer":5,"cavalry":5,"siege":2}
const MAX_COUNTER_ADDITION=5
const MAX_SIEGE_ADDITION=4
const FORTIFIED_PRODUCERS=["barracks","range","stable","workshop"]

static func plan(records: Array, candidates: Array=ORDER) -> Dictionary:
	var owned={}; var visible={}; var seen={}
	var towers=0; var producers=0
	for record in records:
		if not record.get("alive",false) or seen.has(record.get("id",-1)): continue
		seen[record.get("id",-1)]=true
		if record.get("owned",false) and record.get("team",-1)==1:
			var kind=record.get("kind","")
			if record.get("category","")=="unit" and kind in ORDER: owned[kind]=owned.get(kind,0)+1
			if record.get("category","")=="building":
				for item in record.get("queue",[]):
					var queued=item.get("kind","")
					if queued in ORDER: owned[queued]=owned.get(queued,0)+1
		elif not record.get("owned",false) and record.get("team",-1)==0 and not record.get("remembered",true) and record.get("category","")=="unit":
			var kind=record.get("kind","")
			if kind in Rules.UNIT_KINDS: visible[kind]=visible.get(kind,0)+1
		elif not record.get("owned",false) and record.get("team",-1)==0 and not record.get("remembered",true) and record.get("category","")=="building" and record.get("built",false):
			if record.get("kind","")=="tower": towers+=1
			elif record.get("kind","") in FORTIFIED_PRODUCERS: producers+=1
	var desired=BASE.duplicate(); var counters={}
	# Current visible fortifications justify a bounded siege complement. Never
	# remember enemy construction, infer unseen towers, or replace the escort
	# baseline. Queued siege below counts against this same recruitment goal.
	desired.siege+=mini(MAX_SIEGE_ADDITION,towers*2+int(producers/2))
	for kind in ORDER:
		var pressure=0
		for target_kind in Rules.CONTENT.UNIT_COUNTER_BONUSES.get(kind,{}):
			if Rules.CONTENT.UNIT_COUNTER_BONUSES[kind][target_kind]>0: pressure+=visible.get(target_kind,0)
		counters[kind]=mini(MAX_COUNTER_ADDITION,pressure)
		desired[kind]+=counters[kind]
	var choice="spearman"; var best=INF
	for kind in ORDER:
		if kind not in candidates: continue
		var ratio=float(owned.get(kind,0))/desired[kind]
		if ratio<best: choice=kind; best=ratio
	return {"kind":choice,"owned_and_queued":owned,"visible_enemy":visible,"desired":desired}
