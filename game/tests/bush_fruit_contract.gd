extends SceneTree
const V=preload('res://scripts/resource_visuals.gd')
const F=preload('res://scripts/remembered_material.gd')
var checks=[]
func check(n,v):checks.append({'name':n,'passed':bool(v)})
func _initialize():
 var counts=[]
 for stage in 4:
  var m=V._make_mesh('berry',stage)
  check('explicit surface count '+str(stage),m.get_surface_count()==2)
  var triangles=0;var valid=true
  for s in m.get_surface_count():
   var a=m.surface_get_arrays(s);var verts=a[Mesh.ARRAY_VERTEX];var indices=a[Mesh.ARRAY_INDEX]
   var n=indices.size() if indices!=null and indices.size()>0 else verts.size()
   triangles+=n/3
   for i in range(0,n,3):
    var x=verts[indices[i] if indices!=null and indices.size()>0 else i];var y=verts[indices[i+1] if indices!=null and indices.size()>0 else i+1];var z=verts[indices[i+2] if indices!=null and indices.size()>0 else i+2]
    valid=valid and x.is_finite() and y.is_finite() and z.is_finite() and (y-x).cross(z-x).length_squared()>1e-14
  counts.append(triangles)
  check('finite nondegenerate '+str(stage),valid)
  check('exact triangle budget '+str(stage),triangles==[1452,1268,1084,1026][stage])
  check('bounds footprint '+str(stage),m.get_aabb().size.x<1.2 and m.get_aabb().size.z<1.2 and absf(m.get_aabb().size.y-.76)<.00001)
  check('leaf cutout retained '+str(stage),m.surface_get_material(0).transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
  check('only fruit opaque '+str(stage),m.surface_get_material(1).transparency==BaseMaterial3D.TRANSPARENCY_DISABLED)
  check('stage cached '+str(stage),m==V._make_mesh('berry',stage))
 check('strict depletion counts',counts[0]>counts[1] and counts[1]>counts[2] and counts[2]>counts[3])
 var a=Node3D.new();var b=Node3D.new();var x=V.build(a,'berry');var y=V.build(b,'berry')
 var rec={'kind':'berry','category':'resource','id':21,'hp':100,'max_hp':100,'remembered':false};V.present(a,rec);V.present(b,rec)
 var source=x.mesh;var color=source.surface_get_material(0).albedo_color;var texture=source.surface_get_material(0).albedo_texture
 F.apply(a,true)
 check('both surfaces remembered',x.get_surface_override_material(0)!=null and x.get_surface_override_material(1)!=null)
 check('separate proxy unaffected',y.mesh==source and y.get_surface_override_material(0)==null and y.get_surface_override_material(1)==null)
 for hp in [50,25,100]:
  rec.hp=hp;rec.remembered=true;var old=rec.duplicate(true);V.present(a,rec)
  check('input unchanged '+str(hp),rec==old)
  var dim=true
  for s in x.mesh.get_surface_count():dim=dim and x.get_surface_override_material(s)!=null
  check('all current surfaces dim '+str(hp),dim)
 F.apply(a,false)
 check('all full surfaces restore',x.get_surface_override_material(0)==null and x.get_surface_override_material(1)==null)
 check('shared material immutable',source.surface_get_material(0).albedo_color==color and source.surface_get_material(0).albedo_texture==texture)
 check('no physics additions',a.get_child_count()==1 and x.get_child_count()==0)
 a.free();b.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({'suite':'bush_fruit_contract','checks':checks,'failed':failed}));quit(1 if failed else 0)
