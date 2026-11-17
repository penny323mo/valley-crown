extends SceneTree
var checks=[]
func check(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var a=g._spawn("siege",0,Vector3(-25,0,11));var b=g._spawn("siege",0,Vector3(-28,0,11));var foe=g._spawn("archer",1,Vector3(-24,0,15))
 g._update_vision(false);g._publish_faction_views()
 var start_wood=g.economy.bank_milli(0).wood
 check("controlled full-health mechanical force starts legal",a.hp==a.max_hp and b.hp==b.max_hp and g._static_unit_step_is_free(a,a.pos) and g._static_unit_step_is_free(b,b.pos) and g._static_unit_step_is_free(foe,foe.pos))
 for target in [a,b]:
  g._submit("order",{"ids":[foe.id],"target":target.id,"position":target.pos},1)
  for i in 350:
   g._tick(.05)
   if target.hp<target.max_hp:break
 check("ordinary enemy attacks damage both siege",a.hp<a.max_hp and b.hp<b.max_hp and a.alive and b.alive)
 var damaged=[a.hp,b.hp];var attacks=g.attack_ledger.next_attack_id()
 g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("active visible enemy blocks batch service",g.batch_repair_button.disabled)
 g._submit("order",{"ids":[foe.id],"target":-1,"position":Vector3(-5,0,-5)},1)
 for i in 500:g._tick(.05)
 g._submit("stop",{"ids":[a.id,b.id]});g._tick(.05)
 g._publish_faction_views();g.compact_menu.show();g._refresh_idle_dispatch_buttons()
 check("after enemy departure fleet offers two repairs",not g.batch_repair_button.disabled and g.batch_repair_button.get_meta("squad_ids",[]).size()==2)
 var hp_before=[a.hp,b.hp];var wood=g.economy.bank_milli(0).wood;var repairs=g.economy.stats_view(0).repaired.wood
 g._dispatch_batch_repair()
 for i in 1000:
  g._tick(.05)
  if a.hp==a.max_hp and b.hp==b.max_hp:break
 var cost=(ceili(float(a.max_hp-hp_before[0])/5.0)+ceili(float(b.max_hp-hp_before[1])/5.0))*1000
 check("battle damaged fleet restored through ordinary paid work",a.hp==a.max_hp and b.hp==b.max_hp and cost>0 and g.economy.bank_milli(0).wood==wood-cost)
 check("repair expenses reconcile without resource grants",g.economy.stats_view(0).repaired.wood-repairs==cost and wood==start_wood and g.economy.audit().ok)
 print("SERVICE_JOURNEY ",JSON.stringify({"tick":g.tick_count,"damage_hp":damaged,"before_service_hp":hp_before,"final_hp":[a.hp,b.hp],"wood_cost_milli":cost,"attack_ledger_next":attacks,"enemy_alive":foe.alive,"enemy_pos":str(foe.pos)}))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"siege_service_journey","checks":checks,"failed":failed,"scope":"Controlled unit-spawn encounter with economic AI disabled; all HP damage, retreat, travel and repairs use ordinary commands/ticks, no HP/resource grants or forced deaths."}));quit(1 if failed else 0)
