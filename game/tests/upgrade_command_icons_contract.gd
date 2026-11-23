extends SceneTree
# Presentation changes on real HUD buttons. Technique eligibility is seeded
# for the fixture; taps, commands, payment and cancellation use normal paths.
const Icons=preload("res://scripts/command_icons.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]

func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)

func _initialize():call_deferred("run")

func settle():
	for i in 4:await process_frame

func show_in_strip(g,button):
	if not is_instance_valid(button):return false
	g.action_scroll.ensure_control_visible(button)
	await settle()
	return button.size.y>=44 and g.action_scroll.get_global_rect().encloses(button.get_global_rect())

func tap_icon(button,index):
	var p=button.get_global_rect().position+Vector2(18,button.size.y/2)
	for down in [true,false]:
		var e=InputEventScreenTouch.new()
		e.index=index;e.position=p;e.pressed=down
		root.push_input(e)
		await process_frame
	await settle()

func icon_button(g,kind):
	for b in g.actions.get_children():
		if b is Button and b.get_meta("command_icon_kind","")==kind:return b
	return null

func refresh(g):
	g._publish_faction_views()
	g._update_hud()
	await settle()

func test_size(dims):
	root.size=dims
	var g=load("res://main.tscn").instantiate()
	g.set("skirmish_mode","practice");root.add_child(g);g.set_process(false)
	g.test_mode=true;g.ai_enabled=false
	var stock={"food":3000,"wood":3000,"stone":3000,"iron":3000}
	g._test_reset([stock,stock.duplicate(true)]);g._layout_ui()
	var keep=g._first(0,"town_center")
	g._select([keep.id]);await settle()
	var age=icon_button(g,"age2")
	var shown=await show_in_strip(g,age)
	check("age action preserves price and 44px icon control "+str(dims),shown and age.icon==Icons.UPGRADE_ICONS.age2 and age.text=="城防時代\n"+Rules.cost_label("age2") and not age.disabled)
	if not shown:g.free();await settle();return
	var bank=g.economy.bank_milli(0).duplicate(true)
	await tap_icon(age,51)
	check("age icon touch only queues standard research "+str(dims),g.commands.size()==1 and g.commands[0].type=="research" and g.commands[0].building==keep.id and g.economy.bank_milli(0)==bank)
	g._tick(Rules.TICK);await refresh(g)
	var age_paid=g.economy.bank_milli(0).duplicate(true)
	var pending=icon_button(g,"age2")
	check("age payment and existing disabled state unchanged "+str(dims),keep.queue.size()==1 and keep.queue[0].kind=="age2" and pending.disabled and bank.food-age_paid.food==350000 and bank.wood-age_paid.wood==150000 and bank.iron-age_paid.iron==50000)
	var age_id=keep.queue[0].queue_id
	var age_cancel=g.actions.get_node_or_null("CancelQueue%d" % age_id)
	check("paid age queue shows same icon and existing refund "+str(dims),age_cancel!=null and age_cancel.icon==Icons.UPGRADE_ICONS.age2 and age_cancel.text.begins_with("取消城防時代") and age_cancel.text.contains("退回"))
	# Seed completed age so every existing upgrade button appears without
	# timing a 90-second match; no claim about that completion journey.
	g.age_completed_tick[0]=g.tick_count-1
	await refresh(g)
	for kind in Rules.RESEARCH_TECHS:
		var tech=g.actions.get_node_or_null(kind)
		var tech_shown=await show_in_strip(g,tech)
		check("reachable 44px icon, label, effect and price "+kind+" "+str(dims),tech_shown and tech.icon==Icons.UPGRADE_ICONS[kind] and tech.text.begins_with(Rules.NAMES[kind]) and tech.text.contains(Rules.TECH_DETAILS[kind]) and tech.text.contains(Rules.cost_label(kind)))
	var storehouse=g._spawn("storehouse",0,Vector3(-21,0,14))
	await refresh(g)
	g._select([storehouse.id]);await settle()
	var supply=g.actions.get_node_or_null("SupplyStationUpgrade")
	var supply_shown=await show_in_strip(g,supply)
	check("supply icon keeps both prices and 44px control "+str(dims),supply_shown and supply.icon==Icons.UPGRADE_ICONS.supply_station and supply.text.contains("木 100") and supply.text.contains("食 100") and not supply.disabled)
	if supply_shown:
		var before=g.economy.bank_milli(0).duplicate(true)
		await tap_icon(supply,52)
		check("supply icon issues exactly one existing upgrade command "+str(dims),g.commands.size()==1 and g.commands[0].type=="supply_upgrade" and g.commands[0].building==storehouse.id)
		g._tick(Rules.TICK);await refresh(g)
		var paid=g.economy.bank_milli(0)
		var supply_queue=storehouse.queue
		check("ordinary supply payment still exact "+str(dims),supply_queue.size()==1 and paid.wood==before.wood-100000 and paid.food==before.food-100000)
		if not supply_queue.is_empty():
			var item=supply_queue[0]
			var cancel=g.actions.get_node_or_null("CancelQueue%d" % item.queue_id)
			var cancel_shown=await show_in_strip(g,cancel)
			check("same supply icon on exact paid refund action "+str(dims),cancel_shown and cancel.icon==Icons.UPGRADE_ICONS.supply_station and cancel.text.begins_with("取消前線補給站") and cancel.text.contains("退回"))
			if cancel_shown:
				await tap_icon(cancel,53)
				check("refund action keeps queue identity and original callback "+str(dims),g.commands.size()==1 and g.commands[0].type=="cancel_queue_item" and g.commands[0].queue_id==item.queue_id and g.commands[0].building==storehouse.id)
				g._tick(Rules.TICK);await refresh(g)
	var worker=g._first(0,"villager")
	g._select([worker.id]);await settle()
	for kind in Rules.BUILDABLE_KINDS:
		g._start_build(kind);await settle()
		var confirm=g.build_confirm
		var target=await show_in_strip(g,confirm)
		check("confirm identifies selected building without changing its label "+kind+" "+str(dims),target and confirm.icon==Icons.ICONS[kind] and confirm.text=="確認建造" and confirm.disabled)
		if kind=="house" and target:
			await tap_icon(confirm,54)
			check("confirm icon cannot build until ordinary terrain choice "+str(dims),g.commands.is_empty() and g.build_mode=="house" and not g.build_preview_held)
		g._cancel_mode();await settle()
	g.free();await settle()

func run():
	var kinds=Rules.RESEARCH_TECHS+["age2","supply_station"]
	check("exact six upgrade symbols",Icons.UPGRADE_ICONS.size()==kinds.size())
	for kind in kinds:
		var t=Icons.UPGRADE_ICONS[kind]
		check("32px named symbol outside trade and portrait namespaces "+kind,t.get_width()==32 and t.get_height()==32 and t.resource_path=="res://assets/mature/ui/icons/"+kind+".svg" and not Icons.ICONS.has(kind) and not Icons.TRADE_ICONS.has(kind))
	for dims in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390)]:
		await test_size(dims)
	var failed=checks.filter(func(c):return not c.passed).size()
	print(JSON.stringify({"suite":"upgrade_command_icons_contract","checks":checks,"failed":failed,"scope":"Native controlled age fixture with real viewport-routed touches, selection HUD, ordinary queues and payments; not browser or phone acceptance."}))
	quit(1 if failed else 0)
