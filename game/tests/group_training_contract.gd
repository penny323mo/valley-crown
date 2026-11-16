extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func flush(g):
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);await process_frame
 var keep=g._first(0,"town_center")
 var a=g._spawn("barracks",0,keep.pos+Vector3(6,0,6),true)
 var b=g._spawn("range",0,keep.pos+Vector3(-6,0,6),true)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g._select([a.id,b.id]);g._update_hud()
 var before=g.economy.bank_milli(0).duplicate();var pop=g._population(0)
 var plan=g._group_training_plan()
 check("one primary troop from each selected producer",plan.orders==[{"building":a.id,"kind":"spearman"},{"building":b.id,"kind":"archer"}])
 var prices={}
 for kind in ["spearman","archer"]:
  for r in g.Rules.COSTS[kind]:prices[r]=prices.get(r,0)+g.Rules.COSTS[kind][r]
 check("combined displayed price",plan.cost==prices)
 check("preview never spends money",g.economy.bank_milli(0)==before)
 check("group action available",is_instance_valid(g.group_train_button) and not g.group_train_button.disabled)
 g._request_group_training()
 check("ordinary train command per producer",g.commands.size()==2 and g.commands.all(func(c):return c.type=="train"))
 g._request_group_training()
 check("rapid second press cannot double buy",g.commands.size()==2)
 flush(g)
 var paid=true
 for r in prices:paid=paid and g.economy.bank_milli(0)[r]==before[r]-prices[r]*1000
 check("normal ledger charged exact aggregate",paid)
 check("population reserved for both troops",g._population(0)==pop+2)
 check("each producer has exactly one queued troop",a.queue.size()==1 and b.queue.size()==1)
 var count_s=g._count(0,"spearman");var count_a=g._count(0,"archer")
 for i in 700:
  g._tick(g.Rules.TICK)
  if a.queue.is_empty() and b.queue.is_empty():break
 check("both paid troops actually complete training",g._count(0,"spearman")==count_s+1 and g._count(0,"archer")==count_a+1)
 g._update_hud();g.group_train_button.set_meta("squad_ids",[]);g._request_group_training()
 check("stale displayed price refused",g.commands.is_empty())
 g.commands.append({"type":"stop","team":0,"ids":[]})
 check("pending command blocks shared budget plan",g._group_training_plan().orders.is_empty());g.commands.clear()
 g._select([keep.id,a.id]);check("mixed civilian producer excluded",g._group_training_plan().orders.is_empty())
 g._select([a.id]);check("single producer keeps existing batch UI",g._group_training_plan().orders.is_empty())
 check("economy conserved",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"group_training_contract","checks":checks,"failed":failed,"build":g.Rules.BUILD_ID,"scope":"controlled completed buildings, normal funds and paid production, not natural construction or phone acceptance"}));g.queue_free();quit(1 if failed else 0)
