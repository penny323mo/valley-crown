extends SceneTree
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
var prefix=""
func _initialize():call_deferred("run")
func check(label:String,ok:bool):
 checks.append({"name":prefix+label,"passed":ok})
 if not ok:push_error(label)
func run():
 for flags in [[true,true]]:
  prefix=str(flags)+" "
  await observation_reconcile(flags[0],flags[1])
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"attack_readability_combined_fog","total":checks.size(),"checks":checks,"failed":failed,"scope":"Actual executed fixture when this report is emitted: actual enemy fog removal/reappearance with fixed flags, not protected own-unit hidden release proof."}))
 quit(1 if failed else 0)
func observation_reconcile(a: bool, b: bool):
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g._test_reset();g.test_mode=false;g.ai_enabled=false
 await process_frame
 var scout=g._spawn("scout",0,Vector3(8,0,-3));var enemy=g._spawn("villager",1,Vector3(10,0,-3))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._update_visuals(0)
 var old_controller=g.character_presenter.controllers.get(enemy.id)
 check("flags bind before initial observation",old_controller!=null and old_controller.readable_preparation==a and old_controller.readable_followthrough==b)
 check("actual currently observed enemy has controller",g._visible_to(enemy,0) and g.character_presenter.controllers.has(enemy.id))
 g._submit("order",{"ids":[scout.id],"target":-1,"position":Vector3(-25,0,24)},0)
 var hidden=false
 for i in 400:
  g._process(Rules.TICK)
  if not g._visible_to(enemy,0):hidden=true;break
 check("ordinary scout movement removes actual enemy vision",hidden)
 check("actual fog reconciles enemy controller away",hidden and not g.character_presenter.controllers.has(enemy.id))
 g._submit("order",{"ids":[scout.id],"target":-1,"position":Vector3(8,0,-3)},0)
 var seen=false
 for i in 400:
  g._process(Rules.TICK)
  if g._visible_to(enemy,0):seen=true;break
 check("ordinary scout return restores current observation",seen)
 var current=g.faction_views[0].get_record(enemy.id)
 check("reobserved controller comes from actual current record",seen and not current.is_empty() and not current.get("remembered",true) and g.character_presenter.controllers.has(enemy.id))
 var replacement=g.character_presenter.controllers.get(enemy.id)
 check("new controller rebound after real fog removal",replacement!=null and replacement!=old_controller and replacement.readable_preparation==a and replacement.readable_followthrough==b)
 check("enemy has no owned attack protection",replacement!=null and replacement.protected_release_tick==-1 and replacement.preparation_started_tick==-1)
 var state=Codec.capture_result(g)
 check("fog movement final authority remains strict valid",state.ok and not state.data.is_empty())
 g.free();await process_frame
