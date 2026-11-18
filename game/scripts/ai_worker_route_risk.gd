extends RefCounted
# Detached observation-only directed edges. No grid/entity/order/save mutation.
const Rules=preload("res://scripts/rules.gd")
const Path=preload("res://scripts/bounded_grid_pathfinder.gd")
static func blocked_edges(records:Dictionary,team:int,radius:float,start:Vector2i,origin:Vector3)->Dictionary:
 var result={}
 for r in records.values():
  if r.get("remembered",true) or not r.get("alive",false) or r.get("team",-1)!=1-team:continue
  if r.get("category","")!="unit" and not (r.get("category","")=="building" and r.get("kind","")=="tower" and r.get("built",false)):continue
  if Rules.DAMAGE.get(r.get("kind",""),0)<=0:continue
  var reach=Rules.RANGE.get(r.kind,0.0)+radius
  var cx=floori(r.pos.x+Rules.MAP_HALF);var cy=floori(r.pos.z+Rules.MAP_HALF);var span=ceili(reach)+2
  for y in range(maxi(0,cy-span),mini(Rules.MAP_SIZE,cy+span+1)):
   for x in range(maxi(0,cx-span),mini(Rules.MAP_SIZE,cx+span+1)):
    var cell=Vector2i(x,y);var p=origin if cell==start else Vector3(x-Rules.MAP_HALF+0.5,0,y-Rules.MAP_HALF+0.5)
    var old=p.distance_to(r.pos)
    for step in Path.DIRECTIONS:
     var next=cell+step;var q=Vector3(next.x-Rules.MAP_HALF+0.5,0,next.y-Rules.MAP_HALF+0.5)
     var v=q-p;var t=clampf((r.pos-p).dot(v)/v.length_squared(),0,1) if v.length_squared()>0 else 0.0
     var nearest=(p+v*t).distance_to(r.pos)
     if (old>=reach and nearest<reach) or (old<reach and (q.distance_to(r.pos)<=old+0.00001 or nearest<old-0.00001)):
      result[Vector4i(cell.x,cell.y,next.x,next.y)]=true
 return result

static func segment_allowed(records:Dictionary,team:int,radius:float,p:Vector3,q:Vector3)->bool:
 for r in records.values():
  if r.get("remembered",true) or not r.get("alive",false) or r.get("team",-1)!=1-team:continue
  if r.get("category","")!="unit" and not (r.get("category","")=="building" and r.get("kind","")=="tower" and r.get("built",false)):continue
  if Rules.DAMAGE.get(r.get("kind",""),0)<=0:continue
  var reach=Rules.RANGE.get(r.kind,0.0)+radius;var old=p.distance_to(r.pos);var v=q-p
  if v.length_squared()<0.00000001:continue
  var t=clampf((r.pos-p).dot(v)/v.length_squared(),0,1);var nearest=(p+v*t).distance_to(r.pos)
  if (old>=reach and nearest<reach) or (old<reach and (q.distance_to(r.pos)<=old+0.00001 or nearest<old-0.00001)):return false
 return true

# Per-search detached spatial index. No persistent cache or observation alias.
# A bucket includes every threat that can intersect any outgoing grid edge.
const BUCKET_SIZE=4
var buckets:Dictionary={}
var query_start:Vector2i
var query_origin:Vector3
var threat_count:int=0
var canonical_edges:Dictionary={}
static func indexed(records:Dictionary,team:int,radius:float,start:Vector2i,origin:Vector3):
 var index=load("res://scripts/ai_worker_route_risk.gd").new()
 index.query_start=start;index.query_origin=origin
 for r in records.values():
  if r.get("remembered",true) or not r.get("alive",false) or r.get("team",-1)!=1-team:continue
  if r.get("category","")!="unit" and not (r.get("category","")=="building" and r.get("kind","")=="tower" and r.get("built",false)):continue
  if Rules.DAMAGE.get(r.get("kind",""),0)<=0:continue
  var reach=Rules.RANGE.get(r.kind,0.0)+radius
  var threat=Vector4(r.pos.x,r.pos.y,r.pos.z,reach)
  index.threat_count+=1
  # Two cells cover diagonal edges and the actual off-centre source point.
  var lo=Vector2i(floori((r.pos.x+Rules.MAP_HALF-reach-2)/BUCKET_SIZE),floori((r.pos.z+Rules.MAP_HALF-reach-2)/BUCKET_SIZE))
  var hi=Vector2i(floori((r.pos.x+Rules.MAP_HALF+reach+2)/BUCKET_SIZE),floori((r.pos.z+Rules.MAP_HALF+reach+2)/BUCKET_SIZE))
  for y in range(maxi(0,lo.y),mini(ceili(float(Rules.MAP_SIZE)/BUCKET_SIZE)-1,hi.y)+1):
   for x in range(maxi(0,lo.x),mini(ceili(float(Rules.MAP_SIZE)/BUCKET_SIZE)-1,hi.x)+1):
    var key=Vector2i(x,y)
    if not index.buckets.has(key):index.buckets[key]=[]
    index.buckets[key].append(threat)
 return index
func for_origin(start:Vector2i,origin:Vector3):
 var query=load("res://scripts/ai_worker_route_risk.gd").new()
 query.buckets=buckets;query.canonical_edges=canonical_edges
 query.threat_count=threat_count;query.query_start=start;query.query_origin=origin
 return query
func allows(cell:Vector2i,next:Vector2i)->bool:
 var bucket=Vector2i(floori(float(cell.x)/BUCKET_SIZE),floori(float(cell.y)/BUCKET_SIZE))
 if not buckets.has(bucket):return true
 var centre=Vector3(cell.x-Rules.MAP_HALF+0.5,0,cell.y-Rules.MAP_HALF+0.5)
 # Only exact canonical origins share results. Actual offcentre first edges
 # remain query-specific, including a first edge from inside a danger circle.
 var canonical=cell!=query_start or query_origin==centre
 var edge=Vector4i(cell.x,cell.y,next.x,next.y)
 if canonical and canonical_edges.has(edge):return canonical_edges[edge]
 var allowed=_allows_uncached(cell,next,buckets[bucket])
 if canonical:canonical_edges[edge]=allowed
 return allowed
func _allows_uncached(cell:Vector2i,next:Vector2i,local_threats:Array)->bool:
 var p=query_origin if cell==query_start else Vector3(cell.x-Rules.MAP_HALF+0.5,0,cell.y-Rules.MAP_HALF+0.5)
 var q=Vector3(next.x-Rules.MAP_HALF+0.5,0,next.y-Rules.MAP_HALF+0.5)
 var v=q-p;var length=v.length_squared()
 if length<0.00000001:return true
 for threat in local_threats:
  var center=Vector3(threat.x,threat.y,threat.z)
  var old=p.distance_to(center)
  var t=clampf((center-p).dot(v)/length,0,1)
  var nearest=(p+v*t).distance_to(center)
  if (old>=threat.w and nearest<threat.w) or (old<threat.w and (q.distance_to(center)<=old+0.00001 or nearest<old-0.00001)):return false
 return true
