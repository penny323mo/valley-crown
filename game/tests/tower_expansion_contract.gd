extends SceneTree
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.set_process(false);g.ai_enabled=false
 g._test_reset([{"food":1000,"wood":2000,"stone":2000,"iron":1000},{"food":1000,"wood":2000,"stone":2000,"iron":1000}]);g.set_process(false);await process_frame
 var worker=g._first(0,"villager")
 g._spawn("tower",0,Vector3(-10,0,0),true);g._spawn("tower",0,Vector3(0,0,0),false)
 worker.pos=Vector3(14,0,14);worker.node.position=worker.pos;g._navigation_rebuild();g._update_vision(false)
 var p=Vector3(17,0,14)
 check("two existing towers no longer block remote visible ground",g._placement_reason("tower",p,0,worker.id).is_empty())
 check("remote plot outside home neighborhood",p.distance_to(g._first(0,"town_center").pos)>30)
 g._publish_faction_views();g._select([worker.id]);g._start_build("tower");g.pointer_world=p;g.build_preview_held=true;g._update_ghost();g._update_hud()
 check("third tower real preview green with confirmation",g.placement_ok and not g.build_confirm.disabled)
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._confirm_build();check("confirmation only queues order",g.commands.size()==1 and bank==g.economy.bank_milli(0))
 g._execute(g.commands.pop_front())
 check("third tower created through public confirmation",g._count(0,"tower")==3)
 check("third tower charges ordinary full price",g.economy.bank_milli(0).wood==bank.wood-g.COSTS.tower.get("wood",0)*1000 and g.economy.bank_milli(0).stone==bank.stone-g.COSTS.tower.get("stone",0)*1000)
 var third={}
 for e in g.entities:
  if e.kind=="tower" and e.team==0 and e.pos.distance_to(p)<2:third=e
 g._test_advance(70)
 check("worker actually completes third tower",not third.is_empty() and third.built)
 g.visible_cells[0].fill(1);g._refresh_work_memory()
 check("occupied footprint still rejects overlap",g._placement_reason("tower",third.pos,0,worker.id)=="與建築或資源重疊")
 check("out of bounds remains invalid",g._placement_reason("tower",Vector3(99,0,99),0,worker.id)=="地圖邊界")
 g.visible_cells[0].fill(0)
 check("fog remains explicit not a tower limit",g._placement_reason("tower",Vector3(25,0,25),0,worker.id)=="先派村民探索建築範圍")
 check("resource ledger conserved",g.economy.audit().ok)
 print(JSON.stringify({"suite":"tower_expansion_contract","build":g.Rules.BUILD_ID,"checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"funded controlled public preview and authority; not physical phone or natural balance acceptance"}))
 var failed=checks.any(func(c):return not c.passed);g.queue_free();quit(1 if failed else 0)
