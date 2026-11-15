extends SceneTree
const Visuals=preload("res://scripts/progression_visuals.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var body=Node3D.new();root.add_child(body)
 var team=Color("367ec4");var model=Visuals.build(body,"cavalry",team);var rider=model.get_node("RiderArmour")
 check("rider has separate face and helmet dome",rider.has_node("Face") and rider.has_node("HelmetDome"))
 check("helmet has brow eye slit and nose guard",rider.has_node("Brow") and rider.has_node("EyeSlit") and rider.has_node("NoseGuard"))
 check("helmet has two cheek guards",rider.has_node("CheekGuard_-1") and rider.has_node("CheekGuard_1"))
 check("armour includes breastplate and paired pauldrons",rider.has_node("Breastplate") and rider.has_node("Pauldron_-1") and rider.has_node("Pauldron_1"))
 check("faction tabard retains supplied team colour",rider.get_node("Tabard").mesh.material.albedo_color==team)
 check("crest retains faction colour",rider.get_node("Crest").mesh.material.albedo_color==team)
 check("belt has separately readable buckle",rider.has_node("Belt") and rider.has_node("Buckle"))
 check("split tabard fits seated rider",rider.get_node("TabardSkirt_-1").rotation.z<0 and rider.get_node("TabardSkirt_1").rotation.z>0)
 check("face points toward mount muzzle",rider.get_node("NoseGuard").position.z<rider.get_node("Face").position.z)
 var arm=model.get_node("LanceArm");var grip=arm.get_node("Grip");var bind=grip.transform
 Visuals.present({"kind":"cavalry","visual_attack_tick":1},body,team,0.1,true)
 check("existing weapon rig still animates under armour",absf(arm.rotation.x)>0.01 and grip.transform==bind)
 check("new armour has no collision authority",rider.find_children("*","CollisionObject3D",true,false).is_empty())
 check("provisional art status is retained",model.get_meta("provisional_art",false))
 body.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"rider_armour_contract","checks":checks,"failed":failed,"scope":"Native hierarchy and material checks, rendered coherence reviewed separately"}))
 quit(1 if failed else 0)
