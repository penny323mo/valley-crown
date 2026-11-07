extends SceneTree
# Controlled native fixture, not natural match/UI/phone acceptance.
# Unpaid setup buildings/units; training then uses ordinary commands, full
# duration, actual receipt, spawn exit, fixed ticks and bounded MOVE authority.
var g
var checks=[]
var trace=[]
var production_evidence={}
var b
var goal=Vector3(-0.5,0,0.5)
func _initialize(): call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"pass":bool(ok)})
 if not ok: push_error(name)
func xyz(p): return [p.x,p.y,p.z]
func tick(): g._tick(g.Rules.TICK)
func issue(type,data,team=0): g._submit(type,data,team); tick()
func setup():
 g._test_reset(); g._cancel_mode()
 for e in g.entities: e.node.queue_free()
 g.entities.clear(); g.next_id=0
 g.work_memory=[g.WorkMemory.new(),g.WorkMemory.new()]
 g.faction_views=[g.FactionView.new(),g.FactionView.new()]
 g._reset_economy(g.INITIAL_STOCKS)
 b=g._spawn("town_center",0,Vector3(-5,0,0))
 g._spawn("town_center",1,Vector3(25,0,25))
 g._navigation_rebuild(); g._update_vision(); g._publish_faction_views()
func set_point(p): issue("rally",{"building":b.id,"position":p})
func native_authority():
 setup()
 var bank=g.economy.bank_milli(0).duplicate()
 set_point(goal)
 check("visible ground accepted without payment",b.get("rally_point",Vector3.INF)==goal and g.economy.bank_milli(0)==bank)
 for item in [["infinite",Vector3.INF],["nan",Vector3(NAN,0,0)],["outside",Vector3(200,0,0)],["hidden",Vector3(25,0,25)],["occupied",b.pos]]:
  set_point(item[1])
  check("invalid ground preserves prior point "+item[0],b.get("rally_point",Vector3.INF)==goal)
 var house=g._spawn("house",0,Vector3(6,0,0))
 var site=g._spawn("barracks",0,Vector3(10,0,0),false)
 for e in [house,site,g._first(1,"town_center")]:
  issue("rally",{"building":e.id,"position":goal})
  check("ineligible producer rejected "+e.kind+str(e.team),not e.has("rally_point"))
 issue("rally",{"building":b.id,"position":goal},1)
 check("enemy cannot mutate owned rally",b.rally_point==goal)
 g._publish_faction_views()
 check("owned observation includes rally",g.faction_views[0].get_record(b.id).rally_point==goal)
 g.visible_cells[1][g._cell_index(b.pos)]=1; g._publish_faction_views()
 check("enemy observation excludes rally",not g.faction_views[1].get_record(b.id).has("rally_point"))
 issue("rally",{"building":b.id,"clear":true})
 check("clear removes setting without payment",not b.has("rally_point") and g.economy.bank_milli(0)==bank)
 # Execution-time ownership/liveness guard, not only UI preflight.
 g._submit("rally",{"building":b.id,"position":goal}); g._kill(b); tick()
 check("destroyed queued producer cannot receive rally",not b.has("rally_point"))
func production():
 setup(); set_point(goal)
 issue("train",{"building":b.id,"kind":"villager"})
 var receipt=b.queue[0].receipt_id
 production_evidence={"producer_id":b.id,"first_target":xyz(goal),"train_tick":g.tick_count,"receipt_id":receipt,"paid_bank":g.economy.bank_milli(0).duplicate(),"train_remaining":b.queue[0].remaining_ticks}
 check("training pays unchanged fifty food",g.economy.bank_milli(0).food==100000 and g._population(0)==1)
 # Setting changes while paid queue exists affect birth, never receipt/timer.
 var replacement=Vector3(-0.5,0,-0.5)
 var remaining=b.queue[0].remaining_ticks
 set_point(replacement)
 check("rally update does not restart training",b.queue[0].remaining_ticks==remaining-1 and b.queue[0].receipt_id==receipt)
 production_evidence.latest_target=xyz(replacement); production_evidence.rally_update_tick=g.tick_count
 var newborn={}; var birth=-1; var start=Vector3.INF
 for i in 430:
  tick()
  if newborn.is_empty():
   for e in g.entities:
    if e.team==0 and e.category=="unit":
     newborn=e; birth=g.tick_count; start=e.pos
     production_evidence.newborn_id=e.id; production_evidence.birth_tick=birth; production_evidence.birth_position=xyz(start); production_evidence.birth_destination=xyz(e.dest); production_evidence.birth_mode=e.mode
     check("newborn inherits latest ordinary move",e.mode=="MOVE" and e.target==-1 and e.dest==replacement)
  if not newborn.is_empty() and (g.tick_count-birth)%10==0:
   trace.append({"tick":g.tick_count,"position":xyz(newborn.pos),"state":newborn.state,"path_status":newborn.path_status,"bank":g.economy.bank_milli(0)})
 check("full-duration exactly-once spawn",birth>=g.Rules.TRAIN_TICKS.villager and g.trained_total[0]==1 and b.queue.is_empty() and g.spawn_commit_order.size()==1)
 check("real movement reaches rally",not newborn.is_empty() and newborn.pos.distance_to(replacement)<0.2 and newborn.pos.distance_to(start)>1.0)
 production_evidence.final_receipt=g.economy.receipt_view(receipt); production_evidence.final_bank=g.economy.bank_milli(0); production_evidence.audit=g.economy.audit(); production_evidence.commits=g.spawn_commit_order.duplicate(true)
 check("reservation fulfilled with unchanged ledger",g._population(0)==1 and g.economy.receipt_view(receipt).state=="fulfilled" and g.economy.bank_milli(0).food==100000 and g.economy.audit().ok)
 if not newborn.is_empty():
  issue("order",{"ids":[newborn.id],"target":-1,"position":Vector3(-1.5,0,2.5)})
  var manual=newborn.dest
  set_point(goal)
  check("producer changes never overwrite existing manual order",newborn.dest==manual and newborn.state=="move")
  issue("stop",{"ids":[newborn.id]})
  for i in 25: tick()
  check("manual stop is not rallied again",newborn.state=="idle" and newborn.mode=="STOP")
 issue("train",{"building":b.id,"kind":"villager"})
 issue("cancel_train",{"building":b.id})
 for i in 305: tick()
 check("cancelled training cannot rally or spawn",g.trained_total[0]==1 and b.queue.is_empty() and g.economy.audit().ok)
