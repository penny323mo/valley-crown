extends RefCounted
const Difficulty=preload("res://scripts/ai_difficulty.gd")
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
 {"id":"breach","group":3,"mode":"breach","victory":"conquest","title":"攻城突破"},
 {"id":"survival","group":3,"mode":"survival","victory":"conquest","title":"三波守城挑戰"},
 {"id":"escort","group":3,"mode":"escort","victory":"conquest","title":"護送拓荒隊"},
 {"id":"depot","group":3,"mode":"depot","victory":"conquest","title":"前線補給線"},
 {"id":"expedition","group":3,"mode":"expedition","victory":"conquest","title":"前線遠征"}]
const CAMPAIGN=["breach","survival","escort"]
const CAMPAIGN_TITLE="霧谷戰役"
const CAMPAIGN_BLURBS=["突破木柵、攻下敵方主堡。","擊退三波反攻，或攻下敵方主堡。","護送村民建成前哨，擊退最後的反攻。"]
const CAMPAIGN_WIN_REASONS=[["breach_complete"],["waves_defended","keep_destroyed"],["escort_complete"]]
static func campaign_completed(index:int,mode:String,outcome:String,reason:String)->bool:
 return index>=0 and index<CAMPAIGN.size() and mode==CAMPAIGN[index] and outcome=="victory" and reason in CAMPAIGN_WIN_REASONS[index]
static func option(id:String)->Dictionary:
 for item in OPTIONS:
  if item.id==id:return item
 return {}
static func briefing(mode:String,victory:String,difficulty:String="standard")->String:
 var sections=briefing_sections(mode,victory,difficulty)
 return "開局\n"+sections.opening+"\n\n敵軍\n"+sections.enemy+"\n\n勝利\n"+sections.win+"\n\n失敗\n"+sections.lose
static func briefing_sections(mode:String,victory:String,difficulty:String="standard")->Dictionary:
 var opening="5 名村民、1 名斥候及標準起始資源；由採集與建造開始。"
 var enemy="標準電腦：至少 5 兵出征，兩次遠征至少相隔 90 秒。"
 var win="摧毀敵方主堡。"
 var lose="我方主堡被毀或投降。普通對戰持續 60 秒無法復原亦會結束；40 分鐘上限可判和局。"
 if mode=="practice":enemy="電腦照常採集、建造與出兵，但不主動遠征；靠近仍會交戰。"
 elif mode=="pressure":enemy="積極電腦：至少 3 兵出征，兩次遠征至少相隔 60 秒；較早小隊進攻。"
 elif mode=="battle":opening="雙方開局已有城防時代、額外民居、長槍兵 2、弓手 2、騎兵 1、攻城車 1；保留村民、斥候與資源。"
 elif mode=="fortress":opening="雙方已有城防時代、兵營／靶場／馬廄／工坊、兩座箭塔與三座民居，長槍兵 4、弓手 4、騎兵 2、攻城車 2；保留村民、斥候與資源。"
 elif mode=="breach":
  opening="我方已有城防基地、兩座箭塔、槍兵4、弓手4、騎兵2及攻城車2在前線集結；保留村民、斥候及標準資源。"
  enemy="固定木柵、兩座箭塔及4名守軍；無經濟AI、無中途增援。初始配置不是付費所得，正常視野、尋路及傷害不變。"
  win="先摧毀木柵內前哨箭塔，再攻下敵堡。可正常採集補兵；任務暫不支援存檔。"
 elif mode=="survival":
  opening="完整城防基地、兩座箭塔及 12 名混合軍隊，45 秒後第一波。"
  enemy="固定三波劇本增援，普通經濟 AI 關閉，不消耗敵方資源；每波清除後有 45 秒整備。"
  win="擊退全部三波，或摧毀敵堡。"
 elif mode=="escort":
  opening+="三名起始村民為任務村民；至少一人到達前哨區（X -11 至 -3，Z 3 至 9）。此任務暫不支援存檔，普通戰役與遠征存檔不變。"
  enemy="正常付費完成前哨倉庫及箭塔後，30 秒迎接固定 6 人混合反攻；沒有經濟 AI，不消耗敵方資源。保留正常視野、尋路及傷害。"
  win="擊退全部反攻，至少一名任務村民及區內完成的倉庫、箭塔仍存活；建築被毀可重建。"
  lose="主堡被毀、三名任務村民全部死亡或投降。40 分鐘上限可判和局。"
 elif mode=="depot":
  opening+="額外有長槍兵2及弓手1；初始軍隊為劇本配置。"
  enemy="前線有固定長槍兵及弓手，正常視野與戰鬥。可從側翼繞過或擊退守軍，無定時增援。"
  win="前線區界內正常付費建倉庫，實際送抵木材120及糧食80；至少一座前線倉庫仍運作。主堡、區外倉庫、起始庫存、交易及退款不計。"
  lose="主堡被摧毀或投降；時限可判和局。此劇本暫不支援存檔。"
 elif mode=="expedition":
  opening+="可用分開本機存檔，普通戰役存檔不變；只支援相同版本。"
  enemy="固定守軍與一次 6 人反攻，不使用經濟 AI，不消耗敵方資源；攻破哨站後 30 秒出發。"
  win="送抵100糧與付費訓練2軍人、探索箭塔、攻破哨站、擊退反攻、摧毀敵堡，依次完成五階段。"
 if Difficulty.easy(mode,victory,difficulty):enemy="較低襲擊壓力："+Difficulty.details("easy")
 if victory!="control" and mode in ["standard","pressure","battle","fortress"]:enemy+="出征騎兵會襲擊視野內無護衛的外圍村民；派兵護衛或撤回主堡。"
 if mode in ["battle","fortress"]:opening+="此為對稱劇本開局，非付費建造或研究所得。"
 if victory=="control":
  lose="敵方先累積 180 秒控制亦會落敗。"+lose
  enemy="標準電腦，從兩名軍人開始爭奪據點。分數公開，敵軍位置仍受迷霧限制。"
  win="至少兩名軍人進入中央圈，且沒有敵軍；累積控制 180 秒，或摧毀敵堡。"
 elif victory=="supply":
  lose="敵方先送抵資源目標亦會落敗。"+lose
  enemy="標準電腦，雙方經濟規則相同。資源進度公開，敵軍位置仍受迷霧限制。"
  win="先實際送抵 600 糧及 400 木，或摧毀敵堡；起始庫存、退款與身上負重不計。同回合達標為和局。"
 return {"opening":opening,"enemy":enemy,"win":win,"lose":lose}
