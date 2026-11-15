extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(game,name):
 game._publish_faction_views();game._update_vision();game._update_visuals(0.0);game._update_hud();game._layout_ui();game._camera_update()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image();var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(640,360)
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
 game._test_reset();game.set_process(false);game._skip_tutorial();await process_frame
 var keep=game._first(0,"town_center")
 var archer=game._spawn("archer",0,keep.pos+Vector3(4,0,0),true)
 var target=game._spawn("spearman",1,archer.pos+Vector3(3,0,0),true)
 game._update_vision();game.test_mode=false
 var hp=target.hp;var released=game._release_attack(archer,target)
 game._update_attack_effects(0.175,true)
 game.camera_focus=(archer.pos+target.pos)*0.5;game.camera_zoom=15
 var ok=await shot(game,"native-archer-midflight-player-zoom")
 game.camera_zoom=4
 ok=await shot(game,"native-archer-midflight-diagnostic-closeup") and ok
 var cues=game.attack_effects.size()
 print(JSON.stringify({"build":game.Rules.BUILD_ID,"scope":"Controlled visible archer release, cosmetic cue frozen at0.175seconds. Player zoom15 and explicitly diagnostic zoom4; not natural combat, phone acceptance or hit timing evidence","release_applied":released.applied,"arrows":cues,"target_hp_unchanged_without_settlement":target.hp==hp}))
 ok=ok and released.applied and cues==1 and target.hp==hp
 game.queue_free();quit(0 if ok else 1)
