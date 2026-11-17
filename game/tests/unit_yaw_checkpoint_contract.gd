extends SceneTree
# Controlled ordinary movement-phase loop, not natural match progress or physical-phone validation.
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await process_frame
 var u=g._spawn("villager",0,Vector3(0,0,25));g._update_vision(false)
 g._order_move(u,Vector3(-0.004815,0,25.09802))
 var center=Vector3(-1,0,25)
 var clear=true
 for i in 64:
  if not g._static_unit_step_is_free(u,center+Vector3(cos(i*TAU/64),0,sin(i*TAU/64))):clear=false
 check("controlled circular path is statically free",clear)
 var bank=g.economy.snapshot();var hp=u.hp;var commands=g.commands.duplicate(true)
 var first_failure=false
 var legacy=0.0;var max_legacy=0.0;var bounded=true;var orientation=true;var exact_moves=true
 for i in 4096:
  var next=center+Vector3(cos((i+1)*TAU/64),0,sin((i+1)*TAU/64))
  var step=next-u.pos
  legacy=Vector3(0,lerp_angle(legacy,atan2(step.x,step.z),0.35),0).y
  max_legacy=maxf(max_legacy,absf(legacy));u.dest=next
  g._apply_unit_step(u,next,g.Rules.TICK)
  if not first_failure and u.pos.distance_to(next)>=0.00001:
   print("STEP_DIAGNOSTIC "+str({"i":i,"actual":u.pos,"next":next,"step":step,"rotation":u.body.rotation,"legacy":legacy}));first_failure=true
  exact_moves=exact_moves and u.pos.distance_to(next)<0.00001
  bounded=bounded and u.body.rotation.is_finite() and absf(u.body.rotation.y)<=PI+0.000001
  orientation=orientation and absf(sin(u.body.rotation.y)-sin(legacy))<0.0002 and absf(cos(u.body.rotation.y)-cos(legacy))<0.0002
 check("ordinary movement phase completes all circular steps",exact_moves)
 print("LEGACY_MAX "+str(max_legacy))
 check("legacy unwrapped angle exceeds checkpoint limit",max_legacy>100)
 check("all new rotations remain finite canonical radians",bounded)
 check("every step preserves legacy facing direction",orientation)
 check("turning does not alter economy",g.economy.snapshot()==bank)
 check("turning does not alter health",u.hp==hp)
 check("turning does not emit commands",g.commands==commands)
 g._update_vision(false);g._update_hud()
 var c=Codec.capture_result(g)
 check("long-turn state passes unchanged strict checkpoint validation",c.ok)
 if not c.ok:g.free();finish();return
 var e=Codec.encode(c.data,g.Rules.BUILD_ID);var d=Codec.decode(e.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
 check("long-turn checkpoint exact transport roundtrip",e.ok and d.ok and d.data==c.data)
 var bad=c.data.duplicate(true);bad.entities[-1].checkpoint_body_rotation=Vector3(0,NAN,0)
 check("NaN rotation remains rejected",not Codec.validate(bad))
 bad=c.data.duplicate(true);bad.entities[-1].checkpoint_body_rotation=Vector3(0,INF,0)
 check("infinite rotation remains rejected",not Codec.validate(bad))
 bad=c.data.duplicate(true);bad.entities[-1].pos=Vector3(1000,0,0)
 check("out-of-world position remains rejected",not Codec.validate(bad))
 for i in 100:g._tick(g.Rules.TICK)
 g._update_hud();var expected=Codec.capture_result(g)
 g.free();g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;await process_frame
 check("strict long-turn checkpoint restores",Restore.apply(g,d.data))
 check("immediate restored full capture is exact",Codec.capture_result(g).data==c.data)
 g._toggle_pause()
 for i in 100:g._tick(g.Rules.TICK)
 g._update_hud();var actual=Codec.capture_result(g)
 check("full 100-tick continuation is exact after restore",expected.ok and actual.ok and expected.data==actual.data)
 check("restored economy audit passes",g.economy.audit().ok)
 g.free();finish()
func finish():
 var failed=checks.filter(func(c):return not c.passed)
 print(JSON.stringify({"suite":"unit_yaw_checkpoint_contract","checks":checks,"failed":failed.size(),"scope":"controlled movement-phase long-turn orientation and strict checkpoint continuation; not natural full-match or physical-phone acceptance"}))
 quit(0 if failed.is_empty() else 1)
