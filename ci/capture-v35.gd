extends SceneTree
const OUT="/tmp/capture/"
const Store=preload("res://scripts/checkpoint_store.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
func _initialize():call_deferred("run")
func shot(name):
 await process_frame
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(360,640)
 var shell=load("res://scripts/main_menu.gd").new();shell.checkpoint_path="user://native_capture_checkpoint.bin";root.add_child(shell);await process_frame
 shell.selected_mode="survival";shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 for i in 100:g._tick(.05)
 shell._open_menu();shell._show_page("checkpoint");shell._save_checkpoint()
 var disk=Store.read_slot(g.Rules.BUILD_ID,shell.checkpoint_path)
 var before=Codec.capture(g)
 var ok=await shot("native-local-checkpoint-written")
 shell._restore_checkpoint();var restored=shell.match_node;restored.set_process(false)
 var exact=Codec.capture(restored)==before
 var paused=restored.paused and restored.tick_count==100
 shell._show_page("checkpoint")
 ok=(await shot("native-local-checkpoint-restored-menu")) and ok
 shell.menu_layer.hide();restored.show();restored.ui.show();restored._skip_tutorial();restored._publish_faction_views();restored._update_vision();restored._update_visuals(0);restored._update_hud();restored._layout_ui();restored._camera_update()
 ok=(await shot("native-restored-battle-stays-paused")) and ok
 print(JSON.stringify({"build":restored.Rules.BUILD_ID,"scope":"Native isolated local file save and read through real menu callbacks; 100 ordinary starting ticks. Not browser reload persistence, phone or cloud sync acceptance","disk_ok":disk.ok,"exact_snapshot":exact,"restored_paused":paused,"tick":restored.tick_count,"status":shell.checkpoint_status}))
 ok=ok and disk.ok and exact and paused
 shell.queue_free();quit(0 if ok else 1)
