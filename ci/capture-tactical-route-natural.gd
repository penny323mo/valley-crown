extends SceneTree
## Ordinary new woodland game and starting scout. No resource gifts, spawning,
## revealed fog or entity relocation. Camera/selection are presentation only.
var g
var evidence={"scope":"Normal starting scout, ordinary route command; not paid army or completed match","stages":[],"finished":false}
func _initialize():call_deferred("run")
func shot(stage):
 evidence.stages.append({"stage":stage,"tick":g.tick_count})
 if DisplayServer.get_name()=="headless":return
 g._update_hud();g._camera_update()
 for frame in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/capture/route-"+stage+".png")
func run():
 DirAccess.make_dir_recursive_absolute("/tmp/capture")
 root.size=Vector2i(640,360)
 g=load("res://main.tscn").instantiate();g.layout_id="woodland"
 g.history_path="/tmp/route-capture-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame
 var scout=g._first(0,"scout");var origin=scout.pos
 var points=[origin+Vector3(4,0,0),origin+Vector3(6,0,0),origin+Vector3(6,0,3),origin+Vector3(3,0,3),origin+Vector3(3,0,5)]
 g._select([scout.id]);g.camera_focus=origin+Vector3(3,0,1);g.camera_zoom=18
 g._start_tactical_route();g.tactical_draft=points.duplicate();g.tactical_final_advance=true;g.action_key=""
 await shot("plan")
 g._confirm_tactical_route()
 var start=Time.get_ticks_msec();var seen={}
 for i in 1800:
  if Time.get_ticks_msec()-start>225000 or g.game_over:break
  g._tick(g.Rules.TICK)
  if scout.has("tactical_points"):
   var leg=scout.tactical_index
   if not seen.has(leg):
    seen[leg]=true
    evidence.stages.append({"stage":"leg-"+str(leg+1),"tick":g.tick_count})
    if leg==2:await shot("mid-route")
  elif not seen.is_empty():
   evidence.finished=scout.pos.distance_to(points[-1])<1
   await shot("arrival")
   break
 evidence.test_mode=g.test_mode;evidence.history_untouched=not FileAccess.file_exists(g.history_path)
 evidence.audit=g.economy.audit();evidence.ticks=g.tick_count;evidence.visited=seen.keys()
 var output=FileAccess.open("/tmp/capture/tactical-route-proof.json",FileAccess.WRITE);output.store_string(JSON.stringify(evidence));output.close()
 print(JSON.stringify(evidence));quit(0 if evidence.finished and evidence.history_untouched else 1)
