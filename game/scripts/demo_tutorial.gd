extends RefCounted
## Value-only observer and presentation. Checkpointed achieved/skipped state; no commands.
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
# Short touch-only prompts for the two-line landscape card. Full instructions
# (including mouse and objective detail) remain in the existing Details pane.
const LANDSCAPE_HINTS=[
	"點選己方村民。",
	"選取村民後，點漿果或樹木採集。",
	"等村民送資源回主堡，才算入庫。",
	"選村民、民居、位置，再確認施工。",
	"選村民、兵營、位置，再確認施工。",
	"選兵營，訓練長槍兵並等待出生。",
	"選主堡，研究城防時代並等待完成。",
	"城防時代：建馬廄或工坊。",
	"在馬廄訓練騎兵，或在工坊訓練攻城車。",
	"選軍隊後點敵人，並造成傷害。"
]
func landscape_text(paused:bool)->String:
	var i=step()
	if i==KEYS.size():return "教學完成！"
	return ("已暫停 · " if paused else "")+LANDSCAPE_HINTS[i]

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

const TITLES=["選取村民","採集資源","送回資源","完成民居","完成兵營","訓練士兵","研究時代","完成進階建築","訓練進階兵種","實際交戰"]
func resume(): skipped=false
func checklist(paused:bool)->String:
	var lines=[text(paused),"定位只移動鏡頭，不選取或下令。"]
	for i in KEYS.size():
		lines.append(("[完成] " if achieved.has(KEYS[i]) else "[目前] " if i==step() else "[待做] ")+str(i+1)+". "+TITLES[i])
	return "\n".join(lines)
func locate(records:Dictionary)->Dictionary:
	var i=step()
	if i>=KEYS.size():return {"ok":false,"reason":"教學已完成。"}
	var kinds=[]
	match KEYS[i]:
		"select","house","barracks","advanced_building":kinds=["villager"]
		"gather":kinds=["berry","pine","oak"]
		"deposit","age2":kinds=["town_center"]
		"soldier":kinds=["barracks"]
		"advanced_unit":kinds=["stable","workshop"]
		"combat":kinds=["spearman","archer","cavalry","siege","scout"]
	var ids=records.keys();ids.sort()
	for id in ids:
		var r=records[id]
		if not r.get("alive",false) or r.get("remembered",false) or r.get("kind","") not in kinds:continue
		if KEYS[i]=="gather":
			if r.get("category","")!="resource":continue
		elif not r.get("owned",false):continue
		if r.get("category","")=="building" and not r.get("built",false):continue
		return {"ok":true,"id":id,"position":r.pos}
	return {"ok":false,"reason":"未找到所需的己方單位、已完工建築或視野內資源；請先按本步提示準備。"}
