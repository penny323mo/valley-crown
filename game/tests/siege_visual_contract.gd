extends SceneTree
const Visuals=preload("res://scripts/progression_visuals.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var body=Node3D.new();root.add_child(body)
 var model=Visuals.build(body,"siege",Color.BLUE)
 var ram=model.get_node("Ram");var head=ram.get_node("Head");var shaft=ram.get_node("Shaft")
 check("striking head and shaft share moving ram frame",head.get_parent()==shaft.get_parent() and head.get_parent()==ram)
 check("metal head overlaps shaft end",head.position.z+head.mesh.size.z/2>-shaft.mesh.height/2)
 var head_local=head.transform;var relative=head.global_position-shaft.global_position
 var record={"kind":"siege","remembered":false,"visual_moving":true,"visual_attack_tick":10}
 var original=record.duplicate(true)
 Visuals.present(record,body,Color.BLUE,0.1,true)
 check("ram thrust moves assembly forward",ram.position.z< -0.1)
 check("striking head follows shaft throughout thrust",head.transform==head_local and (head.global_position-shaft.global_position).is_equal_approx(relative))
 var paused=ram.transform;Visuals.present(record,body,Color.BLUE,0.1,false)
 check("paused ram keeps exact pose",ram.transform==paused)
 Visuals.present(record,body,Color.BLUE,0.3,true)
 check("ram returns to resting frame",is_equal_approx(ram.position.z,-0.1))
 for x in [-1,1]:
  for z in [-1,1]:
   var wheel=model.get_node("Wheel_%d_%d" % [x,z])
   check("wheel %d %d has open rim hub and six spokes" % [x,z],wheel.get_child_count()==8 and wheel.get_node("Rim").mesh is TorusMesh and wheel.has_node("Hub"))
 check("protective roof has two pitched faces",model.get_node("Roof_-1").rotation.z>0 and model.get_node("Roof_1").rotation.z<0)
 check("observation remains untouched",record==original)
 check("art remains explicitly provisional",model.get_meta("provisional_art",false))
 body.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"siege_visual_contract","checks":checks,"failed":failed,"scope":"Native geometry and animation; rendered quality assessed separately"}))
 quit(1 if failed else 0)
