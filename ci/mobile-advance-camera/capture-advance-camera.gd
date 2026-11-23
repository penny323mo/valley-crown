extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var observations={}
var g
var menu
var serial=0
var began=0
var first_seen={}
var first_hit={}
var first_opponent_hit={}
var mode="standard"
var pan_notice_timing={}
var out=""
var capture_role=""
var metadata_only=false
var info={}
var captured=[]
var park_after_launch=false
const OPENING_TICK=9
const ORIGINAL_TOAST="警戒前進：點目的地；射程內迎擊，敵軍離開後繼續，不追擊。"
const CANCEL_TOAST="警戒前進已取消。請重選。"

func _initialize():
	began=Time.get_ticks_msec()
	print("VC_CAPTURE_BOOT advance_camera")
	call_deferred("run")
func ck(n,v):
	checks.append({"name":n,"pass":bool(v)})
	if not v:push_error(n)
	return bool(v)
func note(key,fields):
	observations[key]=fields
	print("JOURNEY_NOTE ",key," ",JSON.stringify(fields))
func frames(n=4):
	for i in n:await process_frame
func sync_ui():
	g._process(0);g._update_hud();g._layout_ui()
	await frames()
func bank():return g.economy.bank_milli(0).duplicate(true)
func cost_exact(before,after,kind):
	for k in before:
		if after[k]!=before[k]-1000*Rules.COSTS[kind].get(k,0):return false
	return true
func tap(p):
	serial+=1
	for down in [true,false]:
		var e=InputEventScreenTouch.new();e.index=0;e.position=p;e.pressed=down;root.push_input(e)
		park_launch_if_ready()
		await process_frame
		park_launch_if_ready()
	await frames()
func drag(p,q):
	serial+=1
	var t=InputEventScreenTouch.new();t.index=0;t.pressed=true;t.position=p;root.push_input(t)
	await process_frame
	var d=InputEventScreenDrag.new();d.index=0;d.position=q;d.relative=q-p;root.push_input(d)
	await process_frame
	t=InputEventScreenTouch.new();t.index=0;t.pressed=false;t.position=q;root.push_input(t)
	await frames()
func touch_event(i,p,down):
	var e=InputEventScreenTouch.new();e.index=i;e.position=p;e.pressed=down;root.push_input(e)
func shape(r):return [r.position.x,r.position.y,r.size.x,r.size.y]
func phone_rect():return Rect2(Vector2.ZERO,root.get_visible_rect().size)
func reachable(button,lane,include_disabled=false):
	if not is_instance_valid(button) or not button.is_visible_in_tree() or (button.disabled and not include_disabled):return false
	var r=button.get_global_rect()
	return r.size.x>=44 and r.size.y>=44 and phone_rect().encloses(r) and lane.get_global_rect().encloses(r)
func menu_reaches(b):
	var r=b.get_global_rect()
	return b.is_visible_in_tree() and not b.disabled and phone_rect().encloses(r) and (not menu.scroll.is_ancestor_of(b) or menu.scroll.get_global_rect().encloses(r))
func menu_click(name):
	var b=menu.find_child(name,true,false)
	if b==null:return false
	for i in 8:
		if menu_reaches(b):break
		var r=menu.scroll.get_global_rect()
		var dir=-1 if b.get_global_rect().position.y>r.position.y else 1
		var segment=minf(r.size.y*.45,180)
		await drag(r.get_center()-Vector2(0,dir*segment*.55),r.get_center()+Vector2(0,dir*segment*.45))
	if not menu_reaches(b):
		note("menu_clip",{"name":name,"button":shape(b.get_global_rect()),"scroll":shape(menu.scroll.get_global_rect()),"visible":b.is_visible_in_tree(),"phone":shape(phone_rect())})
		return ck("menu button clipped: "+name,false)
	park_after_launch=name=="LaunchMatchButton"
	await tap(b.get_global_rect().get_center())
	park_after_launch=false
	return true
func park_launch_if_ready():
	if park_after_launch and is_instance_valid(menu.match_node):menu.match_node.set_process(false)
func at_target(screen,id):
	var winner=g._pick(screen,true)
	return g._box_point_in_world(screen) and g._friendly_unit_pick(screen,winner)==id
func point_for(ent):
	var world=g.camera.unproject_position(ent.pos+Vector3(0,.60 if ent.category=="unit" else 1.0,0))
	if at_target(world,ent.id):return world
	for radius in [5,10,15,20,25,30]:
		for i in 12:
			var p=world+radius*Vector2.RIGHT.rotated(i*TAU/12)
			if at_target(p,ent.id):return p
	return Vector2.INF
func action(kind,meta="command_icon_kind"):
	for b in g.actions.get_children():
		if b is Button and b.has_meta(meta) and b.get_meta(meta)==kind:return b
	return null
