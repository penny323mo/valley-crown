extends RefCounted
## One explicit authored mission. Objective coordinates and reinforcement roster
## are public scenario rules; live combat remains normal world authority.
const OUTPOST=Vector3(2,0,-9)
const ENEMY_HOME=Vector3(25,0,-24)
const HOME=Vector3(-25,0,24)
const STAGING=Vector3(14.5,0,-15.5)
const COUNTER_ROSTER=["spearman","spearman","archer","archer","cavalry","cavalry"]
const TITLES=["建立軍隊","偵察前線","攻破哨站","擊退反攻","攻下敵堡","遠征完成"]
var stage=0
var stage_ticks=[]
var outpost_id=-1
var counter_ids=[]
var counter_launched=false
var counter_due=-1
var trained=0
var supplied=0
func advance(tick:int, production:int, food:int, scouted:bool, post_alive:bool, counter_alive:bool, keep_alive:bool):
 trained=production;supplied=food
 var passed=false
 match stage:
  0:passed=trained>=2 and supplied>=100000
  1:passed=scouted
  2:passed=not post_alive
  3:passed=counter_launched and not counter_alive
  4:passed=not keep_alive
 if passed:
  stage_ticks.append(tick);stage+=1
  if stage==3:counter_due=tick+600
 return passed
func ready(tick:int)->bool:
 return stage==3 and not counter_launched and tick>=counter_due
func launch(ids:Array)->bool:
 if stage!=3 or counter_launched or ids.size()!=COUNTER_ROSTER.size():return false
 counter_ids=ids.duplicate();counter_launched=true;return true
func target()->Vector3:
 if stage==0:return HOME
 if stage in [1,2]:return OUTPOST
 if stage==3:return HOME
 return ENEMY_HOME
func transition_text()->String:
 return ["建立軍隊","軍隊已建立，探索前線","已發現前哨，準備攻擊","前哨已攻破，30秒後反攻","反攻已擊退，攻下敵堡","遠征完成"][clampi(stage,0,5)]
func caption(tick:int)->String:
 var prefix="前線遠征 %d/5 · %s" % [mini(stage+1,5),TITLES[stage]]
 match stage:
  0:return prefix+"：實際送抵100糧，付費訓練2名軍人（%d/100糧，%d/2人）。" % [mini(supplied/1000,100),mini(trained,2)]
  1:return prefix+"：派斥候或軍隊探索前線箭塔；點目標列定位，迷霧仍需親自探索。"
  2:return prefix+"：摧毀前線箭塔，注意守軍；可研究城防時代、建工坊出攻城車。"
  3:
   if not counter_launched:return prefix+"：固定6人增援於%d秒後出發；回防主堡。集結區被堵會延後，不會重疊出兵。" % maxi(0,ceili((counter_due-tick)/20.0))
   return prefix+"：擊退全部6名劇本增援，保護主堡。"
  4:return prefix+"：摧毀敵方主堡；敵堡箭塔仍會正常防守。"
 return prefix+"：五個階段全部完成。"
func progress_text(tick:int,remaining:int=0)->String:
 match stage:
  0:return "糧 %d/100 · 軍人 %d/2" % [mini(supplied/1000,100),mini(trained,2)]
  1:return "探索前線箭塔 · 點此定位"
  2:return "摧毀前線箭塔 · 點此定位"
  3:
   if not counter_launched:
    var seconds=maxi(0,ceili((counter_due-tick)/20.0))
    return ("反攻 %d 秒後出發" % seconds) if seconds>0 else "集結區受阻 · 等候出發"
   return "反攻餘下 %d/6 · 保護主堡" % clampi(remaining,0,6)
  4:return "摧毀敵方主堡 · 點此定位"
 return "五個階段全部完成"
func report()->Dictionary:
 return {"stage":stage,"stage_ticks":stage_ticks.duplicate(),"counter_launched":counter_launched}
