extends SceneTree
const V=preload("res://scripts/resource_visuals.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func c(n,b):
 checks.append({"name":n,"passed":bool(b)})
 if not b:push_error(n)
func _initialize():call_deferred("run")
func run():
 for kind in ["stone","iron","berry"]:
  var full=[]
  for variant in 3:
   var holder=Node3D.new();var visual=V.build(holder,kind);var heights=[]
   for stage in 4:
    var record={"id":variant,"kind":kind,"category":"resource","hp":[100,75,50,25][stage],"max_hp":100,"remembered":false};var unchanged=record.duplicate(true)
    V.present(holder,record);var mesh=visual.mesh;var verts=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX];var normals=mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL];var box=mesh.get_aabb();heights.append(box.size.y)
    var clean=verts.size()==normals.size()
    for i in verts.size():clean=clean and verts[i].is_finite() and normals[i].is_finite()
    for i in range(0,verts.size(),3):clean=clean and (verts[i+1]-verts[i]).cross(verts[i+2]-verts[i]).length_squared()>1e-12
    var label=kind+" variant "+str(variant)+" stage "+str(stage)
    c(label+" finite nondegenerate opaque geometry",clean)
    c(label+" single surface bounded vertices footprint",mesh.get_surface_count()==1 and verts.size()<=4000 and box.size.x<1.2 and box.size.z<1.2 and box.size.y<1.0 and holder.get_child_count()==1)
    V.present(holder,record);c(label+" cached immutable observation",visual.mesh==mesh and record==unchanged and visual.material_override==null)
    if stage==0:full.append(verts.duplicate())
   c(kind+" variant "+str(variant)+" four coherent depletion heights",(kind=="berry" or (heights[0]>.3 and heights[0]>heights[1] and heights[1]>heights[2] and heights[2]>heights[3])))
   V.present(holder,{"id":variant,"kind":kind,"category":"resource","hp":50,"max_hp":100,"remembered":true})
   c(kind+" variant "+str(variant)+" memory dim applied per proxy",visual.get_surface_override_material(0)!=null)
   V.present(holder,{"id":variant,"kind":kind,"category":"resource","hp":100,"max_hp":100,"remembered":false})
   c(kind+" variant "+str(variant)+" visible stage restores shared material",visual.get_surface_override_material(0)==null)
   holder.free()
  c(kind+" variant rules",(full[0]==full[1] and full[1]==full[2]) if kind=="berry" else (full[0]!=full[1] and full[1]!=full[2] and full[0]!=full[2]))
 c("rock shared texture actual dimensions",preload("res://scripts/licensed_rock_visual.gd").ROCK_TEXTURE.get_size()==Vector2(2048,2048))
 print("TEXTURE_STORAGE_NOTE actual imported texture bytes must be read from renderer/import cache; image dimensions alone not GPU allocation.")
 for kind in ["stone","iron","berry"]:
  var a=Node3D.new();var b=Node3D.new();var va=V.build(a,kind);var vb=V.build(b,kind)
  var record={"id":0,"kind":kind,"category":"resource","hp":100,"max_hp":100,"remembered":false}
  V.present(a,record);V.present(b,record)
  var shared=va.mesh;var material=shared.surface_get_material(0)
  var memory=record.duplicate(true);memory.remembered=true
  V.present(a,memory);preload("res://scripts/remembered_material.gd").apply(a,true)
  c(kind+" same-stage memory does not mutate second proxy",va.mesh==vb.mesh and va.get_surface_override_material(0)!=null and vb.get_surface_override_material(0)==null and vb.mesh.surface_get_material(0)==material)
  V.present(a,record);preload("res://scripts/remembered_material.gd").apply(a,false)
  c(kind+" same-stage visibility restores original shared material",va.get_surface_override_material(0)==null and va.mesh.surface_get_material(0)==material)
  a.free();b.free()
 for variant in 3:
  var rock=preload("res://scripts/licensed_rock_visual.gd")
  var donor=rock.Data.MODELS[variant]
  var stone=rock.make_mesh("stone",0,variant);var iron=rock.make_mesh("iron",0,variant)
  var stone_v=stone.surface_get_arrays(0)[Mesh.ARRAY_VERTEX];var iron_v=iron.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
  c("iron exactly sixty-six solid chunk triangles "+str(variant),iron_v.size()==stone_v.size()+198)
  var exact=true
  for i in stone_v.size():exact=exact and stone_v[i]==iron_v[i]
  c("ore retains exact authored base vertices "+str(variant),exact)
  var enclosed=true;var embedded=true;var bounded=true;var solid=true
  for block in rock.Data.BLOCKS[variant]:
   var edges={}
   for face in block.f:
    for i in 3:
     var a=int(face.i[i]);var b=int(face.i[(i+1)%3]);var key=str(mini(a,b))+":"+str(maxi(a,b));edges[key]=edges.get(key,0)+1
    var a=_vector(block.p[face.i[0]]);var b=_vector(block.p[face.i[1]]);var d=_vector(block.p[face.i[2]])
    solid=solid and (b-a).cross(d-a).dot(_vector(face.n))<-.000001
   for count in edges.values():enclosed=enclosed and count==2
   for i in 6:
    var low=_vector(block.p[i]);var high=_vector(block.p[i+6]);var surface=_height(donor,low.x,low.z)
    embedded=embedded and is_finite(surface) and absf(low.y-(surface-block.nominal_height*.4))<.00001 and high.y>surface+.02
    solid=solid and high.y-low.y>.07
   for point in block.p:
    bounded=bounded and Vector2(point[0],point[2]).length()<=.56 and point[1]>=0 and point[1]<=.90
   var top0=_vector(block.p[6]);var top1=_vector(block.p[7]);var top2=_vector(block.p[8]);var plane=Plane(top0,top1,top2)
   for i in range(9,12):solid=solid and absf(plane.distance_to(_vector(block.p[i])))<.00001
  c("closed outward-wound thick flat-top blocks "+str(variant),enclosed and solid)
  c("all six bottom corners embedded in actual donor surface "+str(variant),embedded)
  c("chunk footprint and height bounded "+str(variant),bounded)
  c("stone and ore share original texture one surface "+str(variant),iron.get_surface_count()==1 and stone.surface_get_material(0).albedo_texture==iron.surface_get_material(0).albedo_texture)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var before=Codec.capture_result(g);var rng=g.rng.state;var records=g.faction_views[0].records();var unchanged=records.duplicate(true)
 for r in records.values():
  if r.get("kind","") not in ["stone","iron","berry"]:continue
  var h=Node3D.new();V.build(h,r.kind)
  for i in 8:V.present(h,r)
  h.free()
 var after=Codec.capture_result(g)
 c("normal game strict authority unchanged by mineral presentation",before.ok and after.ok and before.data==after.data)
 c("normal game RNG and observed records unchanged",rng==g.rng.state and records==unchanged)
 c("normal game economic ledger remains conserved",g.economy.audit().ok)
 g.free()
 var failed=checks.filter(func(x):return not x.passed).size()
 print(JSON.stringify({"suite":"licensed_resource_contract","checks":checks,"failed":failed,"scope":"Original cached mineral mesh variants across observed depletion stages; strict normal-game authority and RNG invariance. No visual quality or physical phone performance claim."}))
 quit(1 if failed else 0)

func _vector(a):return Vector3(a[0],a[1],a[2])
func _height(d,x,z):
 var highest=-INF
 for k in range(0,d.i.size(),3):
  var a=_vector(d.p[d.i[k]]);var b=_vector(d.p[d.i[k+1]]);var e=_vector(d.p[d.i[k+2]])
  var u=b-a;var v=e-a;var den=u.x*v.z-u.z*v.x
  if absf(den)<.0000000001:continue
  var qx=x-a.x;var qz=z-a.z;var t=(qx*v.z-qz*v.x)/den;var w=(u.x*qz-u.z*qx)/den
  if t>=-.000001 and w>=-.000001 and t+w<=1.000001:highest=maxf(highest,a.y+u.y*t+v.y*w)
 return highest
