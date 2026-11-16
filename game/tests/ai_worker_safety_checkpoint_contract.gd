extends SceneTree
const Policy=preload("res://scripts/ai_worker_safety_checkpoint.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh():
 return {"game":{"tick_count":100},"modules":{"economy":{"_worker_farms":{},"_farms":{}}},"entities":[{"id":1,"alive":true,"team":1,"kind":"villager","state":"move","mode":"MOVE","work_epoch":3,"gather_type":"wood","resource_target":2,"last_damage_tick":50,"ai_evacuation":{"resource":2,"origin":Vector3(7,0,8),"epoch":3,"safe_since_tick":-1,"hit_tick":50}},{"id":2,"alive":true,"category":"resource","kind":"pine","pos":Vector3(7,0,8)}]}
func _initialize():
 var d=fresh()
 check("valid moving evacuation",Policy.validate(d))
 var old=d.duplicate(true);old.entities[0].erase("ai_evacuation");old.entities[0].kind="cavalry";old.entities[0].team=0
 check("unrelated legacy entity unchanged",Policy.validate(old))
 var waiting=d.duplicate(true);waiting.entities[0].state="idle";waiting.entities[0].ai_evacuation.safe_since_tick=50
 check("idle safe wait valid at hit tick",Policy.validate(waiting))
 var newhit=waiting.duplicate(true);newhit.entities[0].last_damage_tick=80
 check("newer damage invalidates earlier safe clock",not Policy.validate(newhit))
 for mode in ["survival","expedition","escort"]:
  var scripted=d.duplicate(true);scripted.game.skirmish_mode=mode
  check("scripted scenario rejects inactive AI memo "+mode,not Policy.validate(scripted))
 var deadresource=d.duplicate(true);deadresource.entities[1].alive=false
 check("depleted original resource reference remains valid",Policy.validate(deadresource))
 for kind in ["oak","berry","stone","iron"]:
  var resource=d.duplicate(true);resource.entities[1].kind=kind;resource.entities[0].gather_type={"oak":"wood","berry":"food","stone":"stone","iron":"iron"}[kind]
  check("accept original resource "+kind,Policy.validate(resource))
 for variant in ["missing","extra","notdict","dead","team0","teambool","military","mode","state","epochmismatch","epochtype","epochnegative","resourcebool","resourcefloat","resourcenegative","resourcemissing","originwrong","originnan","origintype","resourceposnan","farm","category","safeearly","safefuture","safenegative","safebool","safemoving","hitnegative","hitfuture","hitfloat","damageearly","damagefuture","damagetype","garrison_host","garrison_pending","construction_return","escort_target","tactical_points","farmindex","farmrecord"]:
  var bad=d.duplicate(true);var e=bad.entities[0];var memo=e.ai_evacuation
  match variant:
   "missing":memo.erase("origin")
   "extra":memo.extra=1
   "notdict":e.ai_evacuation=[]
   "dead":e.alive=false
   "team0":e.team=0
   "teambool":e.team=true
   "military":e.kind="spearman"
   "mode":e.mode="STOP"
   "state":e.state="gather"
   "epochmismatch":memo.epoch=4
   "epochtype":e.work_epoch=3.0
   "epochnegative":memo.epoch= -1;e.work_epoch= -1
   "resourcebool":memo.resource=true
   "resourcefloat":memo.resource=2.0
   "resourcenegative":memo.resource= -1
   "resourcemissing":memo.resource=99
   "originwrong":memo.origin=Vector3.ZERO
   "originnan":memo.origin=Vector3(NAN,0,0)
   "origintype":memo.origin=[]
   "resourceposnan":bad.entities[1].pos=Vector3.INF
   "farm":bad.entities[1].kind="farm"
   "category":bad.entities[1].category="building"
   "safeearly":e.state="idle";memo.safe_since_tick=49
   "safefuture":e.state="idle";memo.safe_since_tick=101
   "safenegative":memo.safe_since_tick= -2
   "safebool":memo.safe_since_tick=false
   "safemoving":memo.safe_since_tick=50
   "hitnegative":memo.hit_tick= -1
   "hitfuture":memo.hit_tick=101
   "hitfloat":memo.hit_tick=50.0
   "damageearly":e.last_damage_tick=49
   "damagefuture":e.last_damage_tick=101
   "damagetype":e.last_damage_tick=50.0
   "garrison_host":e.garrison_host=3
   "garrison_pending":e.garrison_pending=3
   "construction_return":e.construction_return={}
   "escort_target":e.escort_target=3
   "tactical_points":e.tactical_points=[]
   "farmindex":bad.modules.economy._worker_farms[1]=9
   "farmrecord":bad.modules.economy._farms[9]={"worker_id":1}
  check("reject "+variant,not Policy.validate(bad))
 for status in ["NO_PATH","LIMIT_REACHED","NO_WORK"]:
  var bad=d.duplicate(true);bad.entities[0].path_status=status
  check("reject terminal "+status,not Policy.validate(bad))
 for variant in ["missingtype","wrongtype","nonstringtype","missingtarget","wrongtarget","floattarget","booltarget"]:
  var bad=d.duplicate(true);var worker=bad.entities[0]
  match variant:
   "missingtype":worker.erase("gather_type")
   "wrongtype":worker.gather_type="food"
   "nonstringtype":worker.gather_type=1
   "missingtarget":worker.erase("resource_target")
   "wrongtarget":worker.resource_target=3
   "floattarget":worker.resource_target=2.0
   "booltarget":worker.resource_target=true
  check("reject inconsistent own work intent "+variant,not Policy.validate(bad))
 var before=d.duplicate(true)
 check("validation is read only",Policy.validate(d) and d==before)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"ai_worker_safety_checkpoint_contract","checks":checks,"failed":failed,"scope":"optional AI worker evacuation checkpoint validation"}))
 quit(0 if failed==0 else 1)
