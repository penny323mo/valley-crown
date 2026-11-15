extends SceneTree
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func run():
 var game=load("res://main.tscn").instantiate();game.skirmish_mode="fortress";root.add_child(game);game.set_process(false);game.ai_enabled=false
 await process_frame
 game.paused=false;game.application_focused=true;game.application_suspended=false
 game.compact_menu.show();game._set_shortcut_category("army");game._refresh_squad_buttons()
 var before=game.commands.duplicate(true)
 check("healthy roster hides empty wounded actions",not game.army_roster_buttons.cavalry.wounded.visible)
 var cavalry=game._first(0,"cavalry");cavalry.hp-=10;game._update_vision();game._refresh_army_roster()
 check("injured roster reveals wounded action",game.army_roster_buttons.cavalry.wounded.visible)
 for size in [Vector2i(320,568),Vector2i(640,360),Vector2i(844,390)]:
  root.size=size;game._layout_ui();await process_frame;await process_frame
  game.shortcut_scroll.scroll_vertical=0;await process_frame
  var header=game.shortcut_header.get_global_rect();var tab=game.shortcut_category_buttons.army.get_global_rect()
  game.shortcut_scroll.scroll_vertical=10000;await process_frame;await process_frame
  check("header pinned after content scroll "+str(size),game.shortcut_header.get_global_rect()==header)
  check("army tab stays fixed "+str(size),game.shortcut_category_buttons.army.get_global_rect()==tab)
  check("header and scroll fit inside viewport "+str(size),header.position.y>=0 and header.end.x<=size.x+0.1 and game.shortcut_scroll.get_global_rect().end.y<=size.y+0.1)
  check("scroll content does not cover header "+str(size),game.shortcut_scroll.get_global_rect().position.y>=header.end.y)
 root.size=Vector2i(640,360);game._layout_ui();await process_frame;await process_frame
 game.shortcut_scroll.scroll_vertical=0
 var origin=game.shortcut_scroll.get_global_rect().get_center()
 game.all_touch_ids=[6];game.touch_gesture=false
 var press=InputEventScreenTouch.new();press.index=6;press.position=origin;press.pressed=true
 game._track_action_scroll(press,game.get_viewport())
 check("touch swipe binds actual content scroll",game.action_touch_scroll.has(6) and game.action_touch_scroll[6].control.get_ref()==game.shortcut_scroll)
 var drag=InputEventScreenDrag.new();drag.index=6;drag.position=origin-Vector2(0,80)
 game._track_action_scroll(drag,game.get_viewport());await process_frame
 check("content swipe scrolls list",game.shortcut_scroll.scroll_vertical>0)
 game.action_touch_scroll.clear();press.position=game.shortcut_header.get_global_rect().get_center();game._track_action_scroll(press,game.get_viewport())
 check("header touch cannot accidentally scroll list",not game.action_touch_scroll.has(6))
 game.all_touch_ids.clear();game._set_shortcut_category("production")
 check("pinned category switches and resets content",game.shortcut_category=="production" and game.shortcut_scroll.scroll_vertical==0)
 check("navigation does not issue orders",game.commands==before)
 check("economy remains conserved",game.economy.audit().ok)
 game.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"pinned_menu_contract","checks":checks,"failed":failed,"scope":"Native real layout and explicit touch routing; not physical phone"}))
 quit(1 if failed else 0)
