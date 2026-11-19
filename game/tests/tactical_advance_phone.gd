extends SceneTree
var game
var results=[]
var checks=[]
var fails=[]
func _initialize():call_deferred("run")
func ck(label,test):
 checks.append({"name":label,"passed":bool(test)})
 if not test:fails.append(label)
func settle():
 game._update_hud();game._layout_ui()
 for i in 4:await process_frame
func touch(p,down):
 var event=InputEventScreenTouch.new();event.index=0;event.position=p;event.pressed=down
 root.push_input(event)
func tap(p):
 for down in [true,false]:
  touch(p,down);await process_frame
 await settle()
func named(text):
 for button in game.actions.get_children():
  if button is Button and button.text==text:return button
 return null
func shown(b,area):
 return b!=null and b.is_visible_in_tree() and area.encloses(b.get_global_rect()) and root.get_visible_rect().encloses(b.get_global_rect())
func run_case(size,baseline):
 root.size=size;game=load("res://main.tscn").instantiate();game.skirmish_mode="battle";game.victory_mode="conquest";root.add_child(game);game.set_process(false)
 for j in 200:game._process(game.Rules.TICK)
 var ids=[]
 for kind in ["spearman","archer"]:
  var unit=game._first(0,kind)
  if not unit.is_empty():ids.append(unit.id)
 ck("built-in Battle mode owns mixed units "+str(size),ids.size()==2)
 if ids.size()!=2:game.free();return
 # Same ordinary already-validated mixed-selection state as touch box; assert only target UI behavior here.
 game._select(ids);await settle()
 var strip=game.action_scroll.get_global_rect()
 var adv=named("警戒前進")
 var unpick=named("取消選取")
 var row={"size":[size.x,size.y],"build":game.Rules.BUILD_ID,"tick":game.tick_count,"ids":ids,"action_clip":[strip.position.x,strip.position.y,strip.size.x,strip.size.y],"advance_x":adv.position.x if adv else -999,"advance_global_x":adv.get_global_rect().position.x if adv else -999,"advance_visible":shown(adv,strip),"cancel_selection_visible":shown(unpick,strip)}
 results.append(row)
 ck("selected correctly "+str(size),game.selected==ids and game.action_scroll.scroll_horizontal==0)
 ck("present tactical action "+str(size),adv!=null)
 if baseline:
  game.free();await process_frame;return
 ck("advance fully visible without scroll "+str(size),shown(adv,strip))
 ck("cancel selection fully visible "+str(size),shown(unpick,strip))
 if not shown(adv,strip) or not shown(unpick,strip):game.free();await process_frame;return
 var bank=game.economy.bank_milli(0).duplicate(true)
 var queue=game.commands.duplicate(true)
 # An old held CTA must never issue on the replacement selection.
 var oldp=adv.get_global_rect().get_center()
 touch(oldp,true);await process_frame;game._select([ids[1]]);await settle()
 touch(oldp,false);await settle()
 ck("held old tactic cannot arm replacement army "+str(size),not game.touch_command and game.selected==[ids[1]] and game.commands==queue)
 game._select(ids);await settle()
 var start=named("警戒前進").get_global_rect().get_center()
 var dest=start-Vector2(38,0)
 touch(start,true);await process_frame
 var drag=InputEventScreenDrag.new();drag.index=0;drag.position=dest;drag.relative=dest-start;root.push_input(drag);await process_frame
 touch(dest,false);await settle()
 ck("drag over tactic scrolls without arming "+str(size),game.action_scroll.scroll_horizontal>0 and not game.touch_command and game.commands==queue)
 for i in 10:
  var clip=game.action_scroll.get_global_rect()
  var filter=game.actions.get_node_or_null("SelectType_archer")
  if shown(filter,clip):break
  var a=clip.get_center()
  var b=a+Vector2(45 if filter.get_global_rect().position.x<clip.position.x else -45,0)
  touch(a,true);await process_frame
  var swipe=InputEventScreenDrag.new();swipe.index=0;swipe.position=b;swipe.relative=b-a;root.push_input(swipe);await process_frame
  touch(b,false);await settle()
 ck("subtype filter still reachable by ordinary swipes "+str(size),shown(game.actions.get_node_or_null("SelectType_archer"),game.action_scroll.get_global_rect()) and game.commands==queue)
 var worker=game._first(0,"villager");game._select([worker.id,ids[0],ids[1]]);await settle()
 ck("worker and army mixed selection keeps original first worker filter "+str(size),game.actions.get_child(0).name=="SelectType_villager")
 game._select(ids);await settle()
 await tap(named("警戒前進").get_global_rect().get_center())
 ck("first touch only arms tactic and preserves selection/queue/bank "+str(size),game.touch_command and game.unit_command_kind=="advance" and game.selected==ids and game.commands==queue and game.economy.bank_milli(0)==bank)
 ck("valid-target help and visible cancel "+str(size),game.selection_detail.text.contains("點目的地") and shown(game.compact_cancel_button,root.get_visible_rect()))
 await tap(game.compact_cancel_button.get_global_rect().get_center())
 ck("cancel emits no order and leaves army selected "+str(size),not game.touch_command and game.selected==ids and game.commands==queue)
 var target=Vector2.INF
 for y in [0.31,0.40,0.52,0.65]:
  for x in [0.32,0.48,0.63]:
   var p=Vector2(size.x*x,size.y*y)
   if game._box_point_in_world(p) and game._world_at(p).is_finite() and game._pick(p,false)<0:target=p;break
  if target.is_finite():break
 ck("clear regular visible map target "+str(size),target.is_finite())
 if target.is_finite():
  await tap(named("警戒前進").get_global_rect().get_center())
  await tap(target)
  var n=game.commands.size()
  ck("only one ordinary advance for exact mixed army "+str(size),n==queue.size()+1 and game.commands.back().type=="advance" and game.commands.back().ids==ids and not game.touch_command)
  game._process(game.Rules.TICK)
  ck("ordinary advance applied to both "+str(size),game._get_entity(ids[0]).get("mode","")=="ADVANCE" and game._get_entity(ids[1]).get("mode","")=="ADVANCE")
  queue=game.commands.duplicate(true)
  await tap(target)
  ck("direct gesture stays a normal move, no advance "+str(size),game.commands.size()==queue.size()+1 and game.commands.back().type=="order" and game.commands.back().ids==ids)
  game._process(game.Rules.TICK)
  queue=game.commands.duplicate(true)
  # Controlled secondary regression only: native current-vision projection,
  # no visibility injection, spoofed target ID or direct _tap call.
  var unit=game._get_entity(ids[0])
  var enemy=game._spawn("spearman",1,unit.pos+Vector3(0,0,2.5))
  game._update_vision();await settle()
  var point=game.camera.unproject_position(enemy.pos+Vector3(0,.6,0))
  var seen=game._box_point_in_world(point) and game._pick(point)==enemy.id and game.faction_views[0].get_record(enemy.id).get("alive",false)
  ck("nearby hostile regression target actually visible and pickable "+str(size),seen)
  if seen:
   await tap(point)
   ck("ordinary visible enemy tap still queues ordinary attack intent "+str(size),game.commands.size()==queue.size()+1 and game.commands.back().type=="order" and game.commands.back().target==enemy.id and game.commands.back().ids==ids and not game.touch_command)
 ck("bank/ledger invariant "+str(size),game.economy.bank_milli(0)==bank and game.economy.audit().ok)
 await tap(named("取消選取").get_global_rect().get_center())
 ck("normal Cancel Selection still clears selection "+str(size),game.selected.is_empty())
 game.free();await process_frame
func run():
 var baseline="baseline" in OS.get_cmdline_user_args()
 await run_case(Vector2i(390,844),baseline)
 await run_case(Vector2i(640,360),baseline)
 print(JSON.stringify({"suite":"tactical_advance_phone","scope":"Game Battle scenario mixed units; synthetic native touch not browser or phone","results":results,"checks":checks,"failed":fails.size(),"failures":fails}))
 quit(0 if fails.is_empty() else 1)
