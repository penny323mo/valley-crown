extends RefCounted
## Presentation catalogue of existing supported configurations; no new AI rules.
const GROUPS=["經濟對戰","目標爭奪","立即交戰","劇本挑戰"]
const OPTIONS=[
 {"id":"practice","group":0,"mode":"practice","victory":"conquest","title":"防守練習"},
 {"id":"standard","group":0,"mode":"standard","victory":"conquest","title":"標準戰役"},
 {"id":"pressure","group":0,"mode":"pressure","victory":"conquest","title":"積極進攻"},
 {"id":"control","group":1,"mode":"standard","victory":"control","title":"中央據點爭奪"},
 {"id":"supply","group":1,"mode":"standard","victory":"supply","title":"資源爭奪戰"},
 {"id":"battle","group":2,"mode":"battle","victory":"conquest","title":"快速交戰"},
 {"id":"fortress","group":2,"mode":"fortress","victory":"conquest","title":"城防會戰"},
 {"id":"survival","group":3,"mode":"survival","victory":"conquest","title":"三波守城挑戰"},
 {"id":"expedition","group":3,"mode":"expedition","victory":"conquest","title":"前線遠征"}]
static func option(id:String)->Dictionary:
 for item in OPTIONS:
  if item.id==id:return item
 return {}
static func briefing(mode:String,victory:String)->String:
 var opening="5 名村民、1 名斥候及標準起始資源；由採集與建造開始。"
 var enemy="標準電腦：至少 5 兵出征，兩次遠征至少相隔 90 秒。"
 var win="摧毀敵方主堡。"
 var lose="我方主堡被毀或投降。普通對戰持續 60 秒無法復原亦會結束；40 分鐘上限可判和局。"
 if mode=="practice":enemy="電腦照常採集、建造與出兵，但不主動遠征；靠近仍會交戰。"
 elif mode=="pressure":enemy="積極電腦：至少 3 兵出征，兩次遠征至少相隔 60 秒；較早小隊進攻。"
 elif mode=="battle":opening="雙方開局已有城防時代、額外民居、長槍兵 2、弓手 2、騎兵 1、攻城車 1；保留村民、斥候與資源。"
 elif mode=="fortress":opening="雙方已有城防時代、兵營／靶場／馬廄／工坊、兩座箭塔與三座民居，長槍兵 4、弓手 4、騎兵 2、攻城車 2；保留村民、斥候與資源。"
 elif mode=="survival":
  opening="完整城防基地、兩座箭塔及 12 名混合軍隊，45 秒後第一波。"
  enemy="固定三波劇本增援，普通經濟 AI 關閉，不消耗敵方資源；每波清除後有 45 秒整備。"
  win="擊退全部三波，或摧毀敵堡。"
 elif mode=="expedition":
  opening+="可用分開本機存檔，普通戰役存檔不變；只支援相同版本。"
  enemy="固定守軍與一次 6 人反攻，不使用經濟 AI，不消耗敵方資源；攻破哨站後 30 秒出發。"
  win="送抵100糧與付費訓練2軍人、探索箭塔、攻破哨站、擊退反攻、摧毀敵堡，依次完成五階段。"
 if mode in ["battle","fortress"]:opening+="此為對稱劇本開局，非付費建造或研究所得。"
 if victory=="control":
  lose="敵方先累積 180 秒控制亦會落敗。"+lose
  enemy="標準電腦，從兩名軍人開始爭奪據點。分數公開，敵軍位置仍受迷霧限制。"
  win="至少兩名軍人進入中央圈，且沒有敵軍；累積控制 180 秒，或摧毀敵堡。"
 elif victory=="supply":
  lose="敵方先送抵資源目標亦會落敗。"+lose
  enemy="標準電腦，雙方經濟規則相同。資源進度公開，敵軍位置仍受迷霧限制。"
  win="先實際送抵 600 糧及 400 木，或摧毀敵堡；起始庫存、退款與身上負重不計。同回合達標為和局。"
 return "開局\n"+opening+"\n\n敵軍\n"+enemy+"\n\n勝利\n"+win+"\n\n失敗\n"+lose
