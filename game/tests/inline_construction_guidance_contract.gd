extends SceneTree
## Ordinary simulation and actual native touchscreen routing; renderer/phone acceptance separate.
const Mission=preload("res://scripts/frontier_escort.gd")
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func _initialize():call_deferred("run")
func ck(n,ok):
 checks.append({"name":n,"passed":bool(ok)})
 if not ok:push_error(n)
 return bool(ok)
func sync():
 game._camera_update();game._update_hud();game._layout_ui();game._update_ghost()
 for i in 5:await process_frame
func tap_point(p):
 for down in [true,false]:
  var e=InputEventScreenTouch.new()
  e.index=41;e.position=p;e.pressed=down;root.push_input(e)
  await process_frame
 await sync()
func tap_control(b):
 if not is_instance_valid(b) or not b.is_visible_in_tree() or b.size.x<44 or b.size.y<44 or not root.get_visible_rect().encloses(b.get_global_rect()):return false
 await tap_point(b.get_global_rect().get_center())
 return true
func cancel_button():
 for b in game.actions.get_children():
  if b is Button and b.text=="取消建造":return b
 return null
func build(kind):
 for b in game.actions.get_children():
  if b is Button and b.get_meta("command_icon_kind","")==kind:
   game.action_scroll.ensure_control_visible(b)
   for i in 5:await process_frame
   return await tap_control(b)
 return false
func setup(size:Vector2i,mode="standard"):
 root.size=size;await process_frame
 game=load("res://main.tscn").instantiate()
 game.skirmish_mode=mode;root.add_child(game);game.set_process(false)
 await sync()
func advance(limit,predicate):
 for i in limit:
  if predicate.call():return true
  game._tick(Rules.TICK)
 return predicate.call()
func sample(size,warehouse,tower):
 await setup(size,"escort")
 game.camera_focus=Mission.TARGET;game.camera_zoom=22.0;game._camera_update()
 game._submit("order",{"ids":game.frontier_escort.villagers.duplicate(),"target":-1,"position":Vector3(-6.000002,0,7)})
 if not ck(str(size)+" ordinary party arrives",advance(420,func():return game.frontier_escort.stage==1)):return
 for row in [["storehouse",warehouse,3],["tower",tower,1]]:
  var kind=row[0]; var t=str(size)+" "+kind
  game._select([row[2]]);await sync()
  if not ck(t+" real selectable construction control",await build(kind)):return
  var before=game.economy.bank_milli(0)
  var commands=game.command_sequence
  var plot=Mission.TARGET if kind=="storehouse" else row[1]
  var screen=game.camera.unproject_position(plot)
  var expected=game._snap_build_position(kind,game._point(game._cell(game._world_at(screen))))
  if not ck(t+" exact known legal banner-band point",expected==plot and game._placement_reason(kind,plot,0,row[2]).is_empty() and screen.y>=115 and screen.y<169):return
  if not ck(t+" reserved HUD only, no click-through and explicit confirmation",not game.tutorial_panel.visible and game.hud_bottom.get_global_rect().encloses(game.selection_summary.get_global_rect()) and game._box_point_in_world(screen) and game.build_confirm.disabled):return
  await tap_point(screen)
  if not ck(t+" same formerly covered touch now picks exact unpaid site",game.build_preview_held and game.placement_ok and game._snap_build_position(kind,game.pointer_world)==plot and not game.build_confirm.disabled and game.selection_summary.text=="前哨內 · 按確認" and game.command_sequence==commands and game.economy.bank_milli(0)==before):return
  # Warehouse paid at matched baseline anchor so the exact tower test has the
  # same world construction/fog state. Merely selecting either plot costs zero.
  await tap_point(game.camera.unproject_position(row[1]))
  if not ck(t+" actual Confirm queues once",game.build_preview_held and not game.build_confirm.disabled and await tap_control(game.build_confirm) and game.commands.size()==1 and game.command_sequence==commands+1):return
  game._tick(Rules.TICK)
  if not ck(t+" authoritative exact price and construction",game.economy.bank_milli(0).wood==before.wood-80000 and advance(900,func():return game.frontier_escort.buildings.has(kind))):return
  await sync()
 game._select([1]);await sync()
 if not ck(str(size)+" original real shortage notice overrules generic placement",await build("house") and game.build_confirm.disabled and game._shortfall_for("house")!="" and game.selection_summary.text==game._shortfall_for("house") and game.selection_detail.text.contains(game._shortfall_for("house"))):return
 ck(str(size)+" Cancel keeps final audited stocks",await tap_control(cancel_button()) and game.build_mode.is_empty() and game.commands.is_empty() and game.economy.bank_milli(0).wood==40000 and game.economy.audit().ok)
func tutorial_lifecycle():
 await setup(Vector2i(568,320))
 game.toast_time=0;game._refresh_tutorial()
 ck("normal active teaching card visible before build",not game.demo_tutorial.skipped and game.tutorial_panel.visible)
 game._select([1]);await sync()
 var before=game.demo_tutorial.step()
 if not ck("short landscape actual Build suspends passive lesson",await build("house") and not game.tutorial_panel.visible and game.build_confirm.disabled):return
 var bank=game.economy.bank_milli(0)
 var seq=game.command_sequence
 game._message("偵察已返回",4);await sync()
 var old=game.pointer_world
 var p=game.tutorial_panel.get_global_rect().get_center()
 await tap_point(p)
 ck("non-placement notification remains visible and owns its taps",game.tutorial_panel.visible and game.toast_label.text=="偵察已返回" and game.pointer_world==old and not game.build_preview_held and game.command_sequence==seq)
 game.toast_time=0;await sync()
 ck("notice expires without restoring a passive blocker",game.build_mode=="house" and not game.tutorial_panel.visible)
 ck("real Cancel restores lesson and pre-build selection, no payment",await tap_control(cancel_button()) and game.tutorial_panel.visible and game.demo_tutorial.step()==before and game.selected==[1] and game.economy.bank_milli(0)==bank)
 if not ck("reopen for genuine viewport change",await build("house") and not game.tutorial_panel.visible):return
 root.size=Vector2i(390,844);await sync()
 ck("actual resize retains cancellation policy and restores passive lesson",game.build_mode.is_empty() and not game.build_preview_held and game.tutorial_panel.visible and game.demo_tutorial.step()==before and game.economy.bank_milli(0)==bank and game.commands.is_empty())
 ck("portrait retains original full-width placement feedback",await build("house") and game.tutorial_panel.visible and game.toast_build_guidance and game.build_confirm.disabled and game.selection_summary.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART)
func run():
 await sample(Vector2i(568,320),Vector3(-5,0,6),Vector3(-8,0,7))
 game.free();await process_frame
 await sample(Vector2i(512,288),Vector3(-3,0,7),Vector3(-8,0,7))
 game.free();await process_frame
 await tutorial_lifecycle()
 game.free()
 ck("all permanent cases ran",checks.size()>=30)
 var failed=checks.filter(func(k):return not k.passed).size()
 print(JSON.stringify({"suite":"inline_construction_guidance_contract","checks":checks,"failed":failed}))
 quit(1 if failed else 0)
