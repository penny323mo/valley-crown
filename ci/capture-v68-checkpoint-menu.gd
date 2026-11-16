extends SceneTree
var outputs=[]
func _initialize():call_deferred("run")
func shot(name):
 await process_frame;await process_frame
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 var result=root.get_texture().get_image().save_png("/tmp/capture/"+name+".png")
 outputs.append({"name":name,"error":result})
func run():
 root.size=Vector2i(640,360);DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var shell=load("res://scripts/main_menu.gd").new()
 shell.checkpoint_path="user://capture_ordinary_protected.bin";shell.expedition_checkpoint_path="user://capture_expedition.bin"
 root.add_child(shell);await process_frame
 shell.selected_mode="expedition";shell._replace_match()
 var g=shell.match_node;g.set_process(false);g.test_mode=true
 for i in 60:g._tick(.05)
 shell._open_menu();shell._show_page("checkpoint");shell._save_checkpoint()
 await shot("expedition-separate-save-menu")
 var tick=g.tick_count;shell._restore_checkpoint(true)
 var h=shell.match_node;h.test_mode=true;h.set_process(false)
 var restored=h.paused and h.tick_count==tick and h.frontier_expedition.stage==0
 shell._resume_match();h.set_process(false);h.paused=true;h._update_hud();h._update_visuals(.016);h._refresh_fog()
 await shot("expedition-restored-paused")
 print(JSON.stringify({"suite":"expedition_checkpoint_capture","restored":restored,"tick":tick,"outputs":outputs,"scope":"Actual isolated native save and restore of fresh expedition, not browser reload, cross-version migration or natural campaign completion"}))
 quit(0 if restored else 1)
