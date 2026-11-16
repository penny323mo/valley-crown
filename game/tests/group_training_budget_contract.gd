extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset([{"food":70,"wood":60,"stone":0,"iron":0},{"food":150,"wood":200,"stone":100,"iron":0}]);g.set_process(false);await process_frame
 var keep=g._first(0,"town_center")
 var a=g._spawn("barracks",0,keep.pos+Vector3(6,0,6),true)
 var b=g._spawn("barracks",0,keep.pos+Vector3(-6,0,6),true)
 g._update_vision(false);g._publish_faction_views();g._select([b.id,a.id])
 var plan=g._group_training_plan()
 check("shared food budget permits only one building",plan.orders.size()==1 and plan.orders[0].building==a.id)
 check("limited budget price matches one troop",plan.cost==g.Rules.COSTS.spearman)
 while g._population(0)<g._capacity(0)-1:g._spawn("spearman",0,keep.pos+Vector3(3,0,3),true)
 g._publish_faction_views()
 check("last population slot not double-reserved",g._group_training_plan().orders.size()==1)
 g._spawn("spearman",0,keep.pos+Vector3(4,0,3),true);g._publish_faction_views()
 check("full population permits no group purchase",g._group_training_plan().orders.is_empty())
 check("preview preserves economy",g.economy.bank_milli(0).food==70000 and g.economy.bank_milli(0).wood==60000 and g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"group_training_budget_contract","checks":checks,"failed":failed,"scope":"controlled budget and population boundaries"}));g.queue_free();quit(1 if failed else 0)
