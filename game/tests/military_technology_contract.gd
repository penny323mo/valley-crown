extends SceneTree
# Funded synthetic economy, real queue countdown/payment/release APIs.
# Not a natural match, mobile playtest or visual acceptance.
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
func check(label,passed):
	checks.append({"name":label,"passed":bool(passed)})
	if not passed: push_error(label)
func _initialize(): call_deferred("run")
func production_ticks(count):
	for i in count:
		game.tick_count+=1
		for ent in game.entities:
			if ent.alive and ent.category=="building": game._update_production(ent,Rules.TICK,false)
		game._process_ready_production()
func run():
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.test_mode=true; game.ai_enabled=false
	var stock={"food":3000,"wood":3000,"stone":1000,"iron":2000}
	game._test_reset([stock,stock]); game.set_process(false)
	await process_frame
	var castle=game._first(0,"town_center")
	var bank=game.economy.bank_milli(0).duplicate()
	check("age-I technology rejected",not game._enqueue_military_research(castle.id,"forged_blades",0))
	check("invalid technology rejected",not game._enqueue_military_research(castle.id,"arbitrary",0))
	check("enemy castle rejected",not game._enqueue_military_research(castle.id,"forged_blades",1))
	check("rejections do not charge",bank==game.economy.bank_milli(0))
	check("ordinary age research accepted",game._enqueue_research(castle.id,0))
	production_ticks(1800)
	check("age completion retains next tick gate",not game._age2(0))
	game.tick_count+=1
	check("technology queues after age",game._enqueue_military_research(castle.id,"forged_blades",0))
	check("ordinary cost paid",game.economy.bank_milli(0).iron==bank.iron-150000)
	var item=castle.queue[0]
	check("unstarted research cancellation",game._cancel_queue_item(castle.id,item.queue_id,game.economy.quote_refund(item.receipt_id,0),0))
	check("refund restores tech price",game.economy.bank_milli(0).iron==bank.iron-50000)
	check("cancelled research can queue again",game._enqueue_military_research(castle.id,"forged_blades",0))
	var paid_bank=game.economy.bank_milli(0).duplicate()
	check("duplicate research rejected",not game._enqueue_military_research(castle.id,"forged_blades",0))
	check("duplicate does not charge",paid_bank==game.economy.bank_milli(0))
	check("different technology queues",game._enqueue_military_research(castle.id,"tempered_arrows",0))
	production_ticks(899)
	check("no early bonus",game._military_attack_bonus("spearman",0)==0)
	production_ticks(1)
	check("same completion tick has no bonus",game._military_attack_bonus("spearman",0)==0)
	game.tick_count+=1
	check("existing and future types gain melee bonus",game._military_attack_bonus("spearman",0)==2 and game._military_attack_bonus("scout",0)==2 and game._military_attack_bonus("cavalry",0)==2)
	check("unaffected unit profiles",game._military_attack_bonus("archer",0)==0 and game._military_attack_bonus("villager",0)==0 and game._military_attack_bonus("siege",0)==0 and game._military_attack_bonus("tower",0)==0)
	check("opponent does not inherit technology",game._military_attack_bonus("spearman",1)==0)
	var fighter=game._spawn("spearman",0,Vector3(0,0,0))
	var target=game._spawn("cavalry",1,Vector3(0.8,0,0))
	game._update_vision(false)
	var attack=game._release_attack(fighter,target)
	check("actual release includes armor and counter plus tech",attack.applied and attack.event.damage==Rules.CONTENT.resolve_damage("spearman","cavalry").damage+2)
	check("repeat attack cooldown preserved",not game._release_attack(fighter,target).applied)
	production_ticks(900); game.tick_count+=1
	check("ranged research separately completes",game._military_attack_bonus("archer",0)==2)
	check("completed cannot be rebought",not game._enqueue_military_research(castle.id,"forged_blades",0))
	check("research creates no population",game.trained_total[0]==0)
	game._publish_faction_views(); game._select([castle.id]); game._update_hud()
	check("main castle UI shows completed technologies",game.actions.get_node_or_null("forged_blades")!=null and game.actions.get_node("forged_blades").disabled and "已完成" in game.actions.get_node("forged_blades").text)
	# Same real queue/receipt path for computer; no free military bonus.
	var enemy_castle=game._first(1,"town_center")
	game._enqueue_research(enemy_castle.id,1); production_ticks(1800); game.tick_count+=1
	var records=[]
	for i in 4: records.append({"owned":true,"alive":true,"kind":"spearman"})
	game.ai_budget=game.economy.bank_milli(1).duplicate()
	game.commands.clear(); game._ai_military_research(records,enemy_castle,5)
	check("AI preserves small economy",game.commands.is_empty())
	game._ai_military_research(records,enemy_castle,6)
	check("AI proposes earned upgrade",game.commands.size()==1 and game.commands[0].type=="military_research")
	var command=game.commands[0]; game.commands.clear(); game._execute(command)
	check("AI pays same price",enemy_castle.queue.size()==1 and enemy_castle.queue[0].kind=="forged_blades")
	production_ticks(900); game.tick_count+=1
	check("AI bonus waits for actual research",game._military_attack_bonus("spearman",1)==2)
	check("ledger conservation",game.economy.audit().ok)
	game._test_reset(); game.set_process(false)
	check("new match clears both sides",game.military_tech_completed==[{},{}] and game._military_attack_bonus("spearman",0)==0 and game._military_attack_bonus("archer",1)==0)
	var failed=checks.filter(func(c): return not c.passed).size()
	print(JSON.stringify({"suite":"military_technology_contract","checks":checks,"failed":failed,"scope":"Funded synthetic queue and combat fixture, not natural gameplay or mobile visual acceptance"}))
	game.queue_free(); quit(1 if failed else 0)
