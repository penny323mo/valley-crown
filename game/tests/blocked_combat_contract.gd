extends SceneTree
var g
var checks=[]
func c(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func run():
 for mode in ["advance","patrol","attack"]:await scenario(mode)
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"blocked_combat_contract","checks":checks,"failed":failed,"scope":"Controlled legal enclosure; ordinary orders and true search/combat ticks; no natural full-match claim."}))
 quit(1 if failed else 0)
func history(a):
 return [a.path_searches,a.path_failures,a.path_retry_ticks.duplicate(),a.path_next_attempt_tick,a.dest]
func scenario(mode):
 root.size=Vector2i(640,360);g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.ai_enabled=false
 var center=Vector3(-30,0,0)
 for x in [-2,0,2]:
  for z in [-2,0,2]:
   if x!=0 or z!=0:g._spawn("house",0,center+Vector3(x,0,z))
 var a=g._spawn("archer",0,center+Vector3(.5,0,.5));var b=g._spawn("siege",1,center+Vector3(8.5,0,.5));g._navigation_rebuild();g._update_vision();g._select([a.id])
 print("START ",g._static_unit_step_is_free(a,a.pos)," ",g._static_unit_step_is_free(b,b.pos)," visible=",g._visible_to(b,0)," range=",g.Rules.RANGE.archer)
 c(mode+" legal controlled starts",g._static_unit_step_is_free(a,a.pos) and g._static_unit_step_is_free(b,b.pos))
 if mode=="attack":g._submit("order",{"ids":[a.id],"target":b.id,"position":b.pos})
 else:g._submit(mode,{"ids":[a.id],"position":b.pos})
 for i in 100:g._tick(g.Rules.TICK)
 print("FAILED ",a.state," ",a.path_status," ",a.path_reason," hp=",b.hp)
 c(mode+" actual terminal before combat",a.path_status=="NO_PATH" and a.path_reason=="frontier_exhausted")
 c(mode+" outside range no shot",b.hp==b.max_hp)
 var prior=history(a);var original_pos=a.pos
 g._submit("order",{"ids":[b.id],"target":-1,"position":center+Vector3(5.5,0,.5)},1)
 var shots=0;var misleading=false;var intervals=[];var previous=-1;var firing_history=[]
 for i in 600:
  g._tick(g.Rules.TICK)
  if a.get("last_attack_tick",-1)==g.tick_count:
   if firing_history.is_empty():firing_history=history(a)
   if previous>=0:intervals.append(g.tick_count-previous)
   previous=g.tick_count
   shots+=1;g._publish_faction_views();g._update_hud();misleading=misleading or g.selection_summary.text.contains("已停止")
   misleading=misleading or not g.selection_summary.text.contains("攻擊")
  if not b.alive:break
 c(mode+" ordinary in-range fire damages",shots>3 and b.hp<b.max_hp)
 c(mode+" HUD reports current attack",not misleading)
 c(mode+" rate remains authoritative",intervals.all(func(x):return x==g.Rules.ATTACK_TICKS.archer))
 c(mode+" terminal and budget preserved",a.path_status=="NO_PATH" and history(a)==(firing_history if mode=="attack" else prior) and a.pos==original_pos)
 g._submit("order",{"ids":[b.id],"target":-1,"position":center+Vector3(8.5,0,.5)},1)
 for i in 160:g._tick(g.Rules.TICK)
 g._update_hud()
 c(mode+" departure restores terminal warning",g._attack_distance(a.pos,b)>g.Rules.RANGE.archer and g.selection_summary.text.contains("已停止"))
 if mode=="attack":c("attack departing target retains ordinary bounded pursuit",a.pos==original_pos and a.path_initial_searches==1 and a.path_searches>=prior[0] and a.path_failures>=prior[1])
 else:c(mode+" does not chase after departure",a.pos==original_pos and history(a)==prior)
 c(mode+" economy audit stays valid",g.economy.audit().ok)
 g.free()
