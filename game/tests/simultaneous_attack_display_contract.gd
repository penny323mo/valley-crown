extends SceneTree
const Controller=preload("res://scripts/action_character.gd")
const BaselineController=preload("res://tests/fixtures/action_character_v111_baseline.gd")
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
var fixed_authority={}
var fixed_ledgers={}
func _initialize():call_deferred("run")
func check(label:String,ok:bool):
 checks.append({"name":label,"passed":ok})
 if not ok:push_error(label)
func record(kind:String,tick:int,attack:int=-1,hit:int=-1)->Dictionary:
 return {"id":1,"kind":kind,"remembered":false,"last_seen_tick":tick,"pos":Vector3.ZERO,"visual_action":"idle","visual_moving":false,"visual_attack_tick":attack,"visual_hit_tick":hit}
func run():
 for kind in Controller.KINDS:
  var body=Node3D.new();root.add_child(body)
  var c=Controller.new();var bound:bool=c.bind(body,kind,Color("435d6c"))
  check(kind+" native bind",bound)
  if not bound:body.free();continue
  c.observe(record(kind,0),0,true)
  var r=record(kind,1,1,1);var original=r.duplicate(true)
  c.observe(r,0,true)
  var impact:float=c.player.get_animation("attack").length*Controller.IMPACT_FRACTION[kind]
  check(kind+" simultaneous release displays contact",c.clip=="attack" and is_equal_approx(c.playhead,impact))
  check(kind+" both cues consumed and record immutable",c.last_attack_tick==1 and c.last_hit_tick==1 and r==original)
  c.observe(r,.05,true);var advanced:float=c.playhead;c.observe(r,0,true)
  check(kind+" repeated observation never replays release",advanced>impact and c.playhead==advanced)
  c.observe(record(kind,2,1,2),0,true)
  check(kind+" later hit still interrupts recovery",c.clip=="hit" and c.last_hit_tick==2 and c.playhead==0)
  c.observe(record(kind,3,3,2),0,true)
  check(kind+" attack-only still shows contact",c.clip=="attack" and is_equal_approx(c.playhead,impact))
  c.observe(record(kind,5,4,5),0,true)
  check(kind+" unequal newer hit retains priority",c.clip=="hit" and c.last_attack_tick==4 and c.last_hit_tick==5)
  c.observe(record(kind,6,4,5),0,true)
  check(kind+" interrupted attack never replayed",c.clip=="hit" and c.last_attack_tick==4)
  c.observe(record(kind,20,10,10),0,false);c.observe(record(kind,20,10,10),0,true)
  check(kind+" reappearing historical events consumed not replayed",c.last_attack_tick==10 and c.last_hit_tick==10 and c.clip=="hit")
  c.start_death();var death_head:float=c.playhead
  c.observe(record(kind,21,21,21),.05,true)
  check(kind+" death wins over simultaneous cues",c.dead and c.clip=="death" and c.playhead==death_head)
  c.release();body.free()
 for kind in ["spearman","archer"]:
  var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g._test_reset();g.test_mode=false;g.ai_enabled=false
  await process_frame
  var a=g._spawn(kind,0,Vector3(8,0,-3));var b=g._spawn(kind,1,Vector3(8.9 if kind=="spearman" else 11.5,0,-3))
  g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._order(a,"attack",b.id);g._order(b,"attack",a.id)
  var initial=Codec.capture_result(g);check(kind+" initial strict state valid",initial.ok and not initial.data.is_empty())
  var hp:int=a.hp
  for i in 31:
   var tick:int=g.tick_count;g._process(Rules.TICK)
   check(kind+" ordinary tick "+str(i),g.tick_count==tick+1)
   if g.tick_count in [1,31]:
    var n:int=1 if g.tick_count==1 else 2
    check(kind+" release damage unchanged "+str(n),a.hp==hp-5*n and b.hp==hp-5*n and a.last_attack_tick==g.tick_count and b.last_attack_tick==g.tick_count)
    var c=g.character_presenter.controllers.get(a.id)
    check(kind+" real reciprocal release has attack pose "+str(n),c!=null and c.clip=="attack" and c.last_hit_tick==g.tick_count)
  var before=Codec.capture_result(g);var ledger=g.attack_ledger.snapshot();var rng:int=g.rng.state
  g._update_visuals(.05)
  var after=Codec.capture_result(g)
  check(kind+" presentation authority invariant",before.ok and after.ok and not before.data.is_empty() and before.data==after.data and ledger==g.attack_ledger.snapshot() and rng==g.rng.state)
  fixed_authority[kind]=after.data
  fixed_ledgers[kind]=g.attack_ledger.snapshot()
  g.free();await process_frame
 await compare_baseline()
 await observation_reconcile()
 var failed=checks.filter(func(c):return not c.passed)
 print(JSON.stringify({"suite":"simultaneous_attack_display_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed.size(),"total":checks.size(),"scope":"Controller contracts plus ordinary reciprocal combat; controlled spawned pairs; no render or phone claims."}))
 quit(0 if failed.is_empty() else 1)

# Test-only immutable old controller: same game authority, only display implementation differs.
func compare_baseline():
 for kind in ["spearman","archer"]:
  var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g._test_reset();g.test_mode=false;g.ai_enabled=false
  await process_frame
  var a=g._spawn(kind,0,Vector3(8,0,-3));var b=g._spawn(kind,1,Vector3(8.9 if kind=="spearman" else 11.5,0,-3))
  g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._order(a,"attack",b.id);g._order(b,"attack",a.id)
  for unit in [a,b]:
   if g.character_presenter.controllers.has(unit.id):g.character_presenter.controllers[unit.id].release()
   var old=BaselineController.new();var bound:bool=old.bind(unit.body,kind,Color("435d6c"))
   check(kind+" baseline real controller bound "+str(unit.team),bound)
   g.character_presenter.controllers[unit.id]=old
  for i in 31:g._process(Rules.TICK)
  var state=Codec.capture_result(g)
  check(kind+" baseline strict capture nonempty",state.ok and not state.data.is_empty())
  check(kind+" baseline fixed 31tick full authority equal",state.ok and state.data==fixed_authority[kind])
  check(kind+" baseline fixed release ledger equal",g.attack_ledger.snapshot()==fixed_ledgers[kind])
  var old=g.character_presenter.controllers.get(a.id)
  check(kind+" baseline reproduces hit masking release",old!=null and old.clip=="hit")
  g.free();await process_frame

# Actual game visibility and presenter reconciliation, not a fabricated remembered record.
# Controlled spawn locations; visibility changes through ordinary scout movement only.
func observation_reconcile():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g._test_reset();g.test_mode=false;g.ai_enabled=false
 await process_frame
 var scout=g._spawn("scout",0,Vector3(8,0,-3));var enemy=g._spawn("villager",1,Vector3(10,0,-3))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views();g._update_visuals(0)
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
 var state=Codec.capture_result(g)
 check("fog movement final authority remains strict valid",state.ok and not state.data.is_empty())
 g.free();await process_frame
