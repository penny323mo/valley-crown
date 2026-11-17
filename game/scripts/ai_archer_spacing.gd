extends RefCounted
## One short ordinary move between arrows, current own/local enemy observations.
## No new authority, cooldown changes, path resets or persistent policy state.
const Rules=preload("res://scripts/rules.gd")
const STEP=1.5
# One-second AI cadence: reserve a full think interval before the next arrow.
# A half-second cooldown would finish early and then wait, reducing fire rate.
const MELEE=["spearman","cavalry","scout"]
static func threat(unit:Dictionary,records:Array)->Dictionary:
 if not unit.get("owned",false) or not unit.get("alive",false) or unit.get("remembered",true) or unit.get("team",-1)!=1 or unit.get("kind","")!="archer" or unit.get("state","")!="attack":return {}
 if unit.get("cooldown_ticks",0)<20 or unit.get("path_pending",false) or unit.get("path_status","") in ["NO_PATH","LIMIT_REACHED"]:return {}
 var chosen={};var best=INF
 for e in records:
  if e.get("team",-1)!=0 or not e.get("alive",false) or e.get("remembered",true) or e.get("category","")!="unit" or e.get("kind","") not in MELEE:continue
  var d=unit.pos.distance_to(e.pos)
  if d<0.1 or d>2.6:continue
  if d<best or (is_equal_approx(d,best) and (chosen.is_empty() or e.id<chosen.id)):chosen=e;best=d
 return chosen
static func safe(unit:Dictionary,point:Vector3,records:Array)->bool:
 if not point.is_finite() or point.distance_to(unit.pos)>2.2:return false
 for e in records:
  if e.get("team",-1)!=0 or not e.get("alive",false) or e.get("remembered",true):continue
  var before=unit.pos.distance_to(e.pos);var after=point.distance_to(e.pos)
  if e.get("category","")=="unit" and e.get("kind","") in ["spearman","cavalry","scout","archer","siege"] and before<=Rules.SIGHT.archer and after<before-0.01:return false
  if e.get("kind","")=="tower" and e.get("built",false) and after<Rules.RANGE.tower+e.get("radius",1.0)+1.0:return false
 return true
static func destination(unit:Dictionary,records:Array)->Vector3:
 var enemy=threat(unit,records)
 if enemy.is_empty():return Vector3.INF
 var point=unit.pos+(unit.pos-enemy.pos).normalized()*STEP
 return point if safe(unit,point,records) else Vector3.INF
