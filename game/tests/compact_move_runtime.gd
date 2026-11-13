extends "res://tests/compact_click_contract.gd"
# Viewport click -> real simulation. Controlled desktop engine, not iPhone proof.
func run():
 root.size=Vector2i(390,844)
 game=load("res://main.tscn").instantiate(); root.add_child(game)
 game.set_process(false); game.test_mode=true; game._test_reset(); await settle()
 var worker=game._first(0,"villager")
 await tap(game.camera.unproject_position(worker.pos+Vector3(0,0.6,0)))
 var start=worker.pos
 var goal=Vector3.INF
 var screen=Vector2.ZERO
 for z in [-6,-4,0,4,6]:
  for x in [-6,-4,0,4,6]:
   if Vector2(x,z).length()<4 or Vector2(x,z).length()>7: continue
   var candidate=start+Vector3(x,0,z)
   var projected=game.camera.unproject_position(candidate)
   if game._box_point_in_world(projected) and game._pick(projected)<0:
    goal=candidate; screen=projected; break
  if goal.is_finite(): break
 check("visible empty destination",goal.is_finite() and game._box_point_in_world(screen) and game._pick(screen)<0)
 if not goal.is_finite(): quit(1); return
 await tap(screen)
 check("move queued with retained selection",game.commands.size()==1 and game.selected==[worker.id] and not game.touch_command)
 game._test_advance(3.0)
 check("simulation actually moves worker",worker.pos.distance_to(start)>1.0 and worker.pos.distance_to(goal)<start.distance_to(goal))
 check("no instruction mode required",not game.touch_command and game.selected==[worker.id])
 print("COMPACT_MOVE_RUNTIME "+JSON.stringify(checks))
 quit(0 if checks.size()==4 and checks.all(func(c): return c.passed) else 1)
