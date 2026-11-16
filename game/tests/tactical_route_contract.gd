extends SceneTree
## Controlled new-world contracts only; no existing save files or player data.
const Route=preload("res://scripts/tactical_route.gd")
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var g
var history_paths=[]
func check(label,value):
 checks.append({"name":label,"passed":bool(value)})
 if not value:push_error(label)
func _initialize():call_deferred("run")
func fresh():
 var instance=load("res://main.tscn").instantiate()
 instance.history_path="/tmp/tactical-route-history-"+str(Time.get_ticks_usec())+".json"
 history_paths.append(instance.history_path)
 root.add_child(instance);instance.set_process(false);instance.test_mode=true;instance.ai_enabled=false
 return instance
func ticks(count):
 for i in count:
  if g.game_over:break
  g._tick(Rules.TICK)
func route_fields(e):
 return {"points":e.get("tactical_points",[]).duplicate(),"index":e.get("tactical_index",-1),"advance":e.get("tactical_advance",false),"dest":e.dest,"state":e.state}
func run():
 check("one finite point accepted",Route.valid_points([Vector3(1,0,1)]))
 check("five finite points accepted",Route.valid_points([Vector3(1,0,1),Vector3(2,0,1),Vector3(3,0,1),Vector3(4,0,1),Vector3(5,0,1)]))
 check("consecutive duplicate rejected",not Route.valid_points([Vector3.ZERO,Vector3.ZERO]))
 check("non-ground height rejected",not Route.valid_points([Vector3(1,2,1)]))
 check("empty route rejected",not Route.valid_points([]))
 check("six points rejected",not Route.valid_points([Vector3.ZERO,Vector3.ONE,Vector3(2,0,0),Vector3(3,0,0),Vector3(4,0,0),Vector3(5,0,0)]))
 check("dictionary rejected",not Route.valid_points({"point":Vector3.ZERO}))
 check("scalar point rejected",not Route.valid_points([1]))
 check("infinite point rejected",not Route.valid_points([Vector3.INF]))
 check("NaN point rejected",not Route.valid_points([Vector3(NAN,0,0)]))
 check("world boundary rejected",not Route.valid_points([Vector3(Rules.MAP_WORLD_LIMIT,0,0)]))
 g=fresh();await process_frame
 var scout=g._first(0,"scout");var worker=g._first(0,"villager");var enemy=g._first(1,"scout")
 var origin=scout.pos
 var points=[origin+Vector3(4,0,0),origin+Vector3(6,0,0),origin+Vector3(6,0,3)]
 var old_worker=route_fields(worker);var old_enemy=route_fields(enemy)
 g._submit("tactical_route",{"ids":[scout.id,worker.id,enemy.id,scout.id],"points":points,"final_advance":false})
 ticks(1)
 check("ordinary route command applies own military",scout.has("tactical_points") and scout.tactical_points==points and scout.tactical_index==0)
 check("route does not steal worker job",route_fields(worker)==old_worker)
 check("route cannot order enemy",route_fields(enemy)==old_enemy)
 var accepted=route_fields(scout)
 check("malformed direct route refused",not g._order_tactical_route([scout.id],[Vector3.INF],0,false))
 check("invalid command preserves prior route",route_fields(scout)==accepted)
 check("foreign faction cannot order own scout",not g._order_tactical_route([scout.id],points,1,false))
 check("foreign replacement preserves prior route",route_fields(scout)==accepted)
 for invalid_points in [[],[Vector3.ZERO,Vector3.ZERO],[Vector3(Rules.MAP_WORLD_LIMIT,0,0)]]:
  g._submit("tactical_route",{"ids":[scout.id],"points":invalid_points,"final_advance":false})
  # Execute without a movement tick to compare the accepted route exactly.
  g._execute(g.commands.pop_back())
  check("invalid queued replacement preserves route "+str(invalid_points),route_fields(scout)==accepted)
 var seen=[0]
 for i in 1500:
  if not scout.has("tactical_points"):break
  ticks(1)
  var index=scout.get("tactical_index",-1)
  if index>=0 and index not in seen:seen.append(index)
 check("ordinary movement visits all three route legs",seen==[0,1,2])
 check("completed route retires route state",not scout.has("tactical_points") and not scout.has("tactical_index") and not scout.has("tactical_advance"))
 check("completed route reaches final point",scout.pos.distance_to(points[2])<1.6)
 check("ordinary route ends stopped",scout.state=="idle" and scout.mode=="STOP")
 var five_points=[origin+Vector3(4,0,0),origin+Vector3(6,0,0),origin+Vector3(6,0,3),origin+Vector3(6,0,0),origin+Vector3(4,0,0)]
 g._submit("tactical_route",{"ids":[scout.id],"points":five_points,"final_advance":false});ticks(1)
 var five_seen=[0]
 for i in 1800:
  if not scout.has("tactical_points"):break
  ticks(1)
  var index=scout.get("tactical_index",-1)
  if index>=0 and index not in five_seen:five_seen.append(index)
 check("ordinary movement visits all five route legs in order",five_seen==[0,1,2,3,4])
 check("five point route reaches last point and retires",not scout.has("tactical_points") and scout.pos.distance_to(five_points[4])<1.6 and scout.state=="idle")
 var replacement=[origin+Vector3(5,0,0),origin+Vector3(7,0,0)]
 for command in ["stop","defend","order","patrol","advance"]:
  g._order_tactical_route([scout.id],replacement,0,false)
  var payload={"ids":[scout.id],"position":origin+Vector3(2,0,0),"target":-1}
  g._submit(command,payload);ticks(1)
  check(command+" replaces previously applied route",not scout.has("tactical_points"))
 g._order_tactical_route([scout.id],[scout.pos+Vector3(3,0,0)],0,true)
 check("final advance leg uses existing ADVANCE mode",scout.mode=="ADVANCE")
 # Failure injected into controlled runtime state, not a natural path claim.
 scout.path_status="NO_PATH";scout.path_reason="controlled obstruction"
 var failure_position=scout.pos
 g._move_unit_phase(scout,Rules.TICK)
 check("failed leg does not teleport or skip",scout.pos==failure_position)
 check("failed leg stops and retires route",not scout.has("tactical_points") and scout.mode=="STOP")
 # Snapshot created only in memory from this new fixture. Never serialize it.
 g._order_tactical_route([scout.id],[scout.pos+Vector3(3,0,0),scout.pos+Vector3(5,0,0)],0,true)
 ticks(2)
 var captured=Codec.capture_result(g)
 check("active route accepted by checkpoint codec",captured.get("ok",false))
 if captured.get("ok",false):
  var data=captured.data
  var saved=data.entities.filter(func(e):return e.id==scout.id)[0]
  check("checkpoint preserves route points and index",saved.tactical_points==scout.tactical_points and saved.tactical_index==scout.tactical_index and saved.tactical_advance)
  var candidate=fresh();await process_frame
  check("dynamic checkpoint restores into fresh world",Restore.apply(candidate,data))
  var restored=candidate._get_entity(scout.id)
  check("restored route matches applied route",route_fields(restored)==route_fields(scout))
  for mutation in ["index","points","advance","partial","dead","worker","team","mode"]:
   var changed=data.duplicate(true)
   var entry=changed.entities.filter(func(e):return e.id==scout.id)[0]
   if mutation=="index":entry.tactical_index=99
   elif mutation=="points":entry.tactical_points=[Vector3.INF]
   elif mutation=="advance":entry.tactical_advance="true"
   elif mutation=="partial":entry.erase("tactical_index")
   elif mutation=="dead":entry.alive=false
   elif mutation=="worker":entry.kind="villager"
   elif mutation=="team":entry.team=-1
   else:entry.mode="PATROL"
   check("checkpoint rejects malformed route "+mutation,not Codec.validate(changed))
  var legacy=data.duplicate(true)
  for entry in legacy.entities:
   for key in ["tactical_points","tactical_index","tactical_advance"]:entry.erase(key)
  check("legacy entities without route fields remain valid",Codec.validate(legacy))
  candidate.paused=false
  var final_point=restored.tactical_points[-1]
  for i in 1000:
   if not restored.has("tactical_points"):break
   candidate._tick(Rules.TICK)
  check("restored route continues to completion",not restored.has("tactical_points") and restored.pos.distance_to(final_point)<1.6)
  candidate.queue_free()
 # Planning is explicitly staged, with no command before confirmation.
 for viewport_size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=viewport_size;await process_frame
  g._select([scout.id]);g._start_tactical_route();await process_frame
  check(str(viewport_size)+" enters explicit planning",g.touch_command and g.unit_command_kind=="route")
  var prior=route_fields(scout)
  var count_before=g.commands.size()
  g.tactical_draft=[scout.pos+Vector3(2,0,0),scout.pos+Vector3(4,0,0)]
  g.action_key="";g._update_hud();await process_frame
  check(str(viewport_size)+" draft does not change applied order",route_fields(scout)==prior and g.commands.size()==count_before)
  check(str(viewport_size)+" plan overlay does not steal pointer",g.ui.get_node("TacticalRouteOverlay").mouse_filter==Control.MOUSE_FILTER_IGNORE)
  g._cancel_mode()
  check(str(viewport_size)+" cancellation clears draft only",g.tactical_draft.is_empty() and not g.touch_command and route_fields(scout)==prior)
  g._confirm_tactical_route()
  check(str(viewport_size)+" late confirmation after cancel cannot dispatch",g.commands.size()==count_before)
 g._select([scout.id]);g._start_tactical_route()
 g.tactical_draft=[scout.pos+Vector3(2,0,0),scout.pos+Vector3(4,0,0)]
 g._confirm_tactical_route();ticks(1)
 check("explicit UI confirmation dispatches actual route",scout.has("tactical_points") and g.tactical_draft.is_empty() and not g.touch_command)
 g._start_tactical_route();g.tactical_draft=[scout.pos+Vector3(2,0,0)]
 g._select([worker.id])
 check("selection change retires unconfirmed draft",g.tactical_draft.is_empty() and not g.touch_command)
 var invalid_entity={"category":"unit","kind":"scout","alive":true,"team":0,"state":"move","mode":"MOVE","tactical_points":[Vector3.ZERO,Vector3(2,0,0)],"tactical_index":0,"tactical_advance":false}
 check("pure entity valid moving route accepted",Route.valid_entity(invalid_entity))
 for mutation in ["float_index","negative_index","past_end","partial_advance","intermediate_advance","dead","nonunit","worker","bad_team"]:
  var e=invalid_entity.duplicate(true)
  match mutation:
   "float_index":e.tactical_index=0.5
   "negative_index":e.tactical_index=-1
   "past_end":e.tactical_index=2
   "partial_advance":e.erase("tactical_advance")
   "intermediate_advance":e.mode="ADVANCE";e.tactical_advance=true
   "dead":e.alive=false
   "nonunit":e.category="building"
   "worker":e.kind="villager"
   "bad_team":e.team=-1
  check("pure entity rejects "+mutation,not Route.valid_entity(e))
 g._order_tactical_route([scout.id],[scout.pos+Vector3(3,0,0),scout.pos+Vector3(5,0,0)],0,false)
 var path_stop_pos=scout.pos
 g._path_stop(scout,"LIMIT_REACHED","controlled budget exhaustion")
 check("path stop immediately clears all route fields",not scout.has("tactical_points") and not scout.has("tactical_index") and not scout.has("tactical_advance"))
 check("path stop preserves location and failure reason",scout.pos==path_stop_pos and scout.state=="idle" and scout.mode=="STOP" and scout.path_status=="LIMIT_REACHED")
 g._order_tactical_route([scout.id],[scout.pos+Vector3(3,0,0)],0,false)
 check("death fixture begins with applied route",scout.has("tactical_points"))
 g._kill(scout)
 check("death immediately clears all route fields",not scout.alive and not scout.has("tactical_points") and not scout.has("tactical_index") and not scout.has("tactical_advance"))
 # Explicit controlled two-unit fixture; ordinary commands/path scheduling thereafter.
 var a=g._spawn("spearman",0,origin+Vector3(4,0,0))
 var b=g._spawn("spearman",0,origin+Vector3(6,0,0))
 g._update_vision();g._publish_faction_views()
 var a_origin=a.pos;var b_origin=b.pos
 g._submit("tactical_route",{"ids":[a.id,b.id],"points":[origin+Vector3(6,0,3),origin+Vector3(6,0,0)],"final_advance":false});ticks(1)
 check("two units both accept tactical route",a.has("tactical_points") and b.has("tactical_points"))
 for i in 1800:
  if not a.has("tactical_points") and not b.has("tactical_points"):break
  ticks(1)
 check("two unit routes physically move through normal ticks",a.pos.distance_to(a_origin)>0.5 and b.pos.distance_to(b_origin)>0.5)
 check("two unit routes finish or bounded stop without lingering plan",not a.has("tactical_points") and not b.has("tactical_points") and a.mode=="STOP" and b.mode=="STOP")
 check("two unit exits expose arrival or explicit path failure",(a.pos.distance_to(origin+Vector3(6,0,0))<3 or a.path_status in ["NO_PATH","LIMIT_REACHED"]) and (b.pos.distance_to(origin+Vector3(6,0,0))<3 or b.path_status in ["NO_PATH","LIMIT_REACHED"]))
 check("test mode remains enabled",g.test_mode)
 check("economy conserved",g.economy.audit().ok)
 var untouched=true
 for path in history_paths:
  if FileAccess.file_exists(path):untouched=false
 check("isolated history paths untouched",untouched)
 var result={"suite":"tactical_route_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Controlled new-world command and actual movement contracts, dynamic in-memory checkpoint validation; not natural paid progression or screenshots"}
 print(JSON.stringify(result));g.queue_free();quit(0 if result.failed==0 else 1)
