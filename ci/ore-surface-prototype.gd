extends RefCounted
## Disposable feasibility study: preserve the licensed bedrock position and UV shape.
## A geological seam subdivides triangles along coherent inclined planes rather
## than adding nonphysical bright blocks above the surface.
const Data=preload("res://scripts/licensed_rock_data.gd")
const Atlas=preload("res://scripts/licensed_rock_visual.gd")
static var material:StandardMaterial3D
static var cache:Dictionary={}
const BED=Color(.21,.245,.27)
const CONTACT=Color(.37,.38,.38)
const VEIN=Color(.57,.46,.34)
const SILVER=Color(.78,.76,.68)
const ATLAS_CENTER=Vector2(1536,128)/2048.0
const INTERVALS=[[-100.0,-0.058,0],[-0.058,0.057,3],[0.057,100.0,0]]
static func _v(row:Array)->Vector3:return Vector3(row[0],row[1],row[2])
static func _sample(d:Dictionary,i:int,v:int)->Dictionary:
 var p:=_v(d.p[i]);var uv=Vector2(d.uv[i][0],d.uv[i][1])
 var tilt_x:float=[0.48,-0.43,0.28][v]
 var tilt_z:float=[-0.28,0.33,0.53][v]
 var level:float=[0.30,0.28,0.27][v]
 var seam=p.y+tilt_x*p.x+tilt_z*p.z-level
 return {"p":p,"n":_v(d.n[i]),"uv":uv,"seam":seam}
static func _clip(poly:Array,edge:float,keep_greater:bool)->Array:
 var out=[]
 if poly.is_empty():return out
 var previous=poly.back()
 var had=previous.seam>=edge if keep_greater else previous.seam<=edge
 for item in poly:
  var has=item.seam>=edge if keep_greater else item.seam<=edge
  if has!=had and absf(item.seam-previous.seam)>0.0000001:
   var f=(edge-previous.seam)/(item.seam-previous.seam)
   out.append({"p":previous.p.lerp(item.p,f),"n":previous.n.lerp(item.n,f).normalized(),"uv":previous.uv.lerp(item.uv,f),"seam":edge})
  if has:out.append(item)
  previous=item;had=has
 return out
static func _emit(st:SurfaceTool,vertex:Dictionary,poly_color:Color,stitch:int,scale_factor:float):
 var p:Vector3=vertex.p
 st.set_color(poly_color if stitch==0 else poly_color.lerp(VEIN,clampf(absf(vertex.seam)/.058,0.0,1.0)*.38))
 st.set_normal(vertex.n)
 st.set_uv(vertex.uv if stitch==0 else ATLAS_CENTER+Vector2(p.x,p.z)*0.016)
 st.add_vertex(p*scale_factor)
static func mesh(variant:int,depletion:int)->ArrayMesh:
 var v=posmod(variant,3);var stage=clampi(depletion,0,3)
 var key=4*v+stage
 if cache.has(key):return cache[key]
 var d:Dictionary=Data.MODELS[v]
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var factor:float=[1.0,0.83,0.66,0.46][stage]
 for i in range(0,d.i.size(),3):
  var full=[_sample(d,d.i[i],v),_sample(d,d.i[i+1],v),_sample(d,d.i[i+2],v)]
  var face_phase:float=0.84+0.15*absf(sin(i*0.193+v*.71))
  for band in INTERVALS:
   var patch=_clip(_clip(full,band[0],true),band[1],false)
   if patch.size()<3:continue
   var color:Color=[BED,CONTACT,VEIN,SILVER][band[2]]*face_phase
   color.a=1.0
   for q in range(1,patch.size()-1):
    var a:Vector3=patch[0].p
    var b:Vector3=patch[q].p
    var c:Vector3=patch[q+1].p
    if (b-a).cross(c-a).length_squared()<5e-13:continue
    for vertex in [patch[0],patch[q],patch[q+1]]:_emit(st,vertex,color,band[2],factor)
 if material==null:
  material=StandardMaterial3D.new()
  material.albedo_texture=Atlas.ROCK_TEXTURE
  material.vertex_color_use_as_albedo=true
  material.roughness=.88
  material.cull_mode=BaseMaterial3D.CULL_DISABLED
 st.set_material(material)
 var product=st.commit()
 cache[key]=product
 return product
