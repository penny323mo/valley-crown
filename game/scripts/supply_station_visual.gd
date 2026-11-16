extends RefCounted
# Presentation only. Uses the current faction record, including frozen fog memory.
static func apply(body:Node3D,record:Dictionary):
 var banner=body.get_node_or_null("SupplyBanner")
 if not record.get("built",false) or record.get("kind","")!="storehouse" or not record.get("supply_station",false):
  if is_instance_valid(banner):banner.visible=false
  return
 if not is_instance_valid(banner):
  banner=Node3D.new();banner.name="SupplyBanner";body.add_child(banner)
  var pole=MeshInstance3D.new();var cylinder=CylinderMesh.new();cylinder.top_radius=.035;cylinder.bottom_radius=.035;cylinder.height=3.0;pole.mesh=cylinder;pole.position=Vector3(.9,1.5,-.5);banner.add_child(pole)
  var wood=StandardMaterial3D.new();wood.albedo_color=Color("72583d");pole.material_override=wood
  var flag=MeshInstance3D.new();var cloth=BoxMesh.new();cloth.size=Vector3(.9,.65,.055);flag.mesh=cloth;flag.position=Vector3(1.35,2.7,-.5);banner.add_child(flag)
  var material=StandardMaterial3D.new();material.albedo_color=Color("e3c36b");material.roughness=1;flag.material_override=material
  for spec in [Vector3(.48,.12,.075),Vector3(.12,.45,.075)]:
   var mark=MeshInstance3D.new();var cross=BoxMesh.new();cross.size=spec;mark.mesh=cross;mark.position=flag.position;mark.position.z-=.05;banner.add_child(mark)
   var ink=StandardMaterial3D.new();ink.albedo_color=Color("214c45");mark.material_override=ink
 banner.visible=true
