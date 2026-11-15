extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func raw_shot(name):
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func shot(g,name):
 g._publish_faction_views();g._update_vision();g._update_visuals(0.0);g._update_hud();g._layout_ui();g._camera_update()
 return await raw_shot(name)
func run():
 root.size=Vector2i(640,360)
 var menu=load("res://scripts/main_menu.gd").new();root.add_child(menu);await process_frame
 menu.selected_mode="survival";menu._show_page("setup")
 var ok=await raw_shot("native-three-wave-challenge-setup")
 menu.queue_free();await process_frame
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";root.add_child(g);g.set_process(false);g.test_mode=true;g._skip_tutorial();await process_frame
 g.tick_count=900;g._update_siege_challenge()
 var queued=g.commands.size()==1 and g.commands[0].type=="advance"
 while not g.commands.is_empty():g._execute(g.commands.pop_front())
 g.camera_focus=g._first(0,"town_center").pos;g.camera_zoom=24
 ok=(await shot(g,"native-first-wave-launched-player-base")) and ok
 var active=g.siege_challenge.active.size()
 var advancing=g.siege_challenge.active.all(func(id):return g._get_entity(id).mode=="ADVANCE")
 print(JSON.stringify({"build":g.Rules.BUILD_ID,"scope":"Actual survival scenario; clock advanced to first scheduled launch at tick 900 for illustration. No synthetic enemy deaths or victory. Not natural full-match balance or phone acceptance","wave":g.siege_challenge.wave,"active":active,"queued_advance":queued,"all_advancing":advancing}))
 ok=ok and active==6 and queued and advancing and g.siege_challenge.wave==1
 g.queue_free();quit(0 if ok else 1)
