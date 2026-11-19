extends SceneTree
## Targeted rendering/presentation fixture. Separate natural journey proves the real spend and score.
const Mission=preload("res://scripts/frontier_escort.gd")
var checks=[]
func check(name:String,passed:bool):
 checks.append({"name":name,"passed":passed})
func _initialize():
 call_deferred("run")
func scene(mode:String):
 var g=load("res://main.tscn").instantiate()
 g.skirmish_mode=mode;g.victory_mode="conquest";g.test_mode=true
 root.add_child(g);g.set_process(false)
 return g
func run():
 root.size=Vector2i(390,844)
 var g=scene("escort")
 var b=g.escort_outline
 check("all four scoring boundary corners remain inclusive",[Vector3(-11,0,3),Vector3(-3,0,3),Vector3(-11,0,9),Vector3(-3,0,9)].all(Mission.in_zone))
 check("one step outside any edge remains outside",[Vector3(-12,0,6),Vector3(-2,0,6),Vector3(-7,0,2),Vector3(-7,0,10)].all(func(p):return not Mission.in_zone(p)))
 check("only a noncolliding mesh is present",b is MeshInstance3D and b.get_child_count()==0 and b.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
 check("perimeter consists of bounded unique edge segments",g.escort_outline_segments.size()==28 and g.escort_outline_cells.size()==28)
 check("unexplored objective has no outline",not b.visible and b.mesh.get_surface_count()==0)
 var vis=g.visible_cells[0].duplicate();var path=g.work_memory[0].grid.get_id_path(Vector2i(1,1),Vector2i(2,2));var bank=g.economy.bank_milli(0);var commands=g.commands.duplicate(true)
 var idx=g.escort_outline_cells[2]
 g.explored_cells[0][idx]=1
 var explored=g.explored_cells[0].duplicate()
 g._refresh_escort_outline()
 check("one explored inside segment reveals only its expected bit",b.visible and g.escort_outline_mask==(1<<2) and b.mesh.get_surface_count()==1)
 check("rendering does not mutate facts",g.visible_cells[0]==vis and g.explored_cells[0]==explored and g.economy.bank_milli(0)==bank and g.commands==commands)
 check("rendering does not alter known path",g.work_memory[0].grid.get_id_path(Vector2i(1,1),Vector2i(2,2))==path)
 for ci in g.escort_outline_cells:g.explored_cells[0][ci]=1
 g._refresh_escort_outline()
 check("full explored outline uses one draw surface",b.visible and g.escort_outline_mask==((1<<28)-1) and b.mesh.get_surface_count()==1)
 g.frontier_escort.stage=1
 g.build_mode="storehouse";g.build_preview_held=true
 g.pointer_world=Vector3(-11.01,0,6)
 check("warehouse hint follows snapped outside center",g._escort_build_zone_hint()=="前哨外，不計任務")
 g.pointer_world=Vector3(-10.99,0,6)
 check("warehouse hint follows snapped included center",g._escort_build_zone_hint()=="前哨內，完成先計")
 g.build_mode="tower";g.frontier_escort.stage=2
 g.pointer_world=Vector3(-2.99,0,6)
 check("replacement tower uses the same inclusive center",g._escort_build_zone_hint()=="前哨內，完成先計")
 g.pointer_world=Vector3(-1.99,0,6)
 check("replacement tower outside remains a warning",g._escort_build_zone_hint()=="前哨外，不計任務")
 g.build_preview_held=false
 check("no misleading warning without a chosen preview",g._escort_build_zone_hint()=="")
 g.build_mode="house";g.build_preview_held=true
 check("other structures receive no mission placement hint",g._escort_build_zone_hint()=="")
 g.frontier_escort.stage=3;g._refresh_escort_outline()
 check("completed mission retires outline and hint",not b.visible and g._escort_build_zone_hint()=="")
 g.queue_free()
 var other=scene("standard")
 check("standard mode has no outpost mesh and no hint",not is_instance_valid(other.escort_outline) and other._escort_build_zone_hint()=="")
 other.queue_free()
 var n=checks.filter(func(row):return not row.passed).size()
 print(JSON.stringify({"suite":"escort_outpost_boundary_contract","scope":"Presentation and snapped center unit checks; no natural spend claim","checks":checks,"failed":n}))
 quit(0 if n==0 else 1)
