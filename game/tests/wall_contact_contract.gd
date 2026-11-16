extends SceneTree
const Rules=preload("res://scripts/rules.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
var histories=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func _initialize():call_deferred("run")
func fresh():
 var g=load("res://main.tscn").instantiate();g.history_path="/tmp/wall-contact-%d.json"%Time.get_ticks_usec();histories.append(g.history_path)
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 return g
func run():
 for kind in ["spearman","cavalry","siege"]:await approach(kind)
 await guards()
 await continuation()
 var untouched=true
 for p in histories:
  if FileAccess.file_exists(p):untouched=false
 check("isolated histories untouched",untouched)
 var result={"suite":"wall_contact_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Controlled fresh geometry with ordinary attack ticks and paid wall checkpoint continuation; no historical saves, natural battle or screenshot claim"}
 print(JSON.stringify(result));quit(0 if result.failed==0 else 1)
func approach(kind):
 var g=fresh();await process_frame
 var wall=g._spawn("wall",1,Vector3(8,0,0),true)
 var u=g._spawn(kind,0,Vector3(8,0,-5));g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 g._submit("order",{"ids":[u.id],"target":wall.id,"position":wall.pos})
 var speed_ok=true;var swept_ok=true;var actual_range=true;var found_searches=-1;var bounded=true
 for i in 100:
  var before=u.pos;var hp=wall.hp
  g._tick(Rules.TICK)
  if before.distance_to(u.pos)>Rules.SPEED[kind]*Rules.TICK+.0001:speed_ok=false
  var swept_unit=u.duplicate();swept_unit.pos=before
  if before!=u.pos and (not g._path_step_is_free(before,u.pos) or not g._unit_step_is_free(swept_unit,u.pos)):swept_ok=false
  if wall.hp<hp and g._attack_distance(u.pos,wall)>Rules.RANGE[kind]+.0001:actual_range=false
  if u.path_status=="FOUND":
   if found_searches<0:found_searches=u.path_searches
   elif found_searches!=u.path_searches:bounded=false
 check(kind+" normal attack reaches actual wall damage",wall.hp<wall.max_hp)
 check(kind+" ordinary tick speed respected",speed_ok)
 check(kind+" movement respects static and unit swept clearance",swept_ok)
 check(kind+" all actual hits remain within original weapon range",actual_range)
 check(kind+" completed approach does not restart path searches",found_searches>0 and bounded and u.path_retry_searches==0)
 g.free();await process_frame
func guards():
 var g=fresh();await process_frame
 var wall=g._spawn("wall",1,Vector3(8,0,0),true)
 var u=g._spawn("cavalry",0,Vector3(7.5,0,-2.5));g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 g._path_state(u)
 u.state="attack";u.target=wall.id;u.path_status="FOUND";u.path_pending=false;u.path=PackedVector3Array();u.traffic_route=false
 u.path_request_target=wall.id;u.path_request_state="attack";u.path_request_epoch=u.work_epoch;u.path_resolved_goal=u.pos
 var baseline=u.duplicate(true)
 for reason in ["no_found","pending","path","traffic","target","request_target","request_state","epoch","endpoint","state","nonwall","hidden","collision"]:
  var e=baseline.duplicate(true);var target=wall.duplicate(true);var obstacle={}
  match reason:
   "no_found":e.path_status="NO_PATH"
   "pending":e.path_pending=true
   "path":e.path=PackedVector3Array([e.pos])
   "traffic":e.traffic_route=true
   "target":e.target=-1
   "request_target":e.path_request_target=-1
   "request_state":e.path_request_state="move"
   "epoch":e.path_request_epoch=e.work_epoch+1
   "endpoint":e.path_resolved_goal=e.pos+Vector3(2,0,0)
   "state":e.state="idle"
   "nonwall":target.kind="tower"
   "hidden":g.visible_cells[0].fill(0)
   "collision":obstacle=g._spawn("pine",-1,e.pos,true);g._navigation_rebuild()
  var before=e.pos;var searches=e.path_searches
  check("contact rejects "+reason,not g._refine_wall_contact(e,target,Rules.TICK) and e.pos==before and e.path_searches==searches)
  if reason=="hidden":g._update_vision()
  if not obstacle.is_empty():g._kill(obstacle);g._navigation_rebuild()
 var valid=baseline.duplicate(true);var before=valid.pos
 check("valid completed same-cell contact takes ordinary step",g._refine_wall_contact(valid,wall,Rules.TICK) and valid.pos!=before and g._cell(valid.pos)==g._cell(before) and before.distance_to(valid.pos)<=Rules.SPEED.cavalry*Rules.TICK+.0001)
 g.free();await process_frame
func continuation():
 var g=fresh();await process_frame
 var w=g._first(0,"villager");var point=Vector3.INF
 for z in range(-7,8):
  for x in range(-7,8):
   var p=g._snap_build_position("wall",w.pos+Vector3(x,0,z))
   if g._placement_reason("wall",p,0,w.id).is_empty():point=p;break
  if point!=Vector3.INF:break
 check("paid continuation legal wall site found",point!=Vector3.INF)
 if point==Vector3.INF:g.free();return
 var wall=g._place_building("wall",point,w.id,0)
 for i in 1800:
  if wall.built:break
  g._tick(Rules.TICK)
 check("paid wall completed by normal work",wall.built and not wall.cost_receipt_id.is_empty())
 var mover={"id":-999,"kind":"cavalry","team":1,"radius":Rules.UNIT_RADII.cavalry}
 var position=g._nearest_free(wall.pos+Vector3(0,0,-5),8,1,mover)
 var u=g._spawn("cavalry",1,position);g._update_vision();g._publish_faction_views()
 g._execute({"type":"order","team":1,"ids":[u.id],"target":wall.id,"position":wall.pos})
 var contact_boundary=false
 for i in 800:
  g._tick(Rules.TICK)
  if u.state=="attack" and u.path_status=="FOUND" and u.path.is_empty() and not u.path_pending and g._cell(u.path_resolved_goal)==g._cell(u.pos) and g._attack_distance(u.pos,wall)>Rules.RANGE.cavalry:
   contact_boundary=true;break
 check("checkpoint reaches actual FOUND same cell contact boundary",contact_boundary)
 if not contact_boundary:g.free();return
 var captured=Codec.capture_result(g)
 check("paid wall attack checkpoint passes strict codec",captured.ok)
 if captured.ok:
  var h=fresh();await process_frame
  check("paid attack restores to fresh candidate",Restore.apply(h,captured.data));h.paused=false
  for i in 100:g._tick(Rules.TICK);h._tick(Rules.TICK)
  check("wall contact continuation remains exactly deterministic",Codec.capture(g)==Codec.capture(h))
  check("continued wall attack causes real damage",wall.hp<wall.max_hp)
  check("continued economy audit remains conserved",g.economy.audit().ok and h.economy.audit().ok)
  h.free()
 g.free();await process_frame
