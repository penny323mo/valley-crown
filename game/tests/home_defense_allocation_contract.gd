extends SceneTree
const Policy=preload("res://scripts/home_defense_allocation.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func unit(id,kind,team,pos):
	return {"id":id,"kind":kind,"team":team,"owned":team==1,"alive":true,"remembered":false,"category":"unit","pos":pos,"state":"idle","target":-1}
func _initialize():
	var castle={"kind":"town_center","owned":true,"alive":true,"hp":1200,"pos":Vector3.ZERO}
	var scout=unit(1,"scout",0,Vector3(25,0,0))
	var army=[unit(10,"spearman",1,Vector3(24,0,0)),unit(11,"archer",1,Vector3(20,0,0)),unit(12,"cavalry",1,Vector3(-25,0,0))]
	var before=army.duplicate(true)
	var p=Policy.plan(army,[scout],castle,{})
	check("remote scout gets one nearest defender",p.assignments.keys()==[10] and not p.emergency)
	check("stable repeat",Policy.plan(army,[scout],castle,{10:1})==p)
	check("no global remote recall",not p.assignments.has(12))
	var hidden=scout.duplicate();hidden.remembered=true
	check("fog retires target",Policy.plan(army,[hidden],castle,{10:1}).assignments.is_empty())
	check("vanished threat retires target",Policy.plan(army,[],castle,{10:1}).assignments.is_empty())
	var force=[unit(2,"spearman",0,Vector3(4,0,0)),unit(3,"archer",0,Vector3(4,0,1)),unit(4,"cavalry",0,Vector3(4,0,-1))]
	p=Policy.plan(army,force,castle,{})
	check("real keep raid recalls full army",p.emergency and p.assignments.size()==3)
	check("single siege at keep emergency",Policy.plan(army,[unit(5,"siege",0,Vector3(4,0,0))],castle,{}).emergency)
	check("single healthy keep scout not emergency",not Policy.plan(army,[unit(5,"scout",0,Vector3(4,0,0))],castle,{}).emergency)
	castle.hp=400
	check("low keep armed crisis",Policy.plan(army,[force[0]],castle,{}).emergency)
	check("low keep worker not crisis",not Policy.plan(army,[unit(5,"villager",0,Vector3(4,0,0))],castle,{}).emergency)
	check("pure input unchanged",army==before)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"home_defense_allocation_contract","checks":checks,"failed":failed,"scope":"Sanitized stateless bounded defense selection; no hidden lookup or save fields"}))
	quit(1 if failed else 0)
