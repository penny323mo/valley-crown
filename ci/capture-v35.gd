extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._publish_faction_views();g._update_vision();g._update_visuals(0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(360,640)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;g._test_reset();g.set_process(false)
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial()
 var guard=g._first(0,"scout");var ally=g._first(0,"villager")
 guard.pos=Vector3(-4.5,0,4.5);ally.pos=Vector3(3.5,0,4.5);g._set_stance(guard,"STOP");g._set_stance(ally,"STOP")
 g.camera_focus=Vector3(0,0,4.5);g._update_vision(false);g._publish_faction_views();g._select([guard.id]);g._start_escort_command()
 var ok=await shot(g,"native-escort-select-protectee")
 var accepted=g._submit_escort_target(ally.id);g._tick(.05)
 var start=guard.pos
 for i in 200:g._tick(.05)
 var followed=guard.mode=="ESCORT" and guard.pos.distance_to(start)>1.0
 var enemy=g._spawn("spearman",1,guard.pos+Vector3(0.8,0,0));g._set_stance(enemy,"STOP")
 ally.pos=guard.pos+Vector3(0,0,1);guard.escort_next_tick=g.tick_count;guard.cooldown_ticks=0
 g._update_vision(false);g._publish_faction_views();var hp=enemy.hp
 for i in 10:g._tick(.05)
 var attacked=enemy.hp<hp and guard.mode=="ESCORT" and guard.get("escort_target",-1)==ally.id
 g.camera_focus=guard.pos;g._select([guard.id]);ok=(await shot(g,"native-escort-intercepts-visible-attacker")) and ok
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Controlled unit positions and spawned enemy, ordinary escort command, 200 actual movement ticks and real combat damage; no save files, natural-match or phone acceptance","accepted":accepted,"followed":followed,"intercept_damage":attacked,"enemy_hp_before":hp,"enemy_hp_after":enemy.hp}))
 g.queue_free();quit(0 if ok and accepted and followed and attacked else 1)
