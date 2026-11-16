extends SceneTree
const Policy=preload("res://scripts/home_defense.gd")
var checks=[]
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok: push_error(label)
func unit(id,kind,team,pos):
	return {"id":id,"kind":kind,"team":team,"owned":team==1,"alive":true,"remembered":false,"category":"unit","pos":pos,"radius":0.35,"state":"idle","target":-1}
func _initialize():
	var home={"id":100,"kind":"town_center","category":"building","team":1,"owned":true,"alive":true,"pos":Vector3.ZERO}
	var worker=unit(1,"villager",0,Vector3(1,0,0))
	var spear=unit(2,"spearman",0,Vector3(5,0,0))
	var archer=unit(3,"archer",0,Vector3(5,0,1))
	var horse=unit(4,"cavalry",0,Vector3(5,0,-1))
	var records=[home,worker,spear,archer,horse]
	var before=records.duplicate(true)
	var threats=Policy.threats(records,6)
	check("four current home invaders",threats.size()==4)
	for pair in [["spearman",4],["cavalry",3],["archer",2]]:
		var actor=unit(50,pair[0],1,Vector3(-3,0,0))
		check(pair[0]+" selects its counter not closer worker",Policy.choose(actor,threats).id==pair[1])
	var actor=unit(50,"spearman",1,Vector3.ZERO)
	check("worker only raid remains defendable",Policy.choose(actor,[worker]).id==1)
	check("villager never commandeered",Policy.choose(unit(50,"villager",1,Vector3.ZERO),threats).is_empty())
	check("enemy never commandeered",Policy.choose(unit(50,"spearman",0,Vector3.ZERO),threats).is_empty())
	var hidden=horse.duplicate();hidden.remembered=true
	check("remembered invader excluded",Policy.threats([home,hidden],6).is_empty() and Policy.choose(actor,[hidden]).is_empty())
	var dead=horse.duplicate();dead.alive=false
	check("dead invader excluded",Policy.threats([home,dead],6).is_empty())
	var distant=horse.duplicate();distant.pos=Vector3(20,0,0)
	check("distant visible enemy not home threat",Policy.threats([home,distant],6).is_empty())
	var edge=horse.duplicate();edge.pos=Vector3(8,0,2)
	check("building box boundary retained",Policy.threats([home,edge],6).size()==1)
	edge.pos.x+=0.01
	check("outside building boundary excluded",Policy.threats([home,edge],6).is_empty())
	check("duplicate invaders deduplicated",Policy.threats([home,horse,horse],6).size()==1)
	var foreign_home=home.duplicate();foreign_home.owned=false;foreign_home.team=0
	check("enemy building does not define home",Policy.threats([foreign_home,horse],6).is_empty())
	var dead_home=home.duplicate();dead_home.alive=false
	check("destroyed home does not define threat zone",Policy.threats([dead_home,horse],6).is_empty())
	var nearby=spear.duplicate();nearby.pos=Vector3(1,0,0)
	check("available military shot before distant counter",Policy.choose(actor,[horse,nearby]).id==2)
	var tie=spear.duplicate();tie.id=8
	check("stable id tie break",Policy.choose(actor,[tie,spear]).id==2)
	actor.state="attack";actor.target=8
	check("equal current target retained",Policy.choose(actor,[spear,tie]).id==8)
	var reverse=threats.duplicate();reverse.reverse()
	check("input order independent",Policy.choose(actor,threats)==Policy.choose(actor,reverse))
	check("inputs not mutated",records==before)
	check("no threats no invented target",Policy.choose(actor,[]).is_empty())
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"home_defense_contract","checks":checks,"failed":failed,"scope":"Pure sanitized-observation policy, not natural battle or rendering"}))
	quit(1 if failed else 0)