func birth_variants():
 setup(); set_point(goal)
 issue("rally",{"building":b.id,"clear":true})
 issue("train",{"building":b.id,"kind":"villager"})
 for i in 305: tick()
 var unit={}
 for e in g.entities:
  if e.team==0 and e.category=="unit": unit=e
 check("cleared rally preserves baseline newborn idle",not unit.is_empty() and unit.state=="idle" and unit.mode=="DEFEND")
 setup(); set_point(goal)
 issue("train",{"building":b.id,"kind":"villager"})
 unit={}
 for i in 305:
  tick()
  for e in g.entities:
   if e.team==0 and e.category=="unit": unit=e
  if not unit.is_empty(): break
 check("override fixture catches newborn before route search",not unit.is_empty() and unit.state=="move" and not unit.path_has_attempt)
 if not unit.is_empty():
  var start=unit.pos
  issue("stop",{"ids":[unit.id]})
  for i in 25: tick()
  check("manual stop supersedes newborn rally before movement",unit.pos==start and unit.state=="idle" and unit.mode=="STOP" and not unit.path_pending)
 else: check("manual stop supersedes newborn rally before movement",false)

func lifecycle():
 setup(); g._select([b.id]); g._start_ground_rally(b.id)
 check("explicit rally action enters isolated touch mode",g.rally_building==b.id and g.touch_command and g.build_mode.is_empty() and not g.box_select_mode)
 var pending=g.commands.size()
 g._cancel_mode()
 check("cancel emits no command",g.rally_building==-1 and not g.touch_command and g.commands.size()==pending and not b.has("rally_point"))
 g._start_ground_rally(b.id); g._select([])
 check("selection change cancels rally",g.rally_building==-1 and not g.touch_command)
 g._select([b.id]); g._start_ground_rally(b.id); g._toggle_pause()
 check("pause cancels rally",g.paused and g.rally_building==-1 and not g.touch_command)
 g._toggle_pause(); g._start_ground_rally(b.id); g._start_box_select()
 check("box mode replaces rally",g.box_select_mode and g.rally_building==-1 and not g.touch_command)
 g._cancel_mode(); g._start_ground_rally(b.id); g._kill(b)
 check("destroyed producer cancels targeting immediately",g.rally_building==-1 and not g.touch_command)
func run():
 var args=OS.get_cmdline_user_args()
 if args.size()!=1 or not args[0].is_absolute_path(): quit(2); return
 g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
 var script=get_script().resource_path
 var lock_path=script.get_base_dir().path_join("source_lock.json")
 var lock=JSON.parse_string(FileAccess.get_file_as_string(lock_path))
 check("expected exact build",lock is Dictionary and lock.get("build","")==g.Rules.BUILD_ID)
 if checks[0].pass: native_authority(); production(); birth_variants(); lifecycle()
 var failed=checks.filter(func(c): return not c.pass).size()
 var report={"schema":"ground-rally-v1","scope":"Controlled native authority/full-duration production/motion/handler lifecycle, not phone GUI or natural match acceptance.","build":g.Rules.BUILD_ID,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"contract_sha256":FileAccess.get_sha256(script),"source_lock_sha256":FileAccess.get_sha256(lock_path),"engine":Engine.get_version_info(),"checks":checks,"trace":trace,"production":production_evidence,"passed":checks.size()-failed,"failed":failed,"completed":checks.size()==33}
 var out=FileAccess.open(args[0],FileAccess.WRITE)
 if out==null: quit(2); return
 out.store_string(JSON.stringify(report)); out.close()
 print("GROUND_RALLY_CONTRACT "+JSON.stringify({"checks":checks.size(),"failed":failed}))
 quit(0 if failed==0 and checks.size()==33 else 1)
