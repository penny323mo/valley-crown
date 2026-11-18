extends SceneTree
const Visuals=preload("res://scripts/resource_visuals.gd")
const Fog=preload("res://scripts/remembered_material.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 for kind in ["stone","iron","berry"]:
  var holder=Node3D.new();root.add_child(holder);var visual=Visuals.build(holder,kind);var meshes=[];var heights=[];var counts=[]
  for level in 4:
   var record={"kind":kind,"category":"resource","hp":[100,75,50,25][level],"max_hp":100,"remembered":false}
   Visuals.present(holder,record);meshes.append(visual.mesh);heights.append(visual.mesh.get_aabb().size.y);counts.append(visual.mesh.surface_get_array_len(0))
   check(kind+" stage "+str(level)+" finite one surface",visual.mesh.get_surface_count()==1 and visual.mesh.get_aabb().is_finite() and counts[-1]<6000)
   check(kind+" footprint preserved "+str(level),visual.mesh.get_aabb().size.x<1.2 and visual.mesh.get_aabb().size.z<1.2)
   var arrays=visual.mesh.surface_get_arrays(0);var verts=arrays[Mesh.ARRAY_VERTEX];var clean=true
   for i in range(0,verts.size(),3):
    if (verts[i+1]-verts[i]).cross(verts[i+2]-verts[i]).length_squared()<=0.000000000001:clean=false
   check(kind+" stage geometry remains nondegenerate "+str(level),clean)
   var same=visual.mesh;Visuals.present(holder,record);check(kind+" repeated frame reuses mesh "+str(level),same==visual.mesh)
  check(kind+" four distinct stage meshes",meshes[0]!=meshes[1] and meshes[1]!=meshes[2] and meshes[2]!=meshes[3])
  check(kind+" visible depletion geometry",counts[3]<counts[0] if kind=="berry" else heights[3]<heights[0]*0.6)
  var source=meshes[0].surface_get_material(0);var original_color=source.albedo_color;var expected_color=Color.WHITE;Fog.apply(holder,true)
  Visuals.present(holder,{"kind":kind,"category":"resource","hp":50,"max_hp":100,"remembered":true})
  check(kind+" stage change keeps memory dimming",visual.get_surface_override_material(0)!=null and source.albedo_color==original_color and original_color==expected_color)
  Fog.apply(holder,false);check(kind+" visibility restores material",visual.get_surface_override_material(0)==null)
  var other=Node3D.new();root.add_child(other);var untouched=Visuals.build(other,kind)
  Visuals.present(holder,{"kind":kind,"category":"resource","hp":25,"max_hp":100,"remembered":true})
  check(kind+" separate proxy retains full shared mesh",untouched.mesh==meshes[0] and untouched.get_surface_override_material(0)==null)
  Visuals.present(holder,{"kind":kind,"category":"resource","hp":100,"max_hp":100,"remembered":false})
  check(kind+" full-stage restoration reuses original",visual.mesh==meshes[0] and visual.get_surface_override_material(0)==null)
  other.queue_free();holder.queue_free()
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false;await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false
 var worker=g._first(0,"villager");worker.pos=Vector3(-2,0,0);g._set_stance(worker,"STOP")
 var berry=g._spawn("berry",-1,Vector3(0,0,0));var depot=g._spawn("storehouse",0,Vector3(-5,0,0),true)
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0)
 var proxy=g.presentation_nodes[berry.id].body.get_node("ResourceVisual_berry");var full=proxy.mesh
 g._order(worker,"gather",berry.id)
 for i in 3500:
  g._tick(.05)
  if berry.hp<=150:break
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0)
 check("real harvesting changes observed berry appearance",berry.hp<=150 and proxy.mesh!=full and proxy.get_meta("depletion_stage",0)>=1)
 var old_hp=g.faction_views[0].get_record(berry.id).hp;var seen=proxy.mesh
 g._set_stance(worker,"STOP");worker.pos=Vector3(-25,0,24);depot.pos=Vector3(-25,0,24)
 var enemy=g._spawn("villager",1,Vector3(0,0,-1.2));g._update_vision(false);g._publish_faction_views();g._order(enemy,"gather",berry.id)
 for i in 100:g._tick(.05)
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0)
 var memory=g.faction_views[0].get_record(berry.id)
 check("actual hidden harvesting does not update remembered amount",berry.hp<old_hp and memory.remembered and memory.hp==old_hp)
 check("hidden change retains last seen mesh",proxy.mesh==seen)
 worker.pos=Vector3(-2,0,0);g._update_vision(false);g._publish_faction_views();g._update_visuals(0)
 check("reobserved resource reflects current amount",not g.faction_views[0].get_record(berry.id).remembered and g.faction_views[0].get_record(berry.id).hp==berry.hp and proxy.get_surface_override_material(0)==null)
 check("visual lifecycle does not change economy",g.economy.audit().ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"resource_lifecycle_contract","checks":checks,"failed":failed,"scope":"Four bounded shared visual stages plus real native berry harvesting; observation-only, no collision/economy/save changes; not rendered acceptance"}));g.queue_free();quit(1 if failed else 0)
