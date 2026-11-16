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
 g.paused=false;g.application_focused=true;g.application_suspended=false;g._skip_tutorial();g.camera_zoom=16
 var home=g._first(0,"town_center");home.hp=1000;home.last_damage_tick=-1000
 var tower=g._spawn("tower",0,home.pos+Vector3(8,0,0));tower.hp=400;tower.last_damage_tick=-1000
 var workers=[]
 for w in g.entities:
  if w.team==0 and w.kind=="villager":workers.append(w)
 workers[0].pos=home.pos+Vector3(3,0,0);workers[1].pos=tower.pos+Vector3(2,0,0)
 g._navigation_rebuild();g._update_vision(false);g._publish_faction_views();g.camera_focus=home.pos+Vector3(4,0,0)
 g.compact_menu.show();g.compact_menu_dismiss.show();g._set_shortcut_category("economy");g._refresh_idle_dispatch_buttons();g._layout_ui()
 await process_frame
 g.shortcut_scroll.ensure_control_visible(g.batch_repair_button)
 var ok=await shot(g,"native-economy-batch-repair-action")
 var bank=g.economy.bank_milli(0).wood;g._dispatch_batch_repair()
 var queued=g.commands.size();var ids=[]
 for c in g.commands:
  if c.get("repair_batch",false):ids.append(c.ids[0])
 g._select(ids)
 var ticks=0
 for i in 600:
  g._tick(.05);ticks+=1
  if home.hp>=1020 and tower.hp>=420:break
 ok=(await shot(g,"native-two-workers-paid-building-repairs")) and ok
 var proof={"build":g.Rules.BUILD_ID,"menu_submitted":queued,"distinct_workers":ids.size()==2 and ids[0]!=ids[1],"keep_hp_before":1000,"keep_hp_after":home.hp,"tower_hp_before":400,"tower_hp_after":tower.hp,"wood_before":bank,"wood_after":g.economy.bank_milli(0).wood,"ledger_conserved":g.economy.audit().ok,"ticks":ticks,"rendered":DisplayServer.get_name()!="headless","scope":"Controlled damaged player buildings; actual Economy menu callback assigns two idle workers, ordinary movement and paid repairs. No user saves, fabricated screenshots, natural-match balance or phone acceptance."}
 print(JSON.stringify(proof));g.queue_free();quit(0 if ok and proof.distinct_workers and home.hp>=1020 and tower.hp>=420 and proof.wood_after<bank and proof.ledger_conserved else 1)
