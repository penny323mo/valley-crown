extends RefCounted
## Session-only, value-only observer. No commands, authority references or persistence.
const KEYS = ["select", "gather", "deposit", "house", "barracks", "soldier"]
const HINTS = [
	"點選己方村民，開始建立聚落。",
	"向漿果或樹木落指令：右擊；觸控先按「指令」再點目標。",
	"等待村民把負重送回主堡。攜帶資源還未入庫。",
	"選村民→民居→選位置→確認；等待施工完成。",
	"選村民→兵營→選位置→確認；等待施工完成。",
	"選兵營→訓練長槍兵；等待士兵出生，排隊不算完成。"
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
	if i == KEYS.size(): return "教學完成！採集、建造與出兵已掌握。"
	return ("已暫停 · " if paused else "") + "教學 %d/6：" % (i+1) + HINTS[i]
