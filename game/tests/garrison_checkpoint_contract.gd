extends SceneTree
const Policy=preload("res://scripts/garrison_checkpoint.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh():
 return {"entities":[{"id":0,"kind":"town_center","team":0,"alive":true,"built":true,"pos":Vector3.ZERO},{"id":1,"kind":"villager","team":0,"alive":true,"state":"idle","mode":"STOP","target":-1,"path":PackedVector3Array(),"path_pending":false,"pos":Vector3(2.5,0,0),"dest":Vector3(2.5,0,0)}],"modules":{"economy":{"_worker_farms":{},"_farms":{}}}}
func _initialize():
 var d=fresh()
 check("legacy absence remains valid",Policy.validate(d))
 d.entities[1].garrison_host=0
 check("inside retains entry position",Policy.validate(d) and d.entities[1].pos==Vector3(2.5,0,0))
 for variant in ["bool","float","negative","missing","both","dead","soldier","enemy","neutral","hostdead","hostunfinished","hostkind","moving","mode","target","targetbool","path","pathpending","pathpendingtype","construction_return","escort_target","escort_next_tick","tactical_points","farmindex","farmrecord"]:
  var bad=d.duplicate(true);var e=bad.entities[1];var h=bad.entities[0]
  match variant:
   "bool":e.garrison_host=false
   "float":e.garrison_host=0.0
   "negative":e.garrison_host= -1
   "missing":e.garrison_host=9
   "both":e.garrison_pending=0
   "dead":e.alive=false
   "soldier":e.kind="spearman"
   "enemy":e.team=1
   "neutral":e.team= -1
   "hostdead":h.alive=false
   "hostunfinished":h.built=false
   "hostkind":h.kind="storehouse"
   "moving":e.state="move"
   "mode":e.mode="ADVANCE"
   "target":e.target=0
   "targetbool":e.target=false
   "path":e.path=PackedVector3Array([Vector3.ONE])
   "pathpending":e.path_pending=true
   "pathpendingtype":e.path_pending=0
   "construction_return":e.construction_return={}
   "escort_target":e.escort_target=0
   "escort_next_tick":e.escort_next_tick=0
   "tactical_points":e.tactical_points=[]
   "farmindex":bad.modules.economy._worker_farms[1]=7
   "farmrecord":bad.modules.economy._farms[7]={"worker_id":1}
  check("reject inside "+variant,not Policy.validate(bad))
 d.entities[1].erase("garrison_host");d.entities[1].garrison_pending=0
 check("pending arrival idle accepted",Policy.validate(d))
 d.entities[1].state="move";d.entities[1].mode="MOVE"
 check("pending moving accepted",Policy.validate(d))
 for status in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:
  var bad=d.duplicate(true);bad.entities[1].path_status=status
  check("pending rejects terminal "+status,not Policy.validate(bad))
 for value in [true,0.0,-1,8]:
  var bad=d.duplicate(true);bad.entities[1].garrison_pending=value
  check("pending rejects invalid host "+str(value),not Policy.validate(bad))
 var bad=d.duplicate(true);bad.entities[1].state="gather"
 check("pending rejects gathering",not Policy.validate(bad))
 bad=d.duplicate(true);bad.entities[1].alive=false
 check("pending rejects dead residue",not Policy.validate(bad))
 for i in range(2,6):
  var e=d.entities[1].duplicate(true);e.id=i
  if i%2==0:e.erase("garrison_pending");e.garrison_host=0;e.state="idle";e.mode="STOP"
  d.entities.append(e)
 check("five combined reservations accepted",Policy.validate(d))
 var sixth=d.entities[1].duplicate(true);sixth.id=6;d.entities.append(sixth)
 check("six combined reservations rejected",not Policy.validate(d))
 var second=fresh();second.entities[0].team=1;second.entities[1].team=1;second.entities[1].garrison_host=0
 check("same team one accepted",Policy.validate(second))
 for variant in ["far","diagonal","nan","hostnan","wrongpos","selected","pathrequest","evacuation","ownview","enemyview"]:
  var invalid=fresh();invalid.entities[1].garrison_host=0
  invalid.game={"selected":[],"path_requests":[],"worker_evacuations":{}}
  invalid.faction_views=[{"current":{}},{"current":{}}]
  match variant:
   "far":invalid.entities[1].pos=Vector3(4,0,0)
   "diagonal":invalid.entities[1].pos=Vector3(3,0,3)
   "nan":invalid.entities[1].pos=Vector3(NAN,0,0)
   "hostnan":invalid.entities[0].pos=Vector3(0,0,INF)
   "wrongpos":invalid.entities[1].pos=[2.5,0,0]
   "selected":invalid.game.selected=[1]
   "pathrequest":invalid.game.path_requests=[1]
   "evacuation":invalid.game.worker_evacuations[1]={}
   "ownview":invalid.faction_views[0].current[1]={}
   "enemyview":invalid.faction_views[1].current[1]={}
  check("reject spatial or ground residue "+variant,not Policy.validate(invalid))
 for variant in ["destnan","destfar","desttype","posnan","postype","hostnan","hosttype","movemode","idlemode"]:
  var invalid=fresh();invalid.entities[1].garrison_pending=0
  match variant:
   "destnan":invalid.entities[1].dest=Vector3(NAN,0,0)
   "destfar":invalid.entities[1].dest=Vector3(8,0,0)
   "desttype":invalid.entities[1].dest=[2.5,0,0]
   "posnan":invalid.entities[1].pos=Vector3(INF,0,0)
   "postype":invalid.entities[1].pos=null
   "hostnan":invalid.entities[0].pos=Vector3(0,NAN,0)
   "hosttype":invalid.entities[0].pos=[]
   "movemode":invalid.entities[1].state="move";invalid.entities[1].mode="ADVANCE"
   "idlemode":invalid.entities[1].mode="MOVE"
  check("pending rejects destination or mode "+variant,not Policy.validate(invalid))
 var unchanged=fresh();unchanged.entities[1].garrison_host=0;unchanged.entities[1].cargo_type="wood";unchanged.entities[1].carry=5
 var before=unchanged.duplicate(true)
 check("validation preserves living population and cargo",Policy.validate(unchanged) and unchanged==before and unchanged.entities[1].alive and unchanged.entities[1].carry==5)
 var passed=checks.filter(func(c):return c.passed).size()
 print(JSON.stringify({"suite":"garrison_checkpoint_contract","scope":"optional garrison checkpoint validation","failed":checks.size()-passed,"checks":checks}))
 quit(0 if passed==checks.size() else 1)
