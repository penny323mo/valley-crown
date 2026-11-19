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
 var prototype=load(out.get_base_dir()+"/resource_site_dressing.gd")
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
 g._submit("order",{"ids":[scout.id],"position":Vector3(-33.5,0,19.5)})
 for i in 340:g._tick(0.05)
 g._update_hud();g._update_visuals(.016);g._refresh_fog()
 await settle()
 check("exact stamped archived baseline",g._snapshot().build==expected)
 var obs=g.faction_views[0].records()
 var bank=g.economy.bank_milli(0).duplicate(true)
 var masks=[g.visible_cells[0].duplicate(),g.explored_cells[0].duplicate()]
 var nav=g.navigation.get_id_path(Vector2i(2,2),Vector2i(3,3))
 var pointer_probes=probes(g,obs)
 var proof_resources={}
 for r in pointer_probes:
  if r[1]!=r[3]:continue
  proof_resources[r[0]]=proof_resources.get(r[0],0)+1
 check("default camera tests all three real, visible resource pick categories",proof_resources.size()==3)
 await shot("home-before")
 var floor=prototype.new()
 g.add_child(floor)
 floor.reconcile(obs)
 await settle()
 check("only three batched resource surfaces",floor.get_child_count()==3 and floor.get_children().all(func(n):return n is MultiMeshInstance3D and n.multimesh.mesh.get_surface_count()==1))
 check("picking on game resources and surrounding probes unchanged",pointer_probes==probes(g,obs))
 check("observation bank and navigation unchanged",obs==g.faction_views[0].records() and g.economy.bank_milli(0)==bank and g.visible_cells[0]==masks[0] and g.explored_cells[0]==masks[1] and nav==g.navigation.get_id_path(Vector2i(2,2),Vector2i(3,3)))
 await shot("home-prototype")
 var counts={}
 for kind in floor.TYPES:counts[kind]=floor.layouts[kind].visible_instance_count
 check("sourced only locally observed sites",counts.values().all(func(n):return n>0))
 var report={"checks":checks,"images":images,"build":g._snapshot().build,"actual_scope":"Same exact rendered game state, one conditional presentation overlay from separate candidate script; not a released or complete candidate. No generated image or authority change.","camera":{"focus":form(g.camera_focus),"zoom":g.camera_zoom},"target_counts":proof_resources,"site_type_counts":counts}
 print(JSON.stringify(report))
 if not images.is_empty():
  var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report));f.close()
 var good=checks.all(func(q):return q.passed)
 g.queue_free();quit(0 if good else 1)
