extends SceneTree
# External driver for an exact native game/PCK. No production source edits.
const Rules=preload("res://scripts/rules.gd")
var g
var scout
var out=""
var metadata_only=false
var checks=[]
var report={"scope":"Controlled safe scouting/UI demonstration with AI disabled, not natural competitive play: existing scout moves via normal queued orders; real viewport touch GUI dispatch. No fog, health, stocks or unit-count overrides. NOT physical-phone validation or natural campaign acceptance.","captures":[],"moves":[],"gestures":[]}
func _initialize():call_deferred("run")
func check(n,b,detail=null):
 checks.append({"name":n,"pass":bool(b),"detail":detail})
 return bool(b)
func counts():
 var c={"current":0,"explored_only":0,"unknown":0}
 for i in g.visible_cells[0].size():
  if g.visible_cells[0][i]!=0:c.current+=1
  elif g.explored_cells[0][i]!=0:c.explored_only+=1
  else:c.unknown+=1
 return c
func state():
 return {"tick":g.tick_count,"snapshot":g._snapshot(),"scout_pos":str(scout.pos),"camera_focus":str(g.camera_focus),"camera_zoom":g.camera_zoom,"fog":counts(),"selected":g.selected.duplicate(),"commands":g.commands.duplicate(true),"hud_selection":g.selection_title.text,"minimap_rect":str(g.minimap.get_global_rect()),"minimap_visible":g.minimap.is_visible_in_tree()}
func orders():
 return {"selected":g.selected.duplicate(),"commands":JSON.stringify(g.commands),"state":scout.state,"target":scout.target,"path":str(scout.get("path",[])),"destination":str(scout.get("destination",null)),"build_mode":g.build_mode,"command_sequence":g.command_sequence}
func refresh():
 g._camera_update();g._update_visuals(0.0);g._update_hud();g._refresh_fog();g.minimap.queue_redraw()
func capture(name):
 refresh();await process_frame
 var row={"name":name,"state":state(),"metadata_only":metadata_only}
 if not metadata_only:
  await RenderingServer.frame_post_draw
  var path=out+"/"+name+".png"
  var err=root.get_texture().get_image().save_png(path)
  check(name+" real viewport PNG saved",err==OK)
  row.file=path;row.sha256=FileAccess.get_sha256(path)
 report.captures.append(row)
func move_to(destination:Vector3,key:String):
 var start=scout.pos;var start_tick=g.tick_count
 g._submit("order",{"ids":[scout.id],"target":-1,"position":destination,"command_id":key},0)
 for i in 1000:
  g._tick(Rules.TICK)
  # Simulation remains unchanged; render only the recorded evidence states.
  if g.game_over or not scout.alive:break
  if scout.pos.distance_to(destination)<1.4:break
 var success=scout.pos.distance_to(destination)<1.4 and scout.pos.distance_to(start)>2.
 report.moves.append({"command_id":key,"from":str(start),"requested":str(destination),"actual":str(scout.pos),"ticks":g.tick_count-start_tick,"arrived":success,"processed":g.processed_command_ids.has("0:"+key),"fog":counts()})
 return check(key+" normal move arrived",success and g.processed_command_ids.has("0:"+key))
func touch(id:int,p:Vector2,pressed:bool):
 var e=InputEventScreenTouch.new();e.index=id;e.position=p;e.pressed=pressed
 root.push_input(e);await process_frame
func drag(id:int,p:Vector2,relative:Vector2):
 var e=InputEventScreenDrag.new();e.index=id;e.position=p;e.relative=relative
 root.push_input(e);await process_frame
func finish():
 report.checks=checks;report.failed=checks.filter(func(x):return not x.pass).size();report.status="PASS_METADATA_ONLY" if metadata_only else "CAPTURED_GENUINE_GAMEPLAY"
 if report.failed>0:report.status="FAILED_INCOMPLETE"
 var f=FileAccess.open(out+"/report.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close();print(JSON.stringify({"status":report.status,"failed":report.failed,"output":out,"build":report.build}));quit(0 if report.failed==0 else 1)
func run():
 var args=OS.get_cmdline_user_args();out=args[0] if not args.is_empty() else "/tmp/v87-minimap-capture"
 metadata_only="--metadata-only" in args or DisplayServer.get_name()=="headless"
 if DirAccess.dir_exists_absolute(out):push_error("Refusing to overwrite capture evidence: "+out);quit(2);return
 DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(960,540)
 report.build=Rules.BUILD_ID;report.rules_sha256=FileAccess.get_sha256("res://scripts/rules.gd");report.game_sha256=FileAccess.get_sha256("res://scripts/game.gd");report.minimap_sha256=FileAccess.get_sha256("res://scripts/minimap.gd");report.driver_sha256=FileAccess.get_sha256(get_script().resource_path);report.renderer=DisplayServer.get_name();report.physical_phone_validated=false
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.ai_enabled=false
 await process_frame;await process_frame
 scout=g._first(0,"scout")
 check("normal initial game not test mode",not g.test_mode and g.tick_count==0 and not scout.is_empty())
 report.ai_enabled=g.ai_enabled;report.player_display_settings={"camera_zoom":20.0,"compact_map_choice":1};report.initial_snapshot=g._snapshot();report.initial_unit_count=g._population(0)
 g.compact_map_choice=1;g.camera_zoom=20.;g._layout_ui();g._select([scout.id]);g.camera_focus=scout.pos
 refresh();await process_frame
 check("shown minimap and HUD at 960x540",g.minimap.is_visible_in_tree() and g.hud_top.visible and g.hud_bottom.visible and root.size==Vector2i(960,540))
 await capture("01-initial")
 var home=scout.pos
 if not await move_to(Vector3(-12,0,12),"v87-scout-waypoint1"):finish();return
 if not await move_to(Vector3(-4,0,5),"v87-scout-waypoint2"):finish();return
 g.camera_focus=scout.pos;await capture("02-scouted")
 var seen_at_front=g.visible_cells[0].duplicate()
 if not await move_to(home,"v87-scout-return"):finish();return
 var lost=0
 for i in seen_at_front.size():
  if seen_at_front[i]!=0 and g.visible_cells[0][i]==0 and g.explored_cells[0][i]!=0:lost+=1
 check("scouting naturally leaves explored-only cells",lost>0,lost)
 var c=counts();check("all three natural fog states exist",c.current>0 and c.explored_only>0 and c.unknown>0,c)
 g.camera_focus=Vector3(-7,0,9);await capture("03-explored-after-return")
 var before=orders();var focus=g.camera_focus;var m=g.minimap;var a=m._area()
 var p=m.global_position+a.position+a.size*Vector2(.20,.70);var q=m.global_position+a.position+a.size*Vector2(.42,.52)
 await touch(7,p,true);var pressed=g.camera_focus
 await drag(7,q,q-p);var dragged=g.camera_focus
 check("actual touch drag owns map and changes camera",not m.pointer.is_empty() and dragged!=pressed and dragged!=focus)
 check("map gesture preserves selection and unit orders",orders()==before)
 report.gestures.append({"press":str(p),"drag":str(q),"camera_before":str(focus),"camera_pressed":str(pressed),"camera_dragged":str(dragged),"orders_before":before,"orders_during":orders()})
 await capture("04-dragging-minimap")
 await touch(7,q,false)
 check("release ends map ownership without orders",m.pointer.is_empty() and orders()==before)
 check("normal camera zoom retained",g.camera_zoom>=15.)
 report.final_state=state();finish()
