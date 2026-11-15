extends SceneTree
const Visuals=preload("res://scripts/progression_visuals.gd")
const Manual=preload("res://scripts/field_manual.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var body=Node3D.new();root.add_child(body)
 var model=Visuals.build(body,"cavalry",Color("367ec4"))
 var arm=model.get_node("LanceArm");var hand=arm.get_node("Grip");var shaft=hand.get_node("Lance/Shaft");var point=hand.get_node("Lance/Point")
 check("lance is child of actual glove grip",shaft.get_parent().get_parent()==hand and hand.has_node("Glove"))
 check("both articulated arms and shield grip exist",arm.get_child_count()==3 and model.has_node("ShieldArm/Grip/Shield") and model.has_node("ShieldArm/Grip/Glove"))
 check("lance extends through glove instead of floating beside it",absf(shaft.position.x)<0.00001 and absf(shaft.position.y)<0.00001 and absf(shaft.position.z)<shaft.mesh.height/2)
 check("steel point meets wooden shaft",is_equal_approx(point.position.z+point.mesh.height/2,shaft.position.z-shaft.mesh.height/2))
 check("shield overlaps gripping glove",absf(model.get_node("ShieldArm/Grip/Shield").position.x)-model.get_node("ShieldArm/Grip/Shield").mesh.height/2<0.05)
 var record={"kind":"cavalry","remembered":false,"visual_moving":true,"visual_attack_tick":10}
 var original=record.duplicate(true);var grip_local=hand.transform;var shaft_local=shaft.transform
 Visuals.present(record,body,Color.BLUE,0.1,true)
 check("attack animates arm rather than detached weapon",absf(arm.rotation.x)>0.01)
 check("grip and shaft local binding remains rigid under attack",hand.transform==grip_local and shaft.transform==shaft_local)
 var axis=shaft.global_basis.y.normalized();var to_grip=hand.global_position-shaft.global_position
 check("animated shaft still intersects hand in world space",to_grip.cross(axis).length()<0.00001 and absf(to_grip.dot(axis))<=shaft.mesh.height/2)
 var paused=arm.transform;Visuals.present(record,body,Color.BLUE,0.1,false)
 check("pause freezes arm pose",arm.transform==paused)
 Visuals.present(record,body,Color.BLUE,0.3,true)
 check("attack settles into held ready pose",is_zero_approx(arm.rotation.x))
 check("presentation does not mutate detached observation",record==original)
 var count=model.get_child_count()
 for i in 10:Visuals.present(record,body,Color.BLUE,0.05,true)
 check("presentation reuses one equipment set",model.get_child_count()==count and body.get_child_count()==1)
 var tower=Manual.entry(1,Manual.entries(1).find("tower"));var siege=Manual.entry(0,Manual.entries(0).find("siege"))
 check("tower manual no longer contradicts unlimited expansion",not tower.body.contains("每隊最多") and tower.body.contains("沒有兩座上限"))
 check("siege manual documents actual paid repair",siege.body.contains("1 木材") and siege.body.contains("移動或攻擊會中止"))
 body.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"cavalry_grip_contract","checks":checks,"failed":failed,"scope":"Native mesh parent/transform/contact/animation checks only; not rendered art approval or screenshot"}))
 quit(1 if failed else 0)
