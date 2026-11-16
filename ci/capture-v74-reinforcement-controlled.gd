extends SceneTree
## CONTROLLED mechanism demonstration. Fixture troops and revealed view, not paid natural play.
var g
var checks=[]
var shots=[]
var title
func _initialize():call_deferred("run")
func check(n,v):
 checks.append({"name":n,"passed":bool(v)})
 if not v:push_error(n)
func reveal():
 for team in [0,1]:
  g.visible_cells[team].fill(1);g.explored_cells[team].fill(1)
 g._publish_faction_views()
func records():
 var result=g.faction_views[1].records().values().duplicate(true)
 for r in result:
  if r.team==0 and r.kind=="town_center":r.remembered=true
 return result
func shot(label):
 title.text="CONTROLLED · "+label+"\nFixture troops + revealed view. NOT paid natural play."
 reveal();g._select([]);g.camera_focus=Vector3(19,0,-20) if shots.size()>=2 else Vector3(26,0,-23);g.camera_zoom=18
 g._camera_update();g._update_visuals(.016);g._refresh_fog();g._update_hud()
 if DisplayServer.get_name()=="headless":
  shots.append({"phase":label,"rendered":false,"tick":g.tick_count});return
 await process_frame
 await RenderingServer.frame_post_draw
 var path="/tmp/capture/controlled-"+str(shots.size()+1)+".png"
 var err=root.get_texture().get_image().save_png(path)
 shots.append({"phase":label,"rendered":err==OK,"path":path,"tick":g.tick_count})
func run():
 root.size=Vector2i(640,360);DirAccess.make_dir_recursive_absolute("/tmp/capture")
 g=load("res://main.tscn").instantiate();g.skirmish_mode="standard"
 g.history_path="/tmp/controlled-reinforcement-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
 await process_frame
 var overlay=CanvasLayer.new();overlay.layer=100;root.add_child(overlay)
 var panel=PanelContainer.new();panel.position=Vector2(8,46);panel.size=Vector2(624,49);overlay.add_child(panel)
 title=Label.new();title.add_theme_font_size_override("font_size",14);panel.add_child(title)
 var home=g._first(1,"town_center")
 var old=g._spawn("archer",1,Vector3(10,0,-8))
 g._update_vision()
 var units=[]
 for x in range(20,31):
  for z in range(-29,-18):
   var p=Vector3(x+0.5,0,z+0.5)
   if units.size()>=4:break
   if g._attack_distance(p,home)>3 or g.navigation.is_point_solid(g._cell(p)) or g._route_grid({"team":1,"radius":g.Rules.UNIT_RADII.cavalry}).is_point_solid(g._cell(p)):continue
   if g.entities.any(func(e):return e.alive and e.category=="unit" and e.pos.distance_to(p)<1.7):continue
   units.append(g._spawn("cavalry",1,p))
 check("four fixture reserves use unblocked home ground",units.size()==4)
 var fifth=g._spawn("cavalry",1,Vector3(32,0,-24));units.append(fifth)
 var origin=fifth.pos
 reveal()
 var keep=g.faction_views[1].records()[g._first(0,"town_center").id].duplicate(true);keep.remembered=true
 g.ai_raid_members=[old.id];g.ai_raid_departure_count=1;g.ai_raid_keep=keep.duplicate(true);g.ai_last_raid_tick=-1800
 var bank=g.economy.bank_milli(1).duplicate()
 g.commands.clear();g._ai_army(records(),g.faction_views[1].records()[home.id])
 check("four home reserves wait for fifth",g.ai_raid_members==[old.id])
 check("fifth receives ordinary home movement",g.commands.any(func(c):return c.type=="order" and fifth.id in c.get("ids",[])))
 await shot("1 / Four waiting; fifth returns")
 var steps=0
 while steps<600:
  g._tick(g.Rules.TICK);steps+=1
  if fifth.state=="idle" and g._attack_distance(fifth.pos,home)<=3:break
 check("fifth physically moves into home muster",fifth.pos.distance_to(origin)>1 and fifth.state=="idle" and g._attack_distance(fifth.pos,home)<=3)
 check("old frontline member remains alive",old.alive and old.id in g.ai_raid_members)
 await shot("2 / Fifth arrives through normal movement")
 reveal();g.commands.clear()
 g._ai_army(records(),g.faction_views[1].records()[home.id])
 var ids=units.map(func(e):return e.id)
 var orders=g.commands.filter(func(c):return c.type=="order" and c.get("ids",[]).size()==5)
 check("one normal five-unit reinforcement order",orders.size()==1 and orders[0].ids==ids)
 check("old member retained with all five reinforcements",g.ai_raid_members.size()==6 and old.id in g.ai_raid_members and ids.all(func(id):return id in g.ai_raid_members))
 var positions=units.map(func(e):return e.pos)
 var moved=0;var depart_steps=0
 while depart_steps<400 and moved<5:
  g._tick(g.Rules.TICK);depart_steps+=1;moved=0
  for i in units.size():
   if units[i].pos.distance_to(positions[i])>.3:moved+=1
 check("batch physically departs through normal ticks",moved==5)
 if moved==5:
  for i in 30:g._tick(g.Rules.TICK);depart_steps+=1
 check("fixture demonstration grants no resources",g.economy.bank_milli(1)==bank and g.economy.audit().ok)
 check("isolated history remains unwritten",g.test_mode and not FileAccess.file_exists(g.history_path))
 await shot("3 / Five-unit reinforcement departs")
 var result={"suite":"CONTROLLED_reinforcement_capture","build":g.Rules.BUILD_ID,"scope":"Fixture troops and AI state arranged; both factions explicitly revealed. NOT paid natural game or fog validation.","controlled":true,"reveal":true,"paid_recruitment":false,"checks":checks,"shots":shots,"batch_ids":ids,"old_frontline_id":old.id,"fifth_start":origin,"fifth_arrival":positions[4],"movement_ticks":steps,"moved_count":moved,"departure_motion_ticks":depart_steps,"final_positions":units.map(func(e):return {"id":e.id,"position":e.pos,"state":e.state,"path_status":e.path_status,"path_reason":e.path_reason}),"departure_order":orders,"all_passed":checks.all(func(c):return c.passed)}
 var f=FileAccess.open("/tmp/capture/controlled-reinforcement-proof.json",FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "));f.close()
 print(JSON.stringify(result));var ok=result.all_passed;g.free();quit(0 if ok else 1)
