extends RefCounted
const Ledger=preload("res://scripts/economy_ledger.gd")
const RES=["food","wood","stone","iron"]
const QUEUE=["receipt_id","queue_id","kind","research","trade","trade_from","trade_to","remaining_ticks","started","next_retry_tick","candidate_cursor"]
static func keys(d,names):
 if not d is Dictionary or d.size()!=names.size():return false
 for key in names:
  if not d.has(key):return false
 return true
static func amounts(d):
 if not keys(d,RES):return false
 for value in d.values():
  if not value is int or value<0:return false
 return true
static func validate(data):
 var economy=data.modules.economy
 var receipts=economy._receipts
 var active=false;var queued={};var queue_ids={};var trades={}
 for e in data.entities:
  for item in e.get("queue",[]):
   if not item is Dictionary:return false
   var rid=item.get("receipt_id","");queued[rid]=queued.get(rid,0)+1
   var qid=item.get("queue_id",-1);queue_ids[qid]=queue_ids.get(qid,0)+1
   if item.has("trade") or item.has("trade_from") or item.has("trade_to") or str(item.get("kind","")).begins_with("trade_"):active=true
 for r in receipts.values():
  if r is Dictionary and (r.get("purpose","")=="trade" or r.has("trade_from") or r.has("trade_to")):active=true
 for stats in economy.get("_stats",[]):
  if stats is Dictionary and stats.has("traded_in"):active=true
 if not active:return true # No new state: preserve exact-build legacy records.
 if economy.get("_resource_types",[])!=RES:return false
 for field in ["_banks","_initial","_stats"]:
  if not economy.get(field,null) is Array or economy[field].size()!=2:return false
 if not economy.get("_transactions",null) is Dictionary:return false
 var ledger=Ledger.new(RES);ledger._banks=economy._banks
 var totals=[ledger._zero(),ledger._zero()]
 var completion_records={}
 for tx in economy._transactions.values():
  if not tx is Dictionary or not tx.get("signature",null) is Array or not tx.get("result",null) is Dictionary:continue
  var sig=tx.signature;var result=tx.result
  if sig.size()!=3 or sig[0]!="complete_trade" or not result.get("applied",false):continue
  if not sig[1] is String or not sig[2] is int or not result.get("applied",null) is bool or not result.get("ok",null) is bool or not result.ok:return false
  var rid=sig[1]
  if completion_records.has(rid):return false
  completion_records[rid]={"team":sig[2],"result":result}

 for rid in receipts:
  var receipt=receipts[rid]
  if not receipt is Dictionary:return false
  var is_trade=receipt.get("purpose","")=="trade"
  if not is_trade:
   if receipt.has("trade_from") or receipt.has("trade_to"):return false
   continue
  if not rid is String or rid.is_empty() or not ledger.trade_receipt_valid(receipt):return false
  trades[rid]=receipt
  var payment=economy._transactions.get(rid,{})
  if not keys(payment,["signature","result"]) or payment.signature!=["pay_trade",receipt.team,receipt.trade_from,receipt.trade_to]:return false
  if not payment.result is Dictionary or not payment.result.get("ok",null) is bool or not payment.result.get("applied",null) is bool or payment.result.get("ok",false)!=true or payment.result.get("applied",false)!=true or payment.result.get("receipt_id","")!=rid or payment.result.get("paid_milli",{})!=receipt.paid_milli:return false
  if receipt.state=="open":
   if queued.get(rid,0)!=1:return false
  elif queued.get(rid,0)!=0:return false
  if receipt.state=="fulfilled":
   var amount=Ledger.TRADE_RECIPES[receipt.trade_from+"_"+receipt.trade_to]*1000
   if not ledger._can_add(totals[receipt.team][receipt.trade_to],amount):return false
   totals[receipt.team][receipt.trade_to]+=amount
   var record=completion_records.get(rid,{})
   if record.is_empty() or record.team!=receipt.team:return false
   var result=record.result
   if result.get("receipt_id","")!=rid or result.get("resource_type","")!=receipt.trade_to or not result.get("amount_milli",null) is int or result.amount_milli!=amount:return false
   var initial_age=data.game.skirmish_mode in ["battle","fortress","survival"] and data.game.victory_mode=="conquest"
   var age_tick=data.game.age_completed_tick[receipt.team]
   if not age_tick is int or (not initial_age and age_tick<0) or data.game.tick_count-(0 if initial_age else age_tick)<300:return false
 for rid in completion_records:
  if not trades.has(rid) or trades[rid].state!="fulfilled":return false
 for e in data.entities:
  for item in e.get("queue",[]):
   var rid=item.get("receipt_id","")
   var marked=item.has("trade") or item.has("trade_from") or item.has("trade_to") or str(item.get("kind","")).begins_with("trade_")
   if not marked:
    if trades.has(rid):return false
    continue
   if not keys(item,QUEUE) or not item.trade is bool or not item.trade or not item.research is bool or item.research or not item.started is bool:return false
   if not e.get("alive",false) or not e.get("built",false) or e.kind!="town_center" or not e.team is int or e.team not in [0,1] or e.queue.size()>5:return false
   if not item.kind is String or not item.trade_from is String or not item.trade_to is String or item.kind!="trade_"+item.trade_from+"_"+item.trade_to:return false
   if not trades.has(rid):return false
   var receipt=trades[rid]
   if receipt.state!="open" or receipt.team!=e.team or receipt.trade_from!=item.trade_from or receipt.trade_to!=item.trade_to or receipt.refund_policy!=("started" if item.started else "unstarted"):return false
   for field in ["queue_id","remaining_ticks","next_retry_tick","candidate_cursor"]:
    if not item[field] is int or item[field]<0:return false
   if item.queue_id>=data.game.next_queue_id or queue_ids[item.queue_id]!=1 or item.candidate_cursor!=0 or item.next_retry_tick>data.game.tick_count+20 or item.remaining_ticks>300:return false
   if item.remaining_ticks>0 and item.next_retry_tick!=0:return false
   if item.started and e.queue[0]!=item:return false
   if (not item.started and item.remaining_ticks!=300) or (item.started and item.remaining_ticks>=300):return false
   var initial_age=data.game.skirmish_mode in ["battle","fortress","survival"] and data.game.victory_mode=="conquest"
   var age_tick=data.game.age_completed_tick[e.team]
   if not age_tick is int or age_tick< -1 or age_tick>data.game.tick_count:return false
   if not initial_age and (age_tick<0 or data.game.tick_count<=age_tick):return false
   var start=0 if initial_age else age_tick
   if 300-item.remaining_ticks>data.game.tick_count-start:return false
 for team in 2:
  var stats=economy._stats[team]
  if not stats is Dictionary:return false
  for field in ["extracted","generated","delivered","destroyed_cargo","purchased","repaired","refunded"]:
   if not amounts(stats.get(field,null)):return false
  var credit=stats.get("traded_in",ledger._zero())
  if not amounts(credit) or credit!=totals[team] or not amounts(economy._banks[team]) or not amounts(economy._initial[team]):return false
  for resource in RES:
   if not ledger._equal_nonnegative_sums([economy._banks[team][resource],stats.purchased[resource],stats.repaired[resource]],[economy._initial[team][resource],stats.delivered[resource],stats.refunded[resource],credit[resource]]):return false
 return true
