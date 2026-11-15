extends SceneTree
const Visuals=preload("res://scripts/progression_visuals.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var body=Node3D.new();root.add_child(body)
 var model=Visuals.build(body,"cavalry",Color.BLUE)
 check("mount uses rounded body rather than box torso",model.get_node("HorseBody").mesh is SphereMesh)
 check("mount has distinct head neck and muzzle",model.has_node("HorseHead") and model.has_node("Neck") and model.has_node("Muzzle"))
 check("mount has paired ears eyes mane and tail",model.has_node("Ear_-1") and model.has_node("Ear_1") and model.has_node("Eye_-1") and model.has_node("Eye_1") and model.has_node("Mane_4") and model.has_node("Tail"))
 check("saddle and faction cloth are distinct",model.has_node("Saddle") and model.has_node("Saddlecloth"))
 for side in [-1,1]:
  for end in [-1,1]:
   var leg=model.get_node("Leg_%d_%d" % [side,end])
   check("leg %d %d pivots at hip with hoof" % [side,end],is_equal_approx(leg.position.y,0.64) and leg.get_child_count()==3 and leg.has_node("Hoof"))
 var moving={"kind":"cavalry","remembered":false,"visual_moving":true,"visual_attack_tick":-1}
 Visuals.present(moving,body,Color.BLUE,0.1,true)
 var a=model.get_node("Leg_-1_-1");var b=model.get_node("Leg_1_1");var c=model.get_node("Leg_-1_1")
 check("diagonal legs move together",is_equal_approx(a.rotation.x,b.rotation.x))
 check("opposite diagonal moves in opposite phase",is_equal_approx(a.rotation.x,-c.rotation.x))
 var pose=a.transform;Visuals.present(moving,body,Color.BLUE,0.1,false)
 check("pause holds gait",a.transform==pose)
 moving.visual_moving=false;Visuals.present(moving,body,Color.BLUE,0.1,true)
 check("idle restores standing pose",is_zero_approx(a.rotation.x))
 check("rider weapon remains attached to glove",model.has_node("LanceArm/Grip/Glove") and model.has_node("LanceArm/Grip/Lance/Shaft"))
 check("procedural mount remains marked provisional",model.get_meta("provisional_art",false))
 body.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"horse_visual_contract","checks":checks,"failed":failed,"scope":"Native topology and gait, not rendered art acceptance"}))
 quit(1 if failed else 0)
