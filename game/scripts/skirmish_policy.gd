extends RefCounted
## Public match policy only; never modifies resources, vision, damage or production.
const IDS = ["practice", "standard", "pressure", "battle", "fortress", "survival", "expedition", "escort", "breach", "depot"]
static func valid(id: String) -> String:
	return id if id in IDS else "standard"
static func title(id: String) -> String:
	return {"depot":"前線補給線","breach":"攻城突破", "escort":"護送拓荒隊", "expedition":"前線遠征", "survival":"三波守城挑戰", "fortress":"城防會戰", "practice":"防守練習", "standard":"標準戰役", "pressure":"積極進攻", "battle":"快速交戰"}[valid(id)]
static func details(id: String) -> String:
	if valid(id)=="depot":return "保護採集隊，繞過或擊退前線守軍，在前線區界內付費建倉庫；實際送抵120木材及80糧食。村民會照常前往最近的交付點，請在前線附近採集。主堡、區外倉庫、交易、退款及起始庫存不計；不用升級倉庫。\n\n前線倉庫被毀可重建，已送抵的數量保留。完成時須有前線倉庫運作。主堡失守或投降則敗。此劇本暫不支援存檔，既有存檔不變。"
	if valid(id)=="breach":return "單人攻城任務：我方有城防基地、兩座箭塔及12名混合軍隊在前線集結，可立即出征，亦可正常採集及付費補兵。先摧毀木柵包圍的前哨箭塔，再攻下敵堡；我方主堡被毀或投降則敗。\n\n敵方為固定木柵、兩座箭塔及4名守軍，無經濟AI或中途增援。開局軍隊與建築均為明示劇本配置；沿用正常視野、碰撞、尋路、傷害。可以選擇進攻路線，定位不揭霧，不保證初始軍隊必勝。\n\n此任務暫不支援存檔；普通戰役與遠征存檔不變。"
	if valid(id)=="escort":return "單人任務：標記三名起始村民；至少一人抵達前哨區（X -11 至 -3，Z 3 至 9）。\n在區內正常付費完成一座倉庫及一座箭塔，30 秒後迎接固定 6 人混合反攻。全部擊退時，至少一名任務村民及兩座前哨建築必須存活。建築被毀可重建；主堡被毀或三名任務村民全部死亡即敗。\n\n敵軍是一次劇本增援，沒有經濟 AI，不消耗敵方資源。使用正常視野、尋路、採集、建造及傷害規則；定位不揭開迷霧。\n\n此任務暫不支援存檔，普通戰役及遠征存檔不變。"
	if valid(id)=="expedition":return "單人任務：由標準村民、斥候及資源開局。\n1. 實際送抵100糧並付費訓練2名軍人。\n2. 探索前線箭塔。\n3. 攻破哨站。\n4. 30秒後迎接固定6人反攻，全部擊退。\n5. 摧毀敵方主堡。\n\n頂部目標列可定位；定位不會揭開迷霧。敵軍是固定守軍與一次劇本增援，不消耗敵方資源、無經濟AI；正常視野、尋路、傷害與我方採集建造規則保留。主堡失守則敗。可提前完成戰鬥目標，但須依次完成五階段。\n\n可於暫停選單儲存遠征，使用分開本機存檔；普通戰役存檔不變。只支援相同遊戲版本。"
	if valid(id)=="survival":return "單人劇本：你有完整城防基地、兩座箭塔和 12 名混合軍隊，45 秒後迎接第一波。依次抵禦槍兵／弓手、騎兵突擊、混合攻城車部隊；每波全部擊退後有 45 秒修塔補兵。擊退三波或摧毀敵堡取勝；主堡失守則敗。\n\n敵軍為固定劇本增援，不消耗敵方資源，普通經濟 AI 關閉。增援使用正常視野、尋路、攻擊與傷害規則，不能穿越被堵住的集結區。你仍可採集、建造、付費訓練與研究。不是對稱標準對戰。"
	return {"fortress":"雙方開局已有城防時代、完整兵營／靶場／馬廄／工坊、兩座箭塔及三座民居。各有長槍兵 4、弓手 4、騎兵 2、攻城車 2，可立即展開多兵種攻城與補兵。保留原有村民、斥候和起始資源；建築與軍隊為對稱劇本配置，不記作已付費建造。經濟教學關閉，使用標準電腦。摧毀敵方主堡取勝。", "battle":"雙方開局已有城防時代、額外一座民居，以及長槍兵 2、弓手 2、騎兵 1、攻城車 1。保留原有村民、斥候和資源；經濟教學關閉，使用標準電腦。主堡被毀會落敗。", "practice":"敵軍照常採集、建造與出兵，但不主動遠征。靠近敵軍仍會交戰，適合熟習經濟與攻城。", "standard":"敵軍集結至少 5 兵出征，兩次遠征至少相隔 90 秒。", "pressure":"敵軍集結至少 3 兵出征，兩次遠征至少相隔 60 秒。較早的小隊進攻會帶來持續壓力。"}[valid(id)] + "\n雙方使用相同資源、視野與戰鬥規則。"+("出征時，新兵會先在主堡集結成隊，再按原出征間隔增援前線；守城及傷兵恢復優先。出征騎兵會襲擊視野內無守軍保護的外圍村民；派兵護衛採集線或撤回主堡可阻止襲擾。" if valid(id)!="practice" else "")
static func muster(id: String) -> int:
	return 3 if valid(id)=="pressure" else 5
static func interval(id: String) -> int:
	return 1200 if valid(id)=="pressure" else 1800
static func offensive(id: String) -> bool:
	return valid(id)!="practice"
