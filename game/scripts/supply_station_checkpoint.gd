extends RefCounted
# Optional per-building upgrade; historical layouts without these fields remain valid.
const FIELDS=["supply_station","supply_receipt_id","supply_completed_tick"]
const QUEUE_FIELDS=["receipt_id","queue_id","kind","research","remaining_ticks","started","next_retry_tick","candidate_cursor"]
static func keys(d,names):
 if not d is Dictionary or d.size()!=names.size():return false
 for key in names:
  if not d.has(key):return false
 return true
static func receipt_ok(r,team,state,policy):
 if not r is Dictionary or not r.get("team",null) is int:return false
 if not keys(r.get("cost_units",null),["food","wood"]) or not keys(r.get("paid_milli",null),["food","wood","stone","iron"]):return false
 for value in r.cost_units.values():
  if not value is int:return false
 for value in r.paid_milli.values():
  if not value is int:return false
 return r.team==team and r.get("state","")==state and r.get("purpose","")=="purchase" and r.get("refund_policy","")==policy and r.cost_units=={"food":100,"wood":100} and r.paid_milli=={"food":100000,"wood":100000,"stone":0,"iron":0}

static func validate(data):
 for tick in data.game.age_completed_tick:
  if not tick is int or tick< -1 or tick>data.game.tick_count:return false
 var receipts=data.modules.economy._receipts
 var uses={};var queue_ids={};var supply_receipts=[]
 for e in data.entities:
  if not e.get("queue",null) is Array:return false
  for item in e.queue:
   if not item is Dictionary:return false
   var rid=item.get("receipt_id","")
   if rid is String:uses[rid]=uses.get(rid,0)+1
   var qid=item.get("queue_id",-1)
   if qid is int:queue_ids[qid]=queue_ids.get(qid,0)+1
 for e in data.entities:
  var fields=0
  for key in FIELDS:
   if e.has(key):fields+=1
  var completed=fields>0
  var age=(data.game.skirmish_mode in ["battle","fortress","survival"] and data.game.victory_mode=="conquest") or (data.game.age_completed_tick[e.team]>=0 and data.game.tick_count>data.game.age_completed_tick[e.team]) if e.team in [0,1] else false
  if completed:
   if fields!=3 or not e.supply_station is bool or not e.supply_station or e.kind!="storehouse" or not e.built or not age:return false
   if not e.supply_receipt_id is String or e.supply_receipt_id.is_empty() or not e.supply_completed_tick is int or e.supply_completed_tick<600 or e.supply_completed_tick>data.game.tick_count:return false
   if not receipt_ok(receipts.get(e.supply_receipt_id,{}),e.team,"fulfilled","started"):return false
   if data.game.age_completed_tick[e.team]>=0 and e.supply_completed_tick<data.game.age_completed_tick[e.team]+600:return false
   uses[e.supply_receipt_id]=uses.get(e.supply_receipt_id,0)+1;supply_receipts.append(e.supply_receipt_id)
  var count=0
  for item in e.queue:
   if item.get("kind","")!="supply_station":continue
   count+=1
   if not keys(item,QUEUE_FIELDS) or completed or not e.alive or not e.built or e.kind!="storehouse" or not age or e.queue.size()!=1:return false
   if not item.research is bool or not item.research or not item.started is bool:return false
   for key in ["queue_id","remaining_ticks","next_retry_tick","candidate_cursor"]:
    if not item[key] is int or item[key]<0:return false
   if item.queue_id>=data.game.next_queue_id or queue_ids[item.queue_id]!=1 or item.remaining_ticks>600 or item.candidate_cursor!=0 or item.next_retry_tick!=0:return false
   if not item.started and item.remaining_ticks!=600:return false
   if item.started and item.remaining_ticks>=600:return false
   # A queued receipt cannot claim more production than elapsed age-II time.
   var age_start=0 if data.game.skirmish_mode in ["battle","fortress","survival"] and data.game.victory_mode=="conquest" else data.game.age_completed_tick[e.team]
   if 600-item.remaining_ticks>data.game.tick_count-age_start:return false
   if not item.receipt_id is String or item.receipt_id.is_empty():return false
   if not receipt_ok(receipts.get(item.receipt_id,{}),e.team,"open","started" if item.started else "unstarted"):return false
   supply_receipts.append(item.receipt_id)
  if count>1:return false
 for rid in supply_receipts:
  if uses.get(rid,0)!=1:return false
 return true
