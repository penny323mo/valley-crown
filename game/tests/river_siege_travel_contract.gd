extends SceneTree
## Focused engine fixture uses state setup explicitly. Not ordinary-play evidence.
const River=preload("res://scripts/river_terrain.gd")
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func _initialize():call_deferred("run")
func run():
 var runs=[]
 for turn in [[-13.5,1.0,0],[13.5,1.0,0],[-13.5,-1.0,1],[13.5,-1.0,1]]:
  var g=load("res://main.tscn").instantiate()
  g.layout_id=River.ID;g.skirmish_mode="standard"
  g.history_path="/tmp/v139-fixture-no-save.json"
  root.add_child(g);g.set_process(false);g.ai_enabled=false
  await process_frame
  var x=turn[0];var sign=turn[1];var team=turn[2]
  var sobj=g._spawn("siege",team,Vector3(x,0,7.5*sign),true)
  g._update_vision()
  var lane=River.BRIDGE if x<0 else River.FORD
  var target=Vector3(x,0,-7.5*sign)
  var id=sobj.id
  g._submit("order",{"ids":[id],"position":target},team)
  var n=0
  var wet=0
  var lane_ticks=0
  var failed_path=false
  var movement=0.0
  var prev=sobj.pos
  for i in range(530):
   g._tick(.05)
   var moved=g._get_entity(id)
   if not moved.alive:break
   var surf=River.surface_at(River.ID,g._cell(moved.pos))
   if surf==River.WATER:wet+=1
   if surf==lane:lane_ticks+=1
   failed_path=failed_path or moved.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]
   movement+=prev.distance_to(moved.pos);prev=moved.pos
   if moved.pos.distance_to(target)<0.85:n=i+1;break
  check("actual ordinary siege move through "+str(turn),n>0 and wet==0 and lane_ticks>10 and not failed_path and movement>12)
  runs.append({"turn":turn,"arrival_ticks":n,"lane_ticks":lane_ticks,"water_steps":wet,"movement":movement,"lookup":g._get_entity(id).get("path_reason","")})
  g.queue_free();await process_frame
 var f=checks.filter(func(x):return not x.passed)
 print("SIEGE_ROUTE_FIXTURE "+JSON.stringify(runs))
 print(JSON.stringify({"suite":"river_siege_travel_contract","checks":checks,"failed":f.size(),"scope":"Seeded test-only siege units, normal accepted commands and actual physical crossing; no trained full match or art claim."}))
 quit(0 if f.is_empty() else 1)
