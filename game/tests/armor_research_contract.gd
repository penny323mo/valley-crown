extends SceneTree
var g
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func ticks(count):
 for i in count:
  g.tick_count+=1
  for ent in g.entities:
   if ent.alive and ent.category=="building":g._update_production(ent,g.Rules.TICK,false)
  g._process_ready_production()
func _initialize():call_deferred("run")
func run():
 g=load("res://main.tscn").instantiate();root.add_child(g);g.test_mode=true;g.ai_enabled=false;g._test_reset([{"food":1000,"wood":1000,"stone":500,"iron":500},{"food":1000,"wood":1000,"stone":500,"iron":500}]);g.set_process(false);await process_frame
 var keep=g._first(0,"town_center")
 check("age one armor research rejected",not g._enqueue_military_research(keep.id,"reinforced_armor",0))
 check("ordinary age research accepted",g._enqueue_research(keep.id,0));ticks(1800);g.tick_count+=1
 var before=g.economy.bank_milli(0).duplicate()
 check("armor research queues through ordinary payment",g._enqueue_military_research(keep.id,"reinforced_armor",0))
 check("exact wood100 iron150 price",g.economy.bank_milli(0).wood==before.wood-100000 and g.economy.bank_milli(0).iron==before.iron-150000)
 var paid=g.economy.bank_milli(0).duplicate()
 check("duplicate pending research cannot charge again",not g._enqueue_military_research(keep.id,"reinforced_armor",0) and paid==g.economy.bank_milli(0))
 var item=keep.queue[0]
 check("unstarted cancellation works",g._cancel_queue_item(keep.id,item.queue_id,g.economy.quote_refund(item.receipt_id,0),0) and g.economy.bank_milli(0)==before)
 check("cancelled research can be bought again",g._enqueue_military_research(keep.id,"reinforced_armor",0))
 var attacker=g._spawn("spearman",1,Vector3.ZERO,true)
 var defender=g._spawn("cavalry",0,Vector3(0.8,0,0),true)
 g._update_vision(false)
 var old_hit=g._release_attack(attacker,defender)
 check("ordinary pre-research hit issued",old_hit.applied)
 ticks(899)
 check("no early armor",g._military_armor_bonus("cavalry",0)==0)
 ticks(1)
 check("completion tick not retroactive",g._military_armor_bonus("cavalry",0)==0)
 g.tick_count+=1
 check("three intended troops gain defense",g._military_armor_bonus("spearman",0)==1 and g._military_armor_bonus("archer",0)==1 and g._military_armor_bonus("cavalry",0)==1)
 check("workers scouts siege towers unchanged",g._military_armor_bonus("villager",0)==0 and g._military_armor_bonus("scout",0)==0 and g._military_armor_bonus("siege",0)==0 and g._military_armor_bonus("tower",0)==0)
 check("opponent defense unchanged",g._military_armor_bonus("cavalry",1)==0)
 check("armor never grants offensive bonus",g._military_attack_bonus("spearman",0)==0 and g._military_attack_bonus("archer",0)==0)
 attacker.cooldown_ticks=0
 var new_hit=g._release_attack(attacker,defender)
 check("actual attack release reduced by one",new_hit.applied and new_hit.event.damage==maxi(1,old_hit.event.damage-1))
 check("issued hit retains original damage",old_hit.event.damage==g.Rules.CONTENT.resolve_damage("spearman","cavalry").damage)
 check("cannot rebuy completed armor",not g._enqueue_military_research(keep.id,"reinforced_armor",0))
 g._publish_faction_views();g._select([keep.id]);g._update_hud()
 var button=g.actions.get_node_or_null("reinforced_armor")
 check("castle shows armor completed",button!=null and button.disabled and "已完成" in button.text and "護甲 +1" in button.text)
 var manual=load("res://scripts/field_manual.gd")
 check("unit manual describes defense not attack bonus", "護甲 +1" in manual.entry(0,2).body)
 check("research creates no free troops",g.trained_total[0]==0)
 check("resource conservation",g.economy.audit().ok)
 g._test_reset();g.set_process(false)
 check("new match clears armor",g._military_armor_bonus("cavalry",0)==0)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"armor_research_contract","build":g.Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"funded controlled research and authoritative combat; no natural match or phone acceptance"}));g.queue_free();quit(1 if failed else 0)
