extends SceneTree
var outputs=[]
func _initialize():call_deferred("run")
func shot(name):
 await process_frame;await process_frame
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 outputs.append({"name":name,"error":root.get_texture().get_image().save_png("/tmp/capture/"+name+".png")})
func run():
 root.size=Vector2i(640,360);DirAccess.make_dir_recursive_absolute("/tmp/capture")
 var dir="/tmp/backup-capture-"+str(Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(dir)
 var shell=load("res://scripts/main_menu.gd").new();shell.checkpoint_path=dir+"/battle.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin";root.add_child(shell);await process_frame
 shell.selected_mode="expedition";shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 for i in 60:g._tick(.05)
 shell._open_menu();shell._save_checkpoint();var slot_bytes=FileAccess.get_file_as_bytes(shell.expedition_checkpoint_path)
 shell.backup_expedition=true;shell._keep_checkpoint_backup(true)
 await shot("expedition-backup-browser")
 var listing=shell.CheckpointBackups.list_slot(shell.expedition_checkpoint_path,g.Rules.BUILD_ID,true)
 if not listing.ok or listing.entries.is_empty():quit(1);return
 var name=listing.entries[0].name;shell._inspect_checkpoint_backup(true,name)
 await shot("expedition-backup-compatible")
 shell._restore_checkpoint(true,name);var h=shell.match_node;h.set_process(false);h.test_mode=true
 var restored=h!=g and h.paused and h.tick_count==60 and FileAccess.get_file_as_bytes(shell.expedition_checkpoint_path)==slot_bytes
 shell._resume_match();h.set_process(false);h.paused=true;h._update_hud();h._update_visuals(.016);h._refresh_fog()
 await shot("expedition-backup-restored-paused")
 print(JSON.stringify({"suite":"checkpoint_backups_capture","restored":restored,"canonical_unchanged":FileAccess.get_file_as_bytes(shell.expedition_checkpoint_path)==slot_bytes,"outputs":outputs,"scope":"Actual isolated native same-build backup creation and load, no pre-existing samples, no browser reload durability or migration"}))
 quit(0 if restored else 1)
