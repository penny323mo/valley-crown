extends SceneTree
## Controlled native UI lifecycle contract. No browser/device or rendered proof.
const Rules=preload("res://scripts/rules.gd")
const P=Vector3(3,0,13)
var g
var worker={}
var checks=[]
func _initialize():call_deferred("run")
func ck(name:String,v:bool):
 checks.append({"name":name,"pass":v})
 if not v:push_error(name)
 return v
func frames(n=5):
 for i in n:await process_frame
func sync():
 g._process(0);g._update_hud();g._layout_ui();await frames()
func touch(at:Vector2,down:bool,i:int=7):
 var e=InputEventScreenTouch.new();e.index=i;e.pressed=down;e.position=at;root.push_input(e)
func tap(at:Vector2,i:int=7):
 touch(at,true,i);await frames(1);touch(at,false,i);await frames()
func button(b:Control)->Vector2:
 return b.get_global_rect().get_center()
func guard()->Array:
 return [g.economy.bank_milli(0),g.command_sequence,g.commands.filter(func(c):return c.team==0).duplicate(true),g.completed_builds[0]]
func blocked()->bool:
 return not g.build_recon_button.is_visible_in_tree() and g.build_confirm.disabled
func paint():
 # Controlled negative fixture: declared faction-history / current vision
 # only. No screenshots; natural before/after journey is tested separately.
 for y in range(49,57):
  for x in range(39,47):g.explored_cells[0][y*Rules.MAP_SIZE+x]=1
func site_screen():
 return g.camera.unproject_position(P+Vector3(.25,0,.25))
func reset(ids=[]):
 g._test_reset();g._cancel_mode()
 worker=g._first(0,"villager")
 g._set_stance(worker,"STOP");g._update_vision()
 g.camera_focus=P;g._camera_update()
 g._select([worker.id] if ids.is_empty() else ids)
 paint()
 g._start_build("wall")
 await sync()
 await tap(site_screen());await sync()
func ask():
 return is_instance_valid(g.build_recon_button) and g.build_recon_button.is_visible_in_tree() and not g.build_recon_button.disabled
func preview():
 return [g.build_mode,g.pointer_world,g.build_preview_held]
func finish():
 var bad=checks.filter(func(q):return not q.pass)
 print("RECON_NEGATIVE "+JSON.stringify({"checks":checks,"failed":bad.size(),"scope":"Controlled native route visibility change/lifecycle only; no capture or device claim."}))
 quit(1 if not bad.is_empty() else 0)
func run():
 root.size=Vector2i(568,320)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true
 await frames()
 await reset()
 if not ck("controlled remembered solo site genuinely routed through ordinary tap",ask() and g.build_confirm.disabled and g.build_preview_held):finish();return
 var a=button(g.build_recon_button)
 var original=guard()
 touch(a,true);await process_frame
 g._kill(worker);g._update_vision();await sync()
 touch(a,false);await sync()
 ck("stale held press after death has no order, cannot choose a survivor",guard()==original and g.selected.is_empty() and blocked() and g.build_recon_attempt.is_empty())
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 var another=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager" and e.id!=worker.id)[0]
 g._select([another.id]);await sync()
 touch(a,false);await sync()
 ck("selection change cancels stale Recon and does not route to a replacement",guard()==original and g.selected==[another.id] and g.build_mode.is_empty() and g.build_recon_attempt.is_empty())
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 var scout=g._first(0,"scout")
 scout.pos=P+Vector3(-4,0,0);scout.node.position=scout.pos;g._update_vision()
 await sync()
 if not ck("real computed sight flips visible Confirm and hides formerly held Recon",not g.build_confirm.disabled and not g.build_recon_button.is_visible_in_tree()):finish();return
 touch(a,false);await sync()
 ck("sight reveal between press and release does not trigger Confirm or another action",guard()==original and g.build_preview_held and g.pointer_world.distance_to(P)<1.0 and g.build_recon_attempt.is_empty())
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 var key=InputEventKey.new();key.physical_keycode=KEY_P;key.pressed=true;root.push_input(key);await sync()
 key=InputEventKey.new();key.physical_keycode=KEY_P;key.pressed=false;root.push_input(key);await frames()
 touch(a,false);await sync()
 ck("Pause while Recon held retires preview and gives no order",g.paused and guard()==original and g.build_mode.is_empty() and g.build_recon_attempt.is_empty())
 await tap(button(g.pause_button));await sync()
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 root.size=Vector2i(844,390);await sync()
 touch(a,false);await sync()
 ck("resizing consumes the stale release and existing preview teardown",guard()==original and g.build_mode.is_empty() and g.build_recon_attempt.is_empty())
 root.size=Vector2i(568,320);await sync()
 await reset()
 await tap(button(g.build_recon_button));await sync()
 var one=guard();var cancel_b=g.actions.get_children().filter(func(c):return c is Button and c.text=="取消建造")[0]
 await tap(button(cancel_b));await sync()
 ck("Cancel after accepted Recon retires only preview, not the accepted ordinary Move",guard()==one and one[2].size()==1 and one[2][0].type=="order" and g.build_mode.is_empty() and g.build_recon_attempt.is_empty())
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 # The real builder is no longer quiescent (a paid-site job is an owned fact).
 worker.state="build";g._publish_faction_views();await sync()
 touch(a,false);await sync()
 ck("a worker starting construction after press is not stolen by Recon",guard()==original and blocked() and g.build_recon_attempt.is_empty())
 await reset()
 # Test-only loss of path; assert there is no assisted retry or autosubmit.
 await tap(button(g.build_recon_button));await sync()
 g._tick(Rules.TICK)
 g._set_stance(worker,"STOP")
 worker.path_status="NO_PATH";g._publish_faction_views()
 await sync()
 var failed=guard();await tap(button(g.build_recon_button));await sync()
 ck("failed reach retains red held preview and no retry/order/expense even upon another tap",guard()==failed and g.build_confirm.disabled and g.build_preview_held and g.build_recon_button.is_visible_in_tree() and g.build_recon_button.disabled and g.build_recon_button.text=="未到達" and g.selection_summary.text.contains("未取得視野"))
 # The action is never part of ordinary group-wall geometry even when a fogged row is held.
 var own=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager").map(func(e):return e.id).slice(0,2)
 await reset(own)
 g._cycle_wall_line_count();await sync();await tap(site_screen());await sync()
 ck("fogged group Wall gets no Recon and no control inserted into strip",g.wall_line_count==2 and g.build_preview_held and not g.build_recon_button.is_visible_in_tree() and not g.actions.is_ancestor_of(g.build_recon_button) and g.commands.is_empty())
 await reset()
 a=button(g.build_recon_button);original=guard()
 touch(a,true);await process_frame
 g._on_web_touch_cancel([]);await frames()
 touch(a,false);await sync()
 ck("Web bridge touchcancel retires site and consumes stale release",guard()==original and g.build_mode.is_empty() and g.build_recon_attempt.is_empty())
 finish()
