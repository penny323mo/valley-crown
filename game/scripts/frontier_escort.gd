extends RefCounted
## Public authored escort mission; no autonomous orders or grants.
const TARGET=Vector3(-7,0,6)
const OUTPOST_MIN=Vector2i(-11,3)
const OUTPOST_MAX=Vector2i(-3,9)
const STAGING=Vector3(8,0,-8)
const ROSTER=["spearman","spearman","archer","archer","cavalry","cavalry"]
const TITLES=["護送村民","建立前哨","守住前哨","任務完成"]
var villagers=[]
var stage=0
var stage_ticks=[]
var due=-1
var counter_ids=[]
var launched=false
var living=3
var buildings={}
var remaining=0
static func in_zone(p:Vector3)->bool:
 return p.x>=OUTPOST_MIN.x and p.x<=OUTPOST_MAX.x and p.z>=OUTPOST_MIN.y and p.z<=OUTPOST_MAX.y
func update(tick:int,entities:Array)->bool:
 living=0;buildings={};remaining=0
 var arrived=false
 for e in entities:
  if not e.alive:continue
  if e.id in villagers:
   living+=1
   if in_zone(e.pos):arrived=true
  if e.team==0 and e.kind in ["storehouse","tower"] and e.built and in_zone(e.pos) and not str(e.get("cost_receipt_id","")).is_empty():buildings[e.kind]=e.id
  if e.id in counter_ids:remaining+=1
 var pass_stage=(stage==0 and arrived) or (stage==1 and buildings.size()==2) or (stage==2 and launched and remaining==0 and buildings.size()==2 and living>0)
 if living>0 and pass_stage:
  stage+=1;stage_ticks.append(tick)
  if stage==2:due=tick+600
  return true
 return false
func ready(tick:int)->bool:return stage==2 and not launched and tick>=due
func launch(ids:Array)->bool:
 if stage!=2 or launched or ids.size()!=6:return false
 var unique={}
 for id in ids:
  if not id is int or id<0 or unique.has(id):return false
  unique[id]=true
 counter_ids=ids.duplicate();launched=true;remaining=6;return true
func caption(tick:int)->String:
 var task="護送指定三名村民，至少一名抵達前哨。"
 if stage==1:task="在前哨界線內放置倉庫和箭塔中心；付費完成才計算。"
 if stage==2:task=("反攻%d秒後出發；保護村民及前哨。" % maxi(0,ceili((due-tick)/20.0))) if not launched else ("擊退餘下%d名敵軍；前哨被毀可重建。" % remaining)
 if stage==3:task="村民與前哨存活，反攻全部擊退。"
 return "護送拓荒隊 · "+TITLES[stage]+"\n村民 %d/3 · 倉庫 %d/1 · 箭塔 %d/1\n" % [living,int(buildings.has("storehouse")),int(buildings.has("tower"))]+task
func report()->Dictionary:
 return {"stage":stage,"stage_ticks":stage_ticks.duplicate(),"villagers_alive":living,"counter_launched":launched}
func progress_text(tick:int)->String:
 if stage==0:return "村民 %d/3 · 點此定位" % living
 if stage==1:return "倉庫 %d/1 · 箭塔 %d/1" % [int(buildings.has("storehouse")),int(buildings.has("tower"))]
 if stage==2 and not launched:
  return ("反攻 %d 秒後出發" % ceili((due-tick)/20.0)) if tick<due else "集結區受阻 · 等候出發"
 return "村民 %d/3 · 敵軍 %d/6" % [living,remaining]
