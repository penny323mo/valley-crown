extends SceneTree
const Formation=preload("res://scripts/army_formation.gd")
var checks=[]
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok: push_error(name)
func unit(id,kind,pos=Vector3.ZERO): return {"id":id,"kind":kind,"pos":pos,"alive":true}
func _initialize():
	var units=[unit(5,"siege"),unit(4,"archer"),unit(3,"archer"),unit(2,"spearman"),unit(1,"cavalry"),unit(6,"spearman")]
	var original=units.duplicate(true)
	var p=Vector3(0,0,-10)
	var line=Formation.plan(units,p,"line"); var spread=Formation.plan(units,p,"spread")
	check("all military receive slots",line.size()==6)
	var unique={}
	for value in line.values(): unique[value]=true
	check("slots unique",line.size()==unique.size())
	check("melee no further back than ranged",line[1].z<=line[4].z and line[2].z<=line[3].z)
	check("siege behind front row",line[5].z>line[1].z)
	check("spread wider than line",spread[1].distance_to(spread[2])>line[1].distance_to(line[2]))
	units.reverse();check("input order invariant",Formation.plan(units,p,"line")==line)
	units.reverse();check("inputs not modified",units==original)
	check("invalid style no slots",Formation.plan(units,p,"wedge").is_empty())
	check("invalid destination no slots",Formation.plan(units,Vector3.INF,"line").is_empty())
	check("empty selection",Formation.plan([],p,"line").is_empty())
	check("worker excluded",Formation.plan([unit(1,"villager")],p,"line").is_empty())
	var dead=unit(7,"spearman");dead.alive=false
	check("dead excluded",Formation.plan([dead],p,"line").is_empty())
	check("duplicate removed",Formation.plan([units[0],units[0]],p,"line").size()==1)
	var edge=Formation.plan(units,Vector3(37,0,37),"spread")
	check("edge bounded",edge.values().all(func(v):return absf(v.x)<38 and absf(v.z)<38))
	var rotated=Formation.plan(units,Vector3(10,0,0),"line")
	check("direction rotates rear behind front",rotated[5].x<rotated[1].x)
	check("single no offset",Formation.plan([unit(1,"spearman")],p,"line")[1]==p)
	check("zero heading finite",Formation.plan(units,Vector3.ZERO,"line").values().all(func(v):return v.is_finite()))
	var pair=Formation.plan([unit(1,"spearman"),unit(2,"archer")],p,"line")
	check("two-unit ranged strictly behind melee",pair[2].z>pair[1].z)
	var many=[]
	for i in 50: many.append(unit(i,"spearman"))
	var mass=Formation.plan(many,Vector3(0,0,-10),"spread")
	check("population-sized formation bounded",mass.size()==50 and mass.values().all(func(v):return v.is_finite() and absf(v.x)<38 and absf(v.z)<38))
	var positioned=[unit(1,"spearman",Vector3(8.7,0,-4.2)),unit(2,"archer",Vector3(-5.3,0,6.1)),unit(3,"siege",Vector3(1.4,0,2.6))]
	var ordered=Formation.plan(positioned,p,"line");positioned.reverse()
	check("nonzero positions order invariant",Formation.plan(positioned,p,"line")==ordered)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"army_formation_contract","checks":checks,"failed":failed}));quit(1 if failed else 0)
