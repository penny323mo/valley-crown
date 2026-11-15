extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._publish_faction_views();g._update_vision();g._update_visuals(0.0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false);g._skip_tutorial();await process_frame
 var tower=g._spawn("tower",0,Vector3.ZERO,true)
 var near=g._spawn("spearman",1,Vector3(3,0,0),true)
 var ram=g._spawn("siege",1,Vector3(5,0,0),true)
 g._update_vision();g._publish_faction_views();g._select([tower.id]);g.camera_focus=Vector3(2.5,0,0);g.camera_zoom=15;g._camera_update();g._update_visuals(0);await process_frame
 g._tap(g.camera.unproject_position(ram.pos),true)
 var queued=g.commands.size()==1 and g.commands[0].type=="tower_focus" and g.commands[0].target==ram.id
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 g.test_mode=false;tower.cooldown_ticks=0;g._update_tower(tower);g._update_attack_effects(0.175,true)
 g._publish_faction_views();g._select([tower.id])
 var ok=await shot(g,"native-contextual-tower-focus-siege")
 var target=g.attack_ledger.event(1).target_id
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Controlled tower, nearer spearman and farther siege; actual contextual tap and queued command then normal tower shot. Not natural siege or physical phone acceptance","tap_queued":queued,"focus":tower.get("focus_target",-1)==ram.id,"shot_target":target==ram.id,"hud":g.selection_detail.text}))
 ok=ok and queued and target==ram.id and g.selection_detail.text.contains("集中射擊 攻城車")
 g.queue_free();quit(0 if ok else 1)
