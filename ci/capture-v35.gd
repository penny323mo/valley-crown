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
 var fighter=game._spawn("spearman",0,Vector3.ZERO)
 game._select([fighter.id]);game.camera_focus=fighter.pos;game.camera_zoom=15
 var ok=await shot(game,"controlled-fighter-before-earned-rank")
 var dead=0
 for i in 3:
  var target=game._spawn("spearman",1,Vector3(0.7,0,0));target.hp=1;fighter.cooldown_ticks=0
  game._update_vision();game._submit("order",{"ids":[fighter.id],"target":target.id,"position":target.pos},0);game._tick(game.Rules.TICK)
  if not target.alive:dead+=1
 game._select([fighter.id]);ok=await shot(game,"controlled-three-settled-kills-veteran") and ok
 var kills=game.combat_veterancy.count(fighter.id);var rank=game.combat_veterancy.rank(fighter.id)
 print(JSON.stringify({"build":game.Rules.BUILD_ID,"scope":"Controlled three 1HP enemy military targets; actual queued attacks and settled kill credits, no injected rank or free counter; not natural match or phone acceptance","targets_defeated":dead,"earned_kills":kills,"rank":rank,"hud":game.selection_detail.text,"ledger":game.economy.audit().ok}))
 ok=ok and dead==3 and kills==3 and rank==1 and game.selection_detail.text.contains("老兵") and game.economy.audit().ok
 game.queue_free();quit(0 if ok else 1)
