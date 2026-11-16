extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func make_game(mode):
 var g=load("res://main.tscn").instantiate()
 g.skirmish_mode=mode
 g.history_path="/tmp/restore-feedback-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 return g
func run():
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size
  var g=make_game("expedition")
  await process_frame
  # Explicit boundary fixture, not a natural playthrough or player save.
  g.tick_count=100;g.game_time=5
  g._kill(g._get_entity(g.frontier_expedition.outpost_id))
  g.frontier_expedition.stage=3
  g.frontier_expedition.stage_ticks=[20,40,80]
  g.frontier_expedition.counter_due=680
  g.frontier_expedition.trained=2;g.frontier_expedition.supplied=100000
  var data=Codec.capture(g)
  var h=make_game("expedition")
  await process_frame
  var tag=str(size)
  check(tag+" candidate starts with opening guidance",h.toast_label.text.contains("選取村民"))
  check(tag+" restore succeeds",Restore.apply(h,data))
  await process_frame
  check(tag+" restored feedback replaces opening guidance",h.toast_label.text=="已讀取，暫停中 · 擊退反攻" and h.toast_time==3)
  check(tag+" presentation refresh preserves authority",Codec.capture(h)==data)
  check(tag+" remains paused and countdown unchanged",h.paused and h.frontier_expedition.counter_due==680)
  check(tag+" current objective immediately visible",h.objective_button.text.contains("擊退反攻") and h.objective_button.text.contains("29"))
  check(tag+" menu detail matches current stage",h.mission_label.text==h.frontier_expedition.caption(h.tick_count))
  check(tag+" feedback fits one line",h.toast_label.get_theme_font("font").get_string_size(h.toast_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,h.toast_label.get_theme_font_size("font_size")).x<=h.toast_label.size.x)
  h._toggle_pause()
  check(tag+" resume removes paused feedback",not h.paused and h.toast_label.text=="戰事繼續。")
  check(tag+" resume does not advance mission",h.frontier_expedition.stage==3 and h.tick_count==100)
  g.free();h.free()
 var g=make_game("standard");await process_frame
 var data=Codec.capture(g);var h=make_game("standard");await process_frame
 check("ordinary restore succeeds",Restore.apply(h,data))
 check("ordinary restore uses neutral paused feedback",h.toast_label.text=="已讀取，暫停中" and h.paused)
 check("ordinary restore retains exact authority",Codec.capture(h)==data)
 g.free();h.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_restore_feedback_contract","checks":checks,"failed":failed,"scope":"Dynamic native boundary states and presentation-only restore; not natural campaign, browser durability or cross-version migration"}))
 quit(0 if failed==0 else 1)
