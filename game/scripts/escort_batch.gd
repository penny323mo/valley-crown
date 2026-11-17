extends RefCounted
## One-shot owned-selection planner; emits only existing escort command payloads.
const Escort=preload("res://scripts/escort_policy.gd")
const MAX_TARGETS=3
static func eligible(r:Dictionary)->bool:
 return r.get("owned",false) and r.get("alive",false) and not r.get("remembered",true) and r.get("team",-1)==0 and r.get("category","")=="unit" and r.get("pos",Vector3.INF).is_finite()
static func supports(records:Dictionary,selection:Array)->bool:
 var vehicle=false;var guard=false
 for id in selection:
  var r=records.get(id,{})
  if not eligible(r):continue
  vehicle=vehicle or r.kind=="siege"
  guard=guard or r.kind in Escort.GUARDS
 return vehicle and guard
static func plan(records:Dictionary,selection:Array,pending:Array)->Array:
 var targets=[];var guards=[];var seen={};var busy={}
 for c in pending:
  if c.get("team",-1)==0:
   for id in c.get("ids",[]):busy[id]=true
 for id in selection:
  if not id is int or seen.has(id):continue
  seen[id]=true
  var r=records.get(id,{})
  if not eligible(r):continue
  if r.kind=="siege":targets.append(id)
  elif r.kind in Escort.GUARDS:guards.append(id)
 targets.sort();targets=targets.slice(0,MAX_TARGETS);guards.sort()
 var counts={};var groups={}
 for id in targets:counts[id]=0;groups[id]=[]
 # Preserve active escorts; repeated use cannot reset their follow/path epoch.
 for id in guards:
  var r=records[id]
  if r.get("mode","")=="ESCORT" and counts.has(r.get("escort_target",-1)):counts[r.escort_target]+=1
 for id in guards:
  var r=records[id]
  if busy.has(id) or r.get("mode","")=="ESCORT":continue
  var chosen=-1;var distance=INF
  for target in targets:
   var d=r.pos.distance_squared_to(records[target].pos)
   if chosen<0 or counts[target]<counts[chosen] or (counts[target]==counts[chosen] and (d<distance or (is_equal_approx(d,distance) and target<chosen))):chosen=target;distance=d
  if chosen>=0:groups[chosen].append(id);counts[chosen]+=1
 var result=[]
 for target in targets:
  if not groups[target].is_empty():result.append({"ids":groups[target],"target":target})
 return result
static func signature(plan:Array)->Array:
 var result=[]
 for group in plan:result.append(group.target);result.append_array(group.ids);result.append(-1)
 return result
