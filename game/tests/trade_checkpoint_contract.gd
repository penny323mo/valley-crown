extends SceneTree
const Ledger=preload("res://scripts/economy_ledger.gd")
const Policy=preload("res://scripts/trade_checkpoint.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh(started=false,complete=false):
 var l=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
 l.initialize([{"food":200,"wood":200,"stone":100,"iron":0},{"food":200,"wood":200,"stone":100,"iron":0}])
 l.pay_trade("p",0,"food","iron")
 if started:l.mark_started("p",0)
 if complete:l.complete_trade("c","p",0)
 var e={}
 for key in ["_resource_types","_banks","_initial","_stats","_receipts","_transactions"]:e[key]=l.get(key).duplicate(true)
 var q={"receipt_id":"p","queue_id":1,"kind":"trade_food_iron","research":false,"trade":true,"trade_from":"food","trade_to":"iron","remaining_ticks":200 if started else 300,"started":started,"next_retry_tick":0,"candidate_cursor":0}
 return {"game":{"tick_count":400,"age_completed_tick":[0,-1],"skirmish_mode":"standard","victory_mode":"supply","next_queue_id":2},"modules":{"economy":e},"entities":[{"kind":"town_center","alive":true,"built":true,"team":0,"queue":[] if complete else [q]}]}
func _initialize():
 for status in [[false,false],[true,false],[true,true]]:
  var d=fresh(status[0],status[1]);var before=d.duplicate(true)
  check("valid state "+str(status),Policy.validate(d))
  check("validation readonly "+str(status),d==before)
 var legacy=fresh();legacy.entities[0].queue=[];legacy.modules.economy._receipts={};legacy.modules.economy._transactions={}
 check("legacy no trade fields accepted",Policy.validate(legacy))
 for kind in ["unstarted","started","destroyed"]:
  var d=fresh(kind!="unstarted");var l=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
  for key in d.modules.economy:l.set(key,d.modules.economy[key])
  if kind=="destroyed":l.destroy_cost("close","p",0)
  else:l.cancel_cost("close","p",0)
  d.entities[0].queue=[]
  check("closed "+kind+" no phantom output",Policy.validate(d))
 for name in ["keymissing","extra","falseflag","nonbool","research","wrongkind","wrongfrom","wrongto","unknown","dead","unbuilt","wrongbuilding","wrongteam","teambool","duplicate","qidfloat","qidnegative","qidfuture","remainingfloat","remainingnegative","remainingexcess","startedfull","unstartedpartial","cursor","retryearly","retryfuture","noage","agecurrent","agefuture","ageelapsed","receiptmissing","receiptwrongteam","receiptclosed","receiptnontrade","receiptcost","receiptpaid","receiptpolicy","receiptfield","paymissing","paywrong","payamount","orphan","receiptotherqueue","fakecredit","fakebank"]:
  var d=fresh();var e=d.entities[0];var q=e.queue[0];var econ=d.modules.economy;var r=econ._receipts.p
  match name:
   "keymissing":q.erase("trade_to")
   "extra":q.extra=1
   "falseflag":q.trade=false
   "nonbool":q.trade=1
   "research":q.research=true
   "wrongkind":q.kind="villager"
   "wrongfrom":q.trade_from="wood"
   "wrongto":q.trade_to="stone"
   "unknown":q.trade_to="bad"
   "dead":e.alive=false
   "unbuilt":e.built=false
   "wrongbuilding":e.kind="barracks"
   "wrongteam":e.team=1
   "teambool":e.team=false
   "duplicate":e.queue.append(q.duplicate())
   "qidfloat":q.queue_id=1.0
   "qidnegative":q.queue_id= -1
   "qidfuture":q.queue_id=2
   "remainingfloat":q.remaining_ticks=300.0
   "remainingnegative":q.remaining_ticks= -1
   "remainingexcess":q.remaining_ticks=301
   "startedfull":q.started=true;r.refund_policy="started"
   "unstartedpartial":q.remaining_ticks=299
   "cursor":q.candidate_cursor=1
   "retryearly":q.next_retry_tick=1
   "retryfuture":q.next_retry_tick=421
   "noage":d.game.age_completed_tick[0]= -1
   "agecurrent":d.game.age_completed_tick[0]=400
   "agefuture":d.game.age_completed_tick[0]=401
   "ageelapsed":d.game.age_completed_tick[0]=399;q.started=true;q.remaining_ticks=298;r.refund_policy="started"
   "receiptmissing":econ._receipts={}
   "receiptwrongteam":r.team=1
   "receiptclosed":r.state="fulfilled"
   "receiptnontrade":r.purpose="purchase"
   "receiptcost":r.cost_units.food=99
   "receiptpaid":r.paid_milli.food=99999
   "receiptpolicy":r.refund_policy="none"
   "receiptfield":r.extra=1
   "paymissing":econ._transactions={}
   "paywrong":econ._transactions.p.signature[2]="wood"
   "payamount":econ._transactions.p.result.paid_milli.food=0
   "orphan":e.queue=[]
   "receiptotherqueue":q.erase("trade");q.erase("trade_from");q.erase("trade_to");q.kind="villager"
   "fakecredit":econ._stats[0].traded_in={"food":0,"wood":0,"stone":0,"iron":30000}
   "fakebank":econ._banks[0].iron=30000
  check("reject "+name,not Policy.validate(d))
 for name in ["missingcredit","wrongcredit","floatcredit","negativecredit","missingcompletion","doublecompletion","wrongoutput","wrongresource","wrongreceipt","receiptunstarted","missingbankcredit"]:
  var d=fresh(true,true);var econ=d.modules.economy
  match name:
   "missingcredit":econ._stats[0].erase("traded_in")
   "wrongcredit":econ._stats[0].traded_in.iron=60000
   "floatcredit":econ._stats[0].traded_in.iron=30000.0
   "negativecredit":econ._stats[0].traded_in.iron= -1
   "missingcompletion":econ._transactions.erase("c")
   "doublecompletion":econ._transactions.other=econ._transactions.c.duplicate(true)
   "wrongoutput":econ._transactions.c.result.amount_milli=60000
   "wrongresource":econ._transactions.c.result.resource_type="wood"
   "wrongreceipt":econ._transactions.c.result.receipt_id="fake"
   "receiptunstarted":econ._receipts.p.refund_policy="unstarted"
   "missingbankcredit":econ._banks[0].iron=0
  check("reject completed "+name,not Policy.validate(d))
 var waiting=fresh(true);waiting.entities[0].queue[0].remaining_ticks=0;waiting.entities[0].queue[0].next_retry_tick=420
 check("ready overflow retry remains legitimate",Policy.validate(waiting))
 for name in ["completion_without_fulfilled","completed_too_early","completed_no_age","payment_bool","completion_bool","second_started"]:
  var d=fresh(true,true);var econ=d.modules.economy
  match name:
   "completion_without_fulfilled":econ._receipts.p.state="destroyed";econ._stats[0].erase("traded_in");econ._banks[0].iron=0
   "completed_too_early":d.game.tick_count=299
   "completed_no_age":d.game.age_completed_tick[0]= -1
   "payment_bool":econ._transactions.p.result.applied=1
   "completion_bool":econ._transactions.c.result.applied=1
   "second_started":
    d=fresh(true);d.entities[0].queue.push_front({"kind":"villager","queue_id":0,"receipt_id":"ordinary"})
  check("reject extra "+name,not Policy.validate(d))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"trade_checkpoint_contract","checks":checks,"failed":failed,"scope":"Optional resource trade receipt and queue validation with strict credit conservation; runtime fixtures only"}))
 quit(0 if failed==0 else 1)
