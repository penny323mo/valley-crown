extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(game,name):
 game._update_vision();game._update_visuals(0.0);game._update_hud();game._layout_ui();game._camera_update()
 await process_frame
 await RenderingServer.frame_post_draw
 var image=root.get_texture().get_image()
 var error=image.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",image.get_width(),"x",image.get_height()," ",error)
 return error==OK
func run():
 root.size=Vector2i(640,360)
 var game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game.ai_enabled=false
 game._test_reset();game.set_process(false);game._skip_tutorial();await process_frame
 var keep=game._first(0,"town_center");var pos=keep.pos+Vector3(4.5,0,0)
 var siege=game._spawn("siege",1,pos);var tower=game._spawn("tower",0,pos+Vector3(1.8,0,0));tower.built=true;tower.hp=1
 game._update_vision();game._select([tower.id]);game.camera_focus=(tower.pos+siege.pos)*0.5;game.camera_zoom=11
 var ok=await shot(game,"controlled-one-hp-tower-before-attack")
 game._ai_raid_order(game.faction_views[1].get_record(siege.id),game._ai_records(),game.faction_views[1].get_record(keep.id))
 var tower_order=game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==tower.id and siege.id in c.get("ids",[]))
 game._tick(game.Rules.TICK)
 ok=await shot(game,"controlled-tower-destroyed-after-normal-ai-order") and ok
 game._ai_raid_order(game.faction_views[1].get_record(siege.id),game._ai_records(),game.faction_views[1].get_record(keep.id))
 var keep_order=game.commands.any(func(c):return c.type=="order" and c.get("target",-1)==keep.id and siege.id in c.get("ids",[]))
 print(JSON.stringify({"build":game.Rules.BUILD_ID,"scope":"Controlled spawned enemy siege and one HP player tower; actual AI command settlement, not natural battle or victory","tower_order":tower_order,"tower_destroyed":not tower.alive,"keep_order":keep_order,"ledger":game.economy.audit().ok}))
 ok=ok and tower_order and not tower.alive and keep_order and game.economy.audit().ok
 game.queue_free();quit(0 if ok else 1)
