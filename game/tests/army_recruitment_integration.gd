extends SceneTree
class Fixture:
 extends "res://scripts/game.gd"
 var aged=true
 func _age2(_team: int) -> bool: return aged
 func _ai_can_budget(_kind): return true
var checks=[]
var id=0
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok: push_error(label)
func entity(kind,category,team=1):
 id+=1
 return {"id":id,"kind":kind,"category":category,"team":team,"owned":team==1,"alive":true,"remembered":false,"built":true,"queue":[]}
func records():
 var result=[]
 for kind in ["town_center","barracks","range"]: result.append(entity(kind,"building"))
 for i in 4: result.append(entity("berry","resource",-1))
 return result
func _initialize():
 var g=Fixture.new();var r=records()
 r.append(entity("spearman","unit"));r.append(entity("archer","unit"))
 var before=r.duplicate(true)
 check("no enemy opening remains old tie",g._ai_progression_goal(r,8,50,10)=="spearman")
 var enemy=entity("spearman","unit",0);r.append(enemy)
 check("seen spear adapts opening to archer",g._ai_progression_goal(r,8,50,10)=="archer")
 enemy.remembered=true
 check("lost sight cannot affect opening",g._ai_progression_goal(r,8,50,10)=="spearman")
 enemy.remembered=false
 check("worker floor precedes tactics",g._ai_progression_goal(r,2,50,10)=="villager")
 check("housing precedes tactics",g._ai_progression_goal(r,8,20,19)=="house")
 r=records()
 for kind in ["stable","workshop","tower","tower"]: r.append(entity(kind,"building"))
 for kind in ["spearman","archer","cavalry"]:
  for i in 5:r.append(entity(kind,"unit"))
 for i in 2:r.append(entity("siege","unit"))
 r.append(entity("scout","unit"))
 check("no enemy late game preserves tie",g._ai_progression_goal(r,12,50,30)=="spearman")
 enemy=entity("archer","unit",0);r.append(enemy)
 check("seen archer late game recruits cavalry",g._ai_progression_goal(r,12,50,30)=="cavalry")
 for entry in r:
  if entry.kind=="stable": entry.queue=[{"kind":"cavalry"}]
 check("queued counter already covers current deficit",g._ai_progression_goal(r,12,50,30)=="spearman")
 g.aged=false
 check("technology gate precedes adaptive recruitment",g._ai_progression_goal(r,12,50,30)=="age2")
 check("no source mutation initial data",before[0].queue.is_empty())
 g.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"army_recruitment_integration","checks":checks,"failed":failed}))
 quit(1 if failed else 0)
