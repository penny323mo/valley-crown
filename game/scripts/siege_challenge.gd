extends RefCounted
## Explicit scripted reinforcement schedule, not paid AI production.
const PREPARE_TICKS=900 # 45 seconds of simulation time.
const WAVES=[
 ["spearman","spearman","spearman","spearman","archer","archer"],
 ["cavalry","cavalry","cavalry","cavalry","archer","archer","archer","archer"],
 ["siege","siege","spearman","spearman","spearman","spearman","archer","archer","archer","archer","cavalry","cavalry"]]
var wave=0
var active=[]
var next_tick=PREPARE_TICKS
var complete=false
func observe(tick: int, alive: Callable):
 if active.is_empty() or complete:return
 if active.any(func(id):return alive.call(id)):return
 active.clear()
 if wave==WAVES.size():complete=true
 else:next_tick=tick+PREPARE_TICKS
func ready(tick: int) -> bool:
 return not complete and active.is_empty() and wave<WAVES.size() and tick>=next_tick
func roster() -> Array:
 return WAVES[wave].duplicate() if wave<WAVES.size() else []
func launch(ids: Array) -> bool:
 if not active.is_empty() or complete or ids.size()!=roster().size() or ids.is_empty():return false
 active=ids.duplicate();wave+=1;return true
func caption(tick: int) -> String:
 if complete:return "守城挑戰：三波增援全部擊退。"
 if not active.is_empty():
  if wave==WAVES.size():return "守城挑戰：第 3 / 3 波 · 最後一波；守住主堡並擊退增援。"
  return "守城挑戰：第 %d / 3 波 · 擊退本波後有 45 秒整備；保護主堡。" % wave
 var seconds=_remaining_prepare_seconds(tick)
 if seconds==0:return "守城挑戰：第 %d / 3 波 · 待出發；可繼續整備。" % (wave+1)
 return "守城挑戰：第 %d / 3 波將於 %d 秒後抵達集結區；修塔、補兵、準備迎擊。" % [wave+1,seconds]

func _remaining_prepare_seconds(tick: int) -> int:
 return maxi(0,ceili((next_tick-tick)/20.0))

## Battlefield status for the public wave schedule only. Countdown zero
## waits for an authorized open launch cell; never implies units spawned.
func hud_caption(tick: int) -> String:
 if complete:return ""
 if not active.is_empty():
  return "3/3 最後一波" if wave==WAVES.size() else "%d/3 迎擊" % wave
 var seconds=_remaining_prepare_seconds(tick)
 return "%d/3 整備%d秒" % [wave+1,seconds] if seconds>0 else "%d/3 待出發" % (wave+1)
