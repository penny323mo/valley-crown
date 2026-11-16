extends SceneTree
const OUT="/tmp/capture/"
func _initialize():call_deferred("run")
func shot(g,name):
 g._update_vision(false);g._publish_faction_views();g._update_visuals(0);g._update_hud();g._layout_ui();g._camera_update()
 await process_frame
 await process_frame
 if DisplayServer.get_name()=="headless":return true
 await RenderingServer.frame_post_draw
 var im=root.get_texture().get_image();var err=im.save_png(OUT+name+".png")
 print("CAPTURE ",name," ",im.get_width(),"x",im.get_height()," ",err)
 return err==OK
func run():
 root.size=Vector2i(640,360)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false);g.ai_enabled=false
 await process_frame
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=15
 var workers=[]
 for w in g.entities:
  if w.team==0 and w.kind=="villager":workers.append(w)
 var bank0=g.economy.bank_milli(0).wood;var sites=[]
 for i in 2:
  var point=Vector3.INF
  for z in range(-7,8):
   for x in range(-7,8):
    var pnt=g._snap_build_position("house",g.MapRoutes.PLAYER_HOME+Vector3(x,0,z))
    if g._placement_reason("house",pnt,0,workers[i].id).is_empty():point=pnt;break
   if point!=Vector3.INF:break
  if point==Vector3.INF:break
  sites.append(g._place_building("house",point,workers[i].id,0))
 if sites.size()!=2:print("NO_TWO_PAID_SITES");g.queue_free();quit(1);return
 var elapsed=0
 for i in 400:
  g._tick(.05);elapsed+=1
  if sites[0].build_ticks>=20 and sites[1].build_ticks>=20:break
 for w in workers:g._set_stance(w,"STOP")
 var progress=[sites[0].build_ticks,sites[1].build_ticks];var bank=g.economy.bank_milli(0).wood
 g._update_vision(false);g._publish_faction_views();g.camera_focus=(sites[0].pos+sites[1].pos)*.5
 g.compact_menu.show();g.compact_menu_dismiss.show();g._set_shortcut_category("economy");g._refresh_idle_dispatch_buttons();g._layout_ui()
 await process_frame
 g.shortcut_scroll.ensure_control_visible(g.batch_construction_button)
 var ok=await shot(g,"native-economy-resume-unattended-sites")
 g._dispatch_batch_construction();var queued=g.commands.size();var ids=[]
 for c in g.commands:
  if c.get("construction_batch",false):ids.append(c.ids[0])
 g._select(ids)
 ok=(await shot(g,"native-original-paid-sites-resume-work")) and ok
 var ticks=elapsed
 for i in 1500:
  g._tick(.05);ticks+=1
  if sites[0].built and sites[1].built:break
 ok=(await shot(g,"native-two-original-houses-completed")) and ok
 var proof={"build":g.Rules.BUILD_ID,"initial_two_site_payment":bank0-bank==100000,"original_progress":progress,"queued_workers":queued,"distinct_workers":ids.size()==2 and ids[0]!=ids[1],"both_completed":sites[0].built and sites[1].built,"wood_before_resume":bank,"wood_after":g.economy.bank_milli(0).wood,"ledger_conserved":g.economy.audit().ok,"ticks":ticks,"rendered":DisplayServer.get_name()!="headless","scope":"Two normally paid player house sites, deliberately stopped workers, actual Economy callback and ordinary physical completion. No user saves, phone/rendering acceptance or all-blocked-site recovery claim."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and proof.initial_two_site_payment and proof.distinct_workers and proof.both_completed and proof.wood_after==bank and proof.ledger_conserved else 1)
