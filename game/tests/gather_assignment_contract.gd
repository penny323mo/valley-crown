extends SceneTree
const Dispatch=preload("res://scripts/idle_gather_dispatch.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func worker(id,p):return {"id":id,"owned":true,"alive":true,"team":0,"category":"unit","kind":"villager","state":"idle","path":[],"pos":p}
func node(id,p):return {"id":id,"alive":true,"remembered":false,"team":-1,"category":"resource","kind":"pine","hp":100,"pos":p}
func _initialize():
 var r={1:worker(1,Vector3(20,0,0)),2:worker(2,Vector3(2,0,0)),3:worker(3,Vector3(3,0,0)),4:worker(4,Vector3(4,0,0)),10:node(10,Vector3.ZERO)}
 var before=r.duplicate(true);var p=Dispatch.orders(r,[],"wood")
 check("nearest three workers instead of lowest identifiers",p.map(func(o):return o.ids[0])==[2,3,4])
 check("planner does not mutate records",r==before)
 r={1:worker(1,Vector3.ZERO),2:worker(2,Vector3.ZERO),3:worker(3,Vector3.ZERO),10:node(10,Vector3(3,0,0)),11:node(11,Vector3(4,0,0)),12:node(12,Vector3(4.5,0,0))}
 p=Dispatch.orders(r,[],"wood")
 check("nearby batch spreads over three nodes",p.map(func(o):return o.target)==[10,11,12])
 check("worker used only once",p.map(func(o):return o.ids[0])==[1,2,3])
 var reversed={}
 var keys=r.keys();keys.reverse()
 for id in keys:reversed[id]=r[id]
 check("input order independent",Dispatch.orders(reversed,[],"wood")==p)
 r[4]=worker(4,Vector3.ONE);r[4].state="gather";r[4].target=10
 check("existing gather load prefers nearby alternative",Dispatch.orders(r,[],"wood")[0].target==11)
 var c=[{"team":0,"type":"order","ids":[4],"target":11}]
 check("pending reassignment replaces old load",Dispatch.orders(r,c,"wood")[0].target==10)
 c=[{"team":0,"type":"order","ids":[4],"target":10},{"team":0,"type":"order","ids":[4],"target":10}]
 r[11].pos=Vector3(6,0,0);r[12].pos=Vector3(30,0,0)
 check("duplicate pending worker not double counted",Dispatch.orders(r,c,"wood")[0].target==10)
 c=[{"team":0,"type":"stop","ids":[4]}]
 check("pending stop retires observed assignment",Dispatch.orders(r,c,"wood")[0].target==10)
 r[11].pos=Vector3(30,0,0)
 check("does not prefer remote empty forest",Dispatch.orders(r,[],"wood").all(func(o):return o.target==10))
 r[4].owned=false;r[11].pos=Vector3(4,0,0)
 check("unowned work is not own reservation",Dispatch.orders(r,[],"wood")[0].target==10)
 r[4].owned=true;r[4].remembered=true
 check("remembered work not counted",Dispatch.orders(r,[],"wood")[0].target==10)
 r[4].remembered=false;r[4].alive=false
 check("dead work not counted",Dispatch.orders(r,[],"wood")[0].target==10)
 r[4].alive=true;r[4].kind="scout"
 check("military pending order not gathering load",Dispatch.orders(r,[{"team":0,"type":"order","ids":[4],"target":10}],"wood")[0].target==10)
 r[11].hp=0
 check("zero HP resource excluded",Dispatch.orders(r,[],"wood").all(func(o):return o.target!=11))
 r[11].remembered=true;r[12].alive=false
 check("hidden and depleted alternatives excluded",Dispatch.orders(r,[],"wood").all(func(o):return o.target==10))
 r[1].cargo_milli=1000
 check("carried cargo never redirected",Dispatch.orders(r,[],"wood").all(func(o):return o.ids[0]!=1))
 check("pending worker job never stolen",Dispatch.orders(r,[{"team":0,"type":"build","builder":2}],"wood").all(func(o):return o.ids[0]!=2))
 check("ordinary order schema unchanged",p.all(func(o):return o.keys().size()==4 and o.idle_gather=="wood" and o.ids.size()==1))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"gather_assignment_contract","checks":checks,"failed":failed,"scope":"Observation-only advisory assignment, not path safety or rendered acceptance"}))
 quit(1 if failed else 0)
