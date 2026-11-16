extends SceneTree
const Composition=preload("res://scripts/army_composition.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok: push_error(label)
func record(id,kind,team,remembered=false):
 return {"id":id,"kind":kind,"team":team,"owned":team==1,"alive":true,"remembered":remembered,"category":"unit"}
func equal_army():
 var result=[];var id=1
 for kind in Composition.ORDER:
  for n in Composition.BASE[kind]: result.append(record(id,kind,1));id+=1
 return result
func _initialize():
 var base=equal_army();var original=base.duplicate(true)
 check("no observations preserves baseline tie order",Composition.plan(base).kind=="spearman")
 for pair in [["cavalry","spearman"],["spearman","archer"],["archer","cavalry"]]:
  var records=base.duplicate(true);records.append(record(100,pair[0],0))
  var plan=Composition.plan(records)
  check("counter "+pair[0],plan.kind==pair[1] and plan.desired[pair[1]]==6)
  records[-1].remembered=true
  check("hidden old "+pair[0]+" ignored",Composition.plan(records)==Composition.plan(base))
  records[-1].remembered=false;records[-1].alive=false
  check("dead "+pair[0]+" ignored",Composition.plan(records)==Composition.plan(base))
 var records=base.duplicate(true)
 for i in 20: records.append(record(100+i,"archer",0))
 check("counter demand bounded",Composition.plan(records).desired.cavalry==10)
 var reverse=records.duplicate(true);reverse.reverse()
 check("input order cannot change decision",Composition.plan(records)==Composition.plan(reverse))
 records=base.duplicate(true);records.append(record(100,"archer",0));records.append(record(100,"archer",0))
 check("duplicate observation not doubled",Composition.plan(records).desired.cavalry==6)
 records=base.duplicate(true);records.append(record(100,"spearman",0));records.append({"id":101,"kind":"range","category":"building","alive":true,"owned":true,"team":1,"queue":[{"kind":"archer"}]})
 check("already queued counter avoids duplicate overcommit",Composition.plan(records).kind=="spearman" and Composition.plan(records).owned_and_queued.archer==6)
 records=base.duplicate(true);var enemy=record(100,"archer",0);enemy.category="building";records.append(enemy)
 check("building cannot spoof unit",Composition.plan(records)==Composition.plan(base))
 records=base.duplicate(true);records.append(record(100,"archer",-1))
 check("neutral cannot reveal enemy army",Composition.plan(records)==Composition.plan(base))
 records=[record(1,"spearman",1),record(2,"archer",1),record(100,"spearman",0)]
 check("opening counters spear with available archer",Composition.plan(records,["spearman","archer"]).kind=="archer")
 records[-1].kind="archer"
 check("opening never recommends locked cavalry",Composition.plan(records,["spearman","archer"]).kind=="spearman")
 check("no mutation of input",base==original)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"army_composition","checks":checks,"failed":failed}))
 quit(1 if failed else 0)
