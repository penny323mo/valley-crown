extends RefCounted
# Pure full-gap affordability forecast. It never queues, pays, or spawns.
const Rules=preload('res://scripts/rules.gd')
const Economy=preload('res://scripts/economy_ledger.gd')
const Composition=preload('res://scripts/army_composition.gd')
static func plan(records:Array,budget:Dictionary,age2:bool,capacity:int,committed:int,threshold:int)->Dictionary:
 if threshold<1 or threshold>5:return {}
 var copies=records.duplicate(true);var troops=0;var seen={}
 for r in copies:
  if not r.get('owned',false) or not r.get('alive',false) or r.get('team',-1)!=1 or seen.has(r.get('id',-1)):continue
  seen[r.get('id',-1)]=true
  if r.get('category','')=='unit' and r.get('kind','') in Rules.UNIT_KINDS and r.kind!='villager':troops+=1
  elif r.get('category','')=='building':
   for item in r.get('queue',[]):
    # Existing paid births retain priority; no duplicate pending fallback.
    if item.get('kind','') in Rules.UNIT_KINDS:return {}
 var gap=threshold-troops
 if gap<=0 or committed+gap>capacity:return {}
 var funds=budget.duplicate(true);var sequence=[];var first={}
 var reserve=2*Rules.COSTS.villager.food*Economy.SCALE
 for step in gap:
  var legal=[];var producers={}
  for kind in Composition.ORDER:
   if kind in Rules.AGE2_KINDS and not age2:continue
   var affordable=true
   for resource in Rules.COSTS[kind]:
    var remaining=funds.get(resource,0)-Rules.COSTS[kind][resource]*Economy.SCALE
    if remaining<0 or (resource=='food' and remaining<reserve):affordable=false
   if funds.get('food',0)<reserve:affordable=false
   if not affordable:continue
   for r in copies:
    if not r.get('owned',false) or not r.get('alive',false) or r.get('team',-1)!=1 or r.get('category','')!='building' or not r.get('built',false) or r.get('remembered',true):continue
    if kind not in Rules.products_for(r.kind) or r.get('queue',[]).size()>=5:continue
    if not producers.has(kind) or r.id<producers[kind].id:producers[kind]=r
   if producers.has(kind):legal.append(kind)
  # Composition defaults to spearman for an empty list, so reject explicitly.
  if legal.is_empty():return {}
  var kind=Composition.plan(copies,legal).kind
  if kind not in legal:return {}
  var producer=producers[kind]
  if first.is_empty():first={'kind':kind,'building':producer.id}
  sequence.append(kind)
  for resource in Rules.COSTS[kind]:funds[resource]=funds.get(resource,0)-Rules.COSTS[kind][resource]*Economy.SCALE
  # Append only to copied producer: Composition sees each virtual birth once.
  if not producer.has('queue'):producer.queue=[]
  producer.queue.append({'kind':kind})
 return {'kind':first.kind,'building':first.building,'sequence':sequence,'remaining':funds,'gap':gap,'reserve_food':reserve}
