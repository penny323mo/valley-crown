extends SceneTree
const Ledger=preload("res://scripts/economy_ledger.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh(resources=Ledger.FOUR_RESOURCE_TYPES):
 var e=Ledger.new(resources);var stock={}
 for r in resources:stock[r]=200
 e.initialize([stock,stock]);return e
func _initialize():
 for recipe in Ledger.TRADE_RECIPES:
  var pair=recipe.split("_");var e=fresh();var before=e.snapshot()
  var p=e.pay_trade("paid",0,pair[0],pair[1])
  check(recipe+" escrow paid once",p.applied and e.bank_units_floor(0)[pair[0]]==100)
  check(recipe+" payment replay",not e.pay_trade("paid",0,pair[0],pair[1]).applied and e.bank_units_floor(0)[pair[0]]==100)
  check(recipe+" requires started",not e.complete_trade("early","paid",0).applied)
  e.mark_started("paid",0)
  check(recipe+" generic fulfill forbidden",not e.fulfill_cost("bad","paid",0).applied and e.receipt_view("paid").state=="open")
  check(recipe+" atomic complete",e.complete_trade("complete","paid",0).applied and e.bank_units_floor(0)[pair[1]]==200+Ledger.TRADE_RECIPES[recipe])
  var done=e.snapshot()
  check(recipe+" completed replay no credit",not e.complete_trade("complete","paid",0).applied and e.snapshot()==done)
  check(recipe+" alternate tx cannot credit",not e.complete_trade("again","paid",0).applied and e.bank_units_floor(0)[pair[1]]==200+Ledger.TRADE_RECIPES[recipe])
  check(recipe+" cannot cancel fulfilled",not e.cancel_cost("cancel","paid",0).applied)
  var s=e.stats_view(0)
  check(recipe+" delivery harvest generation untouched",s.delivered==before.stats[0].delivered and s.extracted==before.stats[0].extracted and s.generated==before.stats[0].generated)
  check(recipe+" audit and other team unchanged",e.audit().ok and e.bank_milli(1)==before.banks[1])
 for mode in ["unstarted","started","destroyed"]:
  var e=fresh();e.pay_trade("p",0,"food","iron")
  if mode!="unstarted":e.mark_started("p",0)
  var result=e.destroy_cost("close","p",0) if mode=="destroyed" else e.cancel_cost("close","p",0)
  check(mode+" normal refund",result.applied and e.bank_units_floor(0).food==({"unstarted":200,"started":175,"destroyed":100}[mode]))
  check(mode+" never credits output",e.bank_units_floor(0).iron==200 and not e.complete_trade("late","p",0).applied and e.audit().ok)
 var e=fresh()
 for pair in [["food","food"],["iron","wood"],["wood","iron"],["stone","wood"],["bad","food"]]:
  check("reject recipe "+str(pair),not e.pay_trade(str(pair),0,pair[0],pair[1]).applied and e.bank_units_floor(0).food==200)
 check("wrong team rejected",not e.pay_trade("wrong",2,"food","wood").applied)
 e.pay_trade("p",0,"food","wood");e.mark_started("p",0)
 check("wrong completion team rejected",not e.complete_trade("wrongcomplete","p",1).applied)
 # Deliberate isolated integer-boundary fixture, never a serialized save.
 e._banks[0].wood=Ledger.MAX_INT-1
 var before=e.snapshot()
 check("overflow atomic unchanged",not e.complete_trade("overflow","p",0).applied and e.snapshot()==before)
 e._banks[0].wood=200000
 check("overflow same transaction can later complete",e.complete_trade("overflow","p",0).applied and e.audit().ok)
 var two=fresh(["food","wood"])
 two.pay_trade("p",0,"wood","food");two.mark_started("p",0);two.complete_trade("c","p",0)
 check("two resource API remains valid",two.audit().ok and two.bank_units_floor(0)=={"food":260,"wood":100})
 var legacy=fresh();check("no trade legacy stats untouched",not legacy.stats_view(0).has("traded_in") and legacy.audit().ok)
 var insufficient=Ledger.new();insufficient.initialize([{"food":99,"wood":0}])
 check("insufficient stock no mutation",not insufficient.pay_trade("p",0,"food","wood").applied and insufficient.bank_units_floor(0).food==99)
 var conflict=fresh();conflict.pay_trade("p",0,"wood","food")
 check("same payment id changed recipe rejects",not conflict.pay_trade("p",0,"food","wood").applied and conflict.bank_units_floor(0).food==200)
 var pending=fresh();pending.pay_trade("p",0,"food","stone");pending.mark_started("p",0)
 var restored=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
 for key in ["_banks","_initial","_stats","_nodes","_workers","_receipts","_transactions","_farms","_worker_farms"]:restored.set(key,pending.get(key).duplicate(true))
 check("restored pending trade completes identically",pending.complete_trade("c","p",0)==restored.complete_trade("c","p",0) and pending.snapshot()==restored.snapshot())
 var completed=Ledger.new(Ledger.FOUR_RESOURCE_TYPES)
 for key in ["_banks","_initial","_stats","_nodes","_workers","_receipts","_transactions","_farms","_worker_farms"]:completed.set(key,pending.get(key).duplicate(true))
 var saved=completed.snapshot()
 check("restored fulfilled replay cannot duplicate",not completed.complete_trade("c","p",0).applied and completed.snapshot()==saved and completed.audit().ok)
 var tampered=fresh();tampered.pay_trade("p",0,"food","stone");tampered.mark_started("p",0)
 tampered._receipts.p.trade_to="iron" # payment receipt alone defines fixed approved pair, not a variable output.
 tampered._receipts.p.paid_milli.food=99999
 check("malformed receipt cannot settle",not tampered.complete_trade("c","p",0).applied and tampered._receipts.p.state=="open")
 var infinite=fresh();infinite.pay_trade("p",0,"wood","food");infinite.mark_started("p",0);infinite.complete_trade("c","p",0)
 infinite.pay_trade("p2",0,"food","wood");infinite.mark_started("p2",0);infinite.complete_trade("c2","p2",0)
 check("round trip conversion is lossy",infinite.bank_units_floor(0).food==160 and infinite.bank_units_floor(0).wood==160 and infinite.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"trade_ledger_contract","checks":checks,"failed":failed,"scope":"Fixed resource trade atomic receipts, cancellation, overflow and conservation; isolated runtime states only"}))
 quit(0 if failed==0 else 1)