func swipes_for(b):
	var swipes=0
	while swipes<8 and not reachable(b,g.action_scroll):
		var r=g.action_scroll.get_global_rect()
		var dir=-1 if b.get_global_rect().end.x>r.end.x else 1
		var excess=b.get_global_rect().end.x-r.end.x if dir==-1 else r.position.x-b.get_global_rect().position.x
		var length=minf(maxf(18,ceilf(excess)+4),minf(180,r.size.x*.64))
		await drag(r.get_center()-Vector2(dir*length*.5,0),r.get_center()+Vector2(dir*length*.5,0))
		await sync_ui()
		swipes+=1
	return swipes if reachable(b,g.action_scroll) else -1
func ticks_until(predicate,max_steps):
	var i=0
	while i<max_steps and not predicate.call() and not g.game_over and not g.paused:
		g._process(Rules.TICK);i+=1
		observe_contact()
	if i>0:await sync_ui()
	return i
func pure_action(before,seq,cam):
	return bank()==before and g.command_sequence==seq and g.camera.global_transform==cam and g.all_touch_ids.is_empty()
func grab_some_wood():
	var workers=g.entities.filter(func(e):return e.alive and e.team==0 and e.kind=="villager")
	var trees=g.faction_views[0].records().values().filter(func(e):return e.alive and e.kind in ["pine","oak"] and not e.remembered and point_for(e).is_finite())
	if not ck("opening contains visible tap-resolvable owned workers and trees",workers.size()==5 and trees.size()>0):return []
	var assigned=[]
	for worker in workers:
		if assigned.size()>=3:break
		var p=point_for(worker)
		if not p.is_finite():continue
		var closest=trees.duplicate()
		closest.sort_custom(func(a,b):return a.pos.distance_squared_to(worker.pos)<b.pos.distance_squared_to(worker.pos))
		if assigned.size()>=closest.size():break
		var tree=closest[assigned.size()]
		var t=point_for(tree)
		if not t.is_finite():continue
		await tap(p);await sync_ui()
		if not ck("real world touch selected working villager "+str(worker.id),g.selected==[worker.id]):return []
		await tap(t)
		if not ck("real tree touch queued one ordinary gather order for "+str(worker.id),g.commands.size()==1 and g.commands[0].type=="order" and g.commands[0].target==tree.id and g.commands[0].ids==[worker.id]):return []
		g._process(Rules.TICK)
		if not ck("ordinary work authority accepted gather "+str(worker.id),worker.state=="gather" and worker.target==tree.id):return []
		assigned.append(worker.id)
	return assigned
