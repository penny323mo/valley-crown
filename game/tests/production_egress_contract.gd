extends SceneTree
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func _initialize():call_deferred("run")
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)});if not ok:push_error(name)
func run():
 var g=load("res://main.tscn").instantiate();root.add_child(g)
 g.set_process(false);g.test_mode=true;g.ai_enabled=false
 var stock={"food":1000,"wood":1000,"stone":1000,"iron":1000}
 g._test_reset([stock,stock.duplicate(true)]);g.set_process(false);await process_frame
 var worker=g._first(0,"villager");var place=Vector3.INF
 var home=g._first(0,"town_center");var distance=INF
 for z in range(15,Rules.MAP_SIZE-15):
  for x in range(15,Rules.MAP_SIZE-15):
   var p=g._point(Vector2i(x,z));var d=p.distance_squared_to(home.pos)
   if d<distance and g._placement_reason("barracks",p,0,worker.id).is_empty():place=p;distance=d
 if place==Vector3.INF:push_error("no legal fixture producer");g.queue_free();quit(2);return
 var producer=g._spawn("barracks",0,place);g._navigation_rebuild()
 var center=g._cell(place)
 # Synthetic perimeter, explicitly not normal placement proof. Only authority grid is seeded,
 # never funds, ready state, order receipt, birthing, fulfilment, or periodic polling.
 var ring=[]
 for x in range(-6,7):
  for z in range(-6,7):
   if absi(x)==6 or absi(z)==6:
    var cell=center+Vector2i(x,z);ring.append(cell);g.navigation.set_point_solid(cell)
 check("unobserved remote obstruction cannot change faction calculated exits",not g._production_egress(producer,"spearman").is_empty())
 check("authority still detects direct local violation",g.navigation.is_point_solid(ring[0]) and not g.work_memory[0].grid.is_point_solid(ring[0]))
 g.work_memory[0].known_obstacles[-999]={"alive":true,"cells":ring,"category":"building"}
 g._refresh_work_memory()
 
 var before=g.economy.bank_milli(0).duplicate();var births=g.trained_total[0]
 g._submit("train",{"building":producer.id,"kind":"spearman"})
 for i in Rules.TRAIN_TICKS.spearman+85:g._tick(Rules.TICK)
 var paid=g.economy.bank_milli(0).duplicate()
 var receipt=producer.queue[0].receipt_id if not producer.queue.is_empty() else ""
 check("single ordinary payment",paid.food==before.food-50000 and paid.wood==before.wood-20000)
 check("sealed static queue preserves receipt through several retries",not receipt.is_empty() and producer.queue[0].remaining_ticks==0 and g.trained_total[0]==births)
 check("ring still has locally standable old spawn exits",g._spawn_exit(producer,{"kind":"spearman"})!=Vector3.INF)
 check("new component policy denies sealed births",g._production_egress(producer,"spearman").is_empty())
 g._select([producer.id]);g._update_hud()
 check("queue copy promises neither teleport nor moving units",g.queue_label.text.contains("隊列保留"))
 g.work_memory[0].known_obstacles.erase(-999)
 g._navigation_rebuild()
 for i in 70:g._tick(Rules.TICK)
 check("actual reopen and nav rebuild births once",producer.queue.is_empty() and g.trained_total[0]==births+1 and g.economy.bank_milli(0)==paid)
 check("repeated open polls cannot duplicate birth",g.trained_total[0]==births+1 and producer.queue.is_empty())
 check("conserved ledger",g.economy.audit().ok)
 var f=checks.filter(func(c):return not c.passed)
 print(JSON.stringify({"checks":checks,"failed":f.size(),"suite":"production_egress_contract","scope":"Synthetic sealed static ring; all training/payment/queue/retries/fulfilment are actual native production."}))
 g.queue_free();quit(0 if f.is_empty() else 1)
