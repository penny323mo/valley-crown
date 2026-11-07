extends SceneTree
# External native lifecycle contract; not GUI/physical-phone acceptance.
var g
var checks=[]
func _initialize(): call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"pass":bool(ok)})
func start():
 g._cancel_mode(); g.paused=false; g.short_ui=false
 g._select([g._first(0,"villager").id]); g._start_build("house")
func retired():
 return not g.toast_build_guidance and g.toast_time==0 and g.toast_label.text.is_empty() and not g.toast_label.visible
func run():
 g=load("res://main.tscn").instantiate(); root.add_child(g); g.test_mode=true; g.set_process(false)
 var bank=g.economy.bank_milli(0).duplicate(true)
 var tick=g.tick_count
 start(); check("start owns guidance",g.toast_build_guidance and g.toast_time==6)
 g.toast_label.visible=true; g._cancel_mode(); check("cancel retires immediately",retired())
 g._cancel_mode(); check("repeat cancel stays retired",retired())
 start(); g._select_group("army"); check("army selection retires",retired() and g.build_mode.is_empty())
 start(); g._home(); check("home selection retires",retired() and g.build_mode.is_empty())
 start(); g.short_ui=true; g._update_ghost(); check("valid preview owns guidance",g.placement_ok and g.toast_build_guidance and g.toast_time==1)
 g._cancel_mode(); check("valid preview retires",retired())
 start(); g.short_ui=true; g.pointer_world=Vector3(-999,0,-999); g._update_ghost()
 check("invalid preview owns guidance",not g.placement_ok and g.toast_build_guidance and g.toast_time==1)
 g._cancel_mode(); check("invalid preview retires",retired())
 for feedback in ["建造完成。","資源不足，未有扣款。","已取消指令。"]:
  start(); g._message(feedback,7); g.toast_label.visible=true; g._cancel_mode()
  check("ordinary feedback preserved "+feedback,g.toast_label.text==feedback and g.toast_time==7 and g.toast_label.visible and not g.toast_build_guidance)
 start(); g.pointer_world=Vector3(-999,0,-999); g.build_preview_held=true; g._confirm_build()
 var failure=g.toast_label.text
 check("confirm rejection ordinary",not g.toast_build_guidance and not failure.is_empty() and g.toast_time==4)
 g._cancel_mode(); check("confirm rejection preserved",g.toast_label.text==failure and g.toast_time==4)
 start(); g.build_preview_held=true; g.game_over=true; g._confirm_build()
 check("submit authority rejection preserved",g.toast_label.text=="戰役已結束。" and g.toast_time==3 and not g.toast_build_guidance)
 check("rejected confirm still retires mode",g.build_mode.is_empty() and not g.build_preview_held and not is_instance_valid(g.ghost))
 g.game_over=false
 g._message("normal expiry",0.05); g._process(0.1); g._process(0.1)
 check("ordinary expiry unchanged",not g.toast_label.visible and g.toast_time<=0)
 start(); g.toast_time=0; g._process(0); check("guidance expiry hides",not g.toast_label.visible)
 g._cancel_mode(); start(); check("reentry owns fresh guidance",g.toast_build_guidance and g.toast_time==6)
 g._cancel_mode(); check("economy and tick unchanged",g.economy.bank_milli(0)==bank and g.tick_count==tick)
 var args=OS.get_cmdline_user_args()
 var failed_count=0
 for c in checks: if not c.pass: failed_count+=1
 var fixture_path=get_script().resource_path
 var report={"completed":true,"failed":failed_count,"contract_sha256":FileAccess.get_sha256(fixture_path),"source_lock_sha256":FileAccess.get_sha256(fixture_path.get_base_dir()+"/source_lock.json"),"manifest_sha256":FileAccess.get_sha256("res://reports/build-manifest.json"),"build":g.Rules.BUILD_ID,"game_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"checks":checks,"scope":"native lifecycle, not GUI or phone"}
 var f=FileAccess.open(args[0],FileAccess.WRITE); f.store_string(JSON.stringify(report,"  ")); f.close()
 var failed=false
 for c in checks: if not c.pass: failed=true
 quit(1 if failed else 0)
