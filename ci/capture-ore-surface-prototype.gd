extends SceneTree
# Feasibility input only. Compares an exact native released world against the
# same world with the local candidate sourced from one separately bound script.
var out=""
var images={}
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func _initialize():
 call_deferred("run")
func settle():
 for i in 4:await process_frame
func form(x):
 return [x.x,x.y,x.z]
func shot(label:String):
 if DisplayServer.get_name()=="headless":return
 RenderingServer.render_loop_enabled=true
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 RenderingServer.render_loop_enabled=false
 DirAccess.make_dir_recursive_absolute(out)
 var f=out+"/"+label+".png"
 var e=image.save_png(f)
 check("original engine PNG "+label,e==OK and image.get_width()==390 and image.get_height()==844)
 images[label]={"width":image.get_width(),"height":image.get_height(),"sha256":FileAccess.get_sha256(f)}
func probes(g,records):
 var points=[]
 for rec in records.values():
  if rec.get("kind","") not in ["stone","iron","berry"] or rec.get("remembered",false):continue
  var p=g.camera.unproject_position(rec.pos+Vector3(0,0.25,0))
  if not g._box_point_in_world(p):continue
  for a in [Vector2.ZERO,Vector2(-8,0),Vector2(8,0),Vector2(0,8),Vector2(0,-8),Vector2(16,0),Vector2(-16,0)]:
   if g._box_point_in_world(p+a):points.append([rec.kind,rec.id,p+a,g._pick(p+a)])
 return points
func run():
 var args=OS.get_cmdline_user_args()
 out=args[0]
 var expected=args[3]
 var prototype=load(out.get_base_dir()+"/ore-surface.gd")
 check("test-only prototype source is loadable",prototype!=null)
 if prototype==null:quit(1);return
 if DisplayServer.get_name()!="headless":RenderingServer.render_loop_enabled=false
 root.size=Vector2i(390,844)
 var g=load("res://main.tscn").instantiate()
 g.skirmish_mode="standard";g.victory_mode="conquest";g.layout_id="valley"
 g.test_mode=true;g.history_path=out.get_base_dir()+"/no-resource-study-saves.json"
 root.add_child(g);g.set_process(false)
 await settle()
 var scout=g._first(0,"scout")
 var worker=g._first(0,"villager")
 g._submit("order",{"ids":[scout.id],"position":Vector3(-33.5,0,19.5)})
 g._submit("order",{"ids":[worker.id],"position":Vector3(-21.5,0,17.5)})
 for i in 340:g._tick(0.05)
 g._update_hud();g._update_visuals(.016);g._refresh_fog()
 await settle()
 check("exact stamped archived baseline",g._snapshot().build==expected)
 var obs=g.faction_views[0].records()
 var bank=g.economy.bank_milli(0).duplicate(true)
 var masks=[g.visible_cells[0].duplicate(),g.explored_cells[0].duplicate()]
 var nav=g.navigation.get_id_path(Vector2i(2,2),Vector2i(3,3))
 var pointer_probes=probes(g,obs)
 var center_targets=[]
 for rec in obs.values():
  if rec.get("kind","") not in ["iron","stone"] or rec.get("remembered",false):continue
  var here=g.camera.unproject_position(rec.pos+Vector3(0,0.25,0))
  if g._box_point_in_world(here) and g._pick(here)==rec.id:center_targets.append([rec.id,here,rec.kind])
 var proof_resources={}
 for r in pointer_probes:
  if r[1]!=r[3]:continue
  proof_resources[r[0]]=proof_resources.get(r[0],0)+1
 check("default camera tests all three real, visible resource pick categories",proof_resources.size()==3)
 await shot("home-before")
 var size_by_ore={}
 var before_ore_variants={}
 for rec in obs.values():
  if rec.get("kind","")!="iron" or rec.get("remembered",false):continue
  var proxy=g.presentation_nodes.get(rec.id,{})
  if proxy.is_empty():continue
  var visual=proxy.body.get_node_or_null("ResourceVisual_iron")
  if not is_instance_valid(visual):continue
  var prior=visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()/3
  var stage=visual.get_meta("depletion_stage",0)
  visual.mesh=prototype.mesh(posmod(rec.id,3),stage)
  before_ore_variants[posmod(rec.id,3)]=true
  size_by_ore[str(rec.id)]={"old_triangles":prior,"pilot_triangles":visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()/3,"stage":stage}
 check("actual visible ore bodies have one changed mesh and no extra nodes",size_by_ore.size()>=4 and before_ore_variants.size()==3)
 await settle()
 var after=probes(g,obs)
 var lost=[]
 var gained=[]
 for i in pointer_probes.size():
  var b=pointer_probes[i];var a=after[i]
  if b[3]==b[1] and a[3]!=a[1]:lost.append([b[0],b[1],b[2].x,b[2].y])
  if b[3]!=b[1] and a[3]==a[1]:gained.append([a[0],a[1],a[2].x,a[2].y])
 check("ore and stone center tap authority stays identical",center_targets.filter(func(q):return q[2]=="iron").size()>=3 and center_targets.any(func(q):return q[2]=="stone") and center_targets.all(func(q):return g._pick(q[1])==q[0]))
 check("observation bank and navigation unchanged",obs==g.faction_views[0].records() and g.economy.bank_milli(0)==bank and g.visible_cells[0]==masks[0] and g.explored_cells[0]==masks[1] and nav==g.navigation.get_id_path(Vector2i(2,2),Vector2i(3,3)))
 await shot("home-prototype")
 var report={"checks":checks,"images":images,"build":g._snapshot().build,"actual_scope":"Same live simulated game state, replaced observed ore mesh only for a visual artifact prototype; not released.","camera":{"focus":form(g.camera_focus),"zoom":g.camera_zoom},"target_counts":proof_resources,"ore":size_by_ore,"center_probe_counts":{"iron":center_targets.filter(func(q):return q[2]=="iron").size(),"stone":center_targets.filter(func(q):return q[2]=="stone").size()},"lost_edge_hits":lost,"gained_edge_hits":gained}
 print(JSON.stringify(report))
 if not images.is_empty():
  var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report));f.close()
 var good=checks.all(func(q):return q.passed)
 g.queue_free();quit(0 if good else 1)
