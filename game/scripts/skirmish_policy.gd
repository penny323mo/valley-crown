extends RefCounted
## Public match policy only; never modifies resources, vision, damage or production.
const IDS = ["practice", "standard", "pressure", "battle", "fortress"]
static func valid(id: String) -> String:
	return id if id in IDS else "standard"
static func title(id: String) -> String:
	return {"fortress":"城防會戰", "practice":"防守練習", "standard":"標準戰役", "pressure":"積極進攻", "battle":"快速交戰"}[valid(id)]
static func details(id: String) -> String:
	return {"fortress":"雙方開局已有城防時代、完整兵營／靶場／馬廄／工坊、兩座箭塔及三座民居。各有長槍兵 4、弓手 4、騎兵 2、攻城車 2，可立即展開多兵種攻城與補兵。保留原有村民、斥候和起始資源；建築與軍隊為對稱劇本配置，不記作已付費建造。經濟教學關閉，使用標準電腦。摧毀敵方主堡取勝。", "battle":"雙方開局已有城防時代、額外一座民居，以及長槍兵 2、弓手 2、騎兵 1、攻城車 1。保留原有村民、斥候和資源；經濟教學關閉，使用標準電腦。主堡被毀會落敗。", "practice":"敵軍照常採集、建造與出兵，但不主動遠征。靠近敵軍仍會交戰，適合熟習經濟與攻城。", "standard":"敵軍集結至少 5 兵出征，兩次遠征至少相隔 90 秒。", "pressure":"敵軍集結至少 3 兵出征，兩次遠征至少相隔 60 秒。較早的小隊進攻會帶來持續壓力。"}[valid(id)] + "\n雙方使用相同資源、視野與戰鬥規則。"
static func muster(id: String) -> int:
	return 3 if valid(id)=="pressure" else 5
static func interval(id: String) -> int:
	return 1200 if valid(id)=="pressure" else 1800
static func offensive(id: String) -> bool:
	return valid(id)!="practice"
