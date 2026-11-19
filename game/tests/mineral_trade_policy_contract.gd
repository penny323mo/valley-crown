extends SceneTree
const Ledger=preload("res://scripts/economy_ledger.gd")
const Policy=preload("res://scripts/trade_policy.gd")
const SavePolicy=preload("res://scripts/trade_checkpoint.gd")
var checks=[]
var cycles=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func cycle_walk(start,node,seen,ratio):
 for row in Policy.RECIPES.values():
  if row.from!=node:continue
  var next_ratio=ratio*float(row.output)/row.input
  if row.to==start:cycles.append({"path":seen+[start],"ratio":next_ratio})
  elif row.to not in seen:cycle_walk(start,row.to,seen+[row.to],next_ratio)
func fixture(from_resource,to_resource,stage):
 var l=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
 l.initialize([{"food":200,"wood":200,"stone":200,"iron":200},{"food":200,"wood":200,"stone":200,"iron":200}])
 l.pay_trade("p",0,from_resource,to_resource)
 if stage!="pending":l.mark_started("p",0)
 if stage=="completed":l.complete_trade("c","p",0)
 if stage=="cancelled":l.cancel_cost("x","p",0)
 if stage=="destroyed":l.destroy_cost("x","p",0)
 var e={}
 for key in ["_resource_types","_banks","_initial","_stats","_receipts","_transactions"]:e[key]=l.get(key).duplicate(true)
 var q={"receipt_id":"p","queue_id":1,"kind":Policy.kind(from_resource,to_resource),"research":false,"trade":true,"trade_from":from_resource,"trade_to":to_resource,"remaining_ticks":300 if stage=="pending" else 200,"started":stage!="pending","next_retry_tick":0,"candidate_cursor":0}
 return {"game":{"tick_count":400,"age_completed_tick":[0,-1],"skirmish_mode":"standard","victory_mode":"supply","next_queue_id":2},"modules":{"economy":e},"entities":[{"kind":"town_center","alive":true,"built":true,"team":0,"queue":[q] if stage in ["pending","started"] else []}]}
func _initialize():
 var old={"wood_food":60,"food_wood":60,"food_iron":30,"food_stone":40}
 check("original four exchange rates retained",old.keys().all(func(k):return Ledger.TRADE_RECIPES.get(k)==old[k]))
 check("exactly two mineral sales added",Ledger.TRADE_RECIPES.size()==6 and Ledger.TRADE_RECIPES.iron_food==60 and Ledger.TRADE_RECIPES.stone_food==60)
 check("policy and ledger allowlists agree",Policy.RECIPES.size()==6 and Policy.RECIPES.values().all(func(r):return r.input==100 and r.output==Ledger.TRADE_RECIPES.get(r.from+"_"+r.to)))
 for resource in Ledger.FOUR_RESOURCE_TYPES:cycle_walk(resource,resource,[resource],1.0)
 check("all elementary directed cycles enumerated and strictly lossy",cycles.size()==6 and cycles.all(func(c):return c.ratio>0 and c.ratio<1))
 # Every closed walk decomposes into these elementary cycles; rounding only lowers proceeds.
 for source in ["iron","stone"]:
  for stage in ["pending","started","completed","cancelled","destroyed"]:
   var d=fixture(source,"food",stage);var before=d.duplicate(true)
   check(source+" strict receipt/queue "+stage,SavePolicy.validate(d) and d==before)
   var e=d.modules.economy
   check(source+" exact bank "+stage,e._banks[0][source]==(175000 if stage=="cancelled" else 100000) and e._banks[0].food==(260000 if stage=="completed" else 200000))
  var invalid=fixture(source,"food","pending");invalid.entities[0].queue[0].trade_to="wood"
  check(source+" mismatched unlisted queue rejected",not SavePolicy.validate(invalid))
 for source in ["iron","stone"]:
  var l=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
  var stock={"food":200,"wood":200,"stone":200,"iron":200};stock[source]=99;l.initialize([stock])
  var bank=l.bank_milli(0).duplicate(true)
  check(source+" insufficient source atomic",not l.pay_trade("insufficient",0,source,"food").applied and l.bank_milli(0)==bank)
  stock[source]=200;l=Ledger.new(Ledger.FOUR_RESOURCE_TYPES);l.initialize([stock]);var payment=l.pay_trade("p",0,source,"food");l.mark_started("p",0)
  l._banks[0].food=Ledger.MAX_INT-1
  bank=l.bank_milli(0).duplicate(true)
  check(source+" output overflow cannot consume receipt or alter bank",not l.complete_trade("overflow","p",0).applied and l.bank_milli(0)==bank and payment.applied and l.receipt_view("p").get("state","")=="open")
  l._banks[0].food=200000
  check(source+" recovered overflow settles exactly once",l.complete_trade("overflow","p",0).applied and l.bank_milli(0).food==260000 and l.audit().ok)
 for pair in [["wood","food"],["food","wood"],["food","iron"],["food","stone"]]:
  for stage in ["pending","started","completed"]:check("legacy recipe "+str(pair)+" "+stage,SavePolicy.validate(fixture(pair[0],pair[1],stage)))
 print("DIAGNOSTIC cycles "+JSON.stringify(cycles))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"mineral_trade_policy_contract","scope":"Pure controlled ledger and strict queue fixtures; all elementary exchange cycles; no natural-match claim","checks":checks,"failed":failed}));quit(1 if failed else 0)
