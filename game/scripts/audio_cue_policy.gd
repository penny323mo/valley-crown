extends RefCounted
## Presentation-only: accepts only the local FactionView, never authority events.
var previous={}
var last_tick=-1
var last_any=-10000
var last_kind={}
var enabled=false
var activated=false
var blocked=true

func reset():
	previous.clear(); last_tick=-1; last_any=-10000; last_kind.clear()

func allow(kind:String,now_ms:int):
	if not enabled or not activated or blocked: return false
	if kind not in ["select","build","train","combat"]: return false
	var gap=700 if kind=="combat" else 350
	if now_ms-last_any<120 or now_ms-int(last_kind.get(kind,-10000))<gap: return false
	last_any=now_ms; last_kind[kind]=now_ms
	return true

func observe(records:Dictionary,tick:int,now_ms:int):
	if tick<=last_tick: return []
	var next={}
	var candidates=[]
	for id in records:
		var r=records[id]
		if r.get("remembered",false) or not r.get("alive",false): continue
		next[id]={"hp":r.hp,"built":r.built,"owned":r.owned,"category":r.category}
		if last_tick<0: continue
		var old=previous.get(id,{})
		if old.is_empty():
			if r.owned and r.category=="unit": candidates.append("train")
			continue
		if r.owned and r.category=="building" and not old.built and r.built: candidates.append("build")
		if r.hp<old.hp: candidates.append("combat")
	# Advance even while muted/blocked. Never replay missed events on resume.
	previous=next; last_tick=tick
	var result=[]
	for kind in ["build","train","combat"]:
		if kind in candidates and allow(kind,now_ms): result.append(kind)
	return result
