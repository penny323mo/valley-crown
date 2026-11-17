extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var g
var cars=[]
var guards=[]
var out=""
var metadata_only=false
var checks=[]
var report={"captures":[],"scope":"Controlled practice spawns, not natural recruitment. Two siege plus four spearmen; ordinary product EscortBatch action and normal move/follow/intercept ticks. No health/terrain/resource/fog overrides. AI scheduling disabled. Not phone/browser acceptance."}
func _initialize():call_deferred("run")
func check(n,b):checks.append({"name":n,"pass":bool(b)});return bool(b)
func actors(items):
 var rows=[]
 for u in items:rows.append({"id":u.id,"kind":u.kind,"position":str(u.pos),"hp":u.hp,"mode":u.mode,"state":u.state,"target":u.target,"escort_target":u.get("escort_target",-1)})
 return rows
func shot(name,enemy=null):
 g._camera_update();g._refresh_fog();g._update_visuals(0);g._update_hud();await process_frame;await process_frame
 var b=g.escort_batch_button
 if name=="01-mixed-selection-action" and is_instance_valid(b):
  g.action_scroll.ensure_control_visible(b);await process_frame;await process_frame
 var row={"name":name,"tick":g.tick_count,"cars":actors(cars),"guards":actors(guards),"bank":g.economy.bank_milli(0),"selected":g.selected.duplicate(),"button_visible":is_instance_valid(b) and b.is_visible_in_tree(),"button_disabled":b.disabled if is_instance_valid(b) else true,"metadata_only":metadata_only}
 if enemy!=null:row.enemy=actors([enemy])
 if name=="01-mixed-selection-action":check("action visually positioned inside viewport",row.button_visible and Rect2(Vector2.ZERO,Vector2(root.size)).encloses(b.get_global_rect()))
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var p=out+"/"+name+".png";check(name+" PNG",root.get_texture().get_image().save_png(p)==OK);row.file=p;row.sha256=FileAccess.get_sha256(p)
 report.captures.append(row)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if args.size()>0 else "/tmp/v94-escort-capture"
 if DirAccess.dir_exists_absolute(out):quit(2);return
 DirAccess.make_dir_recursive_absolute(out);metadata_only=DisplayServer.get_name()=="headless" or "--metadata-only" in args
 root.size=Vector2i(960,540);report.build=Rules.BUILD_ID;report.driver_sha256=FileAccess.get_sha256(get_script().resource_path)
 for p in ["game","escort_batch","rules"]:report[p+"_sha256"]=FileAccess.get_sha256("res://scripts/"+p+".gd")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="practice";g.history_path=out+"/history.json";root.add_child(g);g.set_process(false);g.ai_enabled=false;await process_frame
 for x in [8,14]:cars.append(g._spawn("siege",0,Vector3(x,0,-4)))
 for x in [7,9,13,15]:guards.append(g._spawn("spearman",0,Vector3(x,0,-7)))
 g._navigation_rebuild();g._update_vision();g._publish_faction_views()
 var ids=[]
 for car in cars:
  ids.append(car.id);g._submit("order",{"ids":[car.id],"target":-1,"position":car.pos+Vector3(0,0,5)})
 for guard in guards:ids.append(guard.id)
 g._select(ids);g.camera_focus=Vector3(11,0,-3);g.camera_zoom=20;g._camera_update();g._layout_ui();g._update_hud()
 var bank=g.economy.bank_milli(0).duplicate(true)
 await shot("01-mixed-selection-action")
 check("action enabled",is_instance_valid(g.escort_batch_button) and not g.escort_batch_button.disabled)
 var pending=g.commands.size();g.escort_batch_button.pressed.emit()
 check("one action two ordinary groups",g.commands.size()==pending+2 and g.commands[-1].type=="escort" and g.commands[-2].type=="escort")
 g._tick(Rules.TICK)
 check("two guards each",guards.filter(func(u):return u.get("escort_target",-1)==cars[0].id).size()==2 and guards.filter(func(u):return u.get("escort_target",-1)==cars[1].id).size()==2)
 check("vehicle move kept",cars.all(func(c):return c.mode!="ESCORT" and c.state=="move" and c.dest.z>c.pos.z))
 await shot("02-two-assigned-groups")
 for i in 140:g._tick(Rules.TICK)
 check("groups normally follow",guards.all(func(u):return u.mode=="ESCORT" and u.pos.z>-6.5) and cars.all(func(c):return c.pos.z>-2))
 await shot("03-moving-escort-groups")
 var enemy=g._spawn("archer",1,cars[0].pos+Vector3(1.5,0,0));g._update_vision();var intercepted=false
 for i in 40:
  g._tick(Rules.TICK)
  for guard in guards:
   if guard.target==enemy.id and guard.state=="attack":intercepted=true
  if intercepted:break
 check("normal visible threat intercepted",intercepted)
 await shot("04-visible-threat-interception",enemy)
 check("bank unchanged",g.economy.bank_milli(0)==bank)
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size()
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"failed":report.failed,"checks":checks.size()}));quit(1 if report.failed else 0)
