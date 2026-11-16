extends "res://tests/contextual_touch_phone.gd"
# Actual viewport routing for mouse-shaped mobile input. Not physical iPhone proof.
func click(point,pressed):
 var event=InputEventMouseButton.new(); event.position=point; event.global_position=point
 event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed
 root.push_input(event,false)
func tap(point):
 click(point,true); await process_frame; click(point,false); await settle()
func run():
 root.size=Vector2i(390,844)
 game=load("res://main.tscn").instantiate(); root.add_child(game)
 game.set_process(false); game.test_mode=true; game._test_reset(); await settle()
 var worker=game._first(0,"villager")
 var worker_point=game.camera.unproject_position(worker.pos+Vector3(0,0.6,0))
 await tap(worker_point)
 check("primary click selects worker",game.selected==[worker.id])
 check("worker building actions immediately visible",game.actions.get_children().any(func(b): return b is Button and b.text.begins_with("民居\n")))
 var point=Vector2.ZERO
 for y in range(180,460,25):
  for x in range(45,345,25):
   var candidate=Vector2(x,y)
   if game._pick(candidate)<0: point=candidate; break
  if point!=Vector2.ZERO: break
 check("empty ground fixture",point!=Vector2.ZERO)
 await tap(point)
 check("primary click queues move without command button",game.commands.size()==1 and game.commands[0].type=="order" and game.commands[0].target==-1 and game.commands[0].ids==[worker.id] and game.selected==[worker.id] and not game.touch_command)
 game.commands.clear()
 await tap(point)
 check("repeat primary click issues exactly one new order",game.commands.size()==1 and game.selected==[worker.id])
 game.commands.clear(); game.paused=true
 await tap(point)
 check("paused primary click cannot order",game.commands.is_empty())
 game.paused=false
 click(point,true); game._select([worker.id]); click(point,false); await settle()
 check("selection change cancels held mouse press",game.commands.is_empty())
 # Mouse drag still box-selects and must not leak a move on release.
 click(point,true)
 var motion=InputEventMouseMotion.new(); motion.position=point+Vector2(40,0); motion.relative=Vector2(40,0); motion.button_mask=MOUSE_BUTTON_MASK_LEFT
 root.push_input(motion,false); click(point+Vector2(40,0),false); await settle()
 check("mouse drag cannot leak contextual order",game.commands.is_empty())
 # Exercise actual pick/projection and viewport routing for each context.
 for kind in ["spearman","berry","farm"]:
  game._select([worker.id]); game.commands.clear(); await settle()
  var position=worker.pos+Vector3(3,0,2)
  var target=game._spawn(kind,1 if kind=="spearman" else (0 if kind=="farm" else -1),position)
  game._update_vision(); await settle()
  var screen=game.camera.unproject_position(target.pos+Vector3(0,0.6 if kind=="spearman" else 1.0,0))
  check("visible contextual fixture "+kind,game._box_point_in_world(screen) and game._pick(screen)==target.id)
  await tap(screen)
  check("primary click contextual order "+kind,game.commands.size()==1 and game.commands[0].target==target.id and game.commands[0].ids==[worker.id] and game.selected==[worker.id] and not game.touch_command)
  check("primary click correct capability "+kind,game._target_order_intent(game.faction_views[0].get_record(worker.id),game.faction_views[0].get_record(target.id),0)==("attack" if kind=="spearman" else "gather"))
  if kind=="farm": check("farm click carries gather intent",game.commands.size()==1 and game.commands[0].get("farm_gather",false))
  target.alive=false; game._update_vision(); game.commands.clear(); await settle()
 game.game_over=true; await tap(point)
 check("ended match cannot order",game.commands.is_empty())
 print("COMPACT_CLICK_CONTRACT "+JSON.stringify(checks))
 quit(0 if checks.size()==19 and checks.all(func(c): return c.passed) else 1)
