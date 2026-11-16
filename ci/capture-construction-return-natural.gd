extends SceneTree
var g
var checks=[]
var outputs=[]
func _initialize():
 root.size=Vector2i(640,360)
 call_deferred("run")
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func shot(name,worker):
 g._select([worker.id]);g.camera_focus=worker.pos;g._camera_update();g._process(0);g._update_hud();g._layout_ui()
 for i in 4:await process_frame
 if DisplayServer.get_name()=="headless":return
 var dir="/tmp/capture"
 DirAccess.make_dir_recursive_absolute(dir)
 await RenderingServer.frame_post_draw
 outputs.append({"path":dir+"/"+name+".png","error":root.get_texture().get_image().save_png(dir+"/"+name+".png")})
func run():
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.test_mode=true;g.history_path="/tmp/construction-return-history-%d.json" % Time.get_ticks_usec();root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 check("isolated history starts absent",not FileAccess.file_exists(g.history_path))
 var w=g._first(0,"villager");var tree={}
 var known=g._gather_records(0)
 for r in known.values():
  if r.alive and r.kind in ["pine","oak"]:
   if tree.is_empty() or w.pos.distance_squared_to(r.pos)<w.pos.distance_squared_to(tree.pos):tree=r
 check("natural initial visible wood exists",not tree.is_empty())
 if tree.is_empty():g.free();quit(1);return
 g._order(w,"gather",tree.id)
 for i in 800:g._tick(.05)
 check("ordinary gathering establishes earned cargo or wood",g.economy.stats_view(0).extracted.wood>0)
 var point=Vector3.INF
 for z in range(-5,6):
  for x in range(-5,6):
   var p=g._snap_build_position("house",w.pos+Vector3(x,0,z))
   if g._placement_reason("house",p,0,w.id).is_empty():point=p;break
  if point!=Vector3.INF:break
 check("natural legal site found",point!=Vector3.INF)
 if point==Vector3.INF:g.free();quit(1);return
 var bank=g.economy.bank_milli(0).wood
 var site=g._place_building("house",point,w.id,0)
 check("house paid once and prior work retained",not site.is_empty() and g.economy.bank_milli(0).wood==bank-g.Rules.COSTS.house.wood*1000 and w.has("construction_return"))
 if site.is_empty():g.free();quit(1);return
 await shot("paid-house-under-construction",w)
 var count=0
 while not site.built and count<3000:g._tick(.05);count+=1
 check("ordinary travel and paid building completes",site.built)
 check("finisher automatically resumes work or deposit",w.state in ["gather","deliver"] and not w.has("construction_return"))
 await shot("house-finished-returning-to-work",w)
 var extracted=g.economy.stats_view(0).extracted.wood
 var bank_after_build=g.economy.bank_milli(0).wood
 for i in 800:g._tick(.05)
 check("bank increases after ordinary postbuild deliveries",g.economy.bank_milli(0).wood>bank_after_build)
 check("wood extraction continues without player order",g.economy.stats_view(0).extracted.wood>extracted)
 check("economy ledger conserves",g.economy.audit().ok)
 await shot("wood-delivered-after-construction",w)
 print("NATURAL_RETURN ",JSON.stringify({"ticks":g.tick_count,"build_ticks_elapsed":count,"built":site.built,"state":w.state,"extracted_wood_milli":g.economy.stats_view(0).extracted.wood,"receipt":g.economy.receipt_view(site.cost_receipt_id).state}))
 check("journey writes no match history",not FileAccess.file_exists(g.history_path))
 var proof={"suite":"construction_return_journey","checks":checks,"outputs":outputs,"failed":checks.filter(func(c):return not c.passed).size(),"ticks":g.tick_count,"bank_wood_after_build":bank_after_build,"bank_wood_final":g.economy.bank_milli(0).wood,"scope":"Practice match ordinary automated gather and paid construction, no gifts or relocation; not manual phone proof"}
 print(JSON.stringify(proof));g.free();quit(1 if checks.any(func(c):return not c.passed) else 0)

