extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(name):
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var err=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",err)
 return err==OK
func scroll_to(control):
 var p=control.get_parent()
 while p!=null and not p is ScrollContainer:p=p.get_parent()
 if p is ScrollContainer:p.ensure_control_visible(control)
func run():
 root.size=Vector2i(640,360)
 var game=load("res://main.tscn").instantiate();game.skirmish_mode="fortress";root.add_child(game);game.set_process(false);game.ai_enabled=false
 await process_frame
 game.paused=false;game.application_focused=true;game.application_suspended=false
 var cavalry=game._first(0,"cavalry");cavalry.hp-=10
 game._update_vision();game._update_visuals(0.0);game._update_hud();game._layout_ui();game._camera_update()
 game.compact_menu.show();game._set_shortcut_category("army");game._refresh_army_roster()
 await process_frame
 scroll_to(game.army_roster_buttons.spearman.all)
 var ok=await shot("pinned-roster-native-top")
 scroll_to(game.army_roster_buttons.cavalry.wounded)
 ok=await shot("pinned-roster-native-cavalry-wounded") and ok
 scroll_to(game.army_roster_buttons.siege.all)
 ok=await shot("pinned-roster-native-siege") and ok
 var before=game.commands.duplicate(true);game._select_roster("cavalry",true)
 print(JSON.stringify({"build":game.Rules.BUILD_ID,"scope":"Native fortress fixture; one cavalry given 10 HP damage to demonstrate wounded selection, not natural combat or phone acceptance","wounded_selected":game.selected==[cavalry.id],"orders_unchanged":game.commands==before}))
 ok=ok and game.selected==[cavalry.id] and game.commands==before
 game.queue_free();quit(0 if ok else 1)
