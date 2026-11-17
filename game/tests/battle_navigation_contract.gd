extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func touch(p,down):
 var e=InputEventScreenTouch.new();e.position=p;e.index=81;e.pressed=down;root.push_input(e,false);await settle()
func run():
 root.size=Vector2i(390,844)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 await settle()
 # Controlled initial positions only; damage is issued/settled by real ticks.
 var victim=g._first(0,"villager");var foe=g._first(1,"scout")
 g._set_stance(victim,"STOP");foe.pos=victim.pos+Vector3(1,0,0);foe.cooldown_ticks=0
 g._update_vision(false);g._order(foe,"attack",victim.id);g._tick(Rules.TICK)
 var first=g.battle_alerts.peek(g.tick_count)
 check("first ordinary settled hit creates own-location alert",not first.is_empty() and first.position==victim.pos)
 var keep=g._first(0,"town_center")
 foe.pos=keep.pos+Vector3(2,0,0);foe.cooldown_ticks=0;g._update_vision(false);g._order(foe,"attack",keep.id);g._tick(Rules.TICK)
 # If starting worker is near keep, use a separate controlled own building.
 if g.battle_alerts.pending(g.tick_count).size()<2:
  var second=g._spawn("house",0,Vector3(-25,0,15));foe.pos=second.pos+Vector3(2,0,0);foe.cooldown_ticks=0
  g._update_vision(false);g._order(foe,"attack",second.id);g._tick(Rules.TICK)
 check("two separated ordinary own hits expose two frozen alert positions",g.battle_alerts.pending(g.tick_count).size()==2)
 g._set_stance(foe,"STOP");g._select([keep.id]);g._update_hud();g._layout_ui();await settle()
 var selected=g.selected.duplicate();var commands=g.commands.duplicate(true);var masks=g.visible_cells[0].duplicate()
 for size in [Vector2i(320,568),Vector2i(844,390),Vector2i(390,844)]:
  root.size=size;await settle();g._layout_ui();await settle()
  var rect=g.battle_jump_button.get_global_rect()
  check("direct battle action reachable "+str(size),g.battle_jump_button.is_visible_in_tree() and rect.size.y>=44 and Rect2(Vector2.ZERO,Vector2(size)).encloses(rect) and not rect.intersects(g.pause_button.get_global_rect()) and not rect.intersects(g.compact_menu_button.get_global_rect()))
  check("HUD retains world gap "+str(size),g.hud_top.get_global_rect().end.y+40<g.hud_bottom.position.y and Rect2(Vector2.ZERO,Vector2(size)).encloses(g.hud_top.get_global_rect()))
 var p=g.battle_jump_button.get_global_rect().get_center()
 await touch(p,true);await touch(p,false)
 check("one routed tap focuses first alert without opening menu",g.camera_focus==first.position and not g.compact_menu.visible and g.battle_alerts.pending(g.tick_count).size()==1)
 check("navigation leaves selected orders and visibility unchanged",g.selected==selected and g.commands==commands and g.visible_cells[0]==masks)
 var next=g.battle_alerts.peek(g.tick_count)
 p=g.battle_jump_button.get_global_rect().get_center();await touch(p,true)
 g.tick_count+=240;g._refresh_attack_alert();await settle();await touch(p,false)
 check("expired held tap does not jump to stale alert",g.camera_focus==first.position and not g.battle_jump_button.visible)
 g.battle_alerts.record_hit({"team":0,"alive":true,"category":"building","kind":"house","pos":next.position},1,g.tick_count);g._refresh_attack_alert();await settle()
 g.paused=true;g._refresh_attack_alert();var expires=g.battle_alerts.pending(g.tick_count)[0].expires
 await settle();check("pause disables jump and preserves simulation expiry",g.battle_jump_button.disabled and g.battle_alerts.pending(g.tick_count)[0].expires==expires)
 g.paused=false;g._refresh_attack_alert();g._focus_battle_jump()
 check("acknowledged alert absent from minimap presentation snapshot",g.battle_alerts.pending(g.tick_count).is_empty())
 g.battle_alerts.record_hit({"team":0,"alive":true,"category":"building","kind":"house","pos":next.position},1,g.tick_count+1)
 check("continuing acknowledged combat does not spam again",g.battle_alerts.pending(g.tick_count+1).is_empty())
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"battle_navigation_contract","checks":checks,"failed":failed,"scope":"Controlled combat setup with real damage settlement and viewport-routed touch, three simulated sizes; not physical phone or natural whole match."}));quit(1 if failed else 0)
