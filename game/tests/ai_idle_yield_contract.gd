extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func c(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func step(g,n):
 for i in n:g._tick(g.Rules.TICK)
func fresh():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g.skirmish_mode="standard";return g
func run():
 var g=fresh();await process_frame
 var worker=g._spawn("villager",1,Vector3(0,0,-10));var carrier=g._spawn("villager",1,Vector3(-1,0,-10));var resource=g._spawn("berry",-1,Vector3(-2,0,-10))
 g._navigation_rebuild();g._update_vision()
 g.ai_enabled=true
 c("fresh uninitialized idle worker safely declined",g._ai_idle_yield_plan(worker).is_empty());g.ai_enabled=false
 g._order_move(worker,worker.pos);g._order(carrier,"gather",resource.id);step(g,80)
 c("carrier cargo earned by ordinary gather ticks",g._cargo_amount(carrier)>0)
 g._set_stance(carrier,"STOP");step(g,620)
 # Explicit controlled collision frontier; no production physics changed.
 carrier.pos=Vector3(-1,0,-10);worker.pos=Vector3(0,0,-10)
 var prior_resource=g._spawn("berry",-1,Vector3(-20,0,-10))
 worker.gather_type="food";worker.resource_target=prior_resource.id;worker.last_damage_tick=10
 worker.ai_evacuation={"epoch":worker.work_epoch,"resource":prior_resource.id,"origin":prior_resource.pos,"safe_since_tick":-1,"shelter_since_tick":-1,"hit_tick":10}
 g._ai_evacuation_wait(worker)
 g._order(carrier,"deliver",g._first(1,"town_center").id)
 carrier.path=PackedVector3Array([Vector3(0,0,-10)]);carrier.path_status="FOUND";carrier.path_pending=false
 g._update_vision();g.ai_claimed_workers.clear();g.ai_enabled=true
 var initial=Codec.capture_result(g);var plan=g._ai_idle_yield_plan(worker)
 c("controlled real collision has safe adjacent yield plan",not plan.is_empty())
 if plan.is_empty():
  print("PLAN_DIAGNOSTIC "+str({"worker":worker,"carrier":carrier,"tick":g.tick_count,"mode":g.skirmish_mode,"paused":g.paused,"over":g.game_over,"enabled":g.ai_enabled}))
  finish(g);return
 var after=Codec.capture_result(g)
 if not initial.ok:print("CAPTURE_REASON "+str(initial))
 c("planning leaves full captured authority unchanged",initial.ok and after.ok and initial.data==after.data)
 g.ai_enabled=false
 c("disabled AI never plans a yield",g._ai_idle_yield_plan(worker).is_empty());g.ai_enabled=true
 g.skirmish_mode="survival"
 c("scripted survival never plans a yield",g._ai_idle_yield_plan(worker).is_empty());g.skirmish_mode="standard"
 var original_team=worker.team;worker.team=0
 c("player worker never commandeered",g._ai_idle_yield_plan(worker).is_empty());worker.team=original_team
 worker.mode="STOP"
 c("explicit stopped worker never commandeered",g._ai_idle_yield_plan(worker).is_empty());worker.mode="MOVE"
 var last=worker.traffic_last_replan;worker.traffic_last_replan=g.tick_count-599
 c("599 tick cooldown still blocks",g._ai_idle_yield_plan(worker).is_empty());worker.traffic_last_replan=last
 g.worker_manual_until[worker.id]=g.tick_count+1
 c("manual command grace prevents yield",g._ai_idle_yield_plan(worker).is_empty());g.worker_manual_until.erase(worker.id)
 g.commands.append({"team":1,"kind":"build","builder":worker.id})
 c("queued construction intent prevents yield",g._ai_idle_yield_plan(worker).is_empty());g.commands.clear()
 var saved_state=worker.state;worker.state="gather"
 c("active worker job is never stolen",g._ai_idle_yield_plan(worker).is_empty());worker.state=saved_state
 var prior_carrier=carrier.duplicate(true);var cargo=g._cargo_amount(carrier)
 c("actual anticipation queues normal command and leaves carrier unchanged",g._ai_request_idle_yield(carrier,carrier.path[0]) and carrier==prior_carrier and g.commands.size()==1)
 var command=g.commands[0].duplicate(true);var negative=command.duplicate(true);negative.erase("command_id");var pending=Codec.capture_result(g)
 c("pending yield strict capture accepts unchanged schema",pending.ok)
 var encoded=Codec.encode(pending.data,g.Rules.BUILD_ID) if pending.ok else {"ok":false}
 var decoded=Codec.decode(encoded.bytes,g.Rules.BUILD_ID) if encoded.ok else {"ok":false}
 c("pending marker roundtrips exact through codec",decoded.ok and decoded.data.game.commands==pending.data.game.commands)
 var clone=fresh();var restored=decoded.ok and Restore.apply(clone,decoded.data)
 c("pending marker strict restore succeeds",restored)
 g.commands.clear();var epoch=worker.work_epoch;worker.work_epoch+=1;g._execute(negative)
 c("stale blocker epoch rejects without move",worker.state=="idle" and worker.work_epoch==epoch+1);worker.work_epoch=epoch
 var carrier_epoch=carrier.work_epoch;carrier.work_epoch+=1;g._execute(negative)
 c("stale carrier epoch rejects without move",worker.state=="idle" and worker.work_epoch==epoch);carrier.work_epoch=carrier_epoch
 var counts=[carrier.path_searches,carrier.path_retry_searches,carrier.path_failures,carrier.traffic_replans,carrier.traffic_last_replan]
 g._execute(command)
 c("accepted yield is ordinary MOVE with new epoch",worker.state=="move" and worker.work_epoch==epoch+1)
 c("carrier cargo and path budgets are untouched",g._cargo_amount(carrier)==cargo and counts==[carrier.path_searches,carrier.path_retry_searches,carrier.path_failures,carrier.traffic_replans,carrier.traffic_last_replan])
 c("yield cooldown persists on ordinary actor",worker.traffic_last_replan==g.tick_count)
 if restored:
  clone._toggle_pause();clone.commands.clear();clone._execute(command)
  step(g,1);step(clone,1)
  var a=Codec.capture_result(g);var b=Codec.capture_result(clone)
  c("executed strict continuation captures complete equal authority",a.ok and b.ok and a.data==b.data)
 clone.free();finish(g)
func finish(g):
 var failed=0
 for row in checks:
  if not row.passed:failed+=1
 print(JSON.stringify({"suite":"ai_idle_yield_contract","checks":checks,"failed":failed,"scope":"Controlled collision frontier after ordinary earned cargo; safe AI yield and strict command continuation, not full-match recovery claim."}))
 g.free();quit(0 if failed==0 else 1)
