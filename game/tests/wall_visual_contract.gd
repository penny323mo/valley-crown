extends SceneTree
const Wall=preload("res://scripts/wall_visual.gd")
const Construction=preload("res://scripts/construction_visual.gd")
const Damage=preload("res://scripts/building_damage_presenter.gd")
const Buildings=preload("res://scripts/advanced_building_visuals.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func bounds(mesh:Mesh):
 var b=mesh.get_aabb()
 return b.position.x>= -.951 and b.end.x<=.951 and b.position.z>= -.951 and b.end.z<=.951 and b.position.y>= -.001 and b.end.y<=1.401
func triangles(mesh):
 var result=0
 for i in mesh.get_surface_count():
  var arrays=mesh.surface_get_arrays(i)
  result+=arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX].size()>0 else arrays[Mesh.ARRAY_VERTEX].size()/3
 return result
func record(id,kind,hp=50,remembered=false):
 return {"id":id,"kind":kind,"category":"building","alive":true,"built":true,"hp":hp,"max_hp":250,"remembered":remembered,"pos":Vector3.ZERO}
func _initialize():
 var a=Wall.instantiate_asset(Color.BLUE);var b=Wall.instantiate_asset(Color.RED)
 root.add_child(a);root.add_child(b)
 var mesh=a.get_node("PalisadeMesh").mesh
 check("wall fits declared occupied 2x2 square",bounds(mesh))
 check("low wall roof below troop camera obstruction",mesh.get_aabb().end.y<=1.401)
 check("four batched material surfaces",mesh.get_surface_count()==4)
 check("finished mesh triangle budget",triangles(mesh)<=1024)
 check("finished shape independent of team tint",mesh.surface_get_arrays(0)==b.get_child(0).mesh.surface_get_arrays(0))
 check("only one mesh and no physics children",a.get_child_count()==1 and a.get_child(0) is MeshInstance3D)
 check("faction accents differ without mesh scale",mesh.surface_get_material(3).albedo_color==Color.BLUE and b.get_child(0).mesh.surface_get_material(3).albedo_color==Color.RED)
 check("construction oak material discoverable",Construction._material(a,"oak")!=null)
 check("compact wall health bar",is_equal_approx(Buildings.health_bar_height("wall"),1.65))
 for stage in 3:
  var m=Wall.construction_mesh(stage)
  check("construction bounds "+str(stage),bounds(m))
  check("construction two batched surfaces "+str(stage),m.get_surface_count()==2)
  check("construction triangle budget "+str(stage),triangles(m)<=640)
  check("deterministic construction geometry "+str(stage),m.surface_get_arrays(0)==Wall.construction_mesh(stage).surface_get_arrays(0))
 for progress in [0.0,.2,.7,1.0]:
  Construction.apply(a,"wall",progress==1.0,progress)
  var site=a.get_node("ConstructionSite")
  check("construction visibility "+str(progress),site.visible==(progress<1.0) and a.get_node("PalisadeMesh").visible==(progress==1.0))
 a.visible=false;Construction.apply(a,"wall",false,.5)
 check("construction does not reveal hidden observed proxy",not a.visible)
 var presenter=Damage.new();var parent=Node3D.new();root.add_child(parent)
 var records={};var id=0;var kinds=Rules.FOOTPRINT.keys()
 if not "wall" in kinds:kinds.append("wall")
 for kind in kinds:
  for hp in [100,50]:records[id]=record(id,kind,hp);id+=1
 presenter.update(records,parent)
 check("all ten building profiles both damage tiers cache",presenter.meshes.size()==20 and presenter.nodes.size()==20 and Damage.MAX_MESHES==20)
 check("wall visible damage tiers",Damage.tier(record(1,"wall",100))==1 and Damage.tier(record(1,"wall",50))==2)
 var wall_mesh=Damage.make_mesh("wall",2)
 check("wall debris is timber not stone colour",wall_mesh.surface_get_material(1).albedo_color==Color("6b5038"))
 check("remembered wall does not reveal current damage",Damage.tier(record(1,"wall",50,true))==0)
 var dead=record(1,"wall");dead.alive=false
 check("dead wall no damage overlay",Damage.tier(dead)==0)
 var construction=record(1,"wall");construction.built=false
 check("unbuilt wall no finished damage overlay",Damage.tier(construction)==0)
 records={}
 for i in 80:records[i]=record(i,"wall")
 presenter.update(records,parent)
 check("existing active damage cap remains 64",presenter.nodes.size()==64 and Damage.MAX_ACTIVE==64)
 presenter.update({},parent)
 check("hidden retirement immediate",presenter.nodes.is_empty() and parent.get_child_count()==0)
 presenter.clear();a.free();b.free();parent.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"wall_visual_contract","checks":checks,"failed":failed,"scope":"Code-native wall geometry, construction and observed damage; not gameplay placement or natural siege acceptance"}))
 quit(0 if failed==0 else 1)
