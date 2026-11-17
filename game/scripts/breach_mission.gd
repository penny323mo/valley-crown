extends RefCounted
## Public authored siege exercise. No economy/visibility/combat overrides.
const FRONT=Vector3(0,0,-13)
const KEEP=Vector3(25,0,-24)
const ARMY=["spearman","spearman","spearman","spearman","archer","archer","archer","archer","cavalry","cavalry","siege","siege"]
const TITLES=["攻破前哨","攻下敵堡","突破完成"]
var post_id=-1
var stage=0
var stage_ticks=[]
func advance(tick:int,post_alive:bool,keep_alive:bool)->bool:
 var changed=false
 if stage==0 and not post_alive:
  stage=1;stage_ticks.append(tick);changed=true
 if stage==1 and not keep_alive:
  stage=2;stage_ticks.append(tick);changed=true
 return changed
func target()->Vector3:return FRONT if stage==0 else KEEP
func caption()->String:
 if stage==0:return "破牆或繞路，推進偵察並摧毀前哨箭塔。"
 if stage==1:return "向敵堡推進偵察；摧毀敵堡，保護我方主堡。"
 return "前哨及敵堡已摧毀。"
