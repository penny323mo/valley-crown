extends RefCounted
## Public match policy only; never modifies resources, vision, damage or production.
const IDS = ["practice", "standard", "pressure"]
static func valid(id: String) -> String:
	return id if id in IDS else "standard"
static func title(id: String) -> String:
	return {"practice":"防守練習", "standard":"標準戰役", "pressure":"積極進攻"}[valid(id)]
static func details(id: String) -> String:
	return {"practice":"敵軍照常採集、建造與出兵，但不主動遠征。靠近敵軍仍會交戰，適合熟習經濟與攻城。", "standard":"敵軍集結至少 5 兵出征，兩次遠征至少相隔 90 秒。", "pressure":"敵軍集結至少 3 兵出征，兩次遠征至少相隔 60 秒。較早的小隊進攻會帶來持續壓力。"}[valid(id)] + "\n雙方使用相同資源、視野與戰鬥規則。"
static func muster(id: String) -> int:
	return 3 if valid(id)=="pressure" else 5
static func interval(id: String) -> int:
	return 1200 if valid(id)=="pressure" else 1800
static func offensive(id: String) -> bool:
	return valid(id)!="practice"
