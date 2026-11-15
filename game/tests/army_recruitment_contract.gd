extends SceneTree
const Planner=preload("res://scripts/army_recruitment.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func producer(id,kind="barracks",length=0):
 var queue=[]
 for i in length:queue.append({"kind":"spearman"})
 return {"id":id,"kind":kind,"category":"building","team":0,"owned":true,"alive":true,"remembered":false,"built":true,"queue":queue}
func _initialize():
 var bank={"food":500000,"wood":500000,"iron":500000,"stone":500000}
 var records={9:producer(9),2:producer(2)}
 var before=records.duplicate(true);var money=bank.duplicate(true)
 var p=Planner.plan(records,"spearman",bank,10)
 check("three normal orders balanced with ID tie break",p.orders==[{"building":2,"kind":"spearman"},{"building":9,"kind":"spearman"},{"building":2,"kind":"spearman"}])
 check("whole resource cost and count exact",p.count==3 and p.cost=={"food":150,"wood":60})
 check("inputs remain unchanged",records==before and bank==money)
 check("dictionary order does not influence plan",Planner.plan({2:records[2],9:records[9]},"spearman",bank,10)==p)
 check("shorter queue preferred over smaller ID",Planner.plan({2:producer(2,"barracks",4),9:producer(9)},"spearman",bank,10).orders.all(func(o):return o.building==9))
 check("queue cap remains five",Planner.plan({2:producer(2,"barracks",4)},"spearman",bank,10).count==1)
 check("full queue unavailable",Planner.plan({2:producer(2,"barracks",5)},"spearman",bank,10).count==0)
 check("population reserves only available places",Planner.plan(records,"spearman",bank,2).count==2 and Planner.plan(records,"spearman",bank,0).count==0)
 check("exact milli resource boundary enforced",Planner.plan(records,"spearman",{"food":100000,"wood":39999},10).count==1)
 check("insufficient first cost emits no orders",Planner.plan(records,"spearman",{"food":49999,"wood":500000},10).count==0)
 check("locked units cannot be planned",Planner.plan(records,"spearman",bank,10,[],false).count==0)
 check("any own pending command blocks duplicate planning",Planner.plan(records,"spearman",bank,10,[{"team":0,"type":"move"}]).count==0)
 check("enemy pending orders do not block",Planner.plan(records,"spearman",bank,10,[{"team":1,"type":"train"}])==p)
 var rejected=true
 for change in [{"owned":false},{"team":1},{"alive":false},{"remembered":true},{"built":false},{"category":"unit"},{"id":99},{"kind":"range"}]:
  var r=producer(2);r.merge(change,true)
  rejected=rejected and Planner.plan({2:r},"spearman",bank,10).count==0
 check("only matching current alive completed own producer accepted",rejected)
 check("nonmilitary and unknown kinds rejected",Planner.plan(records,"villager",bank,10).count==0 and Planner.plan(records,"dragon",bank,10).count==0)
 check("scout uses town center products not primary product",Planner.plan({2:producer(2,"town_center")},"scout",bank,10).count==3)
 check("siege uses workshop and its ordinary costs",Planner.plan({2:producer(2,"workshop")},"siege",bank,10).cost=={"wood":480,"iron":210})
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"army_recruitment_contract","checks":checks,"failed":failed,"scope":"Pure advisory planning from owned current observations; normal commands retain authority"}));quit(1 if failed else 0)
