extends SceneTree
const Policy=preload("res://scripts/wall_checkpoint.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func fresh(ticks=0,alive=true):
 var cap=25+floori(225.0*ticks/200)
 return {"modules":{"economy":{"_receipts":{"p":{"team":0,"cost_units":{"wood":30},"paid_milli":{"food":0,"wood":30000,"stone":0,"iron":0},"refund_policy":"started","purpose":"purchase","state":"fulfilled" if ticks==200 else ("open" if alive else "destroyed")}}}},"entities":[{"id":1,"kind":"wall","category":"building","team":0,"alive":alive,"built":ticks==200,"pos":Vector3(4,0,-6),"radius":1.0,"queue":[],"build_ticks":ticks,"progress":float(ticks)/200,"construction_hcap":cap,"hp":cap,"max_hp":250,"cost_receipt_id":"p"}]}
func _initialize():
 for ticks in [0,1,29,130,199,200]:
  var d=fresh(ticks);var before=d.duplicate(true)
  check("paid construction tick "+str(ticks),Policy.validate(d))
  check("read only tick "+str(ticks),d==before)
 check("completed destroyed retains fulfilled origin",Policy.validate(fresh(200,false)))
 check("unfinished destroyed receipt",Policy.validate(fresh(50,false)))
 var cancelled=fresh(20,false);cancelled.modules.economy._receipts.p.state="cancelled"
 check("unfinished cancelled receipt",Policy.validate(cancelled))
 var old=fresh();old.entities[0].kind="house";old.entities[0].cost_receipt_id=""
 check("other old kinds untouched",Policy.validate(old))
 for key in Policy.FORBIDDEN:
  var bad=fresh();bad.entities[0][key]=false
  check("reject forbidden "+key,not Policy.validate(bad))
 for name in ["category","team","teambool","alivebool","builtbool","halfcenter","vertical","nanpos","radius","queue","tickfloat","ticknegative","tickexcess","progressnan","progresswrong","capwrong","capfloat","hpovercap","hpinfinite","maxhp","zerohpalive","builttoosoon","missingreceipt","freereceipt","duplicate","receiptteam","cost","paid","refund","purpose","state","worker","farm"]:
  var d=fresh();var e=d.entities[0];var r=d.modules.economy._receipts.p
  match name:
   "category":e.category="unit"
   "team":e.team=2
   "teambool":e.team=false
   "alivebool":e.alive=1
   "builtbool":e.built=0
   "halfcenter":e.pos.x=4.5
   "vertical":e.pos.y=1
   "nanpos":e.pos=Vector3(NAN,0,0)
   "radius":e.radius=.5
   "queue":e.queue=[{"receipt_id":"other"}]
   "tickfloat":e.build_ticks=0.0
   "ticknegative":e.build_ticks= -1
   "tickexcess":e.build_ticks=201
   "progressnan":e.progress=NAN
   "progresswrong":e.progress=.5
   "capwrong":e.construction_hcap=250
   "capfloat":e.construction_hcap=25.0
   "hpovercap":e.hp=26
   "hpinfinite":e.hp=INF
   "maxhp":e.max_hp=300
   "zerohpalive":e.hp=0
   "builttoosoon":e.built=true
   "missingreceipt":d.modules.economy._receipts={}
   "freereceipt":e.cost_receipt_id=""
   "duplicate":d.entities.append(e.duplicate(true))
   "receiptteam":r.team=1
   "cost":r.cost_units.wood=29
   "paid":r.paid_milli.wood=29999
   "refund":r.refund_policy="unstarted"
   "purpose":r.purpose="repair"
   "state":r.state="fulfilled"
   "worker":d.modules.economy._workers={1:{}}
   "farm":d.modules.economy._farms={1:{}}
  check("reject malformed "+name,not Policy.validate(d))
 var dead=fresh(200,false);dead.entities[0].hp= -4
 check("combat destroyed completed wall HP accepted",Policy.validate(dead))
 var damaged=fresh(100);damaged.entities[0].hp=20
 check("construction damage deficit retained",Policy.validate(damaged))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wall_checkpoint_contract","checks":checks,"failed":failed,"scope":"Optional paid wall building snapshot validation without new schema; isolated runtime fixtures only"}))
 quit(0 if failed==0 else 1)
