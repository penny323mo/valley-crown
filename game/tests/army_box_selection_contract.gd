extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func touch(p,id,down,cancel=false):
 var e=InputEventScreenTouch.new();e.position=p;e.index=id;e.pressed=down;e.canceled=cancel;root.push_input(e);await process_frame
func drag(p,id,relative):
 var e=InputEventScreenDrag.new();e.position=p;e.index=id;e.relative=relative;root.push_input(e);await process_frame
func rectangle(g,units):
 var r=Rect2(g.camera.unproject_position(units[0].pos+Vector3(0,.6,0)),Vector2.ZERO)
 for u in units:r=r.expand(g.camera.unproject_position(u.pos+Vector3(0,.6,0)))
 return r.grow(12)
func run():
 root.size=Vector2i(960,640)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false;await settle()
 var worker=g._first(0,"villager");var resource={};var best=INF
 for r in g.faction_views[0].records().values():
  if r.kind=="berry" and not r.remembered and r.pos.distance_to(worker.pos)<best:best=r.pos.distance_to(worker.pos);resource=r
 check("real opening worker has visible gather target",not resource.is_empty())
 if resource.is_empty():g.free();quit(1);return
 g._submit("order",{"ids":[worker.id],"target":resource.id,"position":resource.pos});g._tick(Rules.TICK)
 var troops=[]
 for i in 5:troops.append(g._spawn(["scout","spearman","archer","cavalry","siege"][i],0,worker.pos+Vector3(2+i*1.4,0,0)))
 var foe=g._spawn("spearman",1,worker.pos+Vector3(4,0,-1))
 g._update_vision();g._publish_faction_views();g.camera_focus=worker.pos+Vector3(4,0,0);g.camera_zoom=22;g._camera_update();g._layout_ui();await settle()
 var units=[worker]+troops;var rect=rectangle(g,units)
 check("controlled rectangle lies entirely in world input region",g._box_point_in_world(rect.position) and g._box_point_in_world(rect.end))
 var epoch=worker.work_epoch;var target=worker.target;var state=worker.state;var dest=worker.dest;var commands=g.commands.duplicate(true)
 g.compact_menu.show();g.find_child("ArmyBoxSelect",true,false).pressed.emit();await settle()
 check("army entry closes menu and announces one-shot mode",g.box_select_mode and g.box_select_military_only and not g.compact_menu.visible and g.selection_title.text=="框選軍隊")
 await touch(rect.position,10,true);await drag(rect.end,10,rect.size);await touch(rect.end,10,false)
 check("actual touch box retains every military type",troops.all(func(u):return u.id in g.selected))
 check("actual touch box excludes villagers and enemy",worker.id not in g.selected and foe.id not in g.selected and g.selected.all(func(id):return g._get_entity(id).kind!="villager"))
 check("box only changes selection not economy work or commands",worker.work_epoch==epoch and worker.target==target and worker.state==state and worker.dest==dest and g.commands==commands)
 check("completed box clears filter and restores ordinary mode",not g.box_select_mode and not g.box_select_military_only)
 var ordinary=g._box_selection_ids(rect)
 check("next ordinary box includes worker again",worker.id in ordinary and troops.all(func(u):return u.id in ordinary))
 # Real primary-click command after filtered selection must not reach workers.
 var p=g.camera.unproject_position(troops[0].pos+Vector3(0,0,4));var issued=false
 for down in [true,false]:
  var e=InputEventMouseButton.new();e.position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e);await process_frame
 for c in g.commands:
  if c.get("type","")=="order":issued=true;check("following contextual order excludes worker",worker.id not in c.ids)
 check("filtered army can receive ordinary primary-click order",issued)
 g._tick(Rules.TICK)
 check("worker original gathering intent survives troop command",worker.work_epoch==epoch and worker.target==target and worker.state in ["gather","deliver","move"])
 var before=g.selected.duplicate();var count=g.commands.size()
 g._start_box_select(true);await touch(rect.position,11,true);await drag(rect.end,11,rect.size);g._cancel_mode();await touch(rect.end,11,false)
 check("cancel consumes held release and clears military filter",g.selected==before and not g.box_select_military_only and g.commands.size()==count)
 g._start_box_select(true);await touch(rect.position,12,true);await touch(rect.position+Vector2(50,0),13,true);await drag(rect.end,12,rect.size);await touch(rect.end,12,false);await touch(rect.position+Vector2(50,0),13,false)
 check("second finger cancels army box without selecting or ordering",g.selected==before and not g.box_select_mode and not g.box_select_military_only and g.commands.size()==count)
 g._start_box_select(true);await touch(rect.position,14,true);await drag(rect.end,14,rect.size);await touch(rect.end,14,false,true)
 check("OS canceled touch retires army filter",g.selected==before and not g.box_select_military_only)
 g._start_box_select(true);g.test_mode=false;g._notification(NOTIFICATION_APPLICATION_FOCUS_OUT);g._notification(NOTIFICATION_APPLICATION_FOCUS_IN);g.test_mode=true
 check("focus interruption clears filter",not g.box_select_military_only)
 g.paused=false
 g._start_box_select(true);g._start_box_select()
 check("ordinary explicit box never inherits army filter",g.box_select_mode and not g.box_select_military_only)
 g._cancel_mode()
 # Native mouse drag uses the same one-shot predicate.
 g.camera_focus=worker.pos+Vector3(4,0,0);g._camera_update();rect=rectangle(g,units);g._start_box_select(true)
 var mb=InputEventMouseButton.new();mb.position=rect.position;mb.button_index=MOUSE_BUTTON_LEFT;mb.pressed=true;root.push_input(mb);await process_frame
 var mm=InputEventMouseMotion.new();mm.position=rect.end;mm.relative=rect.size;mm.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(mm);await process_frame
 mb=InputEventMouseButton.new();mb.position=rect.end;mb.button_index=MOUSE_BUTTON_LEFT;mb.pressed=false;root.push_input(mb);await process_frame
 check("desktop army box shares one-shot filter",worker.id not in g.selected and troops.all(func(u):return u.id in g.selected) and not g.box_select_military_only)
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await settle();g._start_box_select(true);await settle()
  check("army mode visible and cancel reachable "+str(size),g.selection_title.text=="框選軍隊" and g.selection_summary.text.contains("只選軍隊") and g.actions.get_child_count()>0 and g.actions.get_child(0).text=="取消框選")
  g._cancel_mode()
 g._start_box_select(true);g._test_reset();check("fresh match reset clears transient filter",not g.box_select_mode and not g.box_select_military_only)
 g.free();await settle()
 print(JSON.stringify({"suite":"army_box_selection_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Native synthetic mouse and touch with controlled own army and ordinary opening gather order; no physical-phone or rendered screenshot claim."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
