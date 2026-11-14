extends SceneTree
const Frontier=preload("res://scripts/scout_frontier.gd")
var checks=[]
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok:push_error(name)
func _initialize():
	var home=Vector3(25,0,-24);var origin=home;var forward=-home.normalized()
	check("public centre direction preferred over rear",Frontier.score(origin,origin+forward*10,home,10)<Frontier.score(origin,origin-forward*10,home,10))
	check("nearby forward frontier beats distant map jump",Frontier.score(origin,origin+forward*10,home,10)<Frontier.score(origin,origin+forward*60,home,10))
	check("no own keep axis falls back to distance",is_equal_approx(Frontier.score(Vector3.ZERO,Vector3(3,0,4),Vector3.ZERO,10),25))
	check("zero sight falls back to distance",is_equal_approx(Frontier.score(origin,origin+Vector3(3,0,4),home,0),25))
	for p in [Vector3(3,0,7),Vector3(-12,0,15),Vector3(25,0,10)]:
		check("mirrored map symmetric "+str(p),is_equal_approx(Frontier.score(origin,p,home,10),Frontier.score(-origin,-p,-home,10)))
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"scout_frontier_contract","checks":checks,"failed":failed,"scope":"pure public geometry scoring only; no hidden entities, navigation authority or movement"}));quit(1 if failed else 0)
