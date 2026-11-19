extends RefCounted
## Mission observation only: transaction and paid identity come from normal engine paths.
const Economy=preload("res://scripts/economy_ledger.gd")
const TARGET=Vector3(-11,0,15)
const ZONE_MIN=Vector2i(-16,12)
const ZONE_MAX=Vector2i(-7,18)
const GOALS={"wood":120000,"food":80000}
const Rules=preload("res://scripts/rules.gd")
var totals={"wood":0,"food":0}
var highest_by_worker={}
var delivery_count=0
var first_delivery_tick=-1
static func in_zone(point:Vector3)->bool:
 return point.is_finite() and point.x>=ZONE_MIN.x and point.x<=ZONE_MAX.x and point.z>=ZONE_MIN.y and point.z<=ZONE_MAX.y
static func qualifies(site:Dictionary,ledger:Economy)->bool:
 if site.get("team",-1)!=0 or not site.get("alive",false) or not site.get("built",false) or site.get("kind","")!="storehouse" or not in_zone(site.get("pos",Vector3.INF)):return false
 var receipt=ledger.receipt_view(site.get("cost_receipt_id",""))
 return receipt.get("team",-1)==0 and receipt.get("state","")=="fulfilled" and receipt.get("purpose","")=="purchase" and receipt.get("refund_policy","")==Economy.REFUND_STARTED and receipt.get("cost_units",{})==Rules.COSTS.storehouse
func observe(tick:int,site:Dictionary,ledger:Economy,applied:Dictionary)->bool:
 if not applied.get("applied",false) or applied.get("replayed",false) or not qualifies(site,ledger):return false
 var kind=applied.get("resource_type","")
 if not kind in GOALS:return false
 var amount=applied.get("amount_milli",-1)
 var worker=applied.get("worker_id",-1)
 var revision=applied.get("cargo_revision",-1)
 if not amount is int or amount<=0 or amount>ledger.cargo_capacity(0,tick) or not worker is int or worker<0 or not revision is int or revision<=highest_by_worker.get(worker,-1):return false
 highest_by_worker[worker]=revision
 totals[kind]+=amount
 if first_delivery_tick<0:first_delivery_tick=tick
 delivery_count+=1
 return true
func built_site(entities:Array,ledger:Economy)->bool:
 return entities.any(func(e):return qualifies(e,ledger))
func complete(entities:Array,ledger:Economy)->bool:
 return totals.wood>=GOALS.wood and totals.food>=GOALS.food and built_site(entities,ledger)
func progress()->String:
 return "木 %d/120 · 糧 %d/80" % [mini(120,int(totals.wood/1000)),mini(80,int(totals.food/1000))]
func report()->Dictionary:
 return {"wood_milli":totals.wood,"food_milli":totals.food,"deliveries":delivery_count,"first_tick":first_delivery_tick}
