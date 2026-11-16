extends SceneTree
const Policy=preload("res://scripts/army_composition.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func unit(id,kind):
 return {"id":id,"kind":kind,"team":1,"owned":true,"alive":true,"remembered":false,"category":"unit"}
func tower(id):
 return {"id":id,"kind":"tower","team":0,"owned":false,"alive":true,"remembered":false,"category":"building","built":true}
func shot(g,focus,name,label):
 g.camera_zoom=11;g.camera_focus=focus;g._layout_ui();g._camera_update();g._update_vision();g._publish_faction_views()
 g.camera.position=g.camera_focus+Vector3(-19,25,23);g.camera.look_at(g.camera_focus);g._cover_camera_ground()
 g._update_visuals(.016);g._refresh_fog();g._update_hud();g._message(label,30)
 await process_frame
 await process_frame
 if DisplayServer.get_name()=="headless":
  print("HEADLESS_CAPTURE_SKIPPED ",name)
  return OK
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image()
 return im.save_png("/tmp/capture/"+name+".png")
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(640,360)
 var army=[];var id=1
 for kind in Policy.ORDER:
  for n in Policy.BASE[kind]:army.append(unit(id,kind));id+=1
 var base=army.duplicate(true);var target=tower(100);army.append(target)
 check("visible tower creates real siege recruitment preference",Policy.plan(army).kind=="siege" and Policy.plan(army).desired.siege==4)
 check("escorts remain in desired composition",Policy.plan(army).desired.spearman==5 and Policy.plan(army).desired.archer==5 and Policy.plan(army).desired.cavalry==5)
 for field in ["remembered","alive","built","owned","team","category"]:
  var bad=target.duplicate(true)
  bad[field]={"remembered":true,"alive":false,"built":false,"owned":true,"team":-1,"category":"resource"}[field]
  check("ineligible fortification ignored "+field,Policy.plan(base+[bad]).desired.siege==2)
 check("duplicate tower does not double demand",Policy.plan(army+[target]).desired.siege==4)
 var dense=base.duplicate(true)
 for n in 20:dense.append(tower(100+n))
 check("siege response is capped at six",Policy.plan(dense).desired.siege==6)
 var producers=[]
 for n in 4:
  var b=tower(100+n);b.kind=Policy.FORTIFIED_PRODUCERS[n];producers.append(b)
 check("military production cluster raises siege complement",Policy.plan(base+producers).desired.siege==4)
 var house=tower(200);house.kind="house"
 check("housing does not trigger siege escalation",Policy.plan(base+[house]).desired.siege==2)
 check("opening cannot recommend locked siege",Policy.plan(army,["spearman","archer"]).kind!="siege")
 var queued={"id":300,"kind":"workshop","team":1,"owned":true,"alive":true,"category":"building","queue":[{"kind":"siege"},{"kind":"siege"}]}
 check("queued reinforcements prevent overcommit",Policy.plan(army+[queued]).kind=="spearman")
 var reverse=army.duplicate(true);reverse.reverse()
 check("record order deterministic",Policy.plan(army)==Policy.plan(reverse))
 check("input records unchanged",target==tower(100) and base.size()==17)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true
 var stock={"food":10000,"wood":10000,"stone":10000,"iron":10000}
 g._test_reset([stock,stock]);g.set_process(false);g.ai_enabled=false;g._skip_tutorial();await process_frame
 g.age_completed_tick[1]=0;g.tick_count=1
 var home=g._first(1,"town_center")
 # Explicit funded developed-base fixture, not a natural-play claim.
 for kind in ["barracks","range","stable","workshop","tower","tower","farm","farm","farm","farm","house","house","house","house","house","house","house","house"]:
  g._spawn(kind,1,Vector3(10+(id%7)*4,0,-40+int(id/7)*4));id+=1
 while g._count(1,"villager")<12:g._spawn("villager",1,home.pos+Vector3(1,0,1))
 for kind in Policy.ORDER:
  while g._count(1,kind)<Policy.BASE[kind]:g._spawn(kind,1,home.pos+Vector3(2,0,2))
 var fort=g._spawn("tower",0,home.pos+Vector3(-7,0,0))
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views()
 check("actual faction sees completed enemy tower",g._ai_records().any(func(r):return r.id==fort.id and not r.remembered))
 var visible_plan=Policy.plan(g._ai_records())
 g.visible_cells[1].fill(0);g._publish_faction_views()
 check("actual lost sight removes siege escalation",Policy.plan(g._ai_records()).desired.siege==2)
 check("owned army counts survive lost sight",Policy.plan(g._ai_records()).owned_and_queued==visible_plan.owned_and_queued)
 g._update_vision(false);g._publish_faction_views()
 g.commands.clear();g._ai_update()
 check("strategic economy selects siege from observed tower",g.ai_status.progression_goal=="siege")
 var train=g.commands.filter(func(c):return c.type=="train" and c.get("kind","")=="siege" and c.team==1)
 check("actual AI submits paid workshop training",train.size()==1)
 if not train.is_empty():
  var factory=g._get_entity(train[0].building);var bank=g.economy.bank_milli(1).duplicate()
  g.commands=g.commands.filter(func(c):return c==train[0]);g._tick(.05)
  check("authoritative queue accepts AI siege",factory.queue.size()==1 and factory.queue[0].kind=="siege")
  check("normal resource cost paid exactly",g.economy.bank_milli(1).wood==bank.wood-Rules.COSTS.siege.wood*1000 and g.economy.bank_milli(1).iron==bank.iron-Rules.COSTS.siege.iron*1000)
  # Explicit friendly observer for the capture only: player-owned villager
  # reveals the workshop; no omniscient rendering or hidden-unit sampling.
  var observer=g._spawn("villager",0,factory.pos+Vector3(4,0,0))
  var shot_train=await shot(g,factory.pos,"native-ai-siege-production","AI SIEGE DEMO: paid reinforcement in production")
  print("PRODUCTION_CAPTURE_ERROR ",shot_train," queue=",factory.queue[0].kind," remaining=",factory.queue[0].remaining_ticks)
  observer.pos=g._first(0,"town_center").pos
  var before=g._count(1,"siege")
  for tick in Rules.TRAIN_TICKS.siege+20:
   g.tick_count+=1;g._update_production(factory,Rules.TICK,false);g._process_ready_production()
  check("normal timed production delivers reinforcement",g._count(1,"siege")==before+1)
  var siege={}
  for entity in g.entities:
   if entity.alive and entity.team==1 and entity.kind=="siege":siege=entity
  # Position only for controlled tactical proof, no authority bypass in policy.
  siege.pos=fort.pos+Vector3(-5,0,0);g._update_vision(false);g._publish_faction_views()
  var seen=g._ai_records();var observed=seen.filter(func(r):return r.id==siege.id)[0]
  var keep={"id":g._first(0,"town_center").id,"alive":true,"team":0,"remembered":true,"pos":g._first(0,"town_center").pos}
  g.commands.clear();g._ai_raid_order(observed,seen,keep)
  check("reinforcement receives ordinary tower assault command",g.commands.any(func(c):return c.type=="order" and siege.id in c.ids and c.target==fort.id))
  var hp=fort.hp
  for tick in 200:g._tick(.05)
  check("normal combat actually damages fortification",fort.hp<hp)

  g._select([fort.id])
  var err=await shot(g,fort.pos+Vector3(-2,0,0),"native-ai-siege-response","AI SIEGE DEMO: reinforcement attacks tower")
  print(JSON.stringify({"build":Rules.BUILD_ID,"rendered":DisplayServer.get_name()!="headless","image_error":err,"tower_before":hp,"tower_after":fort.hp,"scope":"Controlled funded developed-base demonstration. AI-selected siege reinforcement completed ordinary paid timed production, then ordinary orders damaged a player tower. Resources/base layout/age supplied explicitly; newborn repositioned for tactical proof, friendly observer moved for workshop capture. Not a natural full-match balance proof."}))
  var failed=checks.filter(func(c):return not c.passed).size()
  print("CAPTURE_CHECK_FAILURES ",failed);g.queue_free();quit(0 if err==OK and shot_train==OK and failed==0 else 1)
 else:quit(1)