func build_and_train(kind,product=""):
	var worker={}
	for w in g.entities:
		if w.alive and w.team==0 and w.kind=="villager" and w.state=="idle" and point_for(w).is_finite():worker=w;break
	if worker.is_empty():
		for w in g.entities:
			if w.alive and w.team==0 and w.kind=="villager" and point_for(w).is_finite():worker=w;break
	if not ck(kind+" visible builder tappable in unchanged opening camera",not worker.is_empty()):return {}
	await tap(point_for(worker));await sync_ui()
	if not ck(kind+" actual world selection of builder",g.selected==[worker.id]):return {}
	var b=action(kind)
	if not ck(kind+" build action exists, no direct authority API",is_instance_valid(b)):return {}
	var row=[]
	for child in g.actions.get_children():
		if child is Button and child.visible:
			var r=child.get_global_rect().intersection(g.action_scroll.get_global_rect()).intersection(phone_rect())
			row.append({"label":child.text,"button":shape(child.get_global_rect()),"visible_width":r.size.x})
	var lane=g.action_scroll.get_global_rect()
	var initial=bank();var seq=g.command_sequence;var cam=g.camera.global_transform
	var motions=await swipes_for(b)
	note(kind+"_build_discovery",{"lane":shape(lane),"visible_before":row,"swipes_at_most_180px":motions,"scroll_after":g.action_scroll.scroll_horizontal})
	if not ck(kind+" reached by actual strip swipe without world order, movement or debit",motions>=0 and pure_action(initial,seq,cam)):return {}
	await tap(b.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" build touch opens unpaid placement mode",g.build_mode==kind and pure_action(initial,seq,cam) and reachable(g.build_confirm,g.action_scroll,true)):return {}
	var plot=Vector3.INF;var distance=INF
	for x in range(-28,-6):
		for z in range(14,35):
			var cell=g._snap_build_position(kind,Vector3(x,0,z))
			var s=g.camera.unproject_position(cell)
			if not g._box_point_in_world(s) or not g._placement_reason(kind,cell,0,worker.id).is_empty():continue
			var d=worker.pos.distance_squared_to(cell)
			if d<distance:distance=d;plot=cell
	if kind=="range" and root.size==Vector2i(568,320):
		var count=0;var best=0;var bounds=[]
		for y in root.size.y:
			if g._box_point_in_world(Vector2(284,y)):
				count+=1;best=maxi(best,count);bounds.append(y)
			else:count=0
		var f=g.queue_label.get_theme_font("font")
		var measured=f.get_string_size(g.queue_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,g.queue_label.get_theme_font_size("font_size")).x
		var cancel=g.actions.get_children().filter(func(c):return c is Button and c.text=="取消建造")[0]
		note("range_direct_price",{"consecutive_world_rows":best,"screen_anchor":str(g.camera.unproject_position(plot)) if plot.is_finite() else "none","price_width":g.queue_label.size.x,"measured_price_width":measured,"price":g.queue_label.text,"hud_bottom":shape(g.hud_bottom.get_global_rect()),"notice":shape(g.tutorial_panel.get_global_rect()),"actual_camera":str(g.camera_focus),"world_rows":bounds})
		if not ck("direct 568 Range offers 64+ world rows and uncropped normal price and both controls",best>=64 and g.queue_label.text=="木 120" and g.queue_label.size.x>=measured and reachable(g.build_confirm,g.action_scroll,true) and reachable(cancel,g.action_scroll)):return {}
		if not ck("direct 568 plot without any cancel or camera workaround",plot.is_finite() and g.camera_focus==g.MapRoutes.PLAYER_HOME):return {}
	if not ck(kind+" legal on-screen plot available by ordinary input",plot.is_finite()):return {}
	cam=g.camera.global_transform
	await tap(g.camera.unproject_position(plot));await sync_ui()
	if not ck(kind+" actual world preview is unpaid, held and legal",g.build_preview_held and not g.build_confirm.disabled and pure_action(initial,seq,cam)):return {}
	await tap(g.build_confirm.get_global_rect().get_center())
	if not ck(kind+" actual confirm commits only one matching build command",g.commands.size()==1 and g.commands[0].type=="build" and g.commands[0].kind==kind and g.command_sequence==seq+1):return {}
	g._process(Rules.TICK);await sync_ui()
	var site=g._first(0,kind)
	if not ck(kind+" single real paid construction exists with exact changed bank",not site.is_empty() and not site.built and cost_exact(initial,bank(),kind)):return {}
	var before_complete=g.tick_count
	var construction_steps=0
	construction_steps+=await ticks_until(func():return site.built,1600)
	if not ck(kind+" worker travelled and built using standard gameplay without grants",site.alive and site.built and construction_steps>=int(Rules.BUILD_TIME[kind]/Rules.TICK)-1):return {}
	if product.is_empty():return site
	var anchor=g.camera.unproject_position(site.pos+Vector3.UP)
	var p=point_for(site)
	var focus_before=g.selected.duplicate()
	note(kind+"_completion_handoff",{"placement_world":str(plot),"construct_tick":before_complete,"complete_tick":g.tick_count,"selected_ids_on_completion":focus_before,"builder_id":worker.id,"building_id":site.id,"anchor":str(anchor),"anchor_world":g._box_point_in_world(anchor),"anchor_picks_site":at_target(anchor,site.id),"point":str(p),"toast":g.toast_label.text if g.toast_time>0 else "","toast_panel":g.tutorial_panel.visible,"toast_panel_rect":shape(g.tutorial_panel.get_global_rect()),"tick":g.tick_count})
	if not g._box_point_in_world(anchor):
		var anchor_seq=g.command_sequence;var anchor_bank=bank()
		await tap(anchor);await sync_ui()
		note(kind+"_blocked_center_touch",{"anchor":str(anchor),"stored_input_world":g._box_point_in_world(anchor),"same_builder_still_selected":g.selected==focus_before,"same_sequence":g.command_sequence==anchor_seq,"no_payment":bank()==anchor_bank})
	if not ck(kind+" completed building selectable by actual world touch",p.is_finite()):return {}
	var select_seq=g.command_sequence;var select_bank=bank()
	var controls_camera=g.camera.global_transform
	var feedback=g.tutorial_panel.get_global_rect()
	var feedback_body=Vector2(feedback.position.x+16,feedback.get_center().y)
	await tap(feedback_body);await sync_ui()
	if not ck(kind+" passive notice background still shields ground with builder selected",g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var detail=g.guidance_detail_button
	if not ck(kind+" active notice Details target remains 44+ and within its panel",reachable(detail,g.tutorial_panel)):return {}
	await tap(detail.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" active detail opens as GUI, never as a world order",g.context_details.is_visible_in_tree() and g.context_detail_kind=="guidance" and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var modal=g.context_details.get_global_rect()
	var under_detail=modal.get_center()
	await tap(under_detail);await sync_ui()
	if not ck(kind+" modal content continues to shield the world",g.context_details.is_visible_in_tree() and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	var close=g.find_child("CloseBattleDetails",true,false)
	await tap(close.get_global_rect().get_center());await sync_ui()
	if not ck(kind+" closing actual modal leaves builder and world unchanged",not g.context_details.visible and g.selected==focus_before and pure_action(select_bank,select_seq,controls_camera)):return {}
	await tap(p);await sync_ui()
	note(kind+"_reselected",{"selected":g.selected,"expected":site.id,"command_delta":g.command_sequence-select_seq,"bank_equal":bank()==select_bank})
	if not ck(kind+" completed target genuinely selected without orders",g.selected==[site.id] and g.command_sequence==select_seq and bank()==select_bank):return {}
	var train=action(true,"primary_train")
	var action_visible=reachable(train,g.action_scroll)
	note(kind+"_first_training",{"lane":shape(g.action_scroll.get_global_rect()),"train_button":shape(train.get_global_rect()) if is_instance_valid(train) else [],"initial_full_44":action_visible,"initial_scroll":g.action_scroll.scroll_horizontal,"label":train.text if is_instance_valid(train) else ""})
	if not ck(kind+" first train exists and reached through actual UI",is_instance_valid(train) and await swipes_for(train)>=0):return {}
	var prior=bank();var pop=g._population(0);var n=g._count(0,product);var start=g.tick_count
	await tap(train.get_global_rect().get_center())
	if not ck(product+" actual train click sends only one ordinary order",g.commands.size()==1 and g.commands[0].type=="train" and g.commands[0].kind==product and g.commands[0].building==site.id):return {}
	g._process(Rules.TICK);await sync_ui()
	if not ck(product+" exact real price debited once and slot reserved",cost_exact(prior,bank(),product) and site.queue.size()==1 and site.queue[0].kind==product and g._population(0)==pop+1):return {}
	await ticks_until(func():return g._count(0,product)==n+1,Rules.TRAIN_TICKS[product]+140)
	if not ck(product+" natural real training time and exactly one newborn",g._count(0,product)==n+1 and g.tick_count-start>=Rules.TRAIN_TICKS[product] and site.queue.is_empty()):return {}
	var unit=g._first(0,product)
	var newborn_anchor=g.camera.unproject_position(unit.pos+Vector3(0,.60,0))
	var infant_point=point_for(unit)
	note(product+"_first_birth",{"tick":g.tick_count,"selected_producer_kept":g.selected==[site.id],"screen":str(newborn_anchor),"anchor_world":g._box_point_in_world(newborn_anchor),"anchor_picks_unit":at_target(newborn_anchor,unit.id),"tap_target":str(infant_point),"toast":g.toast_label.text if g.toast_time>0 else "","hud_summary":g.selection_summary.text,"queue_summary":g.queue_label.text,"builder_state":worker.state})
	return site
func ordinary_open_ground():
	for y in range(146,217,5):
		for x in range(70,500,9):
			var p=Vector2(x,y)
			if not g._box_point_in_world(p) or g._pick(p,true)>=0:continue
			var cell=g._cell(g._world_at(p))
			if g.work_memory[0].grid.region.has_point(cell) and not g.work_memory[0].grid.is_point_solid(cell) and g.visible_cells[0][g._cell_index(g._world_at(p))]!=0:return p
	return Vector2.INF
func own_pending():return g.commands.filter(func(c):return c.team==0)

func hostiles():
	return g.faction_views[0].records().values().filter(func(e):return e.get("team",-1)==1 and e.get("alive",false) and not e.get("remembered",true) and e.get("category","")=="unit")
func event_record(e):
	var a=g._get_entity(e.attacker_id);var t=g._get_entity(e.target_id)
	return {"tick":g.tick_count,"id":e.get("id",-1),"attacker":e.attacker_id,"attacker_team":a.get("team",-2),"attacker_kind":a.get("kind",""),"target":e.target_id,"target_team":t.get("team",-2),"target_kind":t.get("kind",""),"damage":e.damage}
func observe_contact():
	if first_seen.is_empty() and g.tick_count%4==0:
		var enemies=hostiles()
		if not enemies.is_empty():
			var e=enemies[0];var projection=g.camera.unproject_position(e.pos+Vector3(0,.6,0))
			first_seen={"tick":g.tick_count,"world":str(e.pos),"screen":str(projection),"in_world_input":g._box_point_in_world(projection),"kind":e.kind,"actor":e.id}
			note("first_confirmed_player_visible_enemy",first_seen)
	if not first_hit.is_empty() and not first_opponent_hit.is_empty():return
	var end=g.attack_ledger._settled_through
	if end<=0:return
	for aid in range(1,end+1):
		var e=g.attack_ledger.event(aid);var a=g._get_entity(e.attacker_id);var t=g._get_entity(e.target_id)
		if first_hit.is_empty() and a.get("team",-2)==0 and t.get("team",-2)==1:
			first_hit=event_record(e);note("first_actual_player_combat",first_hit)
		if first_opponent_hit.is_empty() and a.get("team",-2)==1 and t.get("team",-2)==0:
			first_opponent_hit=event_record(e);note("first_actual_incoming_combat",first_opponent_hit)
		if not first_hit.is_empty() and not first_opponent_hit.is_empty():break
func world_target(e,radius=34):
	var anchor=g.camera.unproject_position(e.pos+Vector3(0,.6,0))
	if at_target(anchor,e.id):return anchor
	for r in range(4,radius+1,4):
		for i in 16:
			var p=anchor+Vector2.RIGHT.rotated(TAU*float(i)/16)*r
			if at_target(p,e.id):return p
	return Vector2.INF
func paid_group_only():
	var spear=g._first(0,"spearman");var archer=g._first(0,"archer")
	if spear.is_empty() or archer.is_empty():return false
	var ids=[spear.id,archer.id];ids.sort()
	var a=g.camera.unproject_position(spear.pos+Vector3(0,.6,0));var b=g.camera.unproject_position(archer.pos+Vector3(0,.6,0))
	var lo=Vector2(minf(a.x,b.x),minf(a.y,b.y))-Vector2(6,5)
	var hi=Vector2(maxf(a.x,b.x),maxf(a.y,b.y))+Vector2(7,6)
	if not g._box_point_in_world(lo) or not g._box_point_in_world(hi):return false
	var seq=g.command_sequence;var money=bank()
	await drag(lo,hi);await sync_ui()
	var f=g.actions.get_node_or_null("FilterSelectedMilitary")
	if reachable(f,g.action_scroll):await tap(f.get_global_rect().get_center());await sync_ui()
	var selected=g.selected.duplicate();selected.sort()
	return selected==ids and g.command_sequence==seq and bank()==money

func first_defense():
	var started=g.tick_count
	var grouped=await paid_group_only()
	if not ck("paid first Spearman/Archer actually grouped from existing touch controls",grouped):return
	var ids=g.selected.duplicate()
	var alert_at={}
	for i in 3800:
		var a=g.battle_alerts.peek(g.tick_count)
		if not a.is_empty():alert_at=a;break
		if g.game_over or g.paused:break
		g._process(Rules.TICK);observe_contact()
	await sync_ui()
	note("defense_opening_arrival",{"started":started,"final_tick":g.tick_count,"incoming":first_opponent_hit,"first_visible":first_seen,"alert":alert_at,"ai_raids":g.ai_raids,"selected":ids,"status":g.outcome})
	if not ck("ordinary AI contact generated own-location alert without fixture combat",not alert_at.is_empty() and not first_opponent_hit.is_empty()):return
	var b=g.battle_jump_button
	var r=b.get_global_rect();var expected_pos=alert_at.position
	var money=bank();var seq=g.command_sequence;var before=g.camera_focus
	if not ck("first Hit alert is fully visible 44px action, not overlapping pause or menu",b.is_visible_in_tree() and not b.disabled and phone_rect().encloses(r) and r.size.x>=44 and r.size.y>=44 and not r.intersects(g.pause_button.get_global_rect()) and not r.intersects(g.compact_menu_button.get_global_rect())):return
	note("first_alert_ui",{"alert":shape(r),"target_world":str(expected_pos),"old_camera":str(before),"selected":ids,"top":shape(g.hud_top.get_global_rect()),"alert_text":b.text,"tutorial_entry_visible":g.tutorial_entry.visible})
	await tap(r.get_center());await sync_ui()
	if not ck("one real alert tap focuses attacked asset without changing army orders or bank",g.camera_focus==expected_pos and g.selected==ids and g.command_sequence==seq and bank()==money):return
	var enemies=hostiles()
	enemies.sort_custom(func(a,b):return a.pos.distance_squared_to(expected_pos)<b.pos.distance_squared_to(expected_pos))
	var enemy={}
	var epoint=Vector2.INF
	var candidates=[]
	for e in enemies:
		var projection=g.camera.unproject_position(e.pos+Vector3(0,.6,0))
		var p=world_target(e)
		candidates.append({"id":e.id,"kind":e.kind,"center":str(projection),"center_valid":at_target(projection,e.id),"hit":str(p),"distance_from_attacked":expected_pos.distance_to(e.pos)})
		if enemy.is_empty() and p.is_finite():enemy=e;epoint=p
	note("after_alert_targets",{"known_hostiles":candidates,"selected":ids,"camera":str(g.camera_focus),"top":shape(g.hud_top.get_global_rect()),"bottom":shape(g.hud_bottom.get_global_rect()),"tutorial":shape(g.tutorial_panel.get_global_rect()) if g.tutorial_panel.visible else []})
	if not ck("at least one naturally visible enemy has real touchable panel-free region",not enemy.is_empty()):return
	var exact_anchor=g.camera.unproject_position(enemy.pos+Vector3(0,.6,0))
	await tap(epoint)
	var orders=g.commands.filter(func(c):return c.team==0)
	if not ck("actual touch sends exactly one attack-intent order only for selected paid troops",orders.size()==1 and orders[0].type=="order" and orders[0].ids==ids and orders[0].target==enemy.id and bank()==money):return
	var first_event=int(g.attack_ledger._settled_through)
	var answer={}
	for i in 900:
		g._process(Rules.TICK);observe_contact()
		for aid in range(first_event+1,g.attack_ledger._settled_through+1):
			var e=g.attack_ledger.event(aid)
			if e.attacker_id in ids and g._get_entity(e.target_id).get("team",-2)==1:answer=event_record(e);break
		if not answer.is_empty() or g.paused or g.game_over:break
	note("defense_authority",{"enemy":enemy.kind,"id":enemy.id,"target_tap":str(epoint),"center":str(exact_anchor),"distance_from_center":epoint.distance_to(exact_anchor),"own_hit":answer,"selected":ids,"elapsed_battle_tick":g.tick_count})
	ck("at least one of the paid troops inflicted actual settled ordinary combat damage",not answer.is_empty())

func pair_pan():
	var centers=[]
	var delta=Vector2(32,0)
	for y in range(128,210,8):
		if not centers.is_empty():break
		for x in range(154,400,15):
			var a=Vector2(x,y);var b=a+Vector2(82,0)
			if [a,b,a+delta,b+delta].all(g._box_point_in_world):centers=[a,b];break
	if centers.is_empty():return []
	serial+=1
	touch_event(0,centers[0],true);await process_frame
	touch_event(1,centers[1],true);await process_frame
	for i in 8:
		for j in 2:
			var e=InputEventScreenDrag.new()
			e.index=j;e.relative=Vector2(4,0);e.position=centers[j]+Vector2(4*(i+1),0)
			root.push_input(e)
		await process_frame
	touch_event(0,centers[0]+delta,false);await process_frame
	var stamp=Time.get_ticks_usec()
	var before_text=g.toast_label.text
	touch_event(1,centers[1]+delta,false)
	pan_notice_timing={"before_final_lift":before_text,"first_sync_after_lift":g.toast_label.text,"elapsed_dispatch_usec":Time.get_ticks_usec()-stamp,"visible_after_lift":g.toast_label.is_visible_in_tree(),"sim_tick":g.tick_count}
	await sync_ui()
	return [str(centers[0]),str(centers[1]),str(delta)]
func route_snapshot():
	return {"mode":g.touch_command,"kind":g.unit_command_kind,"rally_building":g.rally_building,"rally_group":g.rally_group.duplicate(),"camera":str(g.camera_focus),"zoom":g.camera_zoom,"toast":g.toast_label.text if g.toast_time>0 else "","toast_visible":g.toast_label.is_visible_in_tree(),"selected":g.selected.duplicate(),"commands":g.command_sequence,"bank":bank()}

func checkpoint(stage,details={}):
	var line=JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec()-began,"details":details})
	print("VC_CAPTURE_PROGRESS "+line)
	if out.is_empty() or not DirAccess.dir_exists_absolute(out):return
	var path=out+"/progress.jsonl"
	var f=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f!=null:f.seek_end();f.store_line(line);f.flush();f.close()
func real_frame(name,fields):
	var state=fields.duplicate(true);state.name=name
	checkpoint("state_ready",{"state":name,"band":fields.get("tick",-1)})
	if not metadata_only:
		var draws=[0]
		var observer=func():draws[0]+=1
		RenderingServer.frame_post_draw.connect(observer)
		var start=Time.get_ticks_msec()
		checkpoint("draw_begin",{"state":name,"needed":2,"deadline_ms":45000})
		RenderingServer.render_loop_enabled=true
		while draws[0]<2 and Time.get_ticks_msec()-start<45000:await process_frame
		RenderingServer.render_loop_enabled=false
		RenderingServer.frame_post_draw.disconnect(observer)
		checkpoint("draw_end",{"state":name,"draws":draws[0],"ms":Time.get_ticks_msec()-start})
		if not ck(name+" two actual renderer frame completions",draws[0]>=2):return false
		checkpoint("readback_begin",{"state":name})
		var img=root.get_texture().get_image()
		checkpoint("readback_end",{"state":name,"valid":img!=null})
		if not ck(name+" actual native image dimensions",img!=null and not img.is_empty() and img.get_size()==Vector2i(568,320)):return false
		var palette={}
		for y in range(0,320,13):
			for x in range(0,568,13):palette[img.get_pixel(x,y).to_rgba32()]=true
		if not ck(name+" real native unmodified view is nonblank",palette.size()>24):return false
		state.file=name+".png"
		var path=out+"/"+state.file
		if not ck(name+" native PNG saved",img.save_png(path)==OK):return false
		state.sha256=FileAccess.get_sha256(path)
		checkpoint("png_saved",{"state":name,"sha256":state.sha256})
	captured.append(state)
	return true

func screenshot_fields(snap,gesture):
	var fields=snap.duplicate(true)
	fields.tick=g.tick_count
	fields.map=g.layout_id
	fields.gesture=gesture
	fields.camera_transform=str(g.camera.global_transform)
	fields.troops=g.selected.map(func(id):return {"id":id,"kind":g._get_entity(id).kind,"pos":str(g._get_entity(id).pos)})
	fields.defense=observations.defense_authority
	fields.label_rect=shape(g.toast_label.get_global_rect())
	fields.panel_rect=shape(g.tutorial_panel.get_global_rect())
	var font=g.toast_label.get_theme_font("font")
	fields.text_px=font.get_string_size(g.toast_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,g.toast_label.get_theme_font_size("font_size")).x
	return fields

func verify_and_capture():
	if not ck("post-defense only after paid troops' ordinary combat damage",observations.has("defense_authority") and not observations.defense_authority.own_hit.is_empty()):return
	var adv=g.actions.get_node_or_null("PrimaryTacticalAdvance")
	if not ck("existing fully reachable Advance button for the actual paid troops",reachable(adv,g.action_scroll) and g.selected.size()==2 and own_pending().is_empty()):return
	var original=route_snapshot()
	await tap(adv.get_global_rect().get_center());await sync_ui()
	var armed=route_snapshot()
	if not ck("real Advance tap arms the same original instruction without order or debit",armed.mode and armed.kind=="advance" and armed.toast_visible and armed.toast==ORIGINAL_TOAST and armed.bank==original.bank and armed.commands==original.commands):return
	var gesture=await pair_pan()
	var after=route_snapshot()
	if not ck("both fingers lifted after genuine constant-span pan, with no command or debit",not gesture.is_empty() and after.camera!=armed.camera and after.zoom==armed.zoom and after.commands==armed.commands and after.selected==armed.selected and after.bank==armed.bank and g.all_touch_ids.is_empty() and own_pending().is_empty()):return
	var expected=ORIGINAL_TOAST if capture_role=="baseline" else CANCEL_TOAST
	if not ck("actual visible expected prompt after entire pair ends and before any target",not after.mode and after.toast_visible and g.tutorial_panel.is_visible_in_tree() and after.toast==expected and pan_notice_timing.before_final_lift==ORIGINAL_TOAST and pan_notice_timing.first_sync_after_lift==expected):return
	var fields=screenshot_fields(after,gesture)
	fields.camera_before=armed.camera
	fields.partial_lift_text=pan_notice_timing.before_final_lift
	if not ck("whole post-pan prompt fits actual visible viewport label",phone_rect().encloses(g.toast_label.get_global_rect()) and fields.text_px<=g.toast_label.size.x):return
	var name="before-stale-after-pan" if capture_role=="baseline" else "after-cancel-after-pan"
	if not await real_frame(name,fields):return
	if capture_role=="baseline":return
	adv=g.actions.get_node_or_null("PrimaryTacticalAdvance")
	if not ck("same first-page Advance button reachable without scrolling",reachable(adv,g.action_scroll) and g.action_scroll.scroll_horizontal==0):return
	await tap(adv.get_global_rect().get_center());await sync_ui()
	var rearmed=route_snapshot()
	if not ck("one actual rearm restores accurate instruction without target, order, debit, or camera change",rearmed.mode and rearmed.kind=="advance" and rearmed.camera==after.camera and rearmed.zoom==after.zoom and rearmed.bank==after.bank and rearmed.selected==after.selected and rearmed.commands==after.commands and rearmed.toast_visible and rearmed.toast==ORIGINAL_TOAST and own_pending().is_empty()):return
	fields=screenshot_fields(rearmed,gesture)
	fields.camera_before=armed.camera
	await real_frame("after-one-tap-rearm",fields)

func finish():
	var expected=1 if capture_role=="baseline" else 2
	ck("all promised UI states captured or recorded exactly once",captured.size()==expected)
	info.failed=checks.filter(func(x):return not x.pass).size()
	info.checks=checks;info.assertions=checks.size();info.frames=captured;info.observations=observations
	info.result="FAIL" if info.failed else ("METADATA_ONLY" if metadata_only else "RENDERED")
	info.actual_synthetic_gestures=serial
	info.png_count=captured.filter(func(x):return x.has("sha256")).size()
	checkpoint("finish",{"states":captured.size(),"failed":info.failed,"png_count":info.png_count,"assertions":info.assertions,"gestures":serial})
	var f=FileAccess.open(out+"/report.json",FileAccess.WRITE)
	if f==null:quit(2);return
	f.store_string(JSON.stringify(info,"  "));f.close()
	if is_instance_valid(menu):menu.free()
	quit(1 if info.failed else 0)

func run():
	RenderingServer.render_loop_enabled=false
	var a=OS.get_cmdline_user_args()
	if a.size() not in [5,6] or a[1] not in ["baseline","candidate"] or (a.size()==6 and a[5]!="--metadata-only"):quit(2);return
	out=a[0];capture_role=a[1];metadata_only=a.size()==6
	if not out.begins_with("/") or DirAccess.dir_exists_absolute(out) or FileAccess.file_exists(out) or DirAccess.make_dir_recursive_absolute(out)!=OK:quit(2);return
	var target_size=Vector2i(568,320)
	root.size=target_size;await frames()
	info={"scope":"Native 568x320 actual shipped Standard match, paid opening, AI defense, synthetic touch camera pan; no injected orders, currency, units or positions. Not browser or physical iPhone.","build":Rules.BUILD_ID,"role":capture_role,"size":[568,320],"engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"video_adapter":RenderingServer.get_video_adapter_name(),"game_sha":FileAccess.get_sha256("res://scripts/game.gd"),"rules_sha":FileAccess.get_sha256("res://scripts/rules.gd"),"metadata_only":metadata_only}
	checkpoint("initialize",{"build":info.build,"role":capture_role,"display":info.display})
	if not ck("identity and viewport are pinned",info.build==a[2] and info.game_sha==a[3] and info.rules_sha==a[4] and root.size==target_size and (metadata_only or info.display!="headless")):finish();return
	menu=load("res://main_menu.tscn").instantiate()
	root.add_child(menu);await frames()
	for name in ["StartMatchButton","BattleGroup0","ChooseBattle_"+mode,"LaunchMatchButton"]:
		if not ck("native opening menu route "+name,await menu_click(name)):finish();return
	g=menu.match_node
	if not ck("fresh original Standard skirmish with target opening tick not yet passed",is_instance_valid(g) and g.skirmish_mode==mode and g.ai_enabled and g.tick_count<=OPENING_TICK and g._count(0,"barracks")==0 and g._count(0,"range")==0 and g._count(0,"spearman")==0 and g._count(0,"archer")==0):finish();return
	# Draw speed does not change the initial simulation point. Freeze continuous
	# processing after the real launch touch; fill only with ordinary stock ticks.
	g.set_process(false)
	var launch_tick=g.tick_count
	while g.tick_count<OPENING_TICK and not g.game_over and not g.paused:g._process(Rules.TICK)
	await sync_ui()
	if not ck("paid journey starts at the fixed ordinary tick with original bank",g.tick_count==OPENING_TICK and bank()=={"food":150000,"wood":200000,"stone":100000,"iron":0}):finish();return
	checkpoint("paid_opening_begin",{"native_launch_tick":launch_tick,"ordinary_start_tick":g.tick_count})
	var workers=await grab_some_wood()
	if not ck("three actually commanded lumber workers",workers.size()==3):finish();return
	await ticks_until(func():return g.economy.stats_view(0).delivered.wood>=10000,1200)
	if not ck("naturally cut and deposited wood from actual input",g.economy.stats_view(0).delivered.wood>=10000):finish();return
	if (await build_and_train("house")).is_empty():finish();return
	if (await build_and_train("barracks","spearman")).is_empty():finish();return
	await ticks_until(func():return bank().wood>=165000,2500)
	if not ck("second building and Archer paid from real lumber deliveries",bank().wood>=165000):finish();return
	if (await build_and_train("range","archer")).is_empty():finish();return
	if not ck("both paid births, worker-built producers and audited ordinary bank",g._count(0,"spearman")==1 and g._count(0,"archer")==1 and g._first(0,"house").built and g.demo_tutorial.achieved.has("soldier") and g.economy.audit().ok and g.ai_enabled):finish();return
	checkpoint("paid_opening_complete",{"tick":g.tick_count,"bank":bank()})
	await first_defense()
	await verify_and_capture()
	finish()
