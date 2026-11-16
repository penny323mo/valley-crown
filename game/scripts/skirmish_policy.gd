extends RefCounted
## Public match policy only; never modifies resources, vision, damage or production.
const IDS = ["practice", "standard", "pressure", "battle", "fortress", "survival"]
static func valid(id: String) -> String:
	return id if id in IDS else "standard"
static func title(id: String) -> String:
	return {"survival":"三波守城挑戰", "fortress":"城防會戰", "practice":"防守練習", "standard":"標準戰役", "pressure":"積極進攻", "battle":"快速交戰"}[valid(id)]
static func details(id: String) -> String:
	if valid(id)=="survival":return "單人劇本：你有完整城防基地、兩座箭塔和 12 名混合軍隊，45 秒後迎接第一波。依次抵禦槍兵／弓手、騎兵突擊、混合攻城車部隊；每波全部擊退後有 45 秒修塔補兵。擊退三波或摧毀敵堡取勝；主堡失守則敗。\n\n敵軍為固定劇本增援，不消耗敵方資源，普通經濟 AI 關閉。增援使用正常視野、尋路、攻擊與傷害規則，不能穿越被堵住的集結區。你仍可採集、建造、付費訓練與研究。不是對稱標準對戰。"
	return {"fortress":"雙方開局已有城防時代、完整兵營／靶場／馬廄／工坊、兩座箭塔及三座民居。各有長槍兵 4、弓手 4、騎兵 2、攻城車 2，可立即展開多兵種攻城與補兵。保留原有村民、斥候和起始資源；建築與軍隊為對稱劇本配置，不記作已付費建造。經濟教學關閉，使用標準電腦。摧毀敵方主堡取勝。", "battle":"雙方開局已有城防時代、額外一座民居，以及長槍兵 2、弓手 2、騎兵 1、攻城車 1。保留原有村民、斥候和資源；經濟教學關閉，使用標準電腦。主堡被毀會落敗。", "practice":"敵軍照常採集、建造與出兵，但不主動遠征。靠近敵軍仍會交戰，適合熟習經濟與攻城。", "standard":"敵軍集結至少 5 兵出征，兩次遠征至少相隔 90 秒。", "pressure":"敵軍集結至少 3 兵出征，兩次遠征至少相隔 60 秒。較早的小隊進攻會帶來持續壓力。"}[valid(id)] + "\n雙方使用相同資源、視野與戰鬥規則。"
static func muster(id: String) -> int:
	return 3 if valid(id)=="pressure" else 5
static func interval(id: String) -> int:
	return 1200 if valid(id)=="pressure" else 1800
static func offensive(id: String) -> bool:
	return valid(id)!="practice"
