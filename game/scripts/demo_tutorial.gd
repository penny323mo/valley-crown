extends RefCounted
## Session-only, value-only observer. No commands, authority references or persistence.
const KEYS = ["select", "gather", "deposit", "house", "barracks", "soldier", "age2", "advanced_building", "advanced_unit", "combat"]
const HINTS = [
	"點選己方村民，開始建立聚落。",
	"向漿果或樹木落指令：右擊；觸控選取村民後，點漿果或樹木。",
	"等待村民把負重送回主堡。攜帶資源還未入庫。",
	"選村民→民居→選位置→確認；等待施工完成。",
	"選村民→兵營→選位置→確認；等待施工完成。",
	"選兵營→訓練長槍兵；等待士兵出生，排隊不算完成。",
	"選主堡→研究城防時代；採集所需資源，等待研究完成。",
	"城防時代：選村民建馬廄或工坊，等待完工。",
	"選馬廄訓練騎兵，或選工坊訓練攻城車，等待出生。",
	"選軍隊後點敵方單位或建築，自動攻擊；造成實際傷害。"
]
var achieved = {}
var skipped = false
func reset():
	achieved.clear()
	skipped = false
func skip(): skipped = true
func record(fact: String):
	if not skipped and fact in KEYS: achieved[fact] = true
func step() -> int:
	for i in KEYS.size():
		if not achieved.has(KEYS[i]): return i
	return KEYS.size()
func text(paused: bool) -> String:
	var i = step()
	if i == KEYS.size(): return "教學完成！採集、建造、研究、出兵與攻擊已掌握。"
	return ("已暫停 · " if paused else "") + "教學 %d/%d：" % [i+1,KEYS.size()] + HINTS[i]
