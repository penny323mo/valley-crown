extends SceneTree
const P=preload("res://scripts/escort_policy.gd")
var checks=[]
func check(name,passed):
 checks.append({"name":name,"passed":passed})
 if not passed:push_error(name)
func unit(id,team,kind,pos):
 return {"id":id,"team":team,"kind":kind,"pos":pos,"category":"unit","alive":true,"remembered":false,"owned":team==0,"visible":true}
func _initialize():
 var records={1:unit(1,0,"spearman",Vector3.ZERO),2:unit(2,0,"villager",Vector3(1,0,0))}
 var before=records.duplicate(true)
 check("nearby guard holds without new move",P.decide(records,1,2,0).action=="hold")
 check("observations unchanged",records==before)
 records[2].pos=Vector3(8,0,0)
 check("distant moving ally triggers follow",P.decide(records,1,2,0).action=="follow")
 records[3]=unit(3,1,"cavalry",Vector3(7,0,0))
 check("outside leash follows instead of chasing threat",P.decide(records,1,2,0).action=="follow")
 records[1].pos=Vector3(6,0,0)
 check("visible nearby threat intercepted",P.decide(records,1,2,0)=={"action":"intercept","target":3})
 var hidden=records[3];records.erase(3)
 check("unseen threat ignored",P.decide(records,1,2,0).action=="hold")
 records[3]=hidden;records[3].remembered=true
 check("remembered threat ignored",P.decide(records,1,2,0).action=="hold")
 records[3].remembered=false;records[3].alive=false
 check("dead observed threat ignored",P.decide(records,1,2,0).action=="hold")
 records[3].alive=true;records[3].pos=Vector3(20,0,0)
 check("enemy outside ally leash ignored",P.decide(records,1,2,0).action=="hold")
 records[3].pos=Vector3(7,0,0);records[4]=unit(4,1,"archer",Vector3(5,0,0))
 check("equal-distance threats deterministic",P.decide(records,1,2,0).target==3)
 var reverse={4:records[4],3:records[3],2:records[2],1:records[1]}
 check("record order cannot change threat",P.decide(records,1,2,0)==P.decide(reverse,1,2,0))
 check("explicit pending user order cancels escort",P.decide(records,1,2,0,true).action=="cancel")
 records[2].alive=false
 check("observed dead ally cancels",P.decide(records,1,2,0).action=="cancel")
 records[2].alive=true;records[2].kind="siege"
 check("siege can be protected",P.decide(records,1,2,0).action=="intercept")
 records[1].kind="siege"
 check("siege cannot act as mobile guard",P.decide(records,1,2,0).action=="cancel")
 records[1].kind="archer";records[2].owned=false
 check("foreign or non-owned target rejected",P.decide(records,1,2,0).action=="cancel")
 records[2].owned=true;records[2].pos=Vector3.INF
 check("invalid target position rejected",P.decide(records,1,2,0).action=="cancel")
 check("missing units cancel safely",P.decide({},1,2,0).action=="cancel")
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"escort_policy_contract","checks":checks,"failed":failed}))
 quit(1 if failed else 0)
