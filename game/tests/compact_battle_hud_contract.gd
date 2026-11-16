extends SceneTree
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func settle():
 for i in 5:await process_frame
func tap(control):
 var p=control.get_global_rect().get_center()
 for down in [true,false]:
  var e=InputEventMouseButton.new();e.position=p;e.global_position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down
  root.push_input(e,false);await process_frame
 await settle()
func run():
 for size in [Vector2i(640,360),Vector2i(390,844),Vector2i(320,568),Vector2i(568,320)]:
  root.size=size
  g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;await settle()
  var keep=g._first(0,"town_center");g._select([keep.id]);g.toast_time=0;g._layout_ui();await settle()
  var prefix=str(size)+": "
  check(prefix+"compact summary visible, full prose folded",g.selection_summary.is_visible_in_tree() and not g.selection_detail.is_visible_in_tree() and g.selection_detail.text.contains("10 秒"))
  check(prefix+"HP and current state remain visible",g.selection_summary.text.contains("1200") and g.selection_summary.text.contains("待命"))
  check(prefix+"ordinary bottom height bounded",g.hud_bottom.size.y<=116 if size.x>=568 else g.hud_bottom.size.y<=160)
  check(prefix+"detail target at least 44px",g.context_detail_button.size.x>=44 and g.context_detail_button.size.y>=44)
  var commands=g.commands.duplicate(true)
  g.action_scroll.scroll_horizontal=maxi(0,int(g.context_detail_button.position.x))
  await settle()
  await tap(g.context_detail_button)
  check(prefix+"real tap expands full detail",g.context_details.visible and g.selection_detail.is_visible_in_tree())
  check(prefix+"bounded details above action strip",g.context_details.get_global_rect().end.y<=g.hud_bottom.position.y and g.context_details.size.y<=200 and root.get_visible_rect().encloses(g.context_details.get_global_rect()))
  check(prefix+"details do not overlap a second guidance panel",not g.tutorial_panel.is_visible_in_tree())
  check(prefix+"details exclude world input",not g._box_point_in_world(g.context_details.get_global_rect().get_center()))
  check(prefix+"opening emits no game commands",g.commands==commands)
  g.qa_mode=true
  check(prefix+"expanded QA describes visible full text",g._qa_hud_snapshot().selection_detail==g.selection_detail.text)
  await tap(g.find_child("CloseBattleDetails",true,false))
  check(prefix+"close restores compact view without commands",not g.context_details.visible and g.commands==commands)
  check(prefix+"collapsed QA describes visible summary",g._qa_hud_snapshot().selection_detail==g.selection_summary.text)
  g._message("出口受阻；請選取單位移開",4);g._layout_ui();await settle()
  check(prefix+"feedback replaces tutorial in same strip",g.toast_label.is_visible_in_tree() and not g.tutorial_label.is_visible_in_tree() and g.tutorial_panel.get_global_rect().encloses(g.toast_label.get_global_rect()))
  var skipped=g.demo_tutorial.skipped;var achieved=g.demo_tutorial.achieved.duplicate()
  await tap(g.guidance_detail_button)
  check(prefix+"full feedback accessible",g.guidance_detail.is_visible_in_tree() and g.guidance_detail.text==g.toast_label.text)
  await tap(g.find_child("CloseBattleDetails",true,false))
  g.toast_time=0;g._refresh_tutorial();await settle()
  check(prefix+"expiry restores lesson without skipping",g.tutorial_label.is_visible_in_tree() and not g.toast_label.is_visible_in_tree() and g.demo_tutorial.skipped==skipped and g.demo_tutorial.achieved==achieved)
  # Controlled UI fixture: real paid queue, ready item held at the exit boundary.
  g._enqueue_train(keep.id,"villager",0);keep.queue[0].remaining_ticks=0
  g._update_vision();g._update_hud();await settle()
  check(prefix+"ready queue warning stays visible while folded",g.queue_label.is_visible_in_tree() and g.queue_label.text.contains("出口受阻") and g.hud_bottom.get_global_rect().encloses(g.queue_label.get_global_rect()) and not g.context_details.visible)
  var worker=g._first(0,"villager");g._select([worker.id]);await settle()
  check(prefix+"worker building action remains immediately available",g.actions.get_children().any(func(b):return b is Button and b.text.begins_with("民居\n")))
  g._start_build("house");g.pointer_world=keep.pos;g._update_hud();await settle()
  check(prefix+"placement rejection visible without expanding",g.selection_summary.text.contains("不可建造") and not g.context_details.visible)
  g._cancel_mode();g.free();await settle()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"compact_battle_hud_contract","checks":checks,"failed":failed,"scope":"Native four viewport UI geometry and actual button routing; compact truthful summaries and one guidance strip, not physical-device proof"}))
 quit(1 if failed else 0)
