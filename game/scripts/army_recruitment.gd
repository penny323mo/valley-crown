extends RefCounted
## Observation-only advisory plan. Ordinary train commands remain authoritative.
const Rules=preload("res://scripts/rules.gd")
const ArmyRoster=preload("res://scripts/army_roster.gd")
static func plan(records: Dictionary,kind: String,bank_milli: Dictionary,free_population: int,commands: Array=[],unlocked: bool=true) -> Dictionary:
 var result={"orders":[],"count":0,"cost":{},"reason":""}
 if kind not in ArmyRoster.KINDS:result.reason="無效兵種";return result
 if not unlocked:result.reason="尚未解鎖";return result
 for command in commands:
  if command is Dictionary and command.get("team",-1)==0:result.reason="等候指令執行";return result
 if free_population<=0:result.reason="人口已滿";return result
 var producers=[]
 for id in records:
  var record=records[id]
  if not record is Dictionary or record.get("id",-1)!=id or not record.get("owned",false) or record.get("team",-1)!=0 or not record.get("alive",false) or record.get("remembered",false):continue
  if record.get("category","")!="building" or not record.get("built",false) or kind not in Rules.products_for(record.get("kind","")):continue
  var queue=record.get("queue",[])
  if not queue is Array or queue.size()>=5:continue
  var delay=0
  for item in queue:
   if item is Dictionary:
    delay+=maxi(0,int(item.get("remaining_ticks",Rules.TRAIN_TICKS.get(item.get("kind",""),0))))
  producers.append({"id":id,"length":queue.size(),"delay":delay})
 if producers.is_empty():result.reason="沒有可用生產建築";return result
 var budget=bank_milli.duplicate(true)
 for index in mini(3,free_population):
  producers.sort_custom(func(a,b):
   # Prefer the first available training slot, not merely fewer queue entries.
   # Completed exit-blocked orders remain queued; do not bypass spawn authority.
   if a.length>=5 or b.length>=5:return a.length<5 and b.length>=5
   if a.delay!=b.delay:return a.delay<b.delay
   return a.length<b.length or (a.length==b.length and a.id<b.id))
  if producers[0].length>=5:break
  var affordable=true
  for resource in Rules.COSTS[kind]:
   if budget.get(resource,0)<Rules.COSTS[kind][resource]*1000:affordable=false
  if not affordable:break
  for resource in Rules.COSTS[kind]:
   budget[resource]=budget.get(resource,0)-Rules.COSTS[kind][resource]*1000
   result.cost[resource]=result.cost.get(resource,0)+Rules.COSTS[kind][resource]
  result.orders.append({"building":producers[0].id,"kind":kind})
  producers[0].length+=1
  producers[0].delay+=Rules.TRAIN_TICKS[kind]
 result.count=result.orders.size()
 result.reason="資源不足" if result.count==0 else "可徵兵"
 return result
