extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="survival";root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 var launched=[]
 var clear_tick=-1
 for i in 3000:
  g._tick(.05)
  if launched.is_empty() and g.siege_challenge.wave==1:launched=g.siege_challenge.active.duplicate()
  if not launched.is_empty() and clear_tick<0 and g.siege_challenge.active.is_empty():clear_tick=g.tick_count
  if g.game_over or g.paused:break
 check("unchanged scenario completes three thousand ordinary ticks",g.tick_count==3000 and not g.paused and not g.game_over)
 check("first scheduled wave launches all six units naturally",launched.size()==6)
 check("ordinary attack ledger records actual engagement",g.attack_ledger.next_attack_id()>1)
 check("first wave dies through ordinary simulation without fixture kills",clear_tick>900 and launched.all(func(id):return not g._get_entity(id).alive))
 check("natural clear grants exactly forty five seconds preparation",g.siege_challenge.wave==1 and g.siege_challenge.next_tick==clear_tick+900)
 check("player keep survives opening engagement",g._first(0,"town_center").alive)
 print(JSON.stringify({"suite":"siege_challenge_engagement_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Uninterrupted normal opening simulation, no player orders or artificial kills; not full-match balance acceptance","ticks":g.tick_count,"clear_tick":clear_tick}))
 g.free();quit(0 if checks.all(func(c):return c.passed) else 1)
