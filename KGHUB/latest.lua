-- อาซ้อฟ่างKGHUB Roll/Buy v6.9.3 Color Tags + Server Resume
-- UI-only upgrade: responsive UIScale, safe viewport clamp, focus/hover feedback, automatic scroll canvas, richer settings panel.
-- Core Roll/Buy/Trader logic preserved from v4.1-readable.
if not game:IsLoaded() then game.Loaded:Wait() end
local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local WS=game:GetService("Workspace")
local UIS=game:GetService("UserInputService")
local TweenService=game:GetService("TweenService")
local HttpService=game:GetService("HttpService")
local LP=Players.LocalPlayer
local ENV=(getgenv and getgenv()) or _G
local KEY="__NBTHUB_ROLL_BUY_FINAL"
local old=ENV[KEY]
if type(old)=="table" and old.alive~=false then
 ENV.__KGHUB_RERUN_RESUME={savedAt=os.time(),placeId=game.PlaceId,autoRoll=old.autoRoll==true,autoBuy=old.autoBuy==true,traderAuto=old.traderAuto==true,autoClone=type(old.clone)=="table" and old.clone.enabled==true,eventCurrent=tostring(WS:GetAttribute("MutationEvent") or ""),eventLastHandled=type(old.eventPotion)=="table" and old.eventPotion.lastHandled or nil,eventLastResult=type(old.eventPotion)=="table" and old.eventPotion.lastResult or nil}
else ENV.__KGHUB_RERUN_RESUME=nil end
if type(old)=="table" and type(old.cleanup)=="function" then pcall(old.cleanup,"rerun"); task.wait() end
local RT={alive=true,connections={},autoRoll=false,autoBuy=false,traderAuto=false,traderBuyAll=false,traderBusy=false,busy=false,target=nil,lastTrigger=-1e9,nextRollAt=0,lastRollResultAt=0,rolls=0,bought=0,traderBought=0,chars={},muts={},rules={},ruleSeq=0,builderRarity=nil,traderTargets={},traderKnown={},traderBlocked={},traderEventId=0,traderPending=nil,rollBuyHold=false,rollBuyBatch=nil,lastBuyResult="",uiX=20,uiY=30,minimized=false,currentTab="ROLL"}
ENV[KEY]=RT
RT.eventPotion={enabled=false,events={},potions={["Luck Potion"]={enabled=false,amount=1},["Super Luck Potion"]={enabled=false,amount=1}},lastHandled=nil,lastResult="ยังไม่ทำงาน"}
RT.eventUI={}
RT.clone={enabled=false,rules={},ruleSeq=0,busy=false,lastActionAt=0,nextActionAt=0,status="หยุด",roundRobin=0,selectedSourceUUID=nil,selectedRuleId=nil,lastResult="ยังไม่ทำงาน"}
RT.cloneUI={}
RT.itemUseRemote=RS:WaitForChild("Remotes"):WaitForChild("Items"):WaitForChild("Use")
pcall(function() RT.itemClient=require(RS:WaitForChild("Data"):WaitForChild("DataService")).client; RT.itemClient:waitForData() end)
RT.getItemAmount=function(name)
 local items=RT.itemClient and RT.itemClient:get("Items")
 if type(items)~="table" then return 0 end
 for _,it in pairs(items) do if type(it)=="table" and tostring(it.Name or it.name)==tostring(name) then return math.max(0,math.floor(tonumber(it.amount or it.Amount or it.Quantity) or 0)) end end
 return 0
end
local function keep(c) RT.connections[#RT.connections+1]=c; return c end
local Remotes=RS:WaitForChild("Remotes"):WaitForChild("Characters")
local Roll=Remotes:WaitForChild("Roll")
local Buy=Remotes:WaitForChild("Buy")
local TraderRemotes=RS:WaitForChild("Remotes"):WaitForChild("Trader")
local TraderGetStock=TraderRemotes:WaitForChild("GetStock")
local TraderBuy=TraderRemotes:WaitForChild("Buy")
local Modules=RS:WaitForChild("Modules")
local CharacterInfo=require(Modules:WaitForChild("Characters"):WaitForChild("CharactersInfo"))
local MutationInfo=require(Modules:WaitForChild("Shared"):WaitForChild("MutationInfo"))
local CharacterAssets=RS:WaitForChild("Assets"):WaitForChild("Characters")
local ActiveAttacks=Modules:FindFirstChild("ActiveAttacks")
local ActiveSkillInfo=nil
pcall(function() ActiveSkillInfo=require(Modules:WaitForChild("ActiveSkillInfo")) end)
local rarityRank={Common=1,Rare=2,Epic=3,Legendary=4,Mythic=5,Secret=6,God=7,Limited=8,Supreme=9}
local tierColors={
 Common=Color3.fromRGB(104,112,126), Rare=Color3.fromRGB(66,120,220), Epic=Color3.fromRGB(142,78,210),
 Legendary=Color3.fromRGB(220,145,42), Mythic=Color3.fromRGB(210,70,135), Secret=Color3.fromRGB(44,178,190),
 God=Color3.fromRGB(218,70,70), Limited=Color3.fromRGB(235,185,60), Supreme=Color3.fromRGB(235,235,245)
}
local nativeTierColors=CharacterInfo.Colors or {}
local function tierColor(name) return nativeTierColors[tostring(name or "")] or tierColors[tostring(name or "")] or Color3.fromRGB(70,78,94) end
local function shadeColor(c,m)
 return Color3.new(math.clamp(c.R*m,0,1),math.clamp(c.G*m,0,1),math.clamp(c.B*m,0,1))
end
local function hasFast()
 if LP:GetAttribute("FastSummon") then return true end
 local now=WS:GetServerTimeNow()
 return now<(tonumber(LP:GetAttribute("FastRollEndsAt")) or 0) or now<(tonumber(WS:GetAttribute("FastRollEndsAt")) or 0)
end
local function delayNow() return hasFast() and 0.6 or 2.2 end
local SESSION=tostring(os.time())
local LOG="NBTHUB_ROLL_BUY_"..tostring(game.PlaceId).."_"..SESSION..".log"
local LATEST="NBTHUB_ROLL_BUY_LATEST.log"
local TRADER_CATALOG="NBTHUB_TRADER_CATALOG.json"
local RULES_FILE="NBTHUB_BUY_RULES.json"
local CONFIG_FILE="NBTHUB_CONFIG.json"
RT.cloneFile="KGHUB_AUTO_CLONE_RULES.json"
local function log(s)
 local line=os.date("!%Y-%m-%dT%H:%M:%SZ").." | "..tostring(s).."\n"
 if type(appendfile)=="function" then pcall(appendfile,LOG,line)
 elseif type(readfile)=="function" and type(writefile)=="function" then
  local oldText=""; pcall(function() oldText=readfile(LOG) end); pcall(writefile,LOG,oldText..line)
 end
end
do
 RT.autoStateFile="KGHUB_AUTOSTATE_V2.json"
 RT.writeAutoState=function(reason,armedOverride)
  if type(writefile)~="function" then return false end
  local armed=armedOverride
  if armed==nil then armed=RT.alive==true end
  local data={version=2,armed=armed==true,savedAt=os.time(),placeId=game.PlaceId,jobId=tostring(game.JobId or ""),autoRoll=RT.autoRoll==true,autoBuy=RT.autoBuy==true,traderAuto=RT.traderAuto==true,autoClone=RT.clone and RT.clone.enabled==true}
  local ok,json=pcall(function() return HttpService:JSONEncode(data) end)
  if not ok then return false end
  local ok2=pcall(writefile,RT.autoStateFile,json)
  if reason and reason~="heartbeat" and reason~="sync" then log("AUTOSTATE_WRITE | reason="..tostring(reason).." | armed="..tostring(data.armed).." | roll="..tostring(data.autoRoll).." | buy="..tostring(data.autoBuy).." | trader="..tostring(data.traderAuto).." | clone="..tostring(data.autoClone)) end
  return ok2
 end
 RT.readAutoState=function()
  if type(readfile)~="function" then return nil,"no_readfile" end
  local ok,text=pcall(readfile,RT.autoStateFile); if not ok or type(text)~="string" or text=="" then return nil,"missing" end
  local ok2,data=pcall(function() return HttpService:JSONDecode(text) end); if not ok2 or type(data)~="table" then return nil,"bad_json" end
  return data,nil
 end
end
RT.antiAfkConnection=nil
RT.antiAfkMode="jump_5m"
RT.antiAfkJumpNow=function(source)
 local ok,err=pcall(function()
  local character=LP.Character or LP.CharacterAdded:Wait()
  local humanoid=character:FindFirstChildOfClass("Humanoid")
  if not humanoid then error("Humanoid not found") end
  humanoid.Jump=true
  humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
 end)
 if ok then
  log("ANTI_AFK_JUMP | source="..tostring(source or "timer_5m"))
 else
  log("ANTI_AFK_JUMP_ERROR | source="..tostring(source or "timer_5m").." | "..tostring(err))
 end
 return ok,err
end
task.spawn(function()
 while RT.alive do
  task.wait(300)
  if RT.alive then RT.antiAfkJumpNow("timer_5m") end
 end
end)

local function listSelected(t)
 local out={}; for k,v in pairs(t) do if v then out[#out+1]=k end end; table.sort(out); return table.concat(out,",")
end
local function countSelected(t)
 local n=0; for _,v in pairs(t) do if v then n+=1 end end; return n
end
local function copySet(src)
 local out={}; for k,v in pairs(src or {}) do if v then out[k]=true end end; return out
end
local function sortedKeys(src)
 local out={}; for k,v in pairs(src or {}) do if v then out[#out+1]=tostring(k) end end; table.sort(out); return out
end
local function ruleToSave(r)
 return {id=r.id,type=r.type,enabled=r.enabled~=false,characters=sortedKeys(r.characters),rarity=r.rarity,mutations=sortedKeys(r.mutations)}
end
local function saveRules()
 if type(writefile)~="function" then return end
 local arr={}; for _,r in ipairs(RT.rules) do arr[#arr+1]=ruleToSave(r) end
 local ok,json=pcall(function() return HttpService:JSONEncode(arr) end)
 if ok then pcall(writefile,RULES_FILE,json) end
end
local function loadRules()
 if type(readfile)~="function" then return end
 local ok,text=pcall(readfile,RULES_FILE); if not ok or type(text)~="string" or text=="" then return end
 local ok2,data=pcall(function() return HttpService:JSONDecode(text) end); if not ok2 or type(data)~="table" then return end
 for _,raw in ipairs(data) do
  if type(raw)=="table" and (raw.type=="character" or raw.type=="rarity") then
   local rid=tonumber(raw.id)
   if rid then RT.ruleSeq=math.max(RT.ruleSeq,rid) else RT.ruleSeq+=1; rid=RT.ruleSeq end
   local r={id=rid,type=raw.type,enabled=raw.enabled~=false,rarity=raw.rarity,characters={},mutations={}}
   for _,x in ipairs(raw.characters or {}) do r.characters[tostring(x)]=true end
   for _,x in ipairs(raw.mutations or {}) do r.mutations[tostring(x)]=true end
   RT.rules[#RT.rules+1]=r
  end
 end
 log("RULES_LOADED | count="..#RT.rules)
end
local function setRulesFromSaved(data)
 RT.rules={}; RT.ruleSeq=0
 for _,raw in ipairs(type(data)=="table" and data or {}) do
  if type(raw)=="table" and (raw.type=="character" or raw.type=="rarity") then
   local rid=tonumber(raw.id); if rid then RT.ruleSeq=math.max(RT.ruleSeq,rid) else RT.ruleSeq+=1; rid=RT.ruleSeq end
   local r={id=rid,type=raw.type,enabled=raw.enabled~=false,rarity=raw.rarity,characters={},mutations={}}
   for _,x in ipairs(raw.characters or {}) do r.characters[tostring(x)]=true end
   for _,x in ipairs(raw.mutations or {}) do r.mutations[tostring(x)]=true end
   RT.rules[#RT.rules+1]=r
  end
 end
end
local function saveConfig()
 if type(writefile)~="function" then return false end
 local rules={}; for _,r in ipairs(RT.rules) do rules[#rules+1]=ruleToSave(r) end
 local cfg={version="6.7-event-potion",rules=rules,traderTargets=sortedKeys(RT.traderTargets),traderBuyAll=RT.traderBuyAll==true,builderChars=sortedKeys(RT.chars),builderMutations=sortedKeys(RT.muts),builderRarity=RT.builderRarity,eventPotion={enabled=RT.eventPotion.enabled==true,events=sortedKeys(RT.eventPotion.events),potions={Luck={enabled=RT.eventPotion.potions["Luck Potion"].enabled==true,amount=RT.eventPotion.potions["Luck Potion"].amount},SuperLuck={enabled=RT.eventPotion.potions["Super Luck Potion"].enabled==true,amount=RT.eventPotion.potions["Super Luck Potion"].amount}}},ui={x=RT.uiX or 20,y=RT.uiY or 30,minimized=RT.minimized==true,tab=RT.currentTab or "ROLL"}}
 local ok,json=pcall(function() return HttpService:JSONEncode(cfg) end)
 if not ok then log("CONFIG_SAVE_ERROR | encode="..tostring(json)); return false end
 local ok2,err=pcall(writefile,CONFIG_FILE,json)
 if ok2 then saveRules(); if RT.autoStateReady and RT.writeAutoState then pcall(function() RT.writeAutoState("sync",true) end) end; log("CONFIG_SAVED | rules="..#RT.rules.." | traderTargets="..#sortedKeys(RT.traderTargets)); return true end
 log("CONFIG_SAVE_ERROR | write="..tostring(err)); return false
end
local function loadConfigData()
 if type(readfile)~="function" then return false end
 local ok,text=pcall(readfile,CONFIG_FILE); if not ok or type(text)~="string" or text=="" then return false end
 local ok2,cfg=pcall(function() return HttpService:JSONDecode(text) end); if not ok2 or type(cfg)~="table" then log("CONFIG_LOAD_ERROR | "..tostring(cfg)); return false end
 if type(cfg.rules)=="table" then setRulesFromSaved(cfg.rules) end
 RT.traderTargets={}; for _,x in ipairs(cfg.traderTargets or {}) do RT.traderTargets[tostring(x)]=true end
 RT.traderBuyAll=cfg.traderBuyAll==true
 RT.chars={}; for _,x in ipairs(cfg.builderChars or {}) do RT.chars[tostring(x)]=true end
 RT.muts={}; for _,x in ipairs(cfg.builderMutations or {}) do RT.muts[tostring(x)]=true end
 RT.builderRarity=cfg.builderRarity
 if type(cfg.eventPotion)=="table" then
  local ep=cfg.eventPotion; RT.eventPotion.enabled=ep.enabled==true; RT.eventPotion.events={}
  for _,x in ipairs(ep.events or {}) do RT.eventPotion.events[tostring(x)]=true end
  local pp=type(ep.potions)=="table" and ep.potions or {}
  local function loadPotion(key,raw) if type(raw)=="table" then RT.eventPotion.potions[key].enabled=raw.enabled==true; RT.eventPotion.potions[key].amount=math.clamp(math.floor(tonumber(raw.amount) or 1),0,100) end end
  loadPotion("Luck Potion",pp.Luck); loadPotion("Super Luck Potion",pp.SuperLuck)
 end
 if type(cfg.ui)=="table" then RT.uiX=tonumber(cfg.ui.x) or 20; RT.uiY=tonumber(cfg.ui.y) or 30; RT.minimized=cfg.ui.minimized==true; RT.currentTab=tostring(cfg.ui.tab or "ROLL") end
 RT.autoRoll=false; RT.autoBuy=false; RT.traderAuto=false; RT.traderBusy=false; RT.traderPending=nil; RT.rollBuyHold=false; RT.rollBuyBatch=nil; RT.busy=false
 saveRules()
 log("CONFIG_LOADED | version="..tostring(cfg.version or "?").." | rules="..#RT.rules.." | safeToggles=OFF")
 return true
end
local function removeRuleById(id)
 for i=#RT.rules,1,-1 do if RT.rules[i].id==id then table.remove(RT.rules,i); break end end
 saveRules()
end
local function saveTraderCatalog()
 if type(writefile)~="function" then return end
 local arr={}
 for name,d in pairs(RT.traderKnown) do
  if type(d)=="table" then
   arr[#arr+1]={Name=tostring(name),DisplayName=d.DisplayName,Price=d.Price,Rarity=d.Rarity,MaxStock=d.MaxStock,Image=d.Image}
  end
 end
 table.sort(arr,function(a,b) return tostring(a.Name)<tostring(b.Name) end)
 local ok,json=pcall(function() return HttpService:JSONEncode(arr) end)
 if ok then pcall(writefile,TRADER_CATALOG,json) end
end
local function cleanup(reason)
 if not RT.alive then return end
 if tostring(reason)~="rerun" and RT.writeAutoState then pcall(function() RT.writeAutoState("cleanup:"..tostring(reason),false) end) end
 RT.alive=false; RT.autoRoll=false; RT.autoBuy=false; RT.traderAuto=false; RT.traderBusy=false; RT.rollBuyHold=false; RT.rollBuyBatch=nil; RT.eventPotion.enabled=false; if RT.clone then RT.clone.enabled=false; RT.clone.busy=false end
 for _,c in ipairs(RT.connections) do pcall(function() c:Disconnect() end) end
 if RT.ui then pcall(function() RT.ui:Destroy() end) end
 if ENV[KEY]==RT then ENV[KEY]=nil end
 log("REMOVE | reason="..tostring(reason))
end
RT.cleanup=cleanup
local charCatalog={}
for _,v in pairs(CharacterInfo.Characters or {}) do
 if type(v)=="table" then
  local chance=tonumber(v.Chance) or 0
  if chance>0 and chance~=69 then charCatalog[#charCatalog+1]=v end
 end
end
table.sort(charCatalog,function(a,b)
 local ra,rb=rarityRank[a.Rarity] or 99,rarityRank[b.Rarity] or 99
 if ra~=rb then return ra<rb end
 local ca,cb=tonumber(a.Chance) or 0,tonumber(b.Chance) or 0
 if ca~=cb then return ca>cb end
 return tostring(a.DisplayName or a.Name)<tostring(b.DisplayName or b.Name)
end)
local charSourceKey={}
for k,v in pairs(CharacterInfo.Characters or {}) do if type(v)=="table" and v.Name then charSourceKey[tostring(v.Name)]=k end end
local baseRollWeight=0
for _,c in ipairs(charCatalog) do baseRollWeight+=tonumber(c.Chance) or 0 end
local skillCache={}
local knownSkillConflicts={
 Tobi="SOURCE_CONFLICT: Description says blocks 10 hits; ActiveSkill.NumberofHits=25",
 Dio="SOURCE_CONFLICT: Description says Time Stop 20s; ActiveSkill.TimeStopDuration=30",
 Tsunade="SOURCE_CONFLICT: Description says passive heal 5%; module PassiveHealPercent=0.075 (7.5%)"
}
local function getSkillData(name)
 name=tostring(name or "")
 if skillCache[name]~=nil then return skillCache[name] or nil end
 local display=nil
 if type(ActiveSkillInfo)=="table" and type(ActiveSkillInfo.GetDisplay)=="function" then pcall(function() display=ActiveSkillInfo.GetDisplay(name) end) end
 if type(display)=="table" and type(display.Skill)=="table" and type(display.Module)=="table" then
  local obj=ActiveAttacks and ActiveAttacks:FindFirstChild(name)
  local m=display.Module
  local d={module=m,skill=display.Skill,moduleObject=obj,name=tostring(display.Name or m.Name or name),description=tostring(display.Description or m.Description or ""),image=tostring(display.Image or m.Image or ""),kind=m.Passive==true and "PASSIVE" or "ACTIVE",source="ActiveSkillInfo.GetDisplay"}
  skillCache[name]=d; return d
 end
 local obj=ActiveAttacks and ActiveAttacks:FindFirstChild(name)
 if not obj then skillCache[name]=false; return nil end
 local ok,m=pcall(require,obj)
 if not ok or type(m)~="table" or type(m.ActiveSkill)~="table" then skillCache[name]=false; return nil end
 local d={module=m,skill=m.ActiveSkill,moduleObject=obj,name=tostring(m.Name or name),description=tostring(m.Description or ""),image=tostring(m.Image or ""),kind=m.Passive==true and "PASSIVE" or "ACTIVE",source="ActiveAttacks fallback"}
 skillCache[name]=d; return d
end
local function noLuckChance(c)
 local p=(baseRollWeight>0) and ((tonumber(c.Chance) or 0)/baseRollWeight) or 0
 return p*100,(1-(1-p)^3)*100
end
local function dumpDataTable(tbl,prefix,depth,out,seen)
 out=out or {}; seen=seen or {}; if type(tbl)~="table" or seen[tbl] then return out end; seen[tbl]=true
 local keys={}; for k in pairs(tbl) do keys[#keys+1]=k end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do
  local v=tbl[k]; local key=(prefix=="" and tostring(k)) or (prefix.."."..tostring(k)); local tv=type(v)
  if tv=="string" or tv=="number" or tv=="boolean" then out[#out+1]=key.." = "..tostring(v)
  elseif tv=="table" and depth>0 then dumpDataTable(v,key,depth-1,out,seen) end
 end
 return out
end
local mutCatalog={}
for name,v in pairs(MutationInfo.Mutations or {}) do
 if type(v)=="table" then mutCatalog[#mutCatalog+1]={Name=name,Info=v} end
end
table.sort(mutCatalog,function(a,b)
 local da,db=tonumber(a.Info.Damage) or 0,tonumber(b.Info.Damage) or 0
 if da~=db then return da<db end
 return a.Name<b.Name
end)
loadRules()
loadConfigData()
RT.setupTeleportPersistence=function()
 local q=(type(queue_on_teleport)=="function" and queue_on_teleport) or (type(queueonteleport)=="function" and queueonteleport) or (type(queue_on_tp)=="function" and queue_on_tp) or (type(queueontp)=="function" and queueontp)
 local remoteURL=tostring(ENV.__KGHUB_REMOTE_URL or "")
 local loader
 if remoteURL~="" then
  local quoted=string.format("%q",remoteURL)
  loader="local E=(getgenv and getgenv()) or _G\nif E.__KGHUB_TP_BOOTED then return end\nE.__KGHUB_TP_BOOTED=true\nif game.PlaceId~=107653945083776 then E.__KGHUB_TP_BOOTED=nil return end\nif not game:IsLoaded() then game.Loaded:Wait() end\ntask.wait(1.5)\nE.__KGHUB_REMOTE_URL="..quoted.."\nlocal ok,src=pcall(function() return game:HttpGet("..quoted..") end)\nif not ok or type(src)~=\"string\" or #src<1000 then E.__KGHUB_TP_BOOTED=nil; warn(\"[KGHUB-TP] remote source missing\",src); return end\nlocal fn,err=loadstring(src)\nif not fn then E.__KGHUB_TP_BOOTED=nil; warn(\"[KGHUB-TP] compile failed\",err); return end\nlocal ok2,err2=pcall(fn)\nif not ok2 then E.__KGHUB_TP_BOOTED=nil; warn(\"[KGHUB-TP] run failed\",err2) end"
 else
  loader=[=[
local E=(getgenv and getgenv()) or _G
if E.__KGHUB_TP_BOOTED then return end
E.__KGHUB_TP_BOOTED=true
if game.PlaceId~=107653945083776 then E.__KGHUB_TP_BOOTED=nil return end
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1.5)
local ok,src=pcall(readfile,"KGHUB_v683.lua")
if not ok or type(src)~="string" or #src<1000 then E.__KGHUB_TP_BOOTED=nil; warn("[KGHUB-TP] source missing",src); return end
local fn,err=loadstring(src)
if not fn then E.__KGHUB_TP_BOOTED=nil; warn("[KGHUB-TP] compile failed",err); return end
local ok2,err2=pcall(fn)
if not ok2 then E.__KGHUB_TP_BOOTED=nil; warn("[KGHUB-TP] run failed",err2) end
]=]
 end
 local clearQ=(type(clear_teleport_queue)=="function" and clear_teleport_queue) or (type(clearteleportqueue)=="function" and clearteleportqueue) or (type(clear_tp_queue)=="function" and clear_tp_queue) or (type(cleartpqueue)=="function" and cleartpqueue)
 if type(clearQ)=="function" then local cok,cerr=pcall(clearQ); log("TP_QUEUE_CLEAR | ok="..tostring(cok).." | err="..tostring(cerr)) end
 if type(q)=="function" then
  local ok,err=pcall(q,loader)
  local sourceName=remoteURL~="" and "remote_url" or "KGHUB_v683.lua"
  log(ok and ("TP_QUEUE_READY | source="..sourceName) or ("TP_QUEUE_ERROR | "..tostring(err)))
  RT.teleportQueueReady=ok; RT.teleportSource=sourceName; RT.teleportRemoteURL=remoteURL
 else log("TP_QUEUE_UNAVAILABLE"); RT.teleportQueueReady=false end
 RT.teleportResumeSaved=false
 keep(LP.OnTeleport:Connect(function(state)
  if state~=Enum.TeleportState.Started or RT.teleportResumeSaved then return end
  RT.teleportResumeSaved=true
  if RT.writeAutoState then pcall(function() RT.writeAutoState("teleport_started",true) end) end
  local snap={savedAt=os.time(),placeId=game.PlaceId,autoRoll=RT.autoRoll==true,autoBuy=RT.autoBuy==true,traderAuto=RT.traderAuto==true,autoClone=RT.clone and RT.clone.enabled==true,eventCurrent=tostring(WS:GetAttribute("MutationEvent") or ""),eventLastHandled=RT.eventPotion.lastHandled,eventLastResult=RT.eventPotion.lastResult}
  local ok,json=pcall(function() return HttpService:JSONEncode(snap) end)
  if ok and type(writefile)=="function" then pcall(writefile,"KGHUB_v683_resume.json",json) end
  pcall(saveConfig); if RT.saveCloneConfig then pcall(RT.saveCloneConfig) end
  log("TP_RESUME_SAVED | roll="..tostring(snap.autoRoll).." | buy="..tostring(snap.autoBuy).." | trader="..tostring(snap.traderAuto).." | clone="..tostring(snap.autoClone).." | event="..snap.eventCurrent)
 end))
end
RT.setupTeleportPersistence()
local function pct(mult) return string.format("%+.1f%%",((tonumber(mult) or 1)-1)*100) end
local function itemMutation(v)
 local m=v and v.Mutation
 if m==nil or m==false or m=="" then return "Normal" end
 return tostring(m)
end
local function writeLatest(reason)
 if type(writefile)~="function" then return end
 local body=table.concat({
  "reason="..tostring(reason),
  "player="..LP.Name,
  "delayNow="..delayNow(),
  "autoRoll="..tostring(RT.autoRoll),
  "autoBuy="..tostring(RT.autoBuy),
  "rollBuyHold="..tostring(RT.rollBuyHold),
  "lastBuyResult="..tostring(RT.lastBuyResult or ""),
  "autoTrader="..tostring(RT.traderAuto),
  "traderBuyAll="..tostring(RT.traderBuyAll),
  "rules="..tostring(#RT.rules),
  "builderChars="..listSelected(RT.chars),
  "builderMutations="..listSelected(RT.muts),
  "builderRarity="..tostring(RT.builderRarity or ""),
  "traderTargets="..listSelected(RT.traderTargets),
  "mutationEvent="..tostring(WS:GetAttribute("MutationEvent") or ""),
  "eventPotionEnabled="..tostring(RT.eventPotion.enabled),
  "eventTargets="..listSelected(RT.eventPotion.events),
  "eventPotionLast="..tostring(RT.eventPotion.lastResult or ""),
  "rolls="..RT.rolls,
  "buyConfirmed="..RT.bought,
  "traderBuyConfirmed="..RT.traderBought
 },"\n")
 pcall(writefile,LATEST,body)
end
local pg=LP:WaitForChild("PlayerGui")
local oldGui=pg:FindFirstChild("NBTHUB_RollBuyFinalUI"); if oldGui then oldGui:Destroy() end
local gui=Instance.new("ScreenGui"); gui.Name="NBTHUB_RollBuyFinalUI"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=999999; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=pg; RT.ui=gui
local fullSize=UDim2.fromOffset(980,650)
local frame=Instance.new("Frame"); frame.Size=fullSize; frame.Position=UDim2.fromOffset(RT.uiX or 20,RT.uiY or 30); frame.BackgroundColor3=Color3.fromRGB(9,12,19); frame.BorderSizePixel=0; frame.Parent=gui; frame.Active=true; RT.uiFrame=frame
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,18)
local frameStroke=Instance.new("UIStroke"); frameStroke.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; frameStroke.LineJoinMode=Enum.LineJoinMode.Miter; frameStroke.Color=Color3.fromRGB(78,100,158); frameStroke.Transparency=0.18; frameStroke.Thickness=1.45; frameStroke.Parent=frame
local bgGradient=Instance.new("UIGradient"); bgGradient.Color=ColorSequence.new(Color3.fromRGB(14,18,28),Color3.fromRGB(7,9,15)); bgGradient.Rotation=90; bgGradient.Parent=frame
do
 local side=Instance.new("Frame"); side.Name="Sidebar"; side.Position=UDim2.fromOffset(0,0); side.Size=UDim2.fromOffset(190,650); side.BackgroundColor3=Color3.fromRGB(11,15,24); side.BorderSizePixel=0; side.ZIndex=0; side.Parent=frame
 local edge=Instance.new("Frame"); edge.Position=UDim2.fromOffset(189,12); edge.Size=UDim2.fromOffset(1,626); edge.BackgroundColor3=Color3.fromRGB(50,64,96); edge.BackgroundTransparency=0.35; edge.BorderSizePixel=0; edge.Parent=side
 local brand=Instance.new("TextLabel"); brand.Position=UDim2.fromOffset(18,18); brand.Size=UDim2.fromOffset(164,48); brand.BackgroundTransparency=1; brand.RichText=true; brand.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); brand.TextSize=20; brand.TextXAlignment=Enum.TextXAlignment.Left; brand.TextYAlignment=Enum.TextYAlignment.Top; brand.TextColor3=Color3.fromRGB(244,247,255); brand.Text="<b>อาซ้อฟ่างKGHUB</b>\n<font color='rgb(120,145,255)' size='15'>SUMMON CONTROL</font>"; brand.Parent=side
 local nav=Instance.new("TextLabel"); nav.Position=UDim2.fromOffset(18,78); nav.Size=UDim2.fromOffset(154,18); nav.BackgroundTransparency=1; nav.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); nav.TextSize=13; nav.TextColor3=Color3.fromRGB(160,178,210); nav.TextXAlignment=Enum.TextXAlignment.Left; nav.Text="เมนูหลัก"; nav.Parent=side
 local foot=Instance.new("TextLabel"); foot.Position=UDim2.fromOffset(18,560); foot.Size=UDim2.fromOffset(154,64); foot.BackgroundColor3=Color3.fromRGB(16,21,32); foot.BorderSizePixel=0; foot.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); foot.TextSize=12; foot.TextWrapped=true; foot.TextColor3=Color3.fromRGB(180,195,225); foot.Text="F5 ร้านค้า  •  F6 สุ่ม\nF7 ซื้อ  •  F8 ปิดสคริปต์\nv6.9.3 Color Tags"; foot.Parent=side; Instance.new("UICorner",foot).CornerRadius=UDim.new(0,10)
 local shell=Instance.new("Frame"); shell.Name="ContentShell"; shell.Position=UDim2.fromOffset(198,74); shell.Size=UDim2.fromOffset(770,528); shell.BackgroundColor3=Color3.fromRGB(13,17,26); shell.BackgroundTransparency=0.18; shell.BorderSizePixel=0; shell.ZIndex=0; shell.Parent=frame; Instance.new("UICorner",shell).CornerRadius=UDim.new(0,15)
 local sh=Instance.new("UIStroke"); sh.Color=Color3.fromRGB(55,70,108); sh.Transparency=0.62; sh.Parent=shell
end
do
 local s=Instance.new("UIScale"); s.Name="ResponsiveScale"; s.Parent=frame
 local cam=WS.CurrentCamera; local vp=(cam and cam.ViewportSize) or Vector2.new(1920,1080)
 s.Scale=math.clamp(math.min((vp.X-30)/980,(vp.Y-30)/650),0.58,1.04)
 if cam then keep(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() local v=cam.ViewportSize; s.Scale=math.clamp(math.min((v.X-30)/980,(v.Y-30)/650),0.58,1.04) end)) end
end
local accentBar=Instance.new("Frame"); accentBar.Size=UDim2.fromOffset(750,3); accentBar.Position=UDim2.fromOffset(210,64); accentBar.BorderSizePixel=0; accentBar.BackgroundColor3=Color3.fromRGB(91,112,220); accentBar.Parent=frame; Instance.new("UICorner",accentBar).CornerRadius=UDim.new(1,0)
local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(214,16); title.Size=UDim2.fromOffset(690,34); title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); title.TextSize=23; title.TextColor3=Color3.fromRGB(240,245,255); title.TextXAlignment=Enum.TextXAlignment.Left; title.RichText=true; title.Text="<b>อาซ้อฟ่างKGHUB</b>  <font color='rgb(132,153,255)'>ระบบสุ่มอัตโนมัติ</font>"; title.TextTruncate=Enum.TextTruncate.AtEnd; title.Parent=frame; title.Active=true
do local c=Instance.new("UITextSizeConstraint"); c.MinTextSize=15; c.MaxTextSize=24; c.Parent=title; title.TextScaled=true end
local status=Instance.new("TextLabel"); status.BackgroundTransparency=1; status.Position=UDim2.fromOffset(210,612); status.Size=UDim2.fromOffset(750,24); status.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); status.TextSize=16; status.TextColor3=Color3.fromRGB(205,216,238); status.TextXAlignment=Enum.TextXAlignment.Left; status.TextYAlignment=Enum.TextYAlignment.Top; status.TextTruncate=Enum.TextTruncate.AtEnd; status.Parent=frame
local function mkButton(parent,text,x,y,w,h)
 local b=Instance.new("TextButton"); b.Size=UDim2.fromOffset(w,h or 34); b.Position=UDim2.fromOffset(x,y); b.BackgroundColor3=Color3.fromRGB(27,34,49); b.BorderSizePixel=0; b.TextColor3=Color3.fromRGB(245,248,255); b.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); b.TextSize=17; b.Text=text; b.TextTruncate=Enum.TextTruncate.AtEnd; b.AutoButtonColor=false; b.Active=true; b.Parent=parent
 local press=Instance.new("UIScale"); press.Scale=1; press.Parent=b
 Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
 local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,10); pad.PaddingRight=UDim.new(0,10); pad.PaddingTop=UDim.new(0,2); pad.PaddingBottom=UDim.new(0,2); pad.Parent=b
 local st=Instance.new("UIStroke"); st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; st.LineJoinMode=Enum.LineJoinMode.Miter; st.Color=Color3.fromRGB(72,88,128); st.Transparency=0.34; st.Thickness=1.15; st.Parent=b
 b.MouseEnter:Connect(function() TweenService:Create(press,TweenInfo.new(0.10),{Scale=1.014}):Play() end)
 b.MouseLeave:Connect(function() TweenService:Create(press,TweenInfo.new(0.12),{Scale=1}):Play() end)
 b.MouseButton1Down:Connect(function() TweenService:Create(press,TweenInfo.new(0.05),{Scale=0.978}):Play() end)
 b.MouseButton1Up:Connect(function() TweenService:Create(press,TweenInfo.new(0.09),{Scale=1.014}):Play() end)
 return b
end
local function stylePanel(obj)
 Instance.new("UICorner",obj).CornerRadius=UDim.new(0,13)
 local st=Instance.new("UIStroke"); st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; st.LineJoinMode=Enum.LineJoinMode.Miter; st.Color=Color3.fromRGB(66,82,122); st.Transparency=0.38; st.Thickness=1.15; st.Parent=obj
end
local function styleTextBox(box)
 box.TextXAlignment=Enum.TextXAlignment.Left; box.PlaceholderColor3=Color3.fromRGB(130,145,170)
 local pad=Instance.new("UIPadding"); pad.PaddingLeft=UDim.new(0,12); pad.PaddingRight=UDim.new(0,10); pad.Parent=box
 local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(68,80,108); st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; st.LineJoinMode=Enum.LineJoinMode.Miter; st.Transparency=0.46; st.Thickness=1.1; st.Parent=box
 keep(box.Focused:Connect(function() TweenService:Create(st,TweenInfo.new(0.14),{Color=Color3.fromRGB(95,145,255),Transparency=0.05,Thickness=1.35}):Play() end))
 keep(box.FocusLost:Connect(function() TweenService:Create(st,TweenInfo.new(0.16),{Color=Color3.fromRGB(68,80,108),Transparency=0.55,Thickness=1}):Play() end))
 return st
end
local function styleScroll(scroll)
 scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new(); scroll.ScrollingDirection=Enum.ScrollingDirection.Y
 scroll.ScrollBarImageColor3=Color3.fromRGB(105,135,190); scroll.ScrollBarImageTransparency=0.22
end
local refreshTabs
local tabButtons={}
local tabOrder={"ROLL","RULES","TRADER","INFO","EVENT","CLONE","CONFIG"}
local tabLabels={ROLL="⚡  สุ่ม / ซื้อ",RULES="◆  กฎการซื้อ",TRADER="◈  ร้านค้า",INFO="◉  ข้อมูลตัวละคร",EVENT="✦  อีเวนต์ / ยา",CLONE="♊  Auto Clone",CONFIG="⚙  ตั้งค่า"}
for i,key in ipairs(tabOrder) do
 local b=mkButton(frame,tabLabels[key],16,104+(i-1)*50,158,40); b.TextSize=14; b.TextXAlignment=Enum.TextXAlignment.Left; tabButtons[key]=b
 keep(b.MouseButton1Click:Connect(function()
  RT.currentTab=key
  if refreshTabs then refreshTabs() end
  saveConfig()
  log("UI_TAB="..key)
 end))
end
local rollBtn=mkButton(frame,"สุ่มอัตโนมัติ: ปิด (F6)",210,86,360,56)
local buyBtn=mkButton(frame,"ซื้ออัตโนมัติ: ปิด (F7)",590,86,360,56)
local removeBtn=mkButton(frame,"REMOVE SCRIPT",690,132,260,46); removeBtn.BackgroundColor3=Color3.fromRGB(142,52,64)
local minBtn=mkButton(frame,"—",922,14,38,32); minBtn.TextSize=23
local minimized=RT.minimized==true
local function updateHeaderTitle()
 if minimized then title.Text="อาซ้อฟ่างKGHUB  •  R:"..(RT.autoRoll and "ON" or "OFF").." B:"..(RT.autoBuy and "ON" or "OFF").." T:"..(RT.traderAuto and "ON" or "OFF").." C:"..((RT.clone and RT.clone.enabled) and "ON" or "OFF")
 else title.Text="<b>อาซ้อฟ่างKGHUB</b>  <font color='rgb(132,153,255)'>ระบบสุ่มอัตโนมัติ</font>" end
end
local function setMinimized(v,silent)
 minimized=v and true or false; RT.minimized=minimized; frame.ClipsDescendants=minimized
 for _,child in ipairs(frame:GetChildren()) do
  if child:IsA("GuiObject") and child~=title and child~=minBtn then child.Visible=not minimized end
 end
 if minimized then frame.Size=UDim2.fromOffset(460,60); title.Position=UDim2.fromOffset(18,13); title.Size=UDim2.fromOffset(378,32); minBtn.Position=UDim2.fromOffset(410,12); minBtn.Text="+"
 else frame.Size=fullSize; title.Position=UDim2.fromOffset(214,16); title.Size=UDim2.fromOffset(690,34); minBtn.Position=UDim2.fromOffset(922,14); minBtn.Text="—" end
 do local sc=frame:FindFirstChild("ResponsiveScale"); local cam=WS.CurrentCamera; if sc and cam then local v=cam.ViewportSize; sc.Scale=math.clamp(math.min((v.X-30)/980,(v.Y-30)/650),0.58,1.04) end end
 updateHeaderTitle(); if not minimized and refreshTabs then refreshTabs() end; log("UI_MINIMIZED="..tostring(minimized))
 if not silent then saveConfig() end
end
keep(minBtn.MouseButton1Click:Connect(function() setMinimized(not minimized) end))
local dragging=false; local dragStart=nil; local startPos=nil
keep(title.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true; dragStart=input.Position; startPos=frame.Position end end))
keep(UIS.InputChanged:Connect(function(input) if dragging and input.UserInputType==Enum.UserInputType.MouseMovement and dragStart and startPos then local d=input.Position-dragStart; frame.Position=startPos+UDim2.fromOffset(d.X,d.Y) end end))
keep(UIS.InputEnded:Connect(function(input)
 if input.UserInputType==Enum.UserInputType.MouseButton1 then
  dragging=false; do local cam=WS.CurrentCamera; local vp=(cam and cam.ViewportSize) or Vector2.new(1920,1080); local sc=frame:FindFirstChild("ResponsiveScale"); local z=(sc and sc.Scale) or 1; local x=math.clamp(frame.Position.X.Offset,6,math.max(6,vp.X-frame.Size.X.Offset*z-6)); local y=math.clamp(frame.Position.Y.Offset,6,math.max(6,vp.Y-frame.Size.Y.Offset*z-6)); frame.Position=UDim2.fromOffset(x,y) end; RT.uiX=frame.Position.X.Offset; RT.uiY=frame.Position.Y.Offset; saveConfig()
 end
end))
local leftTitle=Instance.new("TextLabel"); leftTitle.BackgroundTransparency=1; leftTitle.Position=UDim2.fromOffset(210,158); leftTitle.Size=UDim2.fromOffset(350,24); leftTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); leftTitle.TextSize=18; leftTitle.TextColor3=Color3.fromRGB(224,232,248); leftTitle.TextXAlignment=Enum.TextXAlignment.Left; leftTitle.Text="ตัวละคร + ภาพตัวอย่าง | เลือกเป้าหมาย"; leftTitle.Parent=frame
local rightTitle=Instance.new("TextLabel"); rightTitle.BackgroundTransparency=1; rightTitle.Position=UDim2.fromOffset(590,158); rightTitle.Size=UDim2.fromOffset(360,24); rightTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); rightTitle.TextSize=18; rightTitle.TextColor3=Color3.fromRGB(224,232,248); rightTitle.TextXAlignment=Enum.TextXAlignment.Left; rightTitle.Text="ตัวกรองมิวเทชัน"; rightTitle.Parent=frame
local search=Instance.new("TextBox"); search.Size=UDim2.fromOffset(180,36); search.Position=UDim2.fromOffset(210,188); search.BackgroundColor3=Color3.fromRGB(31,35,44); search.BorderSizePixel=0; search.TextColor3=Color3.new(1,1,1); search.PlaceholderText="ค้นหาตัวละคร..."; search.Text=""; search.ClearTextOnFocus=false; search.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); search.TextSize=17; search.Parent=frame
Instance.new("UICorner",search).CornerRadius=UDim.new(0,7); styleTextBox(search)
local charTierOrder={"ALL","Common","Rare","Epic","Legendary","Mythic","Secret","God"}; local charTierIndex=1
local charTierBtn=mkButton(frame,"ระดับ: ทั้งหมด",400,188,92,36); charTierBtn.TextSize=13
local clearCharBtn=mkButton(frame,"ล้าง",500,188,60,36); clearCharBtn.TextSize=14; clearCharBtn.Active=true; clearCharBtn.Selectable=true
local function clearPortrait(vp)
 for _,c in ipairs(vp:GetChildren()) do if c:IsA("Camera") or c:IsA("WorldModel") or c:IsA("Model") then c:Destroy() end end
 vp.CurrentCamera=nil
end
local function renderFrontPortrait(vp,name)
 clearPortrait(vp)
 local src=CharacterAssets:FindFirstChild(tostring(name or "")); if not src then return false,"MODEL_NOT_FOUND" end
 local ok,clone=pcall(function() return src:Clone() end); if not ok or not clone then return false,"CLONE_FAILED" end
 local world=Instance.new("WorldModel"); world.Name="PortraitWorld"; world.Parent=vp
 local model
 if clone:IsA("Model") then model=clone else model=Instance.new("Model"); model.Name=tostring(name); clone.Parent=model end
 model.Parent=world
 for _,d in ipairs(model:GetDescendants()) do
  if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
  elseif d:IsA("BasePart") then d.Anchored=true; d.CanCollide=false; d.CanTouch=false; d.CanQuery=false
  elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then d.Enabled=false end
 end
 local bok,cf,size=pcall(function() local a,b=model:GetBoundingBox(); return a,b end)
 if not bok or not size or size.Magnitude<=0 then world:Destroy(); return false,"NO_BOUNDS" end
 model:PivotTo(model:GetPivot()+(Vector3.zero-cf.Position)); cf,size=model:GetBoundingBox()
 local ref=model:FindFirstChild("HumanoidRootPart",true) or model:FindFirstChild("Head",true)
 local front=(ref and ref:IsA("BasePart")) and ref.CFrame.LookVector or cf.LookVector
 if front.Magnitude<0.1 then front=Vector3.new(0,0,-1) end
 local camera=Instance.new("Camera"); camera.FieldOfView=30; camera.Parent=vp; vp.CurrentCamera=camera
 local maxDim=math.max(size.X,size.Y,size.Z); local dist=math.max(4.5,maxDim*1.65)
 local target=Vector3.new(0,size.Y*0.06,0); local pos=target+front.Unit*dist+Vector3.new(0,size.Y*0.04,0)
 camera.CFrame=CFrame.lookAt(pos,target)
 return true,"ReplicatedStorage.Assets.Characters."..tostring(name)
end
local charPanel=Instance.new("Frame"); charPanel.Size=UDim2.fromOffset(350,360); charPanel.Position=UDim2.fromOffset(210,232); charPanel.BackgroundColor3=Color3.fromRGB(22,25,32); charPanel.BorderSizePixel=0; charPanel.Parent=frame; stylePanel(charPanel)
local charGrid=Instance.new("Frame"); charGrid.BackgroundTransparency=1; charGrid.Position=UDim2.fromOffset(5,7); charGrid.Size=UDim2.fromOffset(340,310); charGrid.Parent=charPanel
local charGridLayout=Instance.new("UIGridLayout"); charGridLayout.CellSize=UDim2.fromOffset(165,72); charGridLayout.CellPadding=UDim2.fromOffset(6,6); charGridLayout.FillDirectionMaxCells=2; charGridLayout.Parent=charGrid
local charPageLabel=Instance.new("TextLabel"); charPageLabel.BackgroundTransparency=1; charPageLabel.Position=UDim2.fromOffset(99,326); charPageLabel.Size=UDim2.fromOffset(152,26); charPageLabel.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); charPageLabel.TextSize=14; charPageLabel.TextColor3=Color3.fromRGB(190,205,230); charPageLabel.Parent=charPanel
local charPrevBtn=mkButton(charPanel,"◀",8,324,44,28); charPrevBtn.TextSize=15
local charNextBtn=mkButton(charPanel,"▶",298,324,44,28); charNextBtn.TextSize=15
local charPage=1; local charPageSize=8; local charFiltered={}; local charCards={}
local refreshCharButtons
local function clearCharCards()
 for _,x in ipairs(charCards) do if x and x.Parent then x:Destroy() end end; charCards={}
end
local function makeCharCard(c)
 local card=Instance.new("Frame"); card.BackgroundColor3=shadeColor(tierColor(c.Rarity),0.48); card.BorderSizePixel=0; card.Parent=charGrid; Instance.new("UICorner",card).CornerRadius=UDim.new(0,8)
 local stroke=Instance.new("UIStroke"); stroke.Color=tierColor(c.Rarity); stroke.Transparency=0.28; stroke.Parent=card
 local vp=Instance.new("ViewportFrame"); vp.Position=UDim2.fromOffset(4,4); vp.Size=UDim2.fromOffset(56,56); vp.BackgroundColor3=Color3.fromRGB(12,14,20); vp.BorderSizePixel=0; vp.Ambient=Color3.fromRGB(175,175,175); vp.LightColor=Color3.fromRGB(255,255,255); vp.LightDirection=Vector3.new(-1,-1,-1); vp.Parent=card; Instance.new("UICorner",vp).CornerRadius=UDim.new(0,6); local vpAspect=Instance.new("UIAspectRatioConstraint"); vpAspect.AspectRatio=1; vpAspect.Parent=vp
 renderFrontPortrait(vp,c.Name)
 local shown=tostring(c.DisplayName or c.Name); if shown~=tostring(c.Name) then shown=shown.." ("..tostring(c.Name)..")" end
 local n=Instance.new("TextLabel"); n.BackgroundTransparency=1; n.Position=UDim2.fromOffset(64,5); n.Size=UDim2.fromOffset(101,31); n.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); n.TextSize=13; n.TextWrapped=true; n.TextXAlignment=Enum.TextXAlignment.Left; n.TextYAlignment=Enum.TextYAlignment.Top; n.TextColor3=Color3.fromRGB(248,250,255); n.Text=shown; n.Parent=card
 local meta=Instance.new("TextLabel"); meta.BackgroundTransparency=1; meta.Position=UDim2.fromOffset(64,38); meta.Size=UDim2.fromOffset(101,21); meta.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); meta.TextSize=12; meta.TextXAlignment=Enum.TextXAlignment.Left; meta.TextColor3=tierColor(c.Rarity); meta.Text=tostring(c.Rarity).." | $"..tostring(c.Price); meta.Parent=card
 local hit=Instance.new("TextButton"); hit.Size=UDim2.fromScale(1,1); hit.BackgroundTransparency=1; hit.Text=""; hit.ZIndex=5; hit.Parent=card
 local selected=RT.chars[tostring(c.Name)]==true; if selected then stroke.Thickness=2.4; stroke.Transparency=0; card.BackgroundColor3=shadeColor(tierColor(c.Rarity),0.78) end
 local cardBase=card.BackgroundColor3; hit.MouseEnter:Connect(function() TweenService:Create(card,TweenInfo.new(0.12),{BackgroundColor3=shadeColor(tierColor(c.Rarity),selected and 0.90 or 0.58)}):Play(); TweenService:Create(stroke,TweenInfo.new(0.12),{Transparency=0.05}):Play() end); hit.MouseLeave:Connect(function() TweenService:Create(card,TweenInfo.new(0.16),{BackgroundColor3=cardBase}):Play(); TweenService:Create(stroke,TweenInfo.new(0.16),{Transparency=selected and 0 or 0.28}):Play() end)
 local badge=Instance.new("TextLabel"); badge.Position=UDim2.fromOffset(145,4); badge.Size=UDim2.fromOffset(20,20); badge.BackgroundColor3=selected and Color3.fromRGB(45,155,95) or Color3.fromRGB(32,36,46); badge.BorderSizePixel=0; badge.Text=selected and "✓" or ""; badge.TextColor3=Color3.new(1,1,1); badge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); badge.TextSize=15; badge.ZIndex=4; badge.Parent=card; Instance.new("UICorner",badge).CornerRadius=UDim.new(1,0)
 hit.Activated:Connect(function() local key=tostring(c.Name); RT.chars[key]=not RT.chars[key]; log("CHAR_SELECT | "..key.."="..tostring(RT.chars[key])); refreshCharButtons(); saveConfig(); writeLatest("character_select") end)
 charCards[#charCards+1]=card
end
refreshCharButtons=function()
 leftTitle.Text="ตัวละคร + ภาพตัวอย่าง | เลือกแล้ว "..countSelected(RT.chars).." / "..#charCatalog
 local q=string.lower(search.Text or ""); charFiltered={}
 local tier=charTierOrder[charTierIndex]
 for _,c in ipairs(charCatalog) do local hay=string.lower(tostring(c.Name or "").." "..tostring(c.DisplayName or "")); local tierOk=tier=="ALL" or tostring(c.Rarity)==tier; if tierOk and (q=="" or string.find(hay,q,1,true)) then charFiltered[#charFiltered+1]=c end end
 local pages=math.max(1,math.ceil(#charFiltered/charPageSize)); charPage=math.clamp(charPage,1,pages); clearCharCards()
 local first=(charPage-1)*charPageSize+1; local last=math.min(#charFiltered,first+charPageSize-1)
 if tostring(RT.currentTab)=="ROLL" and not minimized then for i=first,last do makeCharCard(charFiltered[i]) end end
 charPageLabel.Text=string.format("%d-%d / %d • %d/%d",#charFiltered>0 and first or 0,last,#charFiltered,charPage,pages)
 charPrevBtn.BackgroundTransparency=charPage>1 and 0 or 0.45; charNextBtn.BackgroundTransparency=charPage<pages and 0 or 0.45
end
local charSearchToken=0
keep(search:GetPropertyChangedSignal("Text"):Connect(function() charSearchToken+=1; local token=charSearchToken; task.delay(0.18,function() if RT.alive and token==charSearchToken then charPage=1; refreshCharButtons() end end) end))
keep(charTierBtn.Activated:Connect(function() charTierIndex=charTierIndex%#charTierOrder+1; local tier=charTierOrder[charTierIndex]; charTierBtn.Text="ระดับ: "..(tier=="ALL" and "ทั้งหมด" or tier); charTierBtn.BackgroundColor3=tier=="ALL" and Color3.fromRGB(42,48,64) or shadeColor(tierColor(tier),0.65); charPage=1; refreshCharButtons() end))
keep(charPrevBtn.Activated:Connect(function() if charPage>1 then charPage-=1; refreshCharButtons() end end))
keep(charNextBtn.Activated:Connect(function() local pages=math.max(1,math.ceil(#charFiltered/charPageSize)); if charPage<pages then charPage+=1; refreshCharButtons() end end))
local function clearCharacterSelection()
 RT.chars={}; search.Text=""; charPage=1; charTierIndex=1; charTierBtn.Text="ระดับ: ทั้งหมด"; charTierBtn.BackgroundColor3=Color3.fromRGB(42,48,64); log("CHAR_CLEAR | selected=0 | search_cleared=true"); refreshCharButtons(); saveConfig(); writeLatest("character_clear")
end
keep(clearCharBtn.Activated:Connect(clearCharacterSelection))
local mutScroll=Instance.new("ScrollingFrame"); mutScroll.Size=UDim2.fromOffset(360,404); mutScroll.Position=UDim2.fromOffset(590,188); mutScroll.BackgroundColor3=Color3.fromRGB(22,25,32); mutScroll.BorderSizePixel=0; mutScroll.ScrollBarThickness=6; mutScroll.CanvasSize=UDim2.new(); mutScroll.Parent=frame; stylePanel(mutScroll); styleScroll(mutScroll)
local mutLayout=Instance.new("UIListLayout"); mutLayout.Padding=UDim.new(0,6); mutLayout.Parent=mutScroll
RT.mutationGradientFolder=RS:WaitForChild("Assets"):FindFirstChild("MutationGradient")
local mutButtons={}
local function refreshMutButtons()
 rightTitle.Text="ตัวกรองมิวเทชัน • เลือกแล้ว "..countSelected(RT.muts).." | ไม่เลือก = ทั้งหมด"
 for _,x in ipairs(mutButtons) do
  local selected=RT.muts[x.key]==true
  x.button.BackgroundColor3=selected and Color3.fromRGB(32,41,59) or Color3.fromRGB(25,30,42)
  local st=x.button:FindFirstChildOfClass("UIStroke")
  if st then st.Color=x.color or Color3.fromRGB(92,110,150); st.Transparency=selected and 0.02 or 0.42; st.Thickness=selected and 1.7 or 1.05 end
  local badge=x.button:FindFirstChild("SelectedBadge")
  if badge then badge.Visible=selected; badge.BackgroundColor3=shadeColor(x.color or Color3.fromRGB(92,110,150),0.72) end
 end
end
local function addMutButton(key,meta,sub)
 local h=key=="ANY" and 58 or 68
 local b=mkButton(mutScroll,"",4,0,350,h); b.Size=UDim2.new(1,-8,0,h); b.Text=""; b.ClipsDescendants=true
 local gameGrad=RT.mutationGradientFolder and RT.mutationGradientFolder:FindFirstChild(key)
 local base=Color3.fromRGB(115,130,165)
 if gameGrad and gameGrad:IsA("UIGradient") and #gameGrad.Color.Keypoints>0 then base=gameGrad.Color.Keypoints[1].Value end local bar=Instance.new("Frame"); bar.Name="MutationBar"; bar.Position=UDim2.fromOffset(8,9); bar.Size=UDim2.new(0,5,1,-18); bar.BackgroundColor3=gameGrad and Color3.new(1,1,1) or base; bar.BorderSizePixel=0; bar.ZIndex=3; bar.Parent=b; Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0)
 if gameGrad and gameGrad:IsA("UIGradient") then local g=gameGrad:Clone(); g.Name="GameMutationGradient"; g.Parent=bar end
 local t=Instance.new("TextLabel"); t.Name="MutationTitle"; t.BackgroundTransparency=1; t.Position=UDim2.fromOffset(22,6); t.Size=UDim2.new(1,-96,0,22); t.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); t.TextSize=17; t.TextXAlignment=Enum.TextXAlignment.Left; t.TextColor3=Color3.fromRGB(245,248,255); t.Text=key=="ANY" and "ทุกมิวเทชัน" or key; t.ZIndex=3; t.Parent=b
 if gameGrad and gameGrad:IsA("UIGradient") then local g=gameGrad:Clone(); g.Name="GameMutationGradient"; g.Parent=t end
 local m=Instance.new("TextLabel"); m.Name="MutationMeta"; m.BackgroundTransparency=1; m.Position=UDim2.fromOffset(22,29); m.Size=UDim2.new(1,-34,0,18); m.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); m.TextSize=14; m.TextXAlignment=Enum.TextXAlignment.Left; m.TextColor3=Color3.fromRGB(221,229,244); m.TextTruncate=Enum.TextTruncate.AtEnd; m.Text=meta; m.ZIndex=3; m.Parent=b
 local s=Instance.new("TextLabel"); s.Name="MutationSub"; s.BackgroundTransparency=1; s.Position=UDim2.fromOffset(22,47); s.Size=UDim2.new(1,-34,0,16); s.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); s.TextSize=13; s.TextXAlignment=Enum.TextXAlignment.Left; s.TextColor3=Color3.fromRGB(158,177,208); s.TextTruncate=Enum.TextTruncate.AtEnd; s.Text=sub or ""; s.ZIndex=3; s.Parent=b
 local badge=Instance.new("TextLabel"); badge.Name="SelectedBadge"; badge.AnchorPoint=Vector2.new(1,0); badge.Position=UDim2.new(1,-8,0,7); badge.Size=UDim2.fromOffset(62,20); badge.BackgroundColor3=shadeColor(base,0.72); badge.BorderSizePixel=0; badge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); badge.TextSize=11; badge.TextColor3=Color3.fromRGB(255,255,255); badge.Text="เลือกแล้ว"; badge.Visible=false; badge.ZIndex=4; badge.Parent=b; Instance.new("UICorner",badge).CornerRadius=UDim.new(0.5,0)
 mutButtons[#mutButtons+1]={button=b,key=key,color=base}
 keep(b.MouseButton1Click:Connect(function()
  if key=="ANY" then RT.muts={ANY=not RT.muts.ANY} else RT.muts.ANY=nil; RT.muts[key]=not RT.muts[key] end
  log("MUT_SELECT | "..key.."="..tostring(RT.muts[key])); refreshMutButtons(); saveConfig(); writeLatest("mutation_select")
 end))
end
addMutButton("ANY","ซื้อตัวละครเป้าหมายโดยไม่จำกัดมิวเทชัน","ใช้เมื่อไม่ได้ต้องการมิวเทชันเฉพาะ")
for _,m in ipairs(mutCatalog) do
 local i=m.Info
 local meta="ดาเมจ "..pct(i.Damage).." • HP "..pct(i.Health).." • ป้องกัน "..pct(i.Defense)
 local sub=(tonumber(i.Chance) or 0)>0 and ("โอกาสปกติ: "..tostring(i.Chance)) or ("โอกาสอีเวนต์: "..tostring(i.EventChance or 0))
 addMutButton(m.Name,meta,sub)
end
refreshCharButtons(); refreshMutButtons()
local refresh
local rulesTitle=Instance.new("TextLabel")
rulesTitle.BackgroundTransparency=1; rulesTitle.Position=UDim2.fromOffset(210,84); rulesTitle.Size=UDim2.fromOffset(740,50)
rulesTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); rulesTitle.TextSize=18; rulesTitle.RichText=true; rulesTitle.TextWrapped=true
rulesTitle.TextColor3=Color3.fromRGB(235,241,255); rulesTitle.TextXAlignment=Enum.TextXAlignment.Left; rulesTitle.TextYAlignment=Enum.TextYAlignment.Top; rulesTitle.Parent=frame
local addCharRuleBtn=mkButton(frame,"+ เพิ่มกฎตัวละคร",210,142,176,40); addCharRuleBtn.TextSize=15; addCharRuleBtn.BackgroundColor3=Color3.fromRGB(44,79,153)
local addRarityRuleBtn=mkButton(frame,"+ เพิ่มกฎระดับ",394,142,176,40); addRarityRuleBtn.TextSize=15; addRarityRuleBtn.BackgroundColor3=Color3.fromRGB(53,72,130)
local clearBuilderBtn=mkButton(frame,"ล้างตัวเลือก",578,142,150,40); clearBuilderBtn.TextSize=14
local saveConfigBtn=mkButton(frame,"SAVE CONFIG",210,132,220,46); saveConfigBtn.BackgroundColor3=Color3.fromRGB(55,100,155)
local loadConfigBtn=mkButton(frame,"LOAD CONFIG",450,132,220,46); loadConfigBtn.BackgroundColor3=Color3.fromRGB(70,88,145)
local deleteRulesBtn=mkButton(frame,"ลบกฎทั้งหมด",812,142,138,40); deleteRulesBtn.TextSize=14; deleteRulesBtn.BackgroundColor3=Color3.fromRGB(101,45,55)
local rarityNames={"Common","Rare","Epic","Legendary","Mythic","Secret","God"}
local rarityButtons={}
local function refreshRarityButtons()
 for rn,rb in pairs(rarityButtons) do
  local base=tierColor(rn); local selected=RT.builderRarity==rn
  rb.BackgroundColor3=selected and shadeColor(base,0.82) or Color3.fromRGB(28,34,48); rb.Text=(selected and "✓ " or "")..rn; rb.TextColor3=selected and Color3.fromRGB(255,255,255) or Color3.fromRGB(207,217,237)
  local st=rb:FindFirstChildOfClass("UIStroke"); if st then st.Color=base; st.Transparency=selected and 0.05 or 0.48; st.Thickness=selected and 1.6 or 1 end
 end
end
for i,name in ipairs(rarityNames) do
 local b=mkButton(frame,name,210+(i-1)*106,190,98,34); b.TextSize=13; rarityButtons[name]=b
 keep(b.MouseButton1Click:Connect(function() RT.builderRarity=(RT.builderRarity==name) and nil or name; log("RULE_BUILDER_RARITY="..tostring(RT.builderRarity)); refreshRarityButtons(); saveConfig() end))
end
refreshRarityButtons()local ruleScroll=Instance.new("ScrollingFrame"); ruleScroll.Size=UDim2.fromOffset(740,358); ruleScroll.Position=UDim2.fromOffset(210,232); ruleScroll.BackgroundColor3=Color3.fromRGB(17,22,31); ruleScroll.BorderSizePixel=0; ruleScroll.ScrollBarThickness=5; ruleScroll.CanvasSize=UDim2.new(); ruleScroll.Parent=frame; stylePanel(ruleScroll); styleScroll(ruleScroll)
local ruleLayout=Instance.new("UIListLayout"); ruleLayout.Padding=UDim.new(0,7); ruleLayout.Parent=ruleScroll
local function ruleMutText(r)
 local ks=sortedKeys(r.mutations); if #ks==0 or r.mutations.ANY then return "ทุกมิวเทชัน" end; return table.concat(ks," / ")
end
local function ruleTargetText(r)
 if r.type=="rarity" then return "ระดับ "..tostring(r.rarity) end
 local ks=sortedKeys(r.characters); return #ks>0 and table.concat(ks,", ") or "ไม่พบเป้าหมาย"
end
local function ruleTierName(r)
 if r.type=="rarity" then return tostring(r.rarity or "Common") end
 local best="Common"; local bestRank=0
 for charName in pairs(r.characters or {}) do
  for _,c in ipairs(charCatalog) do
   if tostring(c.Name)==tostring(charName) then local rank=rarityRank[c.Rarity] or 0; if rank>bestRank then bestRank=rank; best=tostring(c.Rarity) end; break end
  end
 end
 return best
end
local refreshRulesUI

RT.openRuleEditor=function(rule,displayIndex)
 if type(rule)~="table" then return end
 if RT.ruleEditorOverlay and RT.ruleEditorOverlay.Parent then RT.ruleEditorOverlay:Destroy() end
 local draftChars=copySet(rule.characters or {})
 local draftMuts=copySet(rule.mutations or {})
 local draftRarity=rule.rarity
 local overlay=Instance.new("Frame"); overlay.Name="RuleEditorOverlay"; overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundColor3=Color3.fromRGB(5,8,14); overlay.BackgroundTransparency=0.16; overlay.ZIndex=600; overlay.Parent=gui; RT.ruleEditorOverlay=overlay
 local backdrop=Instance.new("TextButton"); backdrop.Size=UDim2.fromScale(1,1); backdrop.BackgroundTransparency=1; backdrop.Text=""; backdrop.ZIndex=600; backdrop.Parent=overlay
 local modal=Instance.new("Frame"); modal.Name="RuleEditorModal"; modal.AnchorPoint=Vector2.new(0.5,0.5); modal.Position=UDim2.fromScale(0.5,0.5); modal.Size=UDim2.fromOffset(800,560); modal.BackgroundColor3=Color3.fromRGB(13,18,27); modal.BorderSizePixel=0; modal.ZIndex=601; modal.Parent=overlay; Instance.new("UICorner",modal).CornerRadius=UDim.new(0,14)
 local mst=Instance.new("UIStroke"); mst.Color=Color3.fromRGB(78,103,170); mst.Transparency=0.18; mst.Thickness=1.5; mst.Parent=modal
 local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(20,14); title.Size=UDim2.fromOffset(640,30); title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); title.TextSize=22; title.TextColor3=Color3.fromRGB(245,248,255); title.TextXAlignment=Enum.TextXAlignment.Left; title.ZIndex=602; title.Text="แก้ไขกฎ #"..tostring(displayIndex or "?").." • "..(rule.type=="rarity" and "กฎระดับ" or "กฎตัวละคร"); title.Parent=modal
 local sub=Instance.new("TextLabel"); sub.BackgroundTransparency=1; sub.Position=UDim2.fromOffset(20,47); sub.Size=UDim2.fromOffset(720,22); sub.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); sub.TextSize=14; sub.TextColor3=Color3.fromRGB(158,178,212); sub.TextXAlignment=Enum.TextXAlignment.Left; sub.ZIndex=602; sub.Text="แก้เฉพาะกฎนี้ • ID เดิมและสถานะเปิด/ปิดจะคงไว้"; sub.Parent=modal
 local closeBtn=mkButton(modal,"✕",748,14,32,34); closeBtn.TextSize=19; closeBtn.ZIndex=603; closeBtn.BackgroundColor3=Color3.fromRGB(67,42,52)
 local leftTitle2=Instance.new("TextLabel"); leftTitle2.BackgroundTransparency=1; leftTitle2.Position=UDim2.fromOffset(20,82); leftTitle2.Size=UDim2.fromOffset(360,24); leftTitle2.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); leftTitle2.TextSize=17; leftTitle2.TextColor3=Color3.fromRGB(230,237,250); leftTitle2.TextXAlignment=Enum.TextXAlignment.Left; leftTitle2.ZIndex=602; leftTitle2.Text=rule.type=="rarity" and "ระดับเป้าหมาย" or "ตัวละครเป้าหมาย"; leftTitle2.Parent=modal
 local mutTitle2=leftTitle2:Clone(); mutTitle2.Position=UDim2.fromOffset(410,82); mutTitle2.Text="มิวเทชัน"; mutTitle2.Parent=modal
 local leftPanel=Instance.new("Frame"); leftPanel.Position=UDim2.fromOffset(20,112); leftPanel.Size=UDim2.fromOffset(370,372); leftPanel.BackgroundColor3=Color3.fromRGB(18,24,35); leftPanel.BorderSizePixel=0; leftPanel.ZIndex=602; leftPanel.Parent=modal; Instance.new("UICorner",leftPanel).CornerRadius=UDim.new(0,10)
 local mutPanel=Instance.new("Frame"); mutPanel.Position=UDim2.fromOffset(410,112); mutPanel.Size=UDim2.fromOffset(370,372); mutPanel.BackgroundColor3=Color3.fromRGB(18,24,35); mutPanel.BorderSizePixel=0; mutPanel.ZIndex=602; mutPanel.Parent=modal; Instance.new("UICorner",mutPanel).CornerRadius=UDim.new(0,10)
 local function makeListButton(parent,text,h)
  local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-8,0,h or 40); b.BackgroundColor3=Color3.fromRGB(27,34,48); b.BorderSizePixel=0; b.AutoButtonColor=false; b.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); b.TextSize=14; b.TextColor3=Color3.fromRGB(224,232,246); b.TextXAlignment=Enum.TextXAlignment.Left; b.Text="  "..tostring(text); b.ZIndex=604; b.Parent=parent; Instance.new("UICorner",b).CornerRadius=UDim.new(0,8); local st=Instance.new("UIStroke"); st.Color=Color3.fromRGB(73,89,125); st.Transparency=0.55; st.Parent=b; return b,st
 end
 local charSearch=nil
 local charList=Instance.new("ScrollingFrame"); charList.BackgroundTransparency=1; charList.BorderSizePixel=0; charList.ScrollBarThickness=5; charList.CanvasSize=UDim2.new(); charList.AutomaticCanvasSize=Enum.AutomaticSize.Y; charList.ZIndex=603; charList.Parent=leftPanel
 if rule.type=="character" then
  charSearch=Instance.new("TextBox"); charSearch.Position=UDim2.fromOffset(8,8); charSearch.Size=UDim2.new(1,-16,0,38); charSearch.BackgroundColor3=Color3.fromRGB(27,34,48); charSearch.BorderSizePixel=0; charSearch.ClearTextOnFocus=false; charSearch.PlaceholderText="ค้นหาตัวละคร..."; charSearch.Text=""; charSearch.TextColor3=Color3.fromRGB(245,248,255); charSearch.PlaceholderColor3=Color3.fromRGB(130,146,175); charSearch.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); charSearch.TextSize=15; charSearch.ZIndex=604; charSearch.Parent=leftPanel; Instance.new("UICorner",charSearch).CornerRadius=UDim.new(0,8)
  charList.Position=UDim2.fromOffset(8,54); charList.Size=UDim2.new(1,-16,1,-62)
 else charList.Position=UDim2.fromOffset(8,8); charList.Size=UDim2.new(1,-16,1,-16) end
 local charLayout=Instance.new("UIListLayout"); charLayout.Padding=UDim.new(0,5); charLayout.Parent=charList
 local mutList=Instance.new("ScrollingFrame"); mutList.Position=UDim2.fromOffset(8,8); mutList.Size=UDim2.new(1,-16,1,-16); mutList.BackgroundTransparency=1; mutList.BorderSizePixel=0; mutList.ScrollBarThickness=5; mutList.CanvasSize=UDim2.new(); mutList.AutomaticCanvasSize=Enum.AutomaticSize.Y; mutList.ZIndex=603; mutList.Parent=mutPanel
 local mutLayout=Instance.new("UIListLayout"); mutLayout.Padding=UDim.new(0,5); mutLayout.Parent=mutList
 local renderLeft
 renderLeft=function()
  for _,x in ipairs(charList:GetChildren()) do if x:IsA("TextButton") then x:Destroy() end end
  if rule.type=="rarity" then
   for _,rn in ipairs(rarityNames) do local b,st=makeListButton(charList,rn,42); local sel=tostring(draftRarity)==rn; local c=tierColor(rn); b.BackgroundColor3=sel and shadeColor(c,0.68) or Color3.fromRGB(27,34,48); b.Text=(sel and "  ✓ " or "  ")..rn; st.Color=c; st.Transparency=sel and 0.05 or 0.48; b.Activated:Connect(function() draftRarity=rn; renderLeft() end) end
  else
   local q=string.lower(charSearch and charSearch.Text or "")
   for _,c in ipairs(charCatalog) do local shown=tostring(c.DisplayName or c.Name); local hay=string.lower(tostring(c.Name).." "..shown); if q=="" or string.find(hay,q,1,true) then local key=tostring(c.Name); local b,st=makeListButton(charList,shown.."  •  "..tostring(c.Rarity),44); local sel=draftChars[key]==true; local tc=tierColor(c.Rarity); b.BackgroundColor3=sel and shadeColor(tc,0.62) or Color3.fromRGB(27,34,48); b.Text=(sel and "  ✓ " or "  ")..shown.."  •  "..tostring(c.Rarity); st.Color=tc; st.Transparency=sel and 0.02 or 0.55; b.Activated:Connect(function() draftChars[key]=not draftChars[key]; renderLeft() end) end end
  end
 end
 local renderMuts
 renderMuts=function()
  for _,x in ipairs(mutList:GetChildren()) do if x:IsA("TextButton") then x:Destroy() end end
  local allSelected=next(draftMuts)==nil or draftMuts.ANY==true
  local allBtn,allSt=makeListButton(mutList,"ทุกมิวเทชัน",42); allBtn.BackgroundColor3=allSelected and Color3.fromRGB(44,76,126) or Color3.fromRGB(27,34,48); allBtn.Text=(allSelected and "  ✓ " or "  ").."ทุกมิวเทชัน"; allSt.Transparency=allSelected and 0.05 or 0.55; allBtn.Activated:Connect(function() draftMuts={ANY=true}; renderMuts() end)
  for _,m in ipairs(mutCatalog) do local key=tostring(m.Name); local b,st=makeListButton(mutList,key,42); local sel=draftMuts[key]==true; local g=RT.mutationGradientFolder and RT.mutationGradientFolder:FindFirstChild(key); local c=(g and g:IsA("UIGradient") and #g.Color.Keypoints>0) and g.Color.Keypoints[1].Value or Color3.fromRGB(100,118,158); b.BackgroundColor3=sel and shadeColor(c,0.48) or Color3.fromRGB(27,34,48); b.Text=(sel and "  ✓ " or "  ")..key; st.Color=c; st.Transparency=sel and 0.02 or 0.55; b.Activated:Connect(function() draftMuts.ANY=nil; draftMuts[key]=not draftMuts[key]; if not next(draftMuts) then draftMuts={ANY=true} end; renderMuts() end) end
 end
 renderLeft(); renderMuts()
 if charSearch then charSearch:GetPropertyChangedSignal("Text"):Connect(renderLeft) end
 local cancelBtn=mkButton(modal,"ยกเลิก",538,502,110,40); cancelBtn.TextSize=15; cancelBtn.ZIndex=603
 local saveBtn=mkButton(modal,"บันทึกการแก้ไข",656,502,124,40); saveBtn.TextSize=15; saveBtn.ZIndex=603; saveBtn.BackgroundColor3=Color3.fromRGB(43,121,87)
 local escConn
 local function closeEditor()
  if escConn then pcall(function() escConn:Disconnect() end) end
  if overlay and overlay.Parent then overlay:Destroy() end
  if RT.ruleEditorOverlay==overlay then RT.ruleEditorOverlay=nil end
 end
 closeBtn.Activated:Connect(closeEditor); cancelBtn.Activated:Connect(closeEditor); backdrop.Activated:Connect(closeEditor)
 saveBtn.Activated:Connect(function()
  if rule.type=="character" then if not next(draftChars) then sub.Text="ต้องเลือกตัวละครอย่างน้อย 1 ตัว"; sub.TextColor3=Color3.fromRGB(255,133,133); return end; rule.characters=copySet(draftChars); rule.rarity=nil
  else if not draftRarity then sub.Text="ต้องเลือกระดับ"; sub.TextColor3=Color3.fromRGB(255,133,133); return end; rule.rarity=draftRarity; rule.characters={} end
  rule.mutations=copySet(draftMuts); saveRules(); saveConfig(); log("RULE_EDIT | id="..tostring(rule.id).." | type="..tostring(rule.type).." | target="..ruleTargetText(rule).." | muts="..ruleMutText(rule)); closeEditor(); refreshRulesUI(); if refresh then refresh("แก้ไขกฎแล้ว") else writeLatest("rule_edit") end
 end)
 escConn=UIS.InputBegan:Connect(function(input,gp) if not gp and input.KeyCode==Enum.KeyCode.Escape then closeEditor() end end)
end
refreshRulesUI=function()
 for _,c in ipairs(ruleScroll:GetChildren()) do if c~=ruleLayout then c:Destroy() end end
 rulesTitle.Text="<font size='23'><b>กฎการซื้อ</b></font>  <font color='rgb(129,157,224)'>"..#RT.rules.." กฎ</font>\n<font size='13' color='rgb(163,181,212)'>ตรงกฎใดกฎหนึ่งก็ทำงาน • ภายในกฎเดียวกันต้องตรงทุกเงื่อนไข</font>"
 for displayIndex,r in ipairs(RT.rules) do
  local row=Instance.new("Frame"); row.Size=UDim2.new(1,-8,0,70); row.BackgroundColor3=Color3.fromRGB(24,30,43); row.BorderSizePixel=0; row.Parent=ruleScroll; Instance.new("UICorner",row).CornerRadius=UDim.new(0,10)
  local rtier=ruleTierName(r); local rbase=tierColor(rtier); local st=Instance.new("UIStroke"); st.Color=shadeColor(rbase,0.8); st.Transparency=0.30; st.Thickness=1.1; st.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; st.Parent=row
  local bar=Instance.new("Frame"); bar.Size=UDim2.new(0,5,1,-16); bar.Position=UDim2.fromOffset(8,8); bar.BackgroundColor3=rbase; bar.BorderSizePixel=0; bar.Parent=row; Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0)
  local heading=Instance.new("TextLabel"); heading.BackgroundTransparency=1; heading.Position=UDim2.fromOffset(22,7); heading.Size=UDim2.fromOffset(438,21); heading.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); heading.TextSize=16; heading.TextColor3=Color3.fromRGB(246,249,255); heading.TextXAlignment=Enum.TextXAlignment.Left; heading.Text="กฎ #"..tostring(displayIndex).." • "..(r.type=="rarity" and "กฎระดับ" or "กฎตัวละคร"); heading.Parent=row
  local target=Instance.new("TextLabel"); target.BackgroundTransparency=1; target.Position=UDim2.fromOffset(22,30); target.Size=UDim2.fromOffset(520,18); target.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); target.TextSize=14; target.TextColor3=Color3.fromRGB(219,228,244); target.TextXAlignment=Enum.TextXAlignment.Left; target.TextTruncate=Enum.TextTruncate.AtEnd; target.Text="เป้าหมาย: "..ruleTargetText(r); target.Parent=row
  local mut=Instance.new("TextLabel"); mut.BackgroundTransparency=1; mut.Position=UDim2.fromOffset(22,50); mut.Size=UDim2.fromOffset(560,16); mut.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); mut.TextSize=13; mut.TextColor3=Color3.fromRGB(165,186,219); mut.TextXAlignment=Enum.TextXAlignment.Left; mut.TextTruncate=Enum.TextTruncate.AtEnd; mut.Text="มิวเทชัน: "..ruleMutText(r); mut.Parent=row  do local ks=sortedKeys(r.mutations); if #ks==1 and ks[1]~="ANY" then local gg=RT.mutationGradientFolder and RT.mutationGradientFolder:FindFirstChild(ks[1]); if gg and gg:IsA("UIGradient") then local g=gg:Clone(); g.Name="RuleMutationGradient"; g.Parent=mut; mut.TextColor3=Color3.new(1,1,1) end end end
  local tierBadge=Instance.new("TextLabel"); tierBadge.Position=UDim2.fromOffset(452,7); tierBadge.Size=UDim2.fromOffset(78,22); tierBadge.BackgroundColor3=shadeColor(rbase,0.68); tierBadge.BorderSizePixel=0; tierBadge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); tierBadge.TextSize=12; tierBadge.TextColor3=Color3.fromRGB(255,255,255); tierBadge.Text=rtier; tierBadge.Parent=row; Instance.new("UICorner",tierBadge).CornerRadius=UDim.new(0.5,0)
  local edit=mkButton(row,"แก้ไข",536,6,62,26); edit.TextSize=12; edit.BackgroundColor3=Color3.fromRGB(50,87,155)
  local toggle=mkButton(row,r.enabled~=false and "เปิด" or "ปิด",604,6,58,26); toggle.TextSize=13; toggle.BackgroundColor3=(r.enabled~=false) and Color3.fromRGB(45,126,87) or Color3.fromRGB(66,72,88)
  local del=mkButton(row,"✕",668,6,42,26); del.TextSize=15; del.BackgroundColor3=Color3.fromRGB(82,45,55)
  edit.MouseButton1Click:Connect(function() RT.openRuleEditor(r,displayIndex) end)
  toggle.MouseButton1Click:Connect(function() r.enabled=not (r.enabled~=false); local active=0; for _,rr in ipairs(RT.rules) do if rr.enabled~=false then active+=1 end end; if active==0 then RT.autoBuy=false end; saveRules(); saveConfig(); log("RULE_TOGGLE | id="..r.id.." | enabled="..tostring(r.enabled).." | active="..active); refreshRulesUI(); if refresh then refresh("เปลี่ยนสถานะกฎแล้ว") else writeLatest("rule_toggle") end end)
  del.MouseButton1Click:Connect(function() log("RULE_DELETE | id="..r.id); removeRuleById(r.id); saveConfig(); refreshRulesUI(); if refresh then refresh("ลบกฎแล้ว") else writeLatest("rule_delete") end end)
 end
end
local function clearRuleBuilder()
 RT.chars={}; RT.muts={}; RT.builderRarity=nil; refreshCharButtons(); refreshMutButtons(); refreshRarityButtons()
end
addCharRuleBtn.MouseButton1Click:Connect(function()
 if not next(RT.chars) then log("RULE_ADD_REJECT | type=character | reason=no_character"); return end
 RT.ruleSeq+=1; RT.rules[#RT.rules+1]={id=RT.ruleSeq,type="character",enabled=true,characters=copySet(RT.chars),mutations=copySet(RT.muts)}
 log("RULE_ADD | id="..RT.ruleSeq.." | type=character | chars="..listSelected(RT.chars).." | muts="..(#sortedKeys(RT.muts)==0 and "ANY" or listSelected(RT.muts))); saveRules(); clearRuleBuilder(); saveConfig(); refreshRulesUI(); if refresh then refresh("เพิ่มกฎตัวละครแล้ว") else writeLatest("rule_add_character") end
end)
addRarityRuleBtn.MouseButton1Click:Connect(function()
 if not RT.builderRarity then log("RULE_ADD_REJECT | type=rarity | reason=no_rarity"); return end
 RT.ruleSeq+=1; RT.rules[#RT.rules+1]={id=RT.ruleSeq,type="rarity",enabled=true,rarity=RT.builderRarity,characters={},mutations=copySet(RT.muts)}
 log("RULE_ADD | id="..RT.ruleSeq.." | type=rarity | rarity="..RT.builderRarity.." | muts="..(#sortedKeys(RT.muts)==0 and "ANY" or listSelected(RT.muts))); saveRules(); clearRuleBuilder(); saveConfig(); refreshRulesUI(); if refresh then refresh("เพิ่มกฎระดับแล้ว") else writeLatest("rule_add_rarity") end
end)clearBuilderBtn.MouseButton1Click:Connect(function() clearRuleBuilder(); saveConfig(); log("RULE_BUILDER_CLEAR"); writeLatest("rule_builder_clear") end)
deleteRulesBtn.MouseButton1Click:Connect(function() RT.rules={}; RT.autoBuy=false; saveRules(); saveConfig(); refreshRulesUI(); log("RULE_DELETE_ALL"); if refresh then refresh("ลบกฎทั้งหมดแล้ว") else writeLatest("rule_delete_all") end end)
refreshRulesUI()
local traderTitle=Instance.new("TextLabel"); traderTitle.BackgroundTransparency=1; traderTitle.Position=UDim2.fromOffset(210,84); traderTitle.Size=UDim2.fromOffset(740,30); traderTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); traderTitle.TextSize=24; traderTitle.TextColor3=Color3.fromRGB(245,248,255); traderTitle.TextXAlignment=Enum.TextXAlignment.Left; traderTitle.Text="ร้านค้า • เลือกเป้าหมายให้ชัด แล้วให้ระบบจัดการ"; traderTitle.Parent=frame
RT.traderUI=RT.traderUI or {}; RT.traderSearch=""; RT.traderOnlySelected=false; RT.traderSortMode="RARITY"
do
 local p=Instance.new("Frame"); p.Name="TraderSummaryPanel"; p.Position=UDim2.fromOffset(210,128); p.Size=UDim2.fromOffset(240,462); p.BackgroundColor3=Color3.fromRGB(15,20,30); p.BorderSizePixel=0; p.Parent=frame; stylePanel(p); RT.traderPanel=p
 local h=Instance.new("TextLabel"); h.Position=UDim2.fromOffset(16,14); h.Size=UDim2.fromOffset(208,26); h.BackgroundTransparency=1; h.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); h.TextSize=18; h.TextXAlignment=Enum.TextXAlignment.Left; h.TextColor3=Color3.fromRGB(245,248,255); h.Text="แผงควบคุมร้านค้า"; h.Parent=p
 local sub=Instance.new("TextLabel"); sub.Position=UDim2.fromOffset(16,42); sub.Size=UDim2.fromOffset(208,20); sub.BackgroundTransparency=1; sub.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); sub.TextSize=14; sub.TextXAlignment=Enum.TextXAlignment.Left; sub.TextColor3=Color3.fromRGB(150,166,196); sub.Text="ควบคุมการซื้อและเป้าหมาย"; sub.Parent=p
end
local traderBtn=mkButton(RT.traderPanel,"ระบบซื้อร้านค้า: ปิด (F5)",14,70,212,50); traderBtn.TextSize=16
local traderAllBtn=mkButton(RT.traderPanel,"โหมดซื้อทั้งหมด: ปิด",14,128,212,50); traderAllBtn.TextSize=16
do
 local c=Instance.new("Frame"); c.Name="StatusCard"; c.Position=UDim2.fromOffset(14,190); c.Size=UDim2.fromOffset(212,120); c.BackgroundColor3=Color3.fromRGB(20,26,38); c.BorderSizePixel=0; c.Parent=RT.traderPanel; stylePanel(c)
 local h=Instance.new("TextLabel"); h.Position=UDim2.fromOffset(12,10); h.Size=UDim2.fromOffset(188,20); h.BackgroundTransparency=1; h.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); h.TextSize=16; h.TextXAlignment=Enum.TextXAlignment.Left; h.TextColor3=Color3.fromRGB(235,241,255); h.Text="สถานะร้านค้า"; h.Parent=c
end
local traderHint=Instance.new("TextLabel"); traderHint.BackgroundTransparency=1; traderHint.Position=UDim2.fromOffset(12,34); traderHint.Size=UDim2.fromOffset(188,78); traderHint.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); traderHint.TextSize=15; traderHint.TextColor3=Color3.fromRGB(205,216,235); traderHint.TextWrapped=true; traderHint.RichText=true; traderHint.TextXAlignment=Enum.TextXAlignment.Left; traderHint.TextYAlignment=Enum.TextYAlignment.Top; traderHint.Text="กำลังโหลดข้อมูลร้านค้า..."; traderHint.Parent=RT.traderPanel.StatusCard
do
 local c=Instance.new("Frame"); c.Name="TraderToolsCard"; c.Position=UDim2.fromOffset(14,322); c.Size=UDim2.fromOffset(212,126); c.BackgroundColor3=Color3.fromRGB(20,26,38); c.BorderSizePixel=0; c.Parent=RT.traderPanel; stylePanel(c)
 local h=Instance.new("TextLabel"); h.Position=UDim2.fromOffset(12,9); h.Size=UDim2.fromOffset(188,20); h.BackgroundTransparency=1; h.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); h.TextSize=16; h.TextXAlignment=Enum.TextXAlignment.Left; h.TextColor3=Color3.fromRGB(235,241,255); h.Text="เครื่องมือด่วน"; h.Parent=c
 RT.traderUI.selectAll=mkButton(c,"เลือกทั้งหมด",10,36,92,38); RT.traderUI.selectAll.TextSize=14
 RT.traderUI.clear=mkButton(c,"ล้างที่เลือก",110,36,92,38); RT.traderUI.clear.TextSize=14
 local tip=Instance.new("TextLabel"); tip.Position=UDim2.fromOffset(12,82); tip.Size=UDim2.fromOffset(188,34); tip.BackgroundTransparency=1; tip.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); tip.TextSize=13; tip.TextWrapped=true; tip.TextColor3=Color3.fromRGB(150,166,196); tip.Text="ค้นหา/กรอง/เรียงได้จากแถบด้านขวา"; tip.Parent=c
end
do
 RT.traderUI.search=Instance.new("TextBox"); RT.traderUI.search.Size=UDim2.fromOffset(230,38); RT.traderUI.search.Position=UDim2.fromOffset(470,128); RT.traderUI.search.BackgroundColor3=Color3.fromRGB(25,31,45); RT.traderUI.search.BorderSizePixel=0; RT.traderUI.search.TextColor3=Color3.fromRGB(245,248,255); RT.traderUI.search.PlaceholderText="ค้นหาไอเทม..."; RT.traderUI.search.ClearTextOnFocus=false; RT.traderUI.search.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); RT.traderUI.search.TextSize=16; RT.traderUI.search.Text=""; RT.traderUI.search.Parent=frame; Instance.new("UICorner",RT.traderUI.search).CornerRadius=UDim.new(0,9); styleTextBox(RT.traderUI.search)
 RT.traderUI.onlySelected=mkButton(frame,"เฉพาะที่เลือก",708,128,118,38); RT.traderUI.onlySelected.TextSize=14
 RT.traderUI.sort=mkButton(frame,"เรียง: ระดับ",834,128,116,38); RT.traderUI.sort.TextSize=14
end
local traderScroll=Instance.new("ScrollingFrame"); traderScroll.Size=UDim2.fromOffset(480,414); traderScroll.Position=UDim2.fromOffset(470,176); traderScroll.BackgroundColor3=Color3.fromRGB(16,21,31); traderScroll.BorderSizePixel=0; traderScroll.ScrollBarThickness=6; traderScroll.CanvasSize=UDim2.new(); traderScroll.Parent=frame; stylePanel(traderScroll); styleScroll(traderScroll)
local traderLayout=Instance.new("UIGridLayout"); traderLayout.CellSize=UDim2.fromOffset(232,78); traderLayout.CellPadding=UDim2.fromOffset(6,8); traderLayout.SortOrder=Enum.SortOrder.LayoutOrder; traderLayout.Parent=traderScroll
local traderButtons={}
local initialTraderItems={
 {Name="Legendary Essence",DisplayName="Legendary Essence",Price=250000,Rarity="Legendary"},
 {Name="Trait Shard",DisplayName="Trait Shard",Price=75000,Rarity="Mythic"},
 {Name="Cursed Womb",DisplayName="Cursed Womb",Price=3000000,Rarity="God"},
 {Name="Time Potion",DisplayName="Time Potion",Price=250000,Rarity="Secret"},
 {Name="Super Luck Potion",DisplayName="Super Luck Potion",Price=500000,Rarity="Mythic"},
}
local function refreshTraderButtons()
 local selectedCount=0; local knownCount=0; local visibleCount=0; local q=string.lower(tostring(RT.traderSearch or ""))
 for _ in pairs(traderButtons) do knownCount+=1 end
 for name,x in pairs(traderButtons) do
  local selected=RT.traderTargets[name]==true; if selected then selectedCount+=1 end
  local d=x.data or {}; local rarity=tostring(d.Rarity or "?"); local base=tierColor(rarity); local hay=string.lower(tostring(d.DisplayName or name).." "..rarity.." "..tostring(d.Price or ""))
  local show=(not RT.traderOnlySelected or selected) and (q=="" or string.find(hay,q,1,true)~=nil); x.button.Visible=show; if show then visibleCount+=1 end
  x.button.BackgroundColor3=selected and Color3.fromRGB(31,42,63) or Color3.fromRGB(23,29,42); x.button.TextColor3=Color3.fromRGB(248,250,255); x.button.TextWrapped=true; x.button.RichText=true; x.button.TextYAlignment=Enum.TextYAlignment.Center
  local stock=d.Stock~=nil and tostring(d.Stock) or "ไม่ทราบ"; x.button.Text=""
  local titleLabel=x.button:FindFirstChild("ItemTitle"); if titleLabel then titleLabel.Text=tostring(d.DisplayName or name) end
  local metaLabel=x.button:FindFirstChild("ItemMeta"); if metaLabel then metaLabel.Text="$"..tostring(d.Price or "?").."  |  "..rarity end
  local stockLabel=x.button:FindFirstChild("ItemStock"); if stockLabel then stockLabel.Text="สต็อก: "..stock end
  local bar=x.button:FindFirstChild("TierBar"); if bar then bar.BackgroundColor3=base end; local badge=x.button:FindFirstChild("SelectedBadge"); if badge then badge.Visible=selected end
  local st=x.button:FindFirstChildOfClass("UIStroke"); if st then st.Color=selected and Color3.fromRGB(112,140,255) or shadeColor(base,0.75); st.Transparency=selected and 0.02 or 0.38; st.Thickness=selected and 1.7 or 1.05 end
  x.button.LayoutOrder=(RT.traderSortMode=="PRICE") and (tonumber(d.Price) or 999999999) or ((20-(rarityRank[rarity] or 0))*100000000+(tonumber(d.Price) or 0))
 end
 traderHint.Text="เลือก <b>"..selectedCount.."</b> • พบ <b>"..knownCount.."</b> • แสดง <b>"..visibleCount.."</b>\nโหมดการซื้อ: <b>"..(RT.traderBuyAll and "ซื้อทั้งหมด" or "เฉพาะที่เลือก").."</b>\nระบบอัตโนมัติ: <b>"..(RT.traderAuto and "เปิด" or "ปิด").."</b>\nเรียงตาม: <b>"..(RT.traderSortMode=="PRICE" and "ราคา" or "ระดับ").."</b>"
 if RT.traderUI.onlySelected then RT.traderUI.onlySelected.Text=RT.traderOnlySelected and "✓ เฉพาะที่เลือก" or "เฉพาะที่เลือก"; RT.traderUI.onlySelected.BackgroundColor3=RT.traderOnlySelected and Color3.fromRGB(52,78,155) or Color3.fromRGB(27,34,49) end
 if RT.traderUI.sort then RT.traderUI.sort.Text=RT.traderSortMode=="PRICE" and "เรียง: ราคา" or "เรียง: ระดับ" end
end
local function addTraderKnown(item,source)
 if type(item)~="table" or item.Name==nil then return end
 local name=tostring(item.Name)
 local data=RT.traderKnown[name]
 local isNew=data==nil
 local changed=isNew
 if not data then data={Name=name}; RT.traderKnown[name]=data end
 local function setField(k,v)
  if v~=nil and data[k]~=v then data[k]=v; changed=true end
 end
 setField("DisplayName",item.DisplayName or data.DisplayName or name)
 setField("Price",item.Price)
 setField("Rarity",item.Rarity)
 setField("MaxStock",item.MaxStock)
 setField("Stock",item.Stock)
 setField("Image",item.Image)
 if isNew and source~="seed" and source~="catalog" then
  log("TRADER_DISCOVER | source="..tostring(source or "unknown").." | item="..name.." | price="..tostring(data.Price or "?").." | rarity="..tostring(data.Rarity or "?").." | maxStock="..tostring(data.MaxStock or "?"))
 end
 if changed and source~="catalog" and source~="seed" then saveTraderCatalog() end
 if traderButtons[name] then traderButtons[name].data=data; refreshTraderButtons(); return end
 local b=mkButton(traderScroll,"",0,0,232,78); b.Text=""; b.ClipsDescendants=true; b.TextTransparency=1
 do
  local bar=Instance.new("Frame"); bar.Name="TierBar"; bar.Position=UDim2.fromOffset(8,12); bar.Size=UDim2.new(0,4,1,-24); bar.BorderSizePixel=0; bar.BackgroundColor3=tierColor(data.Rarity); bar.Parent=b; Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0)
  local titleLabel=Instance.new("TextLabel"); titleLabel.Name="ItemTitle"; titleLabel.BackgroundTransparency=1; titleLabel.Position=UDim2.fromOffset(20,8); titleLabel.Size=UDim2.new(1,-96,0,22); titleLabel.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); titleLabel.TextSize=16; titleLabel.TextColor3=Color3.fromRGB(248,250,255); titleLabel.TextXAlignment=Enum.TextXAlignment.Left; titleLabel.TextYAlignment=Enum.TextYAlignment.Center; titleLabel.TextTruncate=Enum.TextTruncate.AtEnd; titleLabel.ZIndex=3; titleLabel.Parent=b
  local metaLabel=Instance.new("TextLabel"); metaLabel.Name="ItemMeta"; metaLabel.BackgroundTransparency=1; metaLabel.Position=UDim2.fromOffset(20,32); metaLabel.Size=UDim2.new(1,-30,0,18); metaLabel.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); metaLabel.TextSize=14; metaLabel.TextColor3=Color3.fromRGB(224,231,245); metaLabel.TextXAlignment=Enum.TextXAlignment.Left; metaLabel.TextTruncate=Enum.TextTruncate.AtEnd; metaLabel.ZIndex=3; metaLabel.Parent=b
  local stockLabel=Instance.new("TextLabel"); stockLabel.Name="ItemStock"; stockLabel.BackgroundTransparency=1; stockLabel.Position=UDim2.fromOffset(20,52); stockLabel.Size=UDim2.new(1,-30,0,16); stockLabel.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); stockLabel.TextSize=13; stockLabel.TextColor3=Color3.fromRGB(166,180,206); stockLabel.TextXAlignment=Enum.TextXAlignment.Left; stockLabel.TextTruncate=Enum.TextTruncate.AtEnd; stockLabel.ZIndex=3; stockLabel.Parent=b
  local badge=Instance.new("TextLabel"); badge.Name="SelectedBadge"; badge.AnchorPoint=Vector2.new(1,0); badge.Position=UDim2.new(1,-8,0,7); badge.Size=UDim2.fromOffset(58,18); badge.BackgroundColor3=Color3.fromRGB(64,92,190); badge.BorderSizePixel=0; badge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); badge.TextSize=11; badge.TextColor3=Color3.fromRGB(255,255,255); badge.Text="เลือกแล้ว"; badge.Visible=false; badge.Parent=b; Instance.new("UICorner",badge).CornerRadius=UDim.new(0.5,0)
 end
 traderButtons[name]={button=b,data=data}
 keep(b.MouseButton1Click:Connect(function()
  RT.traderTargets[name]=not RT.traderTargets[name]
  log("TRADER_SELECT | "..name.."="..tostring(RT.traderTargets[name]))
  refreshTraderButtons(); saveConfig(); writeLatest("trader_select")
 end))
 refreshTraderButtons()
end
keep(RT.traderUI.search:GetPropertyChangedSignal("Text"):Connect(function() RT.traderSearch=RT.traderUI.search.Text or ""; refreshTraderButtons() end))
keep(RT.traderUI.onlySelected.Activated:Connect(function() RT.traderOnlySelected=not RT.traderOnlySelected; refreshTraderButtons() end))
keep(RT.traderUI.sort.Activated:Connect(function() RT.traderSortMode=(RT.traderSortMode=="RARITY") and "PRICE" or "RARITY"; refreshTraderButtons() end))
keep(RT.traderUI.selectAll.Activated:Connect(function() for name in pairs(traderButtons) do RT.traderTargets[name]=true end; refreshTraderButtons(); saveConfig(); log("TRADER_SELECT_ALL") end))
keep(RT.traderUI.clear.Activated:Connect(function() for name in pairs(traderButtons) do RT.traderTargets[name]=false end; refreshTraderButtons(); saveConfig(); log("TRADER_CLEAR_SELECTION") end))
local function loadTraderCatalog()
 if type(readfile)~="function" then return end
 local ok,text=pcall(readfile,TRADER_CATALOG)
 if not ok or type(text)~="string" or text=="" then return end
 local ok2,data=pcall(function() return HttpService:JSONDecode(text) end)
 if not ok2 or type(data)~="table" then log("TRADER_CATALOG_READ_ERROR | "..tostring(data)); return end
 for _,it in ipairs(data) do addTraderKnown(it,"catalog") end
 log("TRADER_CATALOG_LOADED | count="..tostring(#data))
end
for _,it in ipairs(initialTraderItems) do addTraderKnown(it,"seed") end
loadTraderCatalog()
saveTraderCatalog()
local infoTitle=Instance.new("TextLabel"); infoTitle.BackgroundTransparency=1; infoTitle.Position=UDim2.fromOffset(210,84); infoTitle.Size=UDim2.fromOffset(740,30); infoTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); infoTitle.TextSize=24; infoTitle.TextColor3=Color3.fromRGB(238,243,255); infoTitle.TextXAlignment=Enum.TextXAlignment.Left; infoTitle.Text="ข้อมูลตัวละคร • 77 ตัวในตู้ • โอกาสพื้นฐานไม่รวม Luck และการันตี"; infoTitle.Parent=frame
local infoSearch=Instance.new("TextBox"); infoSearch.Size=UDim2.fromOffset(260,42); infoSearch.Position=UDim2.fromOffset(210,116); infoSearch.BackgroundColor3=Color3.fromRGB(31,35,44); infoSearch.BorderSizePixel=0; infoSearch.TextColor3=Color3.new(1,1,1); infoSearch.PlaceholderText="ค้นหาตัวละคร..."; infoSearch.ClearTextOnFocus=false; infoSearch.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); infoSearch.Text=""; infoSearch.TextSize=18; infoSearch.Parent=frame; Instance.new("UICorner",infoSearch).CornerRadius=UDim.new(0,7); styleTextBox(infoSearch)
local infoTierOrder={"ALL","Common","Rare","Epic","Legendary","Mythic","Secret","God"}; local infoTierIndex=1
local infoTierBtn=mkButton(frame,"ระดับ: ทั้งหมด",480,116,132,42); infoTierBtn.TextSize=16
local infoSkillFilters={"ALL","HAS","NONE"}; local infoSkillFilterIndex=1
local infoSkillFilterBtn=mkButton(frame,"สกิล: ทั้งหมด",622,116,142,42); infoSkillFilterBtn.TextSize=16
local infoCount=Instance.new("TextLabel"); infoCount.BackgroundTransparency=1; infoCount.Position=UDim2.fromOffset(778,122); infoCount.Size=UDim2.fromOffset(170,30); infoCount.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); infoCount.TextSize=16; infoCount.TextColor3=Color3.fromRGB(185,205,235); infoCount.TextXAlignment=Enum.TextXAlignment.Left; infoCount.Parent=frame
local infoList=Instance.new("ScrollingFrame"); infoList.Position=UDim2.fromOffset(210,170); infoList.Size=UDim2.fromOffset(260,430); infoList.BackgroundColor3=Color3.fromRGB(20,23,31); infoList.BorderSizePixel=0; infoList.ScrollBarThickness=5; infoList.CanvasSize=UDim2.new(); infoList.Parent=frame; stylePanel(infoList); styleScroll(infoList)
local infoListLayout=Instance.new("UIListLayout"); infoListLayout.Padding=UDim.new(0,6); infoListLayout.Parent=infoList
local infoDetail=Instance.new("Frame"); infoDetail.Position=UDim2.fromOffset(482,170); infoDetail.Size=UDim2.fromOffset(468,430); infoDetail.BackgroundColor3=Color3.fromRGB(20,23,31); infoDetail.BorderSizePixel=0; infoDetail.Parent=frame; stylePanel(infoDetail)
local infoPortrait=Instance.new("ViewportFrame"); infoPortrait.Position=UDim2.fromOffset(12,12); infoPortrait.Size=UDim2.fromOffset(100,100); infoPortrait.BackgroundColor3=Color3.fromRGB(10,12,17); infoPortrait.BorderSizePixel=0; infoPortrait.Ambient=Color3.fromRGB(185,185,185); infoPortrait.LightColor=Color3.fromRGB(255,255,255); infoPortrait.LightDirection=Vector3.new(-1,-1,-1); infoPortrait.Parent=infoDetail; Instance.new("UICorner",infoPortrait).CornerRadius=UDim.new(0,9); do local a=Instance.new("UIAspectRatioConstraint"); a.AspectRatio=1; a.Parent=infoPortrait end
local infoName=Instance.new("TextLabel"); infoName.Position=UDim2.fromOffset(124,12); infoName.Size=UDim2.fromOffset(330,54); infoName.BackgroundTransparency=1; infoName.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); infoName.TextSize=24; infoName.RichText=true; infoName.TextWrapped=true; infoName.TextXAlignment=Enum.TextXAlignment.Left; infoName.TextYAlignment=Enum.TextYAlignment.Top; infoName.TextColor3=Color3.fromRGB(245,248,255); infoName.Parent=infoDetail
local infoQuick=Instance.new("TextLabel"); infoQuick.Position=UDim2.fromOffset(124,70); infoQuick.Size=UDim2.fromOffset(330,62); infoQuick.BackgroundColor3=Color3.fromRGB(17,22,33); infoQuick.BorderSizePixel=0; infoQuick.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); infoQuick.TextSize=17; infoQuick.RichText=true; infoQuick.TextWrapped=true; infoQuick.TextXAlignment=Enum.TextXAlignment.Left; infoQuick.TextYAlignment=Enum.TextYAlignment.Top; infoQuick.TextColor3=Color3.fromRGB(205,217,238); infoQuick.LineHeight=1.12; infoQuick.Parent=infoDetail; Instance.new("UICorner",infoQuick).CornerRadius=UDim.new(0,7)
local skillCard=Instance.new("Frame"); skillCard.Position=UDim2.fromOffset(12,144); skillCard.Size=UDim2.fromOffset(444,96); skillCard.BackgroundColor3=Color3.fromRGB(16,21,32); skillCard.BorderSizePixel=0; skillCard.Parent=infoDetail; Instance.new("UICorner",skillCard).CornerRadius=UDim.new(0,8)
local infoSkillImage=Instance.new("ImageLabel"); infoSkillImage.Position=UDim2.fromOffset(8,8); infoSkillImage.Size=UDim2.fromOffset(64,64); infoSkillImage.BackgroundColor3=Color3.fromRGB(9,11,16); infoSkillImage.BorderSizePixel=0; infoSkillImage.ScaleType=Enum.ScaleType.Fit; infoSkillImage.Parent=skillCard; Instance.new("UICorner",infoSkillImage).CornerRadius=UDim.new(0,7)
local infoSkillBadge=Instance.new("TextLabel"); infoSkillBadge.Position=UDim2.fromOffset(80,6); infoSkillBadge.Size=UDim2.fromOffset(350,24); infoSkillBadge.BackgroundTransparency=1; infoSkillBadge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); infoSkillBadge.TextSize=18; infoSkillBadge.TextXAlignment=Enum.TextXAlignment.Left; infoSkillBadge.TextColor3=Color3.fromRGB(120,225,170); infoSkillBadge.Parent=skillCard
local infoSkillDescTitle=Instance.new("TextLabel"); infoSkillDescTitle.Position=UDim2.fromOffset(80,32); infoSkillDescTitle.Size=UDim2.fromOffset(350,20); infoSkillDescTitle.BackgroundTransparency=1; infoSkillDescTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); infoSkillDescTitle.TextSize=16; infoSkillDescTitle.TextXAlignment=Enum.TextXAlignment.Left; infoSkillDescTitle.TextColor3=Color3.fromRGB(150,175,210); infoSkillDescTitle.Text="คำอธิบายสกิลจากเกม"; infoSkillDescTitle.Parent=skillCard
local infoSkillDesc=Instance.new("TextLabel"); infoSkillDesc.Position=UDim2.fromOffset(80,54); infoSkillDesc.Size=UDim2.fromOffset(350,34); infoSkillDesc.BackgroundTransparency=1; infoSkillDesc.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); infoSkillDesc.TextSize=16; infoSkillDesc.TextWrapped=true; infoSkillDesc.TextXAlignment=Enum.TextXAlignment.Left; infoSkillDesc.TextYAlignment=Enum.TextYAlignment.Top; infoSkillDesc.TextColor3=Color3.fromRGB(230,235,246); infoSkillDesc.LineHeight=1.12; infoSkillDesc.Parent=skillCard
local summaryBtn=mkButton(infoDetail,"สรุป",12,250,136,36); summaryBtn.TextSize=16
local rawBtn=mkButton(infoDetail,"ข้อมูลดิบ",308,250,136,36); rawBtn.TextSize=16
do local b=mkButton(infoDetail,"ความสามารถ",160,250,136,36); b.TextSize=16; RT.infoSkillBtn=b end
local sourceBadge=Instance.new("TextLabel"); sourceBadge.Position=UDim2.fromOffset(330,292); sourceBadge.Size=UDim2.fromOffset(114,22); sourceBadge.BackgroundTransparency=1; sourceBadge.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); sourceBadge.TextSize=13; sourceBadge.TextXAlignment=Enum.TextXAlignment.Right; sourceBadge.TextColor3=Color3.fromRGB(180,195,220); sourceBadge.Text="ข้อมูลจากเกม"; sourceBadge.Parent=infoDetail
local infoTextScroll=Instance.new("ScrollingFrame"); infoTextScroll.Position=UDim2.fromOffset(12,316); infoTextScroll.Size=UDim2.fromOffset(444,102); infoTextScroll.BackgroundColor3=Color3.fromRGB(10,13,20); infoTextScroll.BorderSizePixel=0; infoTextScroll.ScrollBarThickness=5; infoTextScroll.CanvasSize=UDim2.new(); infoTextScroll.Parent=infoDetail; Instance.new("UICorner",infoTextScroll).CornerRadius=UDim.new(0,7); styleScroll(infoTextScroll)
local infoText=Instance.new("TextLabel"); infoText.Position=UDim2.fromOffset(7,6); infoText.Size=UDim2.new(1,-18,0,10); infoText.AutomaticSize=Enum.AutomaticSize.Y; infoText.BackgroundTransparency=1; infoText.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); infoText.TextSize=17; infoText.RichText=true; infoText.TextWrapped=true; infoText.TextXAlignment=Enum.TextXAlignment.Left; infoText.TextYAlignment=Enum.TextYAlignment.Top; infoText.TextColor3=Color3.fromRGB(225,232,245); infoText.LineHeight=1.22; infoText.Parent=infoTextScroll
local infoButtons={}; local infoSelected=nil; local infoMode="SUMMARY"
local skillFriendly={Cooldown="คูลดาวน์",Duration="ระยะเวลา",Damage="ดาเมจ",DamagePercent="ดาเมจ (%)",AttackMultiplier="ตัวคูณพลังโจมตี",DefenseMultiplier="ตัวคูณพลังป้องกัน",SpeedMultiplier="ตัวคูณความเร็ว",StunDuration="ระยะเวลาสตัน",NumberofHits="จำนวนฮิต",HealPercent="ฟื้นฟู HP",PassiveHealPercent="ฟื้นฟูแบบติดตัว",Lifesteal="ดูดเลือด",SummonCount="จำนวนที่อัญเชิญ",MaxSummons="จำนวนอัญเชิญสูงสุด",SummonDuration="ระยะเวลาอัญเชิญ",Range="ระยะ",SplashRadius="รัศมีกระจาย",CriticalChance="โอกาสคริติคอล",CriticalDamage="ดาเมจคริติคอล",BurnDamage="ดาเมจเผาไหม้",FreezeDuration="ระยะเวลาแช่แข็ง",ShieldPercent="เปอร์เซ็นต์โล่",Knockback="แรงผลัก",TimeStopDuration="ระยะเวลาหยุดเวลา",Passive="สกิลติดตัว",Chance="โอกาสเกิด",Amount="ปริมาณ",Count="จำนวน",Radius="รัศมี",Speed="ความเร็ว"}
local commonFields={Name=true,DisplayName=true,Rarity=true,Price=true,Attack=true,Health=true,Defense=true,Speed=true,Range=true,DamageDelay=true,Type=true,Category=true,Chance=true}
local function scalarValue(v)
 local t=type(v); if t=="string" or t=="number" or t=="boolean" then return tostring(v) end; return nil
end
local function collectSkillEffects(tbl,prefix,depth,out)
 out=out or {}; if type(tbl)~="table" or depth<0 then return out end
 local keys={}; for k in pairs(tbl) do keys[#keys+1]=k end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do
  local v=tbl[k]; local path=(prefix=="" and tostring(k)) or (prefix.."."..tostring(k)); local sv=scalarValue(v)
  if sv then
   local label=skillFriendly[tostring(k)] or tostring(k); local shown=sv; local lk=string.lower(tostring(k))
   if type(v)=="boolean" then shown=v and "ใช่" or "ไม่ใช่"
   elseif type(v)=="number" then
    if string.find(lk,"percent",1,true) or string.find(lk,"chance",1,true) then shown=string.format("%.2f%%",math.abs(v)<=1 and v*100 or v)
    elseif string.find(lk,"multiplier",1,true) and math.abs(v)<=5 then shown=string.format("%.2fx (%+.1f%%)",v,(v-1)*100)
    elseif string.find(lk,"duration",1,true) or string.find(lk,"cooldown",1,true) or string.find(lk,"delay",1,true) then shown=tostring(v).." วินาที" end
   end
   out[#out+1]="• "..label.." : "..shown
  elseif type(v)=="table" and depth>0 then collectSkillEffects(v,path,depth-1,out) end
 end
 return out
end
local function collectSpecialFields(c)
 local out={}; local keys={}; for k in pairs(c or {}) do keys[#keys+1]=k end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
 for _,k in ipairs(keys) do if not commonFields[tostring(k)] then local sv=scalarValue(c[k]); if sv then out[#out+1]="• "..tostring(k).." = "..sv end end end
 return out
end
local function formatInfoSummary(c,sd)
 local p1,p3=noLuckChance(c); local lines={}
 lines[#lines+1]="<b>ภาพรวมตัวละคร</b>"
 lines[#lines+1]="• พลังโจมตี "..tostring(c.Attack or "-").."   • HP "..tostring(c.Health or "-").."   • ป้องกัน "..tostring(c.Defense or "-")
 lines[#lines+1]="• ความเร็ว "..tostring(c.Speed or "-").."   • ระยะ "..tostring(c.Range or "-").."   • หน่วงตี "..tostring(c.DamageDelay or "-")
 lines[#lines+1]="• ประเภท "..tostring(c.Type or "-").."   • หมวดหมู่ "..tostring(c.Category or "-")
 lines[#lines+1]=""; lines[#lines+1]="<b>โอกาสสุ่มพื้นฐาน</b> <font color='rgb(155,173,205)'>• ไม่รวม Luck / การันตี</font>"
 lines[#lines+1]=string.format("• 1 ช่อง %.6f%%   • อย่างน้อย 1 ใน 3 %.6f%%",p1,p3)
 lines[#lines+1]="• น้ำหนักตัวละคร "..tostring(c.Chance).." / น้ำหนักรวม "..tostring(baseRollWeight)
 local specials=collectSpecialFields(c); if #specials>0 then lines[#lines+1]=""; lines[#lines+1]="<b>ข้อมูลพิเศษจากเกม</b>"; for i=1,math.min(#specials,6) do lines[#lines+1]=specials[i] end end
 lines[#lines+1]=""; lines[#lines+1]="<b>ความสามารถ</b>"
 if not sd then lines[#lines+1]="• ไม่มีสกิลใน ActiveSkillInfo / ActiveAttacks ของเกมเวอร์ชันนี้" else
  lines[#lines+1]="• ประเภท: "..(sd.kind=="PASSIVE" and "สกิลติดตัว" or "สกิลกดใช้").."   • ชื่อ: "..tostring(sd.name or "-")
  local effects=collectSkillEffects(sd.skill,"ActiveSkill",2,{}); if #effects==0 then lines[#lines+1]="• ไม่พบค่าความสามารถแบบตัวเลขที่แสดงได้" else for i=1,math.min(#effects,8) do lines[#lines+1]=effects[i] end end
 end
 if knownSkillConflicts[tostring(c.Name)] then lines[#lines+1]=""; lines[#lines+1]="⚠ ข้อมูลในเกมมีค่าที่ขัดกัน: "..knownSkillConflicts[tostring(c.Name)] end
 return table.concat(lines,"\n")
end
local function formatInfoRaw(c,sd)
 local lines={}; local p1,p3=noLuckChance(c); local key=charSourceKey[tostring(c.Name)]
 lines[#lines+1]="[CHARACTER RAW]"; for _,x in ipairs(dumpDataTable(c,"",3,{},{})) do lines[#lines+1]=x end
 lines[#lines+1]=""; lines[#lines+1]=string.format("BaseNoLuck1Slot = %.12f%%",p1); lines[#lines+1]=string.format("BaseNoLuck3Slots = %.12f%%",p3); lines[#lines+1]="BaseWeightPool = "..tostring(baseRollWeight)
 lines[#lines+1]=""; lines[#lines+1]="[SKILL RAW]"
 if not sd then lines[#lines+1]="NO SKILL" else
  lines[#lines+1]="DisplaySource = "..tostring(sd.source or "?"); lines[#lines+1]="Name = "..tostring(sd.name); lines[#lines+1]="Description = "..tostring(sd.description); lines[#lines+1]="Image = "..tostring(sd.image)
  for _,x in ipairs(dumpDataTable(sd.skill,"ActiveSkill",4,{},{})) do lines[#lines+1]=x end
  lines[#lines+1]=""; lines[#lines+1]="[MODULE EXTRA]"; local extra={}; for k,v in pairs(sd.module or {}) do if k~="ActiveSkill" then extra[k]=v end end; for _,x in ipairs(dumpDataTable(extra,"Module",3,{},{})) do lines[#lines+1]=x end
 end
 if knownSkillConflicts[tostring(c.Name)] then lines[#lines+1]=""; lines[#lines+1]=knownSkillConflicts[tostring(c.Name)] end
 lines[#lines+1]=""; lines[#lines+1]="[SOURCE]"
 lines[#lines+1]="Stats = ReplicatedStorage.Modules.Characters.CharactersInfo.Characters["..tostring(key).."]"
 lines[#lines+1]="Portrait = ReplicatedStorage.Assets.Characters."..tostring(c.Name)
 lines[#lines+1]="Chance formula = Character.Chance / sum(base roll pool weights), normal roll, no player Luck, no guaranteed override"
 if sd then lines[#lines+1]="Skill = ReplicatedStorage.Modules.ActiveAttacks."..tostring(c.Name); lines[#lines+1]="Skill display = ReplicatedStorage.Modules.ActiveSkillInfo.GetDisplay("..tostring(c.Name)..")" end
 return table.concat(lines,"\n")
end
local function updateInfoModeButtons()
 summaryBtn.BackgroundColor3=infoMode=="SUMMARY" and Color3.fromRGB(68,105,175) or Color3.fromRGB(42,48,64)
 if RT.infoSkillBtn then RT.infoSkillBtn.BackgroundColor3=infoMode=="SKILL" and Color3.fromRGB(68,105,175) or Color3.fromRGB(42,48,64) end
 rawBtn.BackgroundColor3=infoMode=="RAW" and Color3.fromRGB(68,105,175) or Color3.fromRGB(42,48,64)
end
local function renderInfoText()
 if not infoSelected then return end
 local sd=getSkillData(infoSelected.Name)
 if infoMode=="RAW" then infoText.RichText=false; infoText.Text=formatInfoRaw(infoSelected,sd)
 elseif infoMode=="SKILL" then
  infoText.RichText=true; local lines={"<b>ความสามารถของ "..tostring(infoSelected.DisplayName or infoSelected.Name).."</b>",""}
  if not sd then lines[#lines+1]="• ไม่มีสกิลในข้อมูลเกมเวอร์ชันนี้" else
   lines[#lines+1]="• ประเภท: "..(sd.kind=="PASSIVE" and "สกิลติดตัว" or "สกิลกดใช้"); lines[#lines+1]="• ชื่อสกิล: "..tostring(sd.name or "-")
   local effects=collectSkillEffects(sd.skill,"ActiveSkill",4,{}); if #effects==0 then lines[#lines+1]="• ไม่พบค่าความสามารถแบบตัวเลข" else for i=1,math.min(#effects,24) do lines[#lines+1]=effects[i] end end
   if sd.description and sd.description~="" then lines[#lines+1]=""; lines[#lines+1]="คำอธิบายต้นฉบับจากเกม:"; lines[#lines+1]=tostring(sd.description) end
  end
  infoText.Text=table.concat(lines,"\n")
 else infoText.RichText=true; infoText.Text=formatInfoSummary(infoSelected,sd) end
 updateInfoModeButtons()
end
local function selectInfoCharacter(c)
 if not c then return end; infoSelected=c; renderFrontPortrait(infoPortrait,c.Name); local sd=getSkillData(c.Name); local p1,p3=noLuckChance(c)
 local shown=tostring(c.DisplayName or c.Name); if shown~=tostring(c.Name) then shown=shown.." ("..tostring(c.Name)..")" end; local tc=tierColor(c.Rarity); local tr,tg,tb=math.floor(tc.R*255+0.5),math.floor(tc.G*255+0.5),math.floor(tc.B*255+0.5); infoName.Text="<b>"..shown.."</b>\n<font color='rgb("..tr..","..tg..","..tb..")'>"..tostring(c.Rarity).."</font> <font color='rgb(118,222,155)'>• $"..tostring(c.Price).."</font>"; infoName.TextColor3=Color3.fromRGB(245,248,255)
 infoQuick.Text="<font color='rgb(155,173,205)'>โจมตี</font> <b>"..tostring(c.Attack or "-").."</b>   <font color='rgb(155,173,205)'>HP</font> <b>"..tostring(c.Health or "-").."</b>   <font color='rgb(155,173,205)'>ป้องกัน</font> <b>"..tostring(c.Defense or "-").."</b>\n<font color='rgb(155,173,205)'>เร็ว</font> <b>"..tostring(c.Speed or "-").."</b>   <font color='rgb(155,173,205)'>ระยะ</font> <b>"..tostring(c.Range or "-").."</b>   <font color='rgb(155,173,205)'>หน่วง</font> <b>"..tostring(c.DamageDelay or "-").."</b>\n<font color='rgb(155,173,205)'>โอกาส</font> <b>"..string.format("%.4f%%",p1).."</b>   <font color='rgb(155,173,205)'>3 ช่อง</font> <b>"..string.format("%.4f%%",p3).."</b>"
 if sd then infoSkillImage.Image=sd.image; infoSkillImage.Visible=sd.image~=""; infoSkillBadge.Text=(sd.kind=="PASSIVE" and "สกิลติดตัว" or "สกิลกดใช้").." • "..sd.name; infoSkillBadge.TextColor3=Color3.fromRGB(120,225,170); infoSkillDescTitle.Text="คำอธิบายจากเกม"; infoSkillDesc.Text=(sd.description and tostring(sd.description)~="") and tostring(sd.description) or "ไม่พบคำอธิบายสกิลในข้อมูลเกม"
 else infoSkillImage.Image=""; infoSkillImage.Visible=false; infoSkillBadge.Text="ไม่มีสกิล"; infoSkillBadge.TextColor3=Color3.fromRGB(165,175,195); infoSkillDescTitle.Text="สถานะความสามารถ"; infoSkillDesc.Text="ไม่พบ ActiveSkill ของตัวละครนี้ในข้อมูลเกมเวอร์ชันปัจจุบัน" end
 renderInfoText()
end
local function refreshInfoList()
 local q=string.lower(infoSearch.Text or ""); local tier=infoTierOrder[infoTierIndex]; local sf=infoSkillFilters[infoSkillFilterIndex]; local shownCount=0
 for _,x in ipairs(infoButtons) do
  local c=x.data; local hasSkill=ActiveAttacks and ActiveAttacks:FindFirstChild(tostring(c.Name))~=nil; local hay=string.lower(tostring(c.Name).." "..tostring(c.DisplayName).." "..tostring(c.Rarity))
  local tierOk=tier=="ALL" or tostring(c.Rarity)==tier; local skillOk=sf=="ALL" or (sf=="HAS" and hasSkill) or (sf=="NONE" and not hasSkill); local ok=tierOk and skillOk and (q=="" or string.find(hay,q,1,true))
  x.button.Visible=ok; if ok then shownCount+=1 end; x.button.BackgroundColor3=(infoSelected==c) and shadeColor(tierColor(c.Rarity),0.82) or shadeColor(tierColor(c.Rarity),0.46)
 end
 infoCount.Text="แสดง "..shownCount.." / "..#charCatalog.." • สกิล: "..(sf=="ALL" and "ทั้งหมด" or (sf=="HAS" and "มี" or "ไม่มี"))
end
for _,c in ipairs(charCatalog) do
 local b=mkButton(infoList,"",4,0,252,64); b.Size=UDim2.new(1,-8,0,64); b.TextXAlignment=Enum.TextXAlignment.Left; b.TextYAlignment=Enum.TextYAlignment.Center; b.TextWrapped=true; b.RichText=true; b.TextSize=16
 local hasSkill=ActiveAttacks and ActiveAttacks:FindFirstChild(tostring(c.Name))~=nil; local shown=tostring(c.DisplayName or c.Name); if shown~=tostring(c.Name) then shown=shown.." ("..tostring(c.Name)..")" end
 local tc=tierColor(c.Rarity); local tr,tg,tb=math.floor(tc.R*255+0.5),math.floor(tc.G*255+0.5),math.floor(tc.B*255+0.5); b.Text="<b>"..shown.."</b>\n<font size='14' color='rgb("..tr..","..tg..","..tb..")'>"..tostring(c.Rarity).."</font> <font size='14' color='rgb(160,178,210)'> • "..(hasSkill and "มีสกิล" or "ไม่มีสกิล").."</font>"
 infoButtons[#infoButtons+1]={button=b,data=c}; keep(b.Activated:Connect(function() selectInfoCharacter(c); refreshInfoList() end))
end
local infoSearchToken=0
keep(infoSearch:GetPropertyChangedSignal("Text"):Connect(function() infoSearchToken+=1; local t=infoSearchToken; task.delay(0.18,function() if RT.alive and t==infoSearchToken then refreshInfoList() end end) end))
keep(infoTierBtn.Activated:Connect(function() infoTierIndex=infoTierIndex%#infoTierOrder+1; local tier=infoTierOrder[infoTierIndex]; infoTierBtn.Text="ระดับ: "..(tier=="ALL" and "ทั้งหมด" or tier); infoTierBtn.BackgroundColor3=tier=="ALL" and Color3.fromRGB(42,48,64) or shadeColor(tierColor(tier),0.65); refreshInfoList() end))
keep(infoSkillFilterBtn.Activated:Connect(function() infoSkillFilterIndex=infoSkillFilterIndex%#infoSkillFilters+1; local sf=infoSkillFilters[infoSkillFilterIndex]; infoSkillFilterBtn.Text="สกิล: "..(sf=="ALL" and "ทั้งหมด" or (sf=="HAS" and "มี" or "ไม่มี")); refreshInfoList() end))
RT.setupInfoPopup=function()
 local overlay=Instance.new("Frame"); overlay.Name="CharacterInfoPopupOverlay"; overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundTransparency=1; overlay.Visible=false; overlay.ZIndex=500; overlay.Parent=gui
 local backdrop=Instance.new("TextButton"); backdrop.Name="Backdrop"; backdrop.Size=UDim2.fromScale(1,1); backdrop.BackgroundColor3=Color3.fromRGB(0,0,0); backdrop.BackgroundTransparency=1; backdrop.BorderSizePixel=0; backdrop.Text=""; backdrop.AutoButtonColor=false; backdrop.ZIndex=500; backdrop.Parent=overlay
 local modal=Instance.new("Frame"); modal.Name="CharacterInfoPopup"; modal.AnchorPoint=Vector2.new(0.5,0.5); modal.Position=UDim2.fromScale(0.5,0.5); modal.Size=UDim2.fromOffset(760,520); modal.BackgroundColor3=Color3.fromRGB(15,20,30); modal.BorderSizePixel=0; modal.ZIndex=501; modal.Parent=overlay; Instance.new("UICorner",modal).CornerRadius=UDim.new(0,16)
 local mst=Instance.new("UIStroke"); mst.Color=Color3.fromRGB(75,96,145); mst.Thickness=1.4; mst.Transparency=0.08; mst.ApplyStrokeMode=Enum.ApplyStrokeMode.Border; mst.Parent=modal
 local scale=Instance.new("UIScale"); scale.Scale=1; scale.Parent=modal
 local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(22,16); title.Size=UDim2.fromOffset(560,34); title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); title.TextSize=24; title.TextColor3=Color3.fromRGB(246,249,255); title.TextXAlignment=Enum.TextXAlignment.Left; title.ZIndex=502; title.Parent=modal
 local source=Instance.new("TextLabel"); source.BackgroundTransparency=1; source.Position=UDim2.fromOffset(22,50); source.Size=UDim2.fromOffset(560,24); source.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); source.TextSize=14; source.TextColor3=Color3.fromRGB(139,164,204); source.TextXAlignment=Enum.TextXAlignment.Left; source.Text="ข้อมูลจากเกมจริง • ไม่มีการเดาค่าที่เกมไม่ได้ระบุ"; source.ZIndex=502; source.Parent=modal
 local copyBtn=mkButton(modal,"คัดลอกข้อมูล",588,16,118,38); copyBtn.TextSize=14; copyBtn.ZIndex=503
 local closeBtn=mkButton(modal,"✕",712,16,32,38); closeBtn.TextSize=20; closeBtn.ZIndex=503; closeBtn.BackgroundColor3=Color3.fromRGB(74,45,56)
 local scroll=Instance.new("ScrollingFrame"); scroll.Position=UDim2.fromOffset(22,84); scroll.Size=UDim2.new(1,-44,1,-106); scroll.BackgroundColor3=Color3.fromRGB(9,13,20); scroll.BorderSizePixel=0; scroll.ScrollBarThickness=6; scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new(); scroll.ZIndex=502; scroll.Parent=modal; Instance.new("UICorner",scroll).CornerRadius=UDim.new(0,12); styleScroll(scroll)
 local pad=Instance.new("UIPadding"); pad.PaddingTop=UDim.new(0,16); pad.PaddingLeft=UDim.new(0,16); pad.PaddingRight=UDim.new(0,16); pad.PaddingBottom=UDim.new(0,16); pad.Parent=scroll
 local body=Instance.new("TextLabel"); body.Size=UDim2.new(1,-4,0,10); body.AutomaticSize=Enum.AutomaticSize.Y; body.BackgroundTransparency=1; body.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); body.TextSize=18; body.LineHeight=1.18; body.TextWrapped=true; body.TextXAlignment=Enum.TextXAlignment.Left; body.TextYAlignment=Enum.TextYAlignment.Top; body.TextColor3=Color3.fromRGB(226,234,248); body.ZIndex=503; body.Parent=scroll
 RT.infoPopup={overlay=overlay,backdrop=backdrop,modal=modal,scale=scale,title=title,source=source,body=body,copy=copyBtn,close=closeBtn,plain="",closing=false}

 RT.formatSkillPopup=function(c,sd)
  local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
  local labels={AttackType="รูปแบบการโจมตี",Category="หมวด",Damage="ดาเมจ",DamageType="ชนิดดาเมจ",Range="ระยะ",SplashRadius="รัศมี Splash",Cooldown="คูลดาวน์",CastTime="เวลาร่าย",Delay="หน่วงก่อนทำงาน",Animation="อนิเมชัน",Marker="Marker",ResetOtherSimilarUnits="Reset ตัวอื่นชนิดเดียวกัน",StopOthers="หยุดตัวอื่น",DamagePerHit="ดาเมจต่อฮิต",DodgeDuration="ระยะเวลาหลบ",MaximumDamage="ดาเมจสูงสุด",MaximumStacks="สแต็กสูงสุด",AutoSkillOnObtain="AutoSkillOnObtain"}
  local notes={Cooldown="เวลาที่เกมกำหนดก่อนสกิลใช้ได้อีกครั้ง",CastTime="เวลาร่ายที่เกมระบุ",Delay="เวลาหน่วงที่เกมระบุก่อนเอฟเฟกต์ทำงาน",Range="ระยะของสกิลตามข้อมูลเกม",SplashRadius="รัศมีพื้นที่ Splash ตามข้อมูลเกม"}
  local groups={CORE={},TIME={},LEVEL={},MUT={},PASSIVE={},EXTRA={}}
  local function fmt(path,key,v)
   if type(v)=="boolean" then return v and "ใช่ / เปิด" or "ไม่ใช่ / ปิด" end
   if type(v)~="number" then return tostring(v) end
   local lp=string.lower(path); local lk=string.lower(key)
   if string.find(lp,"multipliers",1,true) then return string.format("%.2fx  (%+.1f%%)",v,(v-1)*100) end
   if string.find(lk,"duration",1,true) or lk=="cooldown" or lk=="casttime" or lk=="delay" then return tostring(v).." วินาที" end
   if string.find(lk,"percent",1,true) or string.find(lk,"chance",1,true) then return string.format("%.2f%%",math.abs(v)<=1 and v*100 or v) end
   return tostring(v)
  end
  local function addRow(g,path,key,v,label)
   groups[g][#groups[g]+1]={path=path,key=key,label=label or labels[key] or skillFriendly[key] or key,value=fmt(path,key,v),note=notes[key]}
  end
  local function walk(t,path,depth)
   if type(t)~="table" or depth<0 then return end; local keys={}; for k in pairs(t) do keys[#keys+1]=k end; table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
   for _,k0 in ipairs(keys) do local k=tostring(k0); local v=t[k0]; local p=path.."."..k
    if type(v)=="string" or type(v)=="number" or type(v)=="boolean" then
     if string.find(p,".MutationMultipliers.",1,true) then local mut=p:match("MutationMultipliers%.([^%.]+)") or "?"; addRow("MUT",p,k,v,mut.." • "..(labels[k] or skillFriendly[k] or k))
     elseif string.find(p,".LevelMultipliers.",1,true) then addRow("LEVEL",p,k,v,(labels[k] or skillFriendly[k] or k).."ตามเลเวล")
     elseif string.find(p,".PassiveConfig.",1,true) then addRow("PASSIVE",p,k,v)
     elseif path=="ActiveSkill" and (k=="Cooldown" or k=="CastTime" or k=="Delay") then addRow("TIME",p,k,v)
     elseif path=="ActiveSkill" and (k=="AttackType" or k=="Category" or k=="Damage" or k=="DamageType" or k=="Range" or k=="SplashRadius") then addRow("CORE",p,k,v)
     else addRow("EXTRA",p,k,v) end
    elseif type(v)=="table" and depth>0 then walk(v,p,depth-1) end
   end
  end
  local lines={}; local kind=sd and (sd.kind=="PASSIVE" and "สกิลติดตัว" or "สกิลกดใช้") or "ไม่พบสกิล"
  lines[#lines+1]="<font size='14' color='rgb(126,158,232)'><b>"..kind.."</b></font>"
  lines[#lines+1]="<font size='25' color='rgb(247,250,255)'><b>"..esc(sd and sd.name or "ไม่พบข้อมูลสกิลจากเกม").."</b></font>"
  lines[#lines+1]="<font size='14' color='rgb(151,171,205)'>ตัวละคร: "..esc(c.DisplayName or c.Name).."</font>"
  if not sd then lines[#lines+1]=""; lines[#lines+1]="<font color='rgb(230,181,96)'><b>ไม่พบ ActiveSkill / ActiveAttacks ของตัวละครนี้ในข้อมูลเกมเวอร์ชันปัจจุบัน</b></font>"; return table.concat(lines,"\n") end
  lines[#lines+1]=""; lines[#lines+1]="<font size='19' color='rgb(109,226,166)'><b>▰ คำอธิบายจากเกม</b></font>"
  lines[#lines+1]=(sd.description and tostring(sd.description)~="") and esc(sd.description) or "<font color='rgb(160,174,198)'>ไม่พบคำอธิบายในข้อมูลเกม</font>"
  walk(sd.skill,"ActiveSkill",5); if type(sd.module)=="table" and type(sd.module.PassiveConfig)=="table" then walk(sd.module.PassiveConfig,"Module.PassiveConfig",4) end
  lines[#lines+1]=""; lines[#lines+1]="<font size='19' color='rgb(151,184,255)'><b>▰ อ่านค่าหลักแบบง่าย</b></font>"
  for _,r in ipairs(groups.CORE) do lines[#lines+1]="<b>"..esc(r.label).."</b>  <font color='rgb(245,248,255)'>"..esc(r.value).."</font>"; if r.note then lines[#lines+1]="<font size='14' color='rgb(137,153,181)'>   ↳ "..esc(r.note).."</font>" end end
  for _,r in ipairs(groups.TIME) do lines[#lines+1]="<b>"..esc(r.label).."</b>  <font color='rgb(188,224,255)'>"..esc(r.value).."</font>"; if r.note then lines[#lines+1]="<font size='14' color='rgb(137,153,181)'>   ↳ "..esc(r.note).."</font>" end end
  if #groups.LEVEL>0 then lines[#lines+1]=""; lines[#lines+1]="<font size='17' color='rgb(255,203,122)'><b>▦ ตัวคูณตามเลเวล</b></font>"; for _,r in ipairs(groups.LEVEL) do lines[#lines+1]="• <b>"..esc(r.label).."</b>  "..esc(r.value) end end
  if #groups.MUT>0 then lines[#lines+1]=""; lines[#lines+1]="<font size='17' color='rgb(192,157,255)'><b>◆ ตัวคูณตามมิวเทชัน</b></font>"; for _,r in ipairs(groups.MUT) do lines[#lines+1]="• <b>"..esc(r.label).."</b>  <font color='rgb(240,232,255)'>"..esc(r.value).."</font>" end end
  if #groups.PASSIVE>0 then lines[#lines+1]=""; lines[#lines+1]="<font size='17' color='rgb(112,226,165)'><b>♥ ค่าติดตัว / PassiveConfig</b></font>"; for _,r in ipairs(groups.PASSIVE) do lines[#lines+1]="• <b>"..esc(r.label).."</b>  "..esc(r.value) end end
  if #groups.EXTRA>0 then lines[#lines+1]=""; lines[#lines+1]="<font size='17' color='rgb(174,190,220)'><b>◇ ข้อมูลเพิ่มเติมที่เกมระบุ</b></font>"; for _,r in ipairs(groups.EXTRA) do lines[#lines+1]="• <b>"..esc(r.label).."</b>  "..esc(r.value) end end
  if knownSkillConflicts[tostring(c.Name)] then lines[#lines+1]=""; lines[#lines+1]="<font color='rgb(255,190,90)'><b>⚠ ข้อมูลในเกมมีค่าที่ขัดกัน</b></font>"; lines[#lines+1]=esc(knownSkillConflicts[tostring(c.Name)]) end
  lines[#lines+1]=""; lines[#lines+1]="<font size='14' color='rgb(124,145,180)'>แหล่งข้อมูล: "..esc(sd.source or "ActiveSkillInfo / ActiveAttacks").."\nการจัดหมวดและคำไทยมีไว้ช่วยอ่านเท่านั้น • ค่าทั้งหมดดึงจากข้อมูลเกม</font>"
  return table.concat(lines,"\n")
 end
 RT.closeInfoPopup=function()
  local p=RT.infoPopup; if not p or not p.overlay.Visible or p.closing then return end; p.closing=true
  TweenService:Create(p.scale,TweenInfo.new(0.12,Enum.EasingStyle.Quad,Enum.EasingDirection.In),{Scale=0.96}):Play(); TweenService:Create(p.backdrop,TweenInfo.new(0.12),{BackgroundTransparency=1}):Play()
  task.delay(0.13,function() if p then p.overlay.Visible=false; p.closing=false; p.scale.Scale=1 end end)
 end
 RT.openInfoPopup=function(mode)
  if not infoSelected or not RT.infoPopup then return end; local sd=getSkillData(infoSelected.Name); local p=RT.infoPopup; infoMode=mode; updateInfoModeButtons()
  local shown=tostring(infoSelected.DisplayName or infoSelected.Name); if shown~=tostring(infoSelected.Name) then shown=shown.." ("..tostring(infoSelected.Name)..")" end
  if mode=="RAW" then p.title.Text="ข้อมูลดิบ • "..shown; p.body.RichText=false; p.body.Text=formatInfoRaw(infoSelected,sd); p.source.Text="ข้อมูลตรงจากโมดูลเกม • เหมาะสำหรับตรวจสอบค่าต้นฉบับ"
  elseif mode=="SKILL" then p.title.Text="ความสามารถ • "..shown; p.body.RichText=true; p.body.Text=RT.formatSkillPopup(infoSelected,sd); p.source.Text="ActiveSkillInfo + ActiveAttacks • แสดงเฉพาะค่าที่ตรวจพบจากเกม"
  else p.title.Text="สรุปตัวละคร • "..shown; p.body.RichText=true; p.body.Text=formatInfoSummary(infoSelected,sd); p.source.Text="CharactersInfo + ActiveSkillInfo/ActiveAttacks • ไม่รวม Luck/การันตีในค่าโอกาสพื้นฐาน" end
  p.plain=tostring(p.body.Text):gsub("<br%s*/?>","\n"):gsub("<[^>]->",""); p.scroll=scroll; scroll.CanvasPosition=Vector2.new(0,0); p.overlay.Visible=true; p.closing=false; p.scale.Scale=0.94; p.backdrop.BackgroundTransparency=1
  TweenService:Create(p.scale,TweenInfo.new(0.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play(); TweenService:Create(p.backdrop,TweenInfo.new(0.16),{BackgroundTransparency=0.28}):Play()
 end
 keep(closeBtn.Activated:Connect(function() RT.closeInfoPopup() end)); keep(backdrop.Activated:Connect(function() RT.closeInfoPopup() end))
 keep(copyBtn.Activated:Connect(function() local fn=(type(setclipboard)=="function" and setclipboard) or (type(toclipboard)=="function" and toclipboard); if fn then local ok=pcall(fn,RT.infoPopup.plain or ""); copyBtn.Text=ok and "✓ คัดลอกแล้ว" or "คัดลอกไม่สำเร็จ" else copyBtn.Text="ไม่มีฟังก์ชันคัดลอก" end; task.delay(1.2,function() if copyBtn then copyBtn.Text="คัดลอกข้อมูล" end end) end))
 keep(UIS.InputBegan:Connect(function(input,gp) if input.KeyCode==Enum.KeyCode.Escape and RT.infoPopup and RT.infoPopup.overlay.Visible then RT.closeInfoPopup() end end))
end
RT.setupInfoPopup()
keep(summaryBtn.Activated:Connect(function() RT.openInfoPopup("SUMMARY") end))
if RT.infoSkillBtn then keep(RT.infoSkillBtn.Activated:Connect(function() RT.openInfoPopup("SKILL") end)) end
keep(rawBtn.Activated:Connect(function() RT.openInfoPopup("RAW") end))
if charCatalog[1] then selectInfoCharacter(charCatalog[1]) end
refreshInfoList(); updateInfoModeButtons()

RT.buildEventUI=function()
 RT.eventUI.buttons={}
 local et=Instance.new("TextLabel"); et.Name="EventPotionTitle"; et.BackgroundTransparency=1; et.Position=UDim2.fromOffset(210,86); et.Size=UDim2.fromOffset(740,30); et.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); et.TextSize=24; et.TextColor3=Color3.fromRGB(245,248,255); et.TextXAlignment=Enum.TextXAlignment.Left; et.Text="อีเวนต์อัตโนมัติ • ใช้น้ำยาทันทีเมื่อ Mutation Time มา"; et.Parent=frame; RT.eventUI.title=et
 local es=Instance.new("TextLabel"); es.Name="EventPotionStatus"; es.Position=UDim2.fromOffset(210,124); es.Size=UDim2.fromOffset(480,76); es.BackgroundColor3=Color3.fromRGB(19,25,37); es.BorderSizePixel=0; es.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); es.TextSize=16; es.RichText=true; es.TextWrapped=true; es.TextXAlignment=Enum.TextXAlignment.Left; es.TextYAlignment=Enum.TextYAlignment.Center; es.TextColor3=Color3.fromRGB(222,231,247); es.Parent=frame; stylePanel(es); RT.eventUI.status=es
 local em=mkButton(frame,"ระบบใช้ยาเมื่ออีเวนต์: ปิด",702,124,248,76); em.TextSize=17; RT.eventUI.master=em
 local eh=Instance.new("TextLabel"); eh.BackgroundTransparency=1; eh.Position=UDim2.fromOffset(210,214); eh.Size=UDim2.fromOffset(740,24); eh.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); eh.TextSize=18; eh.TextColor3=Color3.fromRGB(228,236,251); eh.TextXAlignment=Enum.TextXAlignment.Left; eh.Text="เลือก Mutation Time ที่ต้องการ (เลือกได้หลายตัว)"; eh.Parent=frame; RT.eventUI.eventHeader=eh
 local eg=Instance.new("Frame"); eg.Name="EventMutationGrid"; eg.Position=UDim2.fromOffset(210,244); eg.Size=UDim2.fromOffset(740,164); eg.BackgroundTransparency=1; eg.Parent=frame; RT.eventUI.grid=eg
 local gl=Instance.new("UIGridLayout"); gl.CellSize=UDim2.fromOffset(179,76); gl.CellPadding=UDim2.fromOffset(8,8); gl.FillDirectionMaxCells=4; gl.SortOrder=Enum.SortOrder.LayoutOrder; gl.Parent=eg
 for _,m in ipairs(mutCatalog) do if (tonumber(m.Info.EventChance) or 0)>0 then
  local b=mkButton(eg,"",0,0,179,76); b.Text=""; b.BackgroundColor3=Color3.fromRGB(24,30,43); b.ClipsDescendants=true; b.LayoutOrder=math.floor((tonumber(m.Info.Damage) or 0)*100)
  local gg=RT.mutationGradientFolder and RT.mutationGradientFolder:FindFirstChild(m.Name); local base=Color3.fromRGB(95,120,180); if gg and gg:IsA("UIGradient") and #gg.Color.Keypoints>0 then base=gg.Color.Keypoints[1].Value end
  local bar=Instance.new("Frame"); bar.Position=UDim2.fromOffset(8,9); bar.Size=UDim2.new(0,5,1,-18); bar.BackgroundColor3=gg and Color3.new(1,1,1) or base; bar.BorderSizePixel=0; bar.Parent=b; Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0); if gg and gg:IsA("UIGradient") then gg:Clone().Parent=bar end
  local n=Instance.new("TextLabel"); n.BackgroundTransparency=1; n.Position=UDim2.fromOffset(22,9); n.Size=UDim2.fromOffset(145,26); n.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); n.TextSize=17; n.TextXAlignment=Enum.TextXAlignment.Left; n.TextColor3=Color3.fromRGB(248,250,255); n.Text=m.Name; n.Parent=b; if gg and gg:IsA("UIGradient") then gg:Clone().Parent=n end
  local sub=Instance.new("TextLabel"); sub.BackgroundTransparency=1; sub.Position=UDim2.fromOffset(22,39); sub.Size=UDim2.fromOffset(145,22); sub.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); sub.TextSize=13; sub.TextXAlignment=Enum.TextXAlignment.Left; sub.TextColor3=Color3.fromRGB(166,184,216); sub.Text="ช่วงอีเวนต์: "..tostring(m.Info.EventChance).."%"; sub.Parent=b
  RT.eventUI.buttons[m.Name]={button=b,color=base,title=n,sub=sub,bar=bar,chance=m.Info.EventChance}
  keep(b.Activated:Connect(function() RT.eventPotion.events[m.Name]=not RT.eventPotion.events[m.Name]; saveConfig(); if RT.refreshEventUI then RT.refreshEventUI() end; if RT.handleMutationEvent then RT.handleMutationEvent("event_select") end end))
 end end
 local ph=Instance.new("TextLabel"); ph.BackgroundTransparency=1; ph.Position=UDim2.fromOffset(210,418); ph.Size=UDim2.fromOffset(740,24); ph.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); ph.TextSize=18; ph.TextColor3=Color3.fromRGB(228,236,251); ph.TextXAlignment=Enum.TextXAlignment.Left; ph.Text="เลือกน้ำยาและจำนวนที่จะใช้ต่อรอบอีเวนต์"; ph.Parent=frame; RT.eventUI.potionHeader=ph
 local function makePotionCard(name,x)
  local card=Instance.new("Frame"); card.Name=name:gsub(" ","").."Card"; card.Position=UDim2.fromOffset(x,450); card.Size=UDim2.fromOffset(360,140); card.BackgroundColor3=Color3.fromRGB(19,25,37); card.BorderSizePixel=0; card.Parent=frame; stylePanel(card)
  local nm=Instance.new("TextLabel"); nm.BackgroundTransparency=1; nm.Position=UDim2.fromOffset(14,10); nm.Size=UDim2.fromOffset(210,24); nm.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); nm.TextSize=18; nm.TextXAlignment=Enum.TextXAlignment.Left; nm.TextColor3=Color3.fromRGB(245,248,255); nm.Text=name; nm.Parent=card
  local inv=Instance.new("TextLabel"); inv.BackgroundTransparency=1; inv.Position=UDim2.fromOffset(230,10); inv.Size=UDim2.fromOffset(116,24); inv.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); inv.TextSize=14; inv.TextXAlignment=Enum.TextXAlignment.Right; inv.TextColor3=Color3.fromRGB(156,181,218); inv.Parent=card
  local tog=mkButton(card,"○ ไม่ใช้",14,45,190,42); tog.TextSize=16
  local q=Instance.new("TextBox"); q.Position=UDim2.fromOffset(216,45); q.Size=UDim2.fromOffset(130,42); q.BackgroundColor3=Color3.fromRGB(28,35,50); q.BorderSizePixel=0; q.TextColor3=Color3.fromRGB(250,252,255); q.PlaceholderText="จำนวน"; q.ClearTextOnFocus=false; q.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); q.TextSize=18; q.Text=tostring(RT.eventPotion.potions[name].amount or 1); q.Parent=card; Instance.new("UICorner",q).CornerRadius=UDim.new(0,9); styleTextBox(q)
  local hint=Instance.new("TextLabel"); hint.BackgroundTransparency=1; hint.Position=UDim2.fromOffset(14,96); hint.Size=UDim2.fromOffset(332,30); hint.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); hint.TextSize=13; hint.TextWrapped=true; hint.TextXAlignment=Enum.TextXAlignment.Left; hint.TextColor3=Color3.fromRGB(156,174,204); hint.Text="ใช้สูงสุดเท่าที่มี • ระบบส่งแบบ x5 + x1 ตาม UI เกม"; hint.Parent=card
  RT.eventUI[name]={card=card,toggle=tog,qty=q,inventory=inv,title=nm,hint=hint}
  keep(tog.Activated:Connect(function() local p=RT.eventPotion.potions[name]; p.enabled=not p.enabled; saveConfig(); if RT.refreshEventUI then RT.refreshEventUI() end; if RT.handleMutationEvent then RT.handleMutationEvent("potion_toggle") end end))
  keep(q.FocusLost:Connect(function() local p=RT.eventPotion.potions[name]; p.amount=math.clamp(math.floor(tonumber(q.Text) or p.amount or 1),0,100); q.Text=tostring(p.amount); saveConfig(); if RT.refreshEventUI then RT.refreshEventUI() end; if RT.handleMutationEvent then RT.handleMutationEvent("quantity_change") end end))
 end
 makePotionCard("Luck Potion",210); makePotionCard("Super Luck Potion",590)
 keep(em.Activated:Connect(function() RT.eventPotion.enabled=not RT.eventPotion.enabled; saveConfig(); if RT.refreshEventUI then RT.refreshEventUI() end; if RT.eventPotion.enabled and RT.handleMutationEvent then RT.handleMutationEvent("master_toggle") end end))
 RT.refreshEventUI=function()
  local current=WS:GetAttribute("MutationEvent"); local curText=(current==nil or tostring(current)=="") and "ไม่มี Mutation Time" or tostring(current); local x2=LP:GetAttribute("Mutation2x") and "เปิด" or "ปิด"
  es.Text="<b>ตอนนี้:</b> "..curText.."   •   <b>2x Mutation:</b> "..x2.."\n<font size='13' color='rgb(158,178,211)'>ล่าสุด: "..tostring(RT.eventPotion.lastResult or "ยังไม่ทำงาน").."</font>"
  em.Text=RT.eventPotion.enabled and "✓ ระบบใช้ยาเมื่ออีเวนต์: เปิด" or "○ ระบบใช้ยาเมื่ออีเวนต์: ปิด"; em.BackgroundColor3=RT.eventPotion.enabled and Color3.fromRGB(31,139,102) or Color3.fromRGB(28,35,52)
  local selectedCount=0
  for name,x in pairs(RT.eventUI.buttons) do
   local sel=RT.eventPotion.events[name]==true; if sel then selectedCount+=1 end
   x.button.BackgroundColor3=sel and Color3.fromRGB(18,23,34):Lerp(x.color,0.22) or Color3.fromRGB(22,27,39)
   x.title.Text=(sel and "✓ " or "")..name; x.title.TextColor3=sel and Color3.fromRGB(255,255,255) or Color3.fromRGB(216,224,240)
   x.sub.Text=sel and ("✓ เลือกอยู่ • โอกาสอีเวนต์ "..tostring(x.chance).."%") or ("แตะเพื่อเลือก • โอกาสอีเวนต์ "..tostring(x.chance).."%")
   x.sub.TextColor3=sel and Color3.fromRGB(226,237,255) or Color3.fromRGB(139,155,184)
   x.bar.Size=sel and UDim2.new(0,7,1,-16) or UDim2.new(0,4,1,-20); x.bar.Position=sel and UDim2.fromOffset(7,8) or UDim2.fromOffset(9,10)
   local st=x.button:FindFirstChildOfClass("UIStroke"); if st then st.Color=x.color; st.Transparency=sel and 0 or 0.58; st.Thickness=sel and 2.4 or 1 end
  end
  eh.Text="เลือก Mutation Time ที่ต้องการ • เลือกแล้ว "..selectedCount.." ตัว"
  for _,name in ipairs({"Luck Potion","Super Luck Potion"}) do
   local p=RT.eventPotion.potions[name]; local u=RT.eventUI[name]; local enabled=p.enabled==true
   u.card.BackgroundColor3=enabled and Color3.fromRGB(20,49,41) or Color3.fromRGB(18,23,34)
   local pst=u.card:FindFirstChildOfClass("UIStroke"); if pst then pst.Color=enabled and Color3.fromRGB(68,196,135) or Color3.fromRGB(53,64,84); pst.Transparency=enabled and 0.03 or 0.40; pst.Thickness=enabled and 2 or 1 end
   u.title.Text=(enabled and "✓ " or "")..name; u.title.TextColor3=enabled and Color3.fromRGB(238,255,247) or Color3.fromRGB(224,231,244)
   u.toggle.Text=enabled and "✓ เปิดใช้ "..name or "○ เปิดใช้ "..name; u.toggle.BackgroundColor3=enabled and Color3.fromRGB(43,132,91) or Color3.fromRGB(28,35,52)
   u.qty.BackgroundColor3=enabled and Color3.fromRGB(30,48,48) or Color3.fromRGB(28,35,50); u.qty.TextColor3=enabled and Color3.fromRGB(244,255,249) or Color3.fromRGB(205,214,230)
   u.inventory.Text="มี x"..tostring(RT.getItemAmount(name)); u.inventory.TextColor3=enabled and Color3.fromRGB(111,230,167) or Color3.fromRGB(156,181,218)
   u.hint.Text=enabled and ("✓ เปิดใช้อยู่ • เมื่ออีเวนต์ตรงจะใช้ x"..tostring(p.amount or 0)) or "ยังไม่ได้เลือกใช้ • แตะปุ่มด้านบนเพื่อเปิด"
   u.hint.TextColor3=enabled and Color3.fromRGB(157,222,188) or Color3.fromRGB(139,154,180)
   if not u.qty:IsFocused() then u.qty.Text=tostring(p.amount or 0) end
  end
 end
 RT.refreshEventUI()
end
RT.buildEventUI()
RT.setupAutoClone=function()
 local AnimeState=require(Modules:WaitForChild("Shared"):WaitForChild("AnimeState")); AnimeState.Start()
 local CloneInfo=require(Modules:WaitForChild("Shared"):WaitForChild("CloneStuff"):WaitForChild("CloneInfo"))
 local TraitInfo=require(Modules:WaitForChild("Shared"):WaitForChild("Trait"):WaitForChild("TraitInfo"))
 local dataClient=require(RS:WaitForChild("Data"):WaitForChild("DataService")).client
 local Request=RS:WaitForChild("Remotes"):WaitForChild("CloneRemotes"):WaitForChild("Request")
 local C=RT.clone; local U=RT.cloneUI
 local function uid(x) return tostring(x and (x.UUID or x.CharacterId) or "") end
 local function metaFor(name) for _,m in ipairs(CharacterInfo.Characters or {}) do if tostring(m.Name)==tostring(name) then return m end end end
 local function traitRarity(u) local t=TraitInfo.Traits and TraitInfo.Traits[tostring(u and u.Trait or "")]; return t and t.Rarity or nil end
 local function sig(u) return table.concat({tostring(u and u.Name or ""),tostring(u and u.Level or 1),tostring(u and u.Mutation or "None"),tostring(u and u.Trait or "")},"|") end
 local function eligible(u)
  local m=u and metaFor(u.Name); if not m then return false,"ไม่พบข้อมูลตัวละคร" end
  if tostring(m.Rarity)=="Limited" then return false,"Limited โคลนไม่ได้" end
  if tostring(u.Mutation or "") == "Astronaut" then return false,"Astronaut โคลนไม่ได้" end
  if m.CanClone==false then return false,"เกมปิด CanClone" end
  return uid(u)~="","พร้อม"
 end
 local function inv() return AnimeState.GetInventory() or {} end
 local function activeClone() for _,x in ipairs(AnimeState.GetCloning() or {}) do if uid(x)~="" then return x end end end
 local function sourceFor(r)
  for _,x in ipairs(inv()) do if uid(x)==tostring(r.sourceUUID or "") then return x end end
  for _,x in ipairs(inv()) do if sig(x)==tostring(r.sourceSig or "") then r.sourceUUID=uid(x); return x end end
 end
 local function countRule(r)
  local n=0
  for _,x in ipairs(inv()) do
   if r.matchMode=="name" then if tostring(x.Name)==tostring(r.name) then n+=1 end
   elseif sig(x)==tostring(r.sourceSig or "") then n+=1 end
  end
  return n
 end
 local function essenceFor(u)
  local m=metaFor(u and u.Name); if not m then return "?",0,0 end
  local item=tostring(m.Rarity or "Common").." Essence"
  local have=math.floor(tonumber(AnimeState.GetItemAmount(item)) or 0)
  local need=math.floor(tonumber(CloneInfo.GetRequiredFragments(u.Level,u.Mutation)) or 0)
  return item,have,need
 end
 local function secondsFor(u)
  local m=metaFor(u and u.Name); if not m then return 0 end
  local reduce=math.max(0,math.floor(tonumber(dataClient:get("Reduce50Uses")) or 0))
  return tonumber(CloneInfo.GetSecondsWithReduce50(m.Rarity,u.Level,u.Mutation,reduce,traitRarity(u))) or 0
 end
 local function fmt(sec)
  sec=math.max(0,math.ceil(tonumber(sec) or 0)); local h=math.floor(sec/3600); local m=math.floor(sec%3600/60); local s=sec%60
  if h>0 then return string.format("%dh %dm %ds",h,m,s) end; if m>0 then return string.format("%dm %ds",m,s) end; return tostring(s).."s"
 end
 local function ruleById(id) for _,r in ipairs(C.rules) do if r.id==id then return r end end end
 RT.saveCloneConfig=function()
  if type(writefile)~="function" then return false end
  local rows={}
  for _,r in ipairs(C.rules) do rows[#rows+1]={id=r.id,enabled=r.enabled~=false,sourceUUID=r.sourceUUID,sourceSig=r.sourceSig,name=r.name,rarity=r.rarity,level=r.level,mutation=r.mutation,trait=r.trait,maxCount=r.maxCount,delay=r.delay,autoReplace=r.autoReplace==true,matchMode=r.matchMode,reachedOnce=r.reachedOnce==true} end
  local ok,j=pcall(function() return HttpService:JSONEncode({version="1.0",rules=rows}) end); if not ok then return false end
  local ok2=pcall(writefile,RT.cloneFile,j); if ok2 then log("CLONE_CONFIG_SAVED | rules="..#rows) end; return ok2
 end
 RT.loadCloneConfig=function()
  C.enabled=false; C.rules={}; C.ruleSeq=0; C.selectedRuleId=nil
  if type(readfile)~="function" then return false end
  local ok,t=pcall(readfile,RT.cloneFile); if not ok or type(t)~="string" or t=="" then return false end
  local ok2,d=pcall(function() return HttpService:JSONDecode(t) end); if not ok2 or type(d)~="table" then return false end
  for _,raw in ipairs(type(d.rules)=="table" and d.rules or {}) do
   if type(raw)=="table" and tostring(raw.name or "")~="" then
    local id=tonumber(raw.id); if not id then C.ruleSeq+=1; id=C.ruleSeq else C.ruleSeq=math.max(C.ruleSeq,id) end
    C.rules[#C.rules+1]={id=id,enabled=raw.enabled~=false,sourceUUID=tostring(raw.sourceUUID or ""),sourceSig=tostring(raw.sourceSig or ""),name=tostring(raw.name),rarity=tostring(raw.rarity or ""),level=tonumber(raw.level) or 1,mutation=tostring(raw.mutation or "None"),trait=tostring(raw.trait or ""),maxCount=math.clamp(math.floor(tonumber(raw.maxCount) or 2),1,999),delay=math.clamp(tonumber(raw.delay) or 2,0,3600),autoReplace=raw.autoReplace==true,matchMode=raw.matchMode=="name" and "name" or "exact",reachedOnce=raw.reachedOnce==true}
   end
  end
  log("CLONE_CONFIG_LOADED | rules="..#C.rules.." | master=OFF"); return true
 end
 RT.loadCloneConfig()
 local function planNext()
  if #C.rules==0 then return nil,nil,"ยังไม่มีกฎ Auto Clone" end
  local start=(C.roundRobin%#C.rules)+1
  local blocked=nil
  for step=0,#C.rules-1 do
   local idx=((start+step-1)%#C.rules)+1; local r=C.rules[idx]
   if r.enabled~=false then
    local src=sourceFor(r); local current=countRule(r); r.currentCount=current
    if current>=r.maxCount then r.reachedOnce=true
    elseif r.reachedOnce and not r.autoReplace then blocked=blocked or "กฎถึงเป้าหมายแล้ว"
    elseif not src then blocked=blocked or ("หา source ของ "..r.name.." ไม่พบ")
    else
     local ok,why=eligible(src)
     if not ok then blocked=blocked or why
     else
      local item,have,need=essenceFor(src)
      if have<need then blocked=blocked or (item.." ไม่พอ "..have.."/"..need)
      else C.roundRobin=idx; return r,src,"พร้อม" end
     end
    end
   end
  end
  return nil,nil,blocked or "ทุกกฎครบเป้าหมาย"
 end
 RT.clonePlanNext=planNext
 local function fireStart(r,src,source)
  local ok,why=eligible(src); if not ok then C.lastResult=why; return false,why end
  if activeClone() then C.lastResult="เครื่อง Clone กำลังทำงาน"; return false,C.lastResult end
  local item,have,need=essenceFor(src); if have<need then C.lastResult=item.." ไม่พอ "..have.."/"..need; return false,C.lastResult end
  local id=uid(src); C.busy=true; C.activeRuleId=r and r.id or nil; C.pendingStartUUID=id; C.lastActionAt=os.clock(); C.nextActionAt=os.clock()+5
  local sent,err=pcall(function() Request:FireServer("Start",{UUID=id,CharacterId=id}) end)
  C.lastResult=sent and ("ส่ง Start • "..tostring(src.Name)) or ("Start error: "..tostring(err)); log("AUTO_CLONE_START | source="..tostring(source).." | rule="..tostring(r and r.id).." | id="..id.." | name="..tostring(src.Name).." | essence="..have.."/"..need)
  task.delay(1.2,function() if RT.alive then C.busy=false; C.pendingStartUUID=nil end end); return sent,C.lastResult
 end
 RT.cloneStartRule=fireStart
 local function removeRule(id) for i=#C.rules,1,-1 do if C.rules[i].id==id then table.remove(C.rules,i); break end end; if C.selectedRuleId==id then C.selectedRuleId=nil end; RT.saveCloneConfig() end
 local title=Instance.new("TextLabel"); title.BackgroundTransparency=1; title.Position=UDim2.fromOffset(210,82); title.Size=UDim2.fromOffset(510,34); title.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); title.TextSize=25; title.TextXAlignment=Enum.TextXAlignment.Left; title.TextColor3=Color3.fromRGB(248,250,255); title.Text="♊ Auto Clone"; title.Parent=frame
 local subtitle=Instance.new("TextLabel"); subtitle.BackgroundTransparency=1; subtitle.Position=UDim2.fromOffset(212,113); subtitle.Size=UDim2.fromOffset(520,20); subtitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); subtitle.TextSize=12; subtitle.TextXAlignment=Enum.TextXAlignment.Left; subtitle.TextColor3=Color3.fromRGB(139,158,193); subtitle.Text="เลือกต้นแบบ → ตั้งเป้าหมาย → บันทึกกฎ → เปิดระบบ"; subtitle.Parent=frame
 local accent=Instance.new("Frame"); accent.Position=UDim2.fromOffset(210,136); accent.Size=UDim2.fromOffset(740,2); accent.BorderSizePixel=0; accent.BackgroundColor3=Color3.fromRGB(100,128,255); accent.Parent=frame; local ag=Instance.new("UIGradient"); ag.Color=ColorSequence.new(Color3.fromRGB(102,128,255),Color3.fromRGB(88,214,190)); ag.Parent=accent
 local master=mkButton(frame,"▶  เริ่ม AUTO CLONE",742,84,208,46); master.TextSize=16; master.BackgroundColor3=Color3.fromRGB(35,45,64)
 local status=Instance.new("TextLabel"); status.Position=UDim2.fromOffset(210,146); status.Size=UDim2.fromOffset(740,38); status.BackgroundColor3=Color3.fromRGB(18,24,36); status.BorderSizePixel=0; status.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); status.TextSize=13; status.TextColor3=Color3.fromRGB(205,219,244); status.TextXAlignment=Enum.TextXAlignment.Left; status.Text="      พร้อม"; status.Parent=frame; Instance.new("UICorner",status).CornerRadius=UDim.new(0,10); local sst=Instance.new("UIStroke"); sst.Color=Color3.fromRGB(58,74,108); sst.Transparency=0.35; sst.Parent=status
 local stateDot=Instance.new("Frame"); stateDot.Name="CloneStateDot"; stateDot.Position=UDim2.fromOffset(14,14); stateDot.Size=UDim2.fromOffset(10,10); stateDot.BorderSizePixel=0; stateDot.BackgroundColor3=Color3.fromRGB(116,128,150); stateDot.Parent=status; Instance.new("UICorner",stateDot).CornerRadius=UDim.new(1,0)
 local sourcePanel=Instance.new("Frame"); sourcePanel.Position=UDim2.fromOffset(210,194); sourcePanel.Size=UDim2.fromOffset(350,396); sourcePanel.BackgroundColor3=Color3.fromRGB(16,21,32); sourcePanel.BorderSizePixel=0; sourcePanel.Parent=frame; stylePanel(sourcePanel)
 local editorPanel=Instance.new("Frame"); editorPanel.Position=UDim2.fromOffset(574,194); editorPanel.Size=UDim2.fromOffset(376,218); editorPanel.BackgroundColor3=Color3.fromRGB(16,21,32); editorPanel.BorderSizePixel=0; editorPanel.Parent=frame; stylePanel(editorPanel)
 local rulesPanel=Instance.new("Frame"); rulesPanel.Position=UDim2.fromOffset(574,422); rulesPanel.Size=UDim2.fromOffset(376,168); rulesPanel.BackgroundColor3=Color3.fromRGB(16,21,32); rulesPanel.BorderSizePixel=0; rulesPanel.Parent=frame; stylePanel(rulesPanel)
 U.group={title,subtitle,accent,master,status,sourcePanel,editorPanel,rulesPanel}; U.master=master; U.status=status; U.stateDot=stateDot
 local step1=Instance.new("TextLabel"); step1.Position=UDim2.fromOffset(12,10); step1.Size=UDim2.fromOffset(28,26); step1.BackgroundColor3=Color3.fromRGB(62,85,180); step1.BorderSizePixel=0; step1.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); step1.TextSize=14; step1.TextColor3=Color3.new(1,1,1); step1.Text="1"; step1.Parent=sourcePanel; Instance.new("UICorner",step1).CornerRadius=UDim.new(0,8)
 local sh=Instance.new("TextLabel"); sh.BackgroundTransparency=1; sh.Position=UDim2.fromOffset(48,9); sh.Size=UDim2.fromOffset(290,28); sh.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); sh.TextSize=18; sh.TextXAlignment=Enum.TextXAlignment.Left; sh.TextColor3=Color3.fromRGB(240,245,255); sh.Text="เลือกยูนิตต้นแบบ"; sh.Parent=sourcePanel
 local search=Instance.new("TextBox"); search.Position=UDim2.fromOffset(10,48); search.Size=UDim2.fromOffset(330,40); search.BackgroundColor3=Color3.fromRGB(25,32,47); search.BorderSizePixel=0; search.ClearTextOnFocus=false; search.PlaceholderText="ค้นหาชื่อ / ระดับ / มิวเทชัน"; search.Text=""; search.TextColor3=Color3.fromRGB(245,248,255); search.PlaceholderColor3=Color3.fromRGB(132,147,174); search.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); search.TextSize=14; search.Parent=sourcePanel; Instance.new("UICorner",search).CornerRadius=UDim.new(0,9); styleTextBox(search)
 local sourceScroll=Instance.new("ScrollingFrame"); sourceScroll.Position=UDim2.fromOffset(8,98); sourceScroll.Size=UDim2.fromOffset(334,290); sourceScroll.BackgroundTransparency=1; sourceScroll.BorderSizePixel=0; sourceScroll.ScrollBarThickness=5; sourceScroll.Parent=sourcePanel; styleScroll(sourceScroll)
 local sourceLayout=Instance.new("UIListLayout"); sourceLayout.Padding=UDim.new(0,6); sourceLayout.Parent=sourceScroll local step2=step1:Clone(); step2.Text="2"; step2.Position=UDim2.fromOffset(12,10); step2.BackgroundColor3=Color3.fromRGB(69,151,129); step2.Parent=editorPanel
 local eh=Instance.new("TextLabel"); eh.BackgroundTransparency=1; eh.Position=UDim2.fromOffset(48,9); eh.Size=UDim2.fromOffset(316,28); eh.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); eh.TextSize=18; eh.TextXAlignment=Enum.TextXAlignment.Left; eh.TextColor3=Color3.fromRGB(240,245,255); eh.Text="ตั้งเป้าหมาย"; eh.Parent=editorPanel
 local selected=Instance.new("TextLabel"); selected.Position=UDim2.fromOffset(12,44); selected.Size=UDim2.fromOffset(352,52); selected.BackgroundColor3=Color3.fromRGB(22,29,43); selected.BorderSizePixel=0; selected.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); selected.TextSize=13; selected.TextWrapped=true; selected.TextXAlignment=Enum.TextXAlignment.Left; selected.TextYAlignment=Enum.TextYAlignment.Center; selected.TextColor3=Color3.fromRGB(202,217,242); selected.Text="  ยังไม่ได้เลือกต้นแบบ"; selected.Parent=editorPanel; Instance.new("UICorner",selected).CornerRadius=UDim.new(0,9); local selStroke=Instance.new("UIStroke"); selStroke.Color=Color3.fromRGB(58,75,108); selStroke.Transparency=0.45; selStroke.Parent=selected
 local function tinyLabel(text,x,w) local l=Instance.new("TextLabel"); l.BackgroundTransparency=1; l.Position=UDim2.fromOffset(x,101); l.Size=UDim2.fromOffset(w,17); l.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); l.TextSize=11; l.TextColor3=Color3.fromRGB(137,157,192); l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=text; l.Parent=editorPanel; return l end
 tinyLabel("จำนวนเป้าหมาย",12,96); tinyLabel("หน่วงหลังจบ",116,96); tinyLabel("วิธีนับยูนิต",220,144)
 local maxBox=Instance.new("TextBox"); maxBox.Position=UDim2.fromOffset(12,120); maxBox.Size=UDim2.fromOffset(96,34); maxBox.BackgroundColor3=Color3.fromRGB(27,34,48); maxBox.BorderSizePixel=0; maxBox.Text="2"; maxBox.PlaceholderText="จำนวน"; maxBox.TextColor3=Color3.new(1,1,1); maxBox.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json"); maxBox.TextSize=14; maxBox.Parent=editorPanel; Instance.new("UICorner",maxBox).CornerRadius=UDim.new(0,8); styleTextBox(maxBox)
 local delayBox=maxBox:Clone(); delayBox.Position=UDim2.fromOffset(116,120); delayBox.Text="2"; delayBox.PlaceholderText="วินาที"; delayBox.Parent=editorPanel
 local modeBtn=mkButton(editorPanel,"ตรงทุกค่า",220,120,144,34); modeBtn.TextSize=12
 local replaceBtn=mkButton(editorPanel,"เติมกลับ: เปิด",12,162,144,36); replaceBtn.TextSize=12
 local saveBtn=mkButton(editorPanel,"บันทึกกฎ",164,162,116,36); saveBtn.TextSize=13; saveBtn.BackgroundColor3=Color3.fromRGB(55,91,181)
 local nowBtn=mkButton(editorPanel,"ครั้งเดียว",288,162,76,36); nowBtn.TextSize=12; nowBtn.BackgroundColor3=Color3.fromRGB(39,112,87)
 local note=Instance.new("TextLabel"); note.BackgroundTransparency=1; note.Position=UDim2.fromOffset(12,201); note.Size=UDim2.fromOffset(352,14); note.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); note.TextSize=10; note.TextXAlignment=Enum.TextXAlignment.Left; note.TextColor3=Color3.fromRGB(123,143,176); note.Text="ค่าระดับ / Mutation / Trait จะตามยูนิตต้นฉบับ"; note.Parent=editorPanel
 local step3=step1:Clone(); step3.Text="3"; step3.Position=UDim2.fromOffset(12,9); step3.BackgroundColor3=Color3.fromRGB(176,113,54); step3.Parent=rulesPanel
 local rh=eh:Clone(); rh.Position=UDim2.fromOffset(48,8); rh.Size=UDim2.fromOffset(316,28); rh.Text="กฎที่กำลังใช้งาน"; rh.Parent=rulesPanel
 local ruleScroll=Instance.new("ScrollingFrame"); ruleScroll.Position=UDim2.fromOffset(8,42); ruleScroll.Size=UDim2.fromOffset(360,118); ruleScroll.BackgroundTransparency=1; ruleScroll.BorderSizePixel=0; ruleScroll.ScrollBarThickness=5; ruleScroll.Parent=rulesPanel; styleScroll(ruleScroll)
 local ruleLayout=Instance.new("UIListLayout"); ruleLayout.Padding=UDim.new(0,6); ruleLayout.Parent=ruleScroll
 local function rowBtn(parent,text,x,w,bg) local b=Instance.new("TextButton"); b.Position=UDim2.fromOffset(x,8); b.Size=UDim2.fromOffset(w,30); b.BackgroundColor3=bg; b.BorderSizePixel=0; b.AutoButtonColor=true; b.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); b.TextSize=12; b.TextColor3=Color3.fromRGB(245,248,255); b.Text=text; b.Parent=parent; Instance.new("UICorner",b).CornerRadius=UDim.new(0,7); return b end
 local draftReplace=true; local draftMode="exact"
 local function selectedUnit() for _,x in ipairs(inv()) do if uid(x)==tostring(C.selectedSourceUUID or "") then return x end end end
 local function refreshEditor()
  local u=selectedUnit(); local r=C.selectedRuleId and ruleById(C.selectedRuleId) or nil
  if r and not u then u=sourceFor(r); if u then C.selectedSourceUUID=uid(u) end end
  if u then
   local m=metaFor(u.Name); local item,have,need=essenceFor(u)
   selected.Text="  "..tostring(u.Name).." • "..tostring(m and m.Rarity or "?").." • Lv."..tostring(u.Level or 1).." • "..tostring(u.Mutation or "None").."\n  "..item.." "..have.."/"..need.." • ใช้เวลา ~"..fmt(secondsFor(u))
   selected.BackgroundColor3=Color3.fromRGB(24,37,51); selStroke.Color=Color3.fromRGB(73,137,151); selStroke.Transparency=0.15
  else
   selected.Text="  ยังไม่ได้เลือกต้นแบบ\n  เลือกยูนิตจากรายการด้านซ้ายก่อน"
   selected.BackgroundColor3=Color3.fromRGB(22,29,43); selStroke.Color=Color3.fromRGB(58,75,108); selStroke.Transparency=0.45
  end
  modeBtn.Text=draftMode=="exact" and "ตรงทุกค่า" or "ชื่อเดียวกัน"
  modeBtn.BackgroundColor3=draftMode=="exact" and Color3.fromRGB(50,70,112) or Color3.fromRGB(64,73,92)
  replaceBtn.Text=draftReplace and "↻ เติมกลับ: เปิด" or "↻ เติมกลับ: ปิด"
  replaceBtn.BackgroundColor3=draftReplace and Color3.fromRGB(43,112,86) or Color3.fromRGB(61,68,82)
  saveBtn.Text=C.selectedRuleId and "✓ อัปเดตกฎ" or "+ บันทึกกฎ"
 end
 U.cloneLevelColor=Color3.fromRGB(79,183,232)
 U.cloneMutationColor=function(name)
  local g=RT.mutationGradientFolder and RT.mutationGradientFolder:FindFirstChild(tostring(name or ""))
  local c=Color3.fromRGB(128,140,162)
  if g and g:IsA("UIGradient") and #g.Color.Keypoints>0 then c=g.Color.Keypoints[1].Value end
  return c,g
 end
 U.makeCloneTag=function(parent,text,x,w,color,gradient)
  local t=Instance.new("TextLabel"); t.Position=UDim2.fromOffset(x,32); t.Size=UDim2.fromOffset(w,22); t.BackgroundColor3=Color3.fromRGB(20,27,39):Lerp(color,0.28); t.BorderSizePixel=0; t.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); t.TextSize=11; t.TextColor3=Color3.fromRGB(246,249,255); t.Text=tostring(text); t.TextTruncate=Enum.TextTruncate.AtEnd; t.Parent=parent; Instance.new("UICorner",t).CornerRadius=UDim.new(0,7)
  local st=Instance.new("UIStroke"); st.Color=color; st.Transparency=0.18; st.Thickness=1; st.Parent=t
  if gradient and gradient:IsA("UIGradient") then local bar=Instance.new("Frame"); bar.Position=UDim2.fromOffset(0,0); bar.Size=UDim2.fromOffset(4,22); bar.BackgroundColor3=Color3.new(1,1,1); bar.BorderSizePixel=0; bar.Parent=t; Instance.new("UICorner",bar).CornerRadius=UDim.new(0,7); local gg=gradient:Clone(); gg.Parent=bar end
  return t
 end
 local function refreshSources()
  for _,x in ipairs(sourceScroll:GetChildren()) do if x~=sourceLayout then x:Destroy() end end
  local q=string.lower(search.Text or "")
  for _,u in ipairs(inv()) do
   local ok=eligible(u); local m=metaFor(u.Name); local rarity=tostring(m and m.Rarity or "?"); local mut=tostring(u.Mutation or "None"); local hay=string.lower(tostring(u.Name).." "..rarity.." "..mut)
   if ok and (q=="" or string.find(hay,q,1,true)) then
    local sel=uid(u)==tostring(C.selectedSourceUUID or ""); local tc=tierColor(rarity); local mc,mg=U.cloneMutationColor(mut)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-6,0,60); b.BackgroundColor3=sel and Color3.fromRGB(25,34,49):Lerp(tc,0.24) or Color3.fromRGB(23,29,42); b.BorderSizePixel=0; b.AutoButtonColor=false; b.Text=""; b.Parent=sourceScroll; Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
    local nm=Instance.new("TextLabel"); nm.Position=UDim2.fromOffset(12,5); nm.Size=UDim2.new(1,-24,0,23); nm.BackgroundTransparency=1; nm.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Bold,Enum.FontStyle.Normal); nm.TextSize=14; nm.TextXAlignment=Enum.TextXAlignment.Left; nm.TextColor3=sel and Color3.fromRGB(255,255,255) or Color3.fromRGB(232,239,250); nm.Text=(sel and "âœ“  " or "")..tostring(u.Name); nm.TextTruncate=Enum.TextTruncate.AtEnd; nm.Parent=b
    U.makeCloneTag(b,rarity,12,90,tc,nil); U.makeCloneTag(b,mut,108,118,mc,mg); U.makeCloneTag(b,"Lv."..tostring(u.Level or 1),232,82,U.cloneLevelColor,nil)
    local st=Instance.new("UIStroke"); st.Color=tc; st.Transparency=sel and 0.04 or 0.70; st.Thickness=sel and 1.9 or 1; st.Parent=b
    b.Activated:Connect(function() C.selectedSourceUUID=uid(u); C.selectedRuleId=nil; draftReplace=true; draftMode="exact"; maxBox.Text="2"; delayBox.Text="2"; refreshSources(); refreshEditor() end)
   end
  end
 end
 local function refreshRules()
  for _,x in ipairs(ruleScroll:GetChildren()) do if x~=ruleLayout then x:Destroy() end end
  for _,r in ipairs(C.rules) do
   local cnt=countRule(r); r.currentCount=cnt; local goal=math.max(1,tonumber(r.maxCount) or 1); local ratio=math.clamp(cnt/goal,0,1)
   local row=Instance.new("Frame"); row.Size=UDim2.new(1,-6,0,60); row.BackgroundColor3=C.selectedRuleId==r.id and Color3.fromRGB(35,47,70) or Color3.fromRGB(22,28,41); row.BorderSizePixel=0; row.Parent=ruleScroll; Instance.new("UICorner",row).CornerRadius=UDim.new(0,9)
   local rst=Instance.new("UIStroke"); rst.Color=r.enabled~=false and Color3.fromRGB(65,117,112) or Color3.fromRGB(62,69,84); rst.Transparency=C.selectedRuleId==r.id and 0.18 or 0.58; rst.Parent=row
   local txt=Instance.new("TextLabel"); txt.BackgroundTransparency=1; txt.Position=UDim2.fromOffset(9,5); txt.Size=UDim2.fromOffset(218,38); txt.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); txt.TextSize=12; txt.TextWrapped=true; txt.TextXAlignment=Enum.TextXAlignment.Left; txt.TextYAlignment=Enum.TextYAlignment.Top; txt.TextColor3=Color3.fromRGB(225,234,248); txt.Text="#"..r.id.."  "..r.name.."    "..cnt.."/"..r.maxCount.."\n"..(r.matchMode=="exact" and "ตรงทุกค่า" or "ชื่อเดียวกัน").." • "..tostring(r.delay).." วิ • "..(r.autoReplace and "เติมกลับ" or "ครั้งเดียว"); txt.Parent=row
   local barBg=Instance.new("Frame"); barBg.Position=UDim2.fromOffset(9,49); barBg.Size=UDim2.fromOffset(218,4); barBg.BackgroundColor3=Color3.fromRGB(43,50,65); barBg.BorderSizePixel=0; barBg.Parent=row; Instance.new("UICorner",barBg).CornerRadius=UDim.new(1,0)
   local bar=Instance.new("Frame"); bar.Size=UDim2.new(ratio,0,1,0); bar.BackgroundColor3=ratio>=1 and Color3.fromRGB(81,194,139) or Color3.fromRGB(86,130,224); bar.BorderSizePixel=0; bar.Parent=barBg; Instance.new("UICorner",bar).CornerRadius=UDim.new(1,0)
   local tog=rowBtn(row,r.enabled~=false and "เปิด" or "พัก",234,48,r.enabled~=false and Color3.fromRGB(42,121,85) or Color3.fromRGB(66,72,86))
   local edit=rowBtn(row,"แก้",286,36,Color3.fromRGB(52,68,100)); edit.TextSize=11
   local del=rowBtn(row,"×",326,28,Color3.fromRGB(88,47,57)); del.TextSize=16
   tog.Activated:Connect(function() r.enabled=not (r.enabled~=false); RT.saveCloneConfig(); refreshRules() end)
   edit.Activated:Connect(function() C.selectedRuleId=r.id; C.selectedSourceUUID=r.sourceUUID; draftReplace=r.autoReplace==true; draftMode=r.matchMode or "exact"; maxBox.Text=tostring(r.maxCount); delayBox.Text=tostring(r.delay); refreshSources(); refreshEditor(); refreshRules() end)
   del.Activated:Connect(function() removeRule(r.id); refreshRules(); refreshEditor() end)
  end
 end
 RT.refreshCloneUI=function()
  local a=activeClone(); local msg
  if a then local left=AnimeState.GetCloneLeft(a); msg="กำลังโคลน "..tostring(a.Name).." • เหลือ "..fmt(left)
  elseif C.enabled then local r,src,why=planNext(); msg=r and ("คิวถัดไป #"..r.id.." "..src.Name.." • "..countRule(r).."/"..r.maxCount) or tostring(why)
  else msg=#C.rules>0 and ("พร้อม • มีกฎ "..#C.rules.." กฎ • กดเริ่มเพื่อทำงาน") or "ยังไม่มีกฎ • เลือกยูนิตแล้วบันทึกกฎก่อน" end
  C.status=msg
  master.Text=C.enabled and "■  หยุด AUTO CLONE" or "▶  เริ่ม AUTO CLONE"
  master.BackgroundColor3=C.enabled and Color3.fromRGB(40,134,96) or Color3.fromRGB(48,62,94)
  stateDot.BackgroundColor3=a and Color3.fromRGB(246,180,71) or (C.enabled and Color3.fromRGB(71,211,143) or Color3.fromRGB(123,137,161))
  status.Text="      "..msg
  refreshEditor()
 end
 keep(master.Activated:Connect(function() C.enabled=not C.enabled; C.busy=false; C.nextActionAt=os.clock(); C.claimedUUID=nil; log("AUTO_CLONE_MASTER="..tostring(C.enabled)); RT.refreshCloneUI() end))
 keep(search:GetPropertyChangedSignal("Text"):Connect(function() refreshSources() end))
 keep(modeBtn.Activated:Connect(function() draftMode=draftMode=="exact" and "name" or "exact"; refreshEditor() end))
 keep(replaceBtn.Activated:Connect(function() draftReplace=not draftReplace; refreshEditor() end))
 keep(saveBtn.Activated:Connect(function()
  local u=selectedUnit(); if not u then C.lastResult="เลือกต้นแบบก่อน"; RT.refreshCloneUI(); return end
  local m=metaFor(u.Name); local max=math.clamp(math.floor(tonumber(maxBox.Text) or 2),1,999); local delay=math.clamp(tonumber(delayBox.Text) or 2,0,3600)
  local r=C.selectedRuleId and ruleById(C.selectedRuleId) or nil
  if not r then C.ruleSeq+=1; r={id=C.ruleSeq}; C.rules[#C.rules+1]=r end
  r.enabled=true; r.sourceUUID=uid(u); r.sourceSig=sig(u); r.name=tostring(u.Name); r.rarity=tostring(m and m.Rarity or ""); r.level=tonumber(u.Level) or 1; r.mutation=tostring(u.Mutation or "None"); r.trait=tostring(u.Trait or ""); r.maxCount=max; r.delay=delay; r.autoReplace=draftReplace; r.matchMode=draftMode; r.reachedOnce=false
  C.selectedRuleId=r.id; RT.saveCloneConfig(); log("CLONE_RULE_SAVE | id="..r.id.." | name="..r.name.." | max="..max.." | delay="..delay.." | replace="..tostring(r.autoReplace)); RT.refreshCloneUI()
 end))
 keep(nowBtn.Activated:Connect(function() local r=C.selectedRuleId and ruleById(C.selectedRuleId) or nil; local u=selectedUnit(); if not r and u then r={id=0,name=u.Name,sourceUUID=uid(u),sourceSig=sig(u),maxCount=999,delay=0,autoReplace=true,matchMode="exact"} end; if not u and r then u=sourceFor(r) end; if r and u then fireStart(r,u,"manual_button") else C.lastResult="เลือกต้นแบบหรือกฎก่อน" end; RT.refreshCloneUI() end))
 keep(AnimeState.CloningChanged:Connect(function() if RT.refreshCloneUI then RT.refreshCloneUI() end end))
 keep(AnimeState.InventoryChanged:Connect(function() refreshRules(); if RT.refreshCloneUI then RT.refreshCloneUI() end end))
 keep(AnimeState.InventoryInserted:Connect(function() refreshRules(); if RT.refreshCloneUI then RT.refreshCloneUI() end end))
 task.spawn(function()
  while RT.alive do
   task.wait(0.5)
   if C.enabled then
    local a=activeClone()
    if a then
     local id=uid(a); local left=tonumber(AnimeState.GetCloneLeft(a)) or 0
     if left<=0 and C.claimedUUID~=id and not C.busy then
      C.claimedUUID=id; C.busy=true; local rid=C.activeRuleId; local rr=rid and ruleById(rid) or nil
      local ok,err=pcall(function() Request:FireServer("Claim",{UUID=id,CharacterId=id}) end); log("AUTO_CLONE_CLAIM | id="..id.." | rule="..tostring(rid).." | ok="..tostring(ok).." | err="..tostring(err)); C.lastResult=ok and ("Claim "..tostring(a.Name)) or tostring(err); C.nextActionAt=os.clock()+math.max(0,tonumber(rr and rr.delay) or 1)
      task.delay(1,function() if RT.alive then C.busy=false end end)
     end
    else
     C.claimedUUID=nil; C.activeRuleId=nil
     if not C.busy and os.clock()>=tonumber(C.nextActionAt or 0) then local r,src,why=planNext(); if r and src then fireStart(r,src,"auto_queue") else C.lastResult=tostring(why) end end
    end
   end
   if RT.currentTab=="CLONE" and not RT.minimized and RT.refreshCloneUI then RT.refreshCloneUI() end
  end
 end)
 refreshSources(); refreshEditor(); refreshRules(); RT.refreshCloneUI()
end
RT.setupAutoClone()
local configTitle=Instance.new("TextLabel"); configTitle.BackgroundTransparency=1; configTitle.Position=UDim2.fromOffset(210,88); configTitle.Size=UDim2.fromOffset(740,28); configTitle.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal); configTitle.TextSize=19; configTitle.TextColor3=Color3.fromRGB(224,232,248); configTitle.TextXAlignment=Enum.TextXAlignment.Left; configTitle.Text="ตั้งค่า / ระบบ"; configTitle.Parent=frame
local configInfo=Instance.new("TextLabel"); configInfo.BackgroundColor3=Color3.fromRGB(24,28,38); configInfo.BorderSizePixel=0; configInfo.Position=UDim2.fromOffset(210,194); configInfo.Size=UDim2.fromOffset(740,396); configInfo.FontFace=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal); configInfo.TextSize=16; configInfo.TextColor3=Color3.fromRGB(200,214,238); configInfo.TextXAlignment=Enum.TextXAlignment.Left; configInfo.TextYAlignment=Enum.TextYAlignment.Top; configInfo.TextWrapped=true; configInfo.RichText=true; configInfo.Text="<font size='22'><b>อาซ้อฟ่างKGHUB v6.7 • EVENT POTION</b></font>\nCONFIG FILE: NBTHUB_CONFIG.json\nRULES FILE: NBTHUB_BUY_RULES.json\nTRADER CATALOG: NBTHUB_TRADER_CATALOG.json\nDATABASE: 77 roll characters + lazy portraits + lazy skill modules\n\n<b>UI:</b> Sidebar navigation • dashboard cards • viewport scaling • safe drag • hover feedback • auto scrolling\n<b>LOAD CONFIG:</b> restores rules, trader targets, BUY ALL, UI position, minimized state and last tab.\n<b>Safety:</b> Auto Roll / Auto Buy / Auto Trader always load OFF. Event Potion restores its saved setting and fires only once per matching Mutation Time.\n\n<b>Hotkeys:</b> F5 Trader | F6 Roll | F7 Auto Buy | F8 Remove"; configInfo.Parent=frame; stylePanel(configInfo)
local rollGroup={rollBtn,buyBtn,leftTitle,rightTitle,search,charTierBtn,clearCharBtn,charPanel,mutScroll}
local rulesGroup={rulesTitle,addCharRuleBtn,addRarityRuleBtn,clearBuilderBtn,deleteRulesBtn,ruleScroll}
for _,b in pairs(rarityButtons) do rulesGroup[#rulesGroup+1]=b end
local traderGroup={traderTitle,traderScroll,RT.traderUI.search,RT.traderUI.onlySelected,RT.traderUI.sort}
local infoGroup={infoTitle,infoSearch,infoTierBtn,infoSkillFilterBtn,infoCount,infoList,infoDetail}
local eventGroup={RT.eventUI.title,RT.eventUI.status,RT.eventUI.master,RT.eventUI.eventHeader,RT.eventUI.grid,RT.eventUI.potionHeader,RT.eventUI["Luck Potion"].card,RT.eventUI["Super Luck Potion"].card}
local configGroup={configTitle,configInfo,saveConfigBtn,loadConfigBtn,removeBtn}
local tabGroups={ROLL=rollGroup,RULES=rulesGroup,TRADER=traderGroup,INFO=infoGroup,EVENT=eventGroup,CLONE=RT.cloneUI.group or {},CONFIG=configGroup}
refreshTabs=function()
 local active=tostring(RT.currentTab or "ROLL")
 if not tabGroups[active] then active="ROLL"; RT.currentTab=active end
 for key,group in pairs(tabGroups) do
  local show=(key==active) and not minimized
  for _,obj in ipairs(group) do if obj and obj.Parent then obj.Visible=show end end
 end
 for key,b in pairs(tabButtons) do
  b.Visible=not minimized
  b.BackgroundColor3=(key==active) and Color3.fromRGB(55,78,176) or Color3.fromRGB(17,22,33)
  b.TextColor3=(key==active) and Color3.fromRGB(255,255,255) or Color3.fromRGB(190,202,228)
 end
 local traderPanel=frame:FindFirstChild("TraderSummaryPanel"); if traderPanel then traderPanel.Visible=(active=="TRADER") and not minimized end
 if active=="ROLL" and not minimized then refreshCharButtons() else clearCharCards() end
 if active=="INFO" and not minimized then if infoSelected then selectInfoCharacter(infoSelected) end; refreshInfoList() else clearPortrait(infoPortrait) end
 if active=="EVENT" and not minimized and RT.refreshEventUI then RT.refreshEventUI() end
 if active=="CLONE" and not minimized and RT.refreshCloneUI then RT.refreshCloneUI() end
 status.Visible=not minimized
end
refreshTabs()
refresh=function(msg)
 local enabledRules=0; for _,r in ipairs(RT.rules) do if r.enabled~=false then enabledRules+=1 end end
 status.Text=(msg or "พร้อม").." | สุ่ม "..(RT.autoRoll and "เปิด" or "ปิด").." | ซื้อ "..(RT.autoBuy and "เปิด" or "ปิด").." | กฎ "..enabledRules.."/"..#RT.rules.." | ซื้อสำเร็จ "..RT.bought.." | ร้านค้า "..RT.traderBought
 rollBtn.Text=RT.autoRoll and "สุ่มอัตโนมัติ: เปิด (F6)" or "สุ่มอัตโนมัติ: ปิด (F6)"
 if RT.autoBuy and enabledRules==0 then buyBtn.Text="ซื้ออัตโนมัติ: เปิด • ต้องเพิ่มกฎ" else buyBtn.Text=RT.autoBuy and "ซื้ออัตโนมัติ: เปิด (F7)" or "ซื้ออัตโนมัติ: ปิด (F7)" end
 traderBtn.Text=RT.traderAuto and "ระบบซื้อร้านค้า: เปิด (F5)" or "ระบบซื้อร้านค้า: ปิด (F5)"
 traderAllBtn.Text=RT.traderBuyAll and "โหมดซื้อทั้งหมด: เปิด" or "โหมดซื้อทั้งหมด: ปิด"
 rollBtn.BackgroundColor3=RT.autoRoll and Color3.fromRGB(31,139,102) or Color3.fromRGB(28,35,52)
 if RT.autoBuy and enabledRules==0 then buyBtn.BackgroundColor3=Color3.fromRGB(180,108,42) else buyBtn.BackgroundColor3=RT.autoBuy and Color3.fromRGB(31,139,102) or Color3.fromRGB(28,35,52) end
 traderBtn.BackgroundColor3=RT.traderAuto and Color3.fromRGB(36,128,98) or Color3.fromRGB(27,34,49)
 traderAllBtn.BackgroundColor3=RT.traderBuyAll and Color3.fromRGB(154,96,40) or Color3.fromRGB(27,34,49)
 updateHeaderTitle()
 writeLatest(msg or "refresh")
end
local function applyConfigToUI(message)
 RT.autoRoll=false; RT.autoBuy=false; RT.traderAuto=false; RT.busy=false; RT.rollBuyHold=false; RT.rollBuyBatch=nil; if RT.clone then RT.clone.enabled=false; RT.clone.busy=false end
 frame.Position=UDim2.fromOffset(RT.uiX or 20,RT.uiY or 30)
 refreshCharButtons(); refreshMutButtons(); refreshRarityButtons(); refreshRulesUI(); refreshTraderButtons(); refreshInfoList(); if infoSelected then selectInfoCharacter(infoSelected) end; if RT.refreshEventUI then RT.refreshEventUI() end; if RT.refreshCloneUI then RT.refreshCloneUI() end
 setMinimized(RT.minimized==true,true)
 refresh(message or "Config loaded - automation kept OFF")
 if RT.handleMutationEvent then task.defer(function() RT.handleMutationEvent("config_loaded") end) end
end
keep(saveConfigBtn.MouseButton1Click:Connect(function()
 local ok=saveConfig(); if RT.saveCloneConfig then RT.saveCloneConfig() end; refresh(ok and "CONFIG SAVED" or "CONFIG SAVE FAILED")
end))
keep(loadConfigBtn.MouseButton1Click:Connect(function()
 local ok=loadConfigData(); if RT.loadCloneConfig then RT.loadCloneConfig() end; if ok then applyConfigToUI("CONFIG LOADED - toggles OFF") else refresh("NO CONFIG FOUND") end
end))
local function startRuntime()
RT.usePotionExact=function(name,requested,eventName)
 local wanted=math.clamp(math.floor(tonumber(requested) or 0),0,100); local owned=RT.getItemAmount(name); local amount=math.min(wanted,owned)
 if amount<=0 then log("EVENT_POTION_SKIP | event="..tostring(eventName).." | item="..name.." | wanted="..wanted.." | owned="..owned); return 0,"ไม่มีของ" end
 local left=amount; local sent=0
 while left>=5 and RT.alive do local ok,err=pcall(function() RT.itemUseRemote:FireServer(name,5) end); if not ok then log("EVENT_POTION_ERROR | item="..name.." | chunk=5 | "..tostring(err)); break end; sent+=5; left-=5; task.wait(0.12) end
 while left>0 and RT.alive do local ok,err=pcall(function() RT.itemUseRemote:FireServer(name,1) end); if not ok then log("EVENT_POTION_ERROR | item="..name.." | chunk=1 | "..tostring(err)); break end; sent+=1; left-=1; task.wait(0.09) end
 log("EVENT_POTION_REQUEST | event="..tostring(eventName).." | item="..name.." | wanted="..wanted.." | owned="..owned.." | sent="..sent); return sent,(sent< wanted and "ของไม่พอ/ส่งได้บางส่วน" or "ส่งครบ")
end
RT.handleMutationEvent=function(source)
 local raw=WS:GetAttribute("MutationEvent"); local current=(raw==nil or tostring(raw)=="") and nil or tostring(raw)
 if not current then RT.eventPotion.lastHandled=nil; if RT.refreshEventUI then RT.refreshEventUI() end; return end
 local ep=RT.eventPotion; if not ep.enabled or not ep.events[current] or ep.lastHandled==current then if RT.refreshEventUI then RT.refreshEventUI() end; return end
 local planned=false; for _,name in ipairs({"Luck Potion","Super Luck Potion"}) do local p=ep.potions[name]; if p.enabled and (tonumber(p.amount) or 0)>0 then planned=true end end
 if not planned then ep.lastResult="พบ "..current.." แต่ยังไม่ได้ติ๊กน้ำยา"; if RT.refreshEventUI then RT.refreshEventUI() end; return end
 ep.lastHandled=current; ep.lastResult="พบ "..current.." • กำลังส่งคำสั่งใช้ยา"; log("EVENT_POTION_TRIGGER | event="..current.." | source="..tostring(source)); if RT.refreshEventUI then RT.refreshEventUI() end
 task.spawn(function()
  local out={}; for _,name in ipairs({"Luck Potion","Super Luck Potion"}) do local p=ep.potions[name]; if p.enabled and (tonumber(p.amount) or 0)>0 then local n,note=RT.usePotionExact(name,p.amount,current); out[#out+1]=name.." x"..n.." ("..note..")" end end
  ep.lastResult=current.." • "..table.concat(out," • "); task.wait(0.35); if RT.refreshEventUI then RT.refreshEventUI() end; writeLatest("event_potion:"..current)
 end)
end
keep(WS:GetAttributeChangedSignal("MutationEvent"):Connect(function() RT.handleMutationEvent("MutationEvent_changed") end))
keep(LP:GetAttributeChangedSignal("Mutation2x"):Connect(function() if RT.refreshEventUI then RT.refreshEventUI() end end))
task.defer(function() if RT.alive then RT.handleMutationEvent("startup") end end)
local function ruleMatches(r,v)
 if not r or r.enabled==false or not v then return false end
 if r.type=="character" then
  if not (r.characters and r.characters[tostring(v.Name)]) then return false end
 elseif r.type=="rarity" then
  if tostring(v.Rarity or "")~=tostring(r.rarity or "") then return false end
 else return false end
 local muts=r.mutations or {}
 if next(muts) then
  local mut=itemMutation(v)
  if not muts.ANY and not muts[mut] then return false end
 end
 return true
end
local function shouldBuy(v)
 if not v then return false,"no_item" end
 if #RT.rules==0 then return false,"no_rules" end
 for _,r in ipairs(RT.rules) do
  if ruleMatches(r,v) then return true,"rule#"..tostring(r.id),r end
 end
 return false,"no_rule_match"
end
local function fmt(v)
 if not v then return "?" end
 return tostring(v.DisplayName or v.Name or "?").."["..tostring(v.Rarity or "?")..","..itemMutation(v).."]"
end
local function promptPos(p)
 local x=p and p.Parent
 if x and x:IsA("BasePart") then return x.Position end
 if x and x:IsA("Attachment") then return x.WorldPosition end
end
local function findPrompt()
 if RT.target and RT.target.Parent then return RT.target end
 local plots=WS:FindFirstChild("Plots"); if not plots then return nil end
 for _,plot in ipairs(plots:GetChildren()) do
  local owner=plot:GetAttribute("Owner")
  local uid=tonumber(plot:GetAttribute("UserId") or plot:GetAttribute("OwnerUserId"))
  if owner==LP.Name or uid==LP.UserId then
   local p=plot:FindFirstChild("RollPrompt",true)
   if p and p:IsA("ProximityPrompt") then RT.target=p; return p end
  end
 end
 return nil
end
local function inRange(p)
 if not p or not p.Parent or not p.Enabled then return false end
 local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
 local pos=promptPos(p); if not hrp or not pos then return false end
 return (hrp.Position-pos).Magnitude<=((tonumber(p.MaxActivationDistance) or 10)+1.5)
end
local function traderFindItem(stock,name)
 if type(stock)~="table" or type(stock.Items)~="table" then return nil end
 for _,item in ipairs(stock.Items) do
  if type(item)=="table" and tostring(item.Name)==tostring(name) then return item end
 end
 return nil
end
local function traderSignature(stock)
 if type(stock)~="table" then return "nil" end
 local out={"event="..tostring(stock.EventId or 0),"ends="..tostring(stock.EventEndsAt or 0)}
 for _,item in ipairs(stock.Items or {}) do
  if type(item)=="table" then out[#out+1]=tostring(item.Name)..":"..tostring(item.Stock or 0) end
 end
 return table.concat(out,"|")
end
local tryTraderBuy
local releaseRollBuy
local function traderRetryKey(name)
 return tostring(RT.traderEventId).."|"..tostring(name)
end
local function traderResetEventState()
 RT.traderBlocked={}; RT.traderRetry={}; RT.traderPending=nil; RT.traderBusy=false; RT.traderNextBuyAt=0
end
local function processTraderStock(stock,source)
 if type(stock)~="table" then return end
 RT.traderStock=stock
 local eventId=tonumber(stock.EventId) or 0
 if eventId~=RT.traderEventId then
  RT.traderEventId=eventId; traderResetEventState()
  log("TRADER_EVENT | eventId="..eventId.." | endsAt="..tostring(stock.EventEndsAt or 0))
 end
 for _,item in ipairs(stock.Items or {}) do addTraderKnown(item,source) end
 local sig=traderSignature(stock)
 local stockChanged=sig~=RT.traderStockSig
 if stockChanged then RT.traderStockSig=sig; log("TRADER_STOCK | source="..tostring(source).." | "..sig) end
 local pending=RT.traderPending
 if pending then
  local item=traderFindItem(stock,pending.name)
  local nowStock=tonumber(item and item.Stock) or 0
  if nowStock<pending.before then
   local key=traderRetryKey(pending.name); RT.traderRetry[key]=0
   log("TRADER_STOCK_DECREASE | item="..pending.name.." | before="..pending.before.." | after="..nowStock.." | attempt="..tostring(pending.attempt).." | note=not_account_confirmation")
   RT.traderPending=nil; RT.traderBusy=false; RT.traderNextBuyAt=os.clock()+2.2
  end
 end
 refreshTraderButtons()
 if stockChanged or source=="buy_event" then refresh("Trader stock updated") end
 if RT.traderAuto and tryTraderBuy then task.defer(tryTraderBuy) end
end
local function requestTraderStock(source)
 if RT.traderRequesting then return end
 RT.traderRequesting=true
 local ok,stock=pcall(function() return TraderGetStock:InvokeServer() end)
 RT.traderRequesting=false
 if ok and type(stock)=="table" then processTraderStock(stock,source)
 else log("TRADER_GETSTOCK_ERROR | source="..tostring(source).." | "..tostring(stock)) end
end
tryTraderBuy=function()
 if not RT.alive or not RT.traderAuto or RT.traderBusy then return end
 RT.traderRetry=RT.traderRetry or {}; RT.traderBlocked=RT.traderBlocked or {}
 local now=os.clock(); if now<(RT.traderNextBuyAt or 0) then return end
 local stock=RT.traderStock
 if type(stock)~="table" then requestTraderStock("need_stock"); return end
 for _,item in ipairs(stock.Items or {}) do
  if type(item)=="table" then
   local name=tostring(item.Name or ""); local count=tonumber(item.Stock) or 0
   local key=traderRetryKey(name); local attempts=tonumber(RT.traderRetry[key]) or 0
   if name~="" and (RT.traderBuyAll or RT.traderTargets[name]) and count>0 and not RT.traderBlocked[name] and attempts<3 then
    attempts+=1; RT.traderRetry[key]=attempts; RT.traderBusy=true
    RT.traderPending={name=name,before=count,at=now,eventId=RT.traderEventId,attempt=attempts}
    RT.traderNextBuyAt=now+2.2
    log("TRADER_BUY_REQUEST | mode="..(RT.traderBuyAll and "ALL" or "SELECTED").." | item="..name.." | stock="..count.." | price="..tostring(item.Price or "?").." | attempt="..attempts.."/3")
    local ok,err=pcall(function() TraderBuy:FireServer(name) end)
    if not ok then
     RT.traderPending=nil; RT.traderBusy=false
     if attempts>=3 then RT.traderBlocked[name]=true; log("TRADER_GIVE_UP | item="..name.." | reason=fire_error | "..tostring(err))
     else log("TRADER_RETRY | item="..name.." | reason=fire_error | nextAttempt="..(attempts+1)) end
     return
    end
    task.delay(1.25,function()
     if not RT.alive then return end
     local pend=RT.traderPending
     if pend and pend.name==name and pend.eventId==RT.traderEventId and pend.attempt==attempts then
      requestTraderStock("verify_after_request")
      task.delay(0.30,function()
       local p2=RT.traderPending
       if not RT.alive or not p2 or p2.name~=name or p2.eventId~=RT.traderEventId or p2.attempt~=attempts then return end
       RT.traderPending=nil; RT.traderBusy=false
       if attempts>=3 then RT.traderBlocked[name]=true; log("TRADER_GIVE_UP | item="..name.." | reason=stock_unchanged | attempts="..attempts)
       else log("TRADER_RETRY | item="..name.." | reason=stock_unchanged | nextAttempt="..(attempts+1)) end
       RT.traderNextBuyAt=math.max(RT.traderNextBuyAt or 0,os.clock()+2.2)
       refresh("Trader waiting before retry")
      end)
     end
    end)
    return
   end
  end
 end
end
local function enabledRuleCount()
 local n=0; for _,r in ipairs(RT.rules) do if r.enabled~=false then n+=1 end end; return n
end
local function toggleAutoBuy(source)
 if RT.autoBuy then
  RT.autoBuy=false
  if RT.rollBuyHold and releaseRollBuy then releaseRollBuy(tostring(source).."_off") end
 else
  if enabledRuleCount()==0 then log("AUTO_BUY_REJECT | reason=no_enabled_rules | source="..tostring(source)); refresh("Add/enable a Buy Rule first"); return end
  RT.autoBuy=true
 end
 log("AUTO_BUY="..tostring(RT.autoBuy).." | source="..tostring(source).." | rules="..enabledRuleCount())
 refresh(tostring(source).." Auto Buy")
end
keep(rollBtn.MouseButton1Click:Connect(function()
 RT.autoRoll=not RT.autoRoll; RT.busy=false; log("AUTO_ROLL="..tostring(RT.autoRoll)); refresh("Auto Roll toggled")
end))
keep(buyBtn.MouseButton1Click:Connect(function() toggleAutoBuy("button") end))
keep(traderBtn.MouseButton1Click:Connect(function()
 RT.traderAuto=not RT.traderAuto; RT.traderBusy=false; RT.traderPending=nil
 if RT.traderAuto then RT.traderBlocked={}; RT.traderRetry={}; RT.traderNextBuyAt=0 end
 log("AUTO_TRADER="..tostring(RT.traderAuto).." | buyAll="..tostring(RT.traderBuyAll).." | targets="..listSelected(RT.traderTargets))
 refreshTraderButtons(); refresh("Auto Trader toggled")
 if RT.traderAuto then task.defer(function() requestTraderStock("toggle_on") end) end
end))
keep(traderAllBtn.MouseButton1Click:Connect(function()
 RT.traderBuyAll=not RT.traderBuyAll; RT.traderBlocked={}; RT.traderRetry={}; RT.traderNextBuyAt=0; RT.traderBusy=false; RT.traderPending=nil
 log("TRADER_BUY_ALL="..tostring(RT.traderBuyAll))
 saveConfig()
 refreshTraderButtons(); refresh("Trader BUY ALL toggled")
 if RT.traderAuto then task.defer(function() requestTraderStock("buy_all_toggle") end) end
end))
keep(removeBtn.MouseButton1Click:Connect(function() cleanup("button") end))
keep(TraderBuy.OnClientEvent:Connect(function(stock)
 if type(stock)=="table" then processTraderStock(stock,"buy_event") end
end))
for _,attr in ipairs({"TraderEventActive","TraderEventEndsAt","TraderEventId"}) do
 keep(WS:GetAttributeChangedSignal(attr):Connect(function()
  if RT.traderAuto then task.defer(function() requestTraderStock("attr:"..attr) end) end
 end))
end
releaseRollBuy=function(reason)
 local batch=RT.rollBuyBatch
 if batch then log("BUY_HOLD_RELEASE | rollId="..tostring(batch.rollId).." | reason="..tostring(reason)) end
 RT.rollBuyHold=false; RT.rollBuyBatch=nil; RT.busy=false
 refresh("Roll Buy "..tostring(reason or "released"))
end
keep(Buy.OnClientEvent:Connect(function(who,confirmedRollId,slot)
 if who~=LP then return end
 local batch=RT.rollBuyBatch; local slotKey=tonumber(slot) or slot
 if batch and tostring(batch.rollId)==tostring(confirmedRollId) and batch.pending[slotKey] then
  RT.bought+=1; RT.lastBuyResult="rollId="..tostring(confirmedRollId).." slot="..tostring(slotKey)
  batch.pending[slotKey]=nil
  log("BUY_CONFIRMED | rollId="..tostring(confirmedRollId).." | slot="..tostring(slotKey).." | confirmed="..RT.bought)
  local left=false; for _ in pairs(batch.pending) do left=true; break end
  if not left then task.delay(0.12,function() if RT.alive and RT.rollBuyBatch==batch then releaseRollBuy("confirmed") end end) end
  refresh("Buy confirmed")
 else
  log("BUY_CONFIRM_UNTRACKED | rollId="..tostring(confirmedRollId).." | slot="..tostring(slotKey))
 end
end))
keep(Roll.OnClientEvent:Connect(function(who,plot,rolled,a,rollId)
 if who~=LP then return end
 local resultNow=os.clock(); RT.busy=false; RT.lastRollResultAt=resultNow; RT.rolls+=1
 if resultNow-RT.lastTrigger<5 then RT.nextRollAt=math.max(RT.nextRollAt,RT.lastTrigger+delayNow()+0.10) else RT.nextRollAt=math.max(RT.nextRollAt,resultNow+delayNow()+0.10) end
 local names={}; for i=1,3 do names[#names+1]=fmt(rolled and rolled[i]) end
 log("ROLL_RESULT | rollId="..tostring(rollId).." | "..table.concat(names," | "))
 local matches={}
 if RT.autoBuy and rollId~=nil and type(rolled)=="table" then
  for i=1,3 do
   local item=rolled[i]; local buy,why=shouldBuy(item)
   if buy then matches[#matches+1]={slot=i,desc=fmt(item)}; log("BUY_MATCH_FOUND | rollId="..tostring(rollId).." | slot="..i.." | item="..fmt(item).." | reason="..why)
   else log("BUY_SKIP | slot="..i.." | item="..fmt(item).." | reason="..why) end
  end
 end
 if #matches>0 then
  local gateDelay=delayNow()+0.12; local pending={}; for _,m in ipairs(matches) do pending[m.slot]=true end
  local batch={rollId=rollId,pending=pending,matches=matches,created=os.clock(),gateDelay=gateDelay}
  RT.rollBuyBatch=batch; RT.rollBuyHold=true
  log("BUY_HOLD | rollId="..tostring(rollId).." | matches="..#matches.." | wait="..string.format("%.2f",gateDelay)); refresh("Target found - waiting buy window")
  task.delay(gateDelay,function()
   if not RT.alive or not RT.autoBuy or RT.rollBuyBatch~=batch then return end
   for idx,m in ipairs(matches) do
    task.delay((idx-1)*0.12,function()
     if not RT.alive or not RT.autoBuy or RT.rollBuyBatch~=batch or not batch.pending[m.slot] then return end
     local ok,err=pcall(function() Buy:FireServer(batch.rollId,m.slot) end)
     if ok then log("BUY_REQUEST | rollId="..tostring(batch.rollId).." | slot="..m.slot.." | item="..m.desc)
     else batch.pending[m.slot]=nil; log("BUY_ERROR | rollId="..tostring(batch.rollId).." | slot="..m.slot.." | "..tostring(err)) end
    end)
   end
   task.delay(2.30+(#matches-1)*0.12,function()
    if RT.alive and RT.rollBuyBatch==batch then
     local left={}; for pendingSlot in pairs(batch.pending) do left[#left+1]=tostring(pendingSlot) end; table.sort(left)
     log("BUY_TIMEOUT | rollId="..tostring(batch.rollId).." | pendingSlots="..table.concat(left,",")); releaseRollBuy("timeout")
    end
   end)
  end)
 else refresh(RT.autoBuy and "No selected target in roll" or "Roll received") end
end))
task.spawn(function()
 while RT.alive do
  if RT.autoRoll and not RT.rollBuyHold and type(fireproximityprompt)=="function" then
   local p=findPrompt()
   if p and inRange(p) then
    local now=os.clock()
    if RT.busy and now-RT.lastTrigger>delayNow()+1.15 then RT.busy=false; RT.nextRollAt=math.max(RT.nextRollAt,now+0.15); log("AUTO_ROLL_WATCHDOG | no_result_after="..string.format("%.2f",now-RT.lastTrigger)) end
    if not RT.busy and now>=RT.nextRollAt and now-RT.lastTrigger>=delayNow()+0.10 then
     RT.busy=true; RT.lastTrigger=now; RT.nextRollAt=now+delayNow()+0.10
     local ok,err=pcall(fireproximityprompt,p)
     if ok then log("AUTO_TRIGGER | path="..p:GetFullName().." | cadence="..string.format("%.2f",delayNow()+0.10))
     else RT.busy=false; RT.nextRollAt=now+0.35; log("AUTO_TRIGGER_ERROR | "..tostring(err)) end
    end
   end
  end
  task.wait(0.03)
 end
end)
task.spawn(function()
 while RT.alive do
  if RT.traderAuto then requestTraderStock("poll") end
  if tostring(RT.currentTab)=="EVENT" and RT.refreshEventUI then RT.refreshEventUI() end
  task.wait(1.0)
 end
end)
keep(UIS.InputBegan:Connect(function(i,gp)
 if gp then return end
 if i.KeyCode==Enum.KeyCode.F5 then
  RT.traderAuto=not RT.traderAuto; RT.traderBusy=false; RT.traderPending=nil
  log("AUTO_TRADER="..tostring(RT.traderAuto).." | targets="..listSelected(RT.traderTargets)); refresh("F5 Auto Trader")
  if RT.traderAuto then task.defer(function() requestTraderStock("F5_on") end) end
 elseif i.KeyCode==Enum.KeyCode.F6 then RT.autoRoll=not RT.autoRoll; RT.busy=false; log("AUTO_ROLL="..tostring(RT.autoRoll)); refresh("F6 Auto Roll")
 elseif i.KeyCode==Enum.KeyCode.F7 then toggleAutoBuy("F7")
 elseif i.KeyCode==Enum.KeyCode.F8 then cleanup("F8") end
end))
if type(writefile)=="function" then pcall(writefile,LOG,"อาซ้อฟ่างKGHUB ROLL+BUY SESSION\n") end
setMinimized(RT.minimized==true,true)
saveConfig()
RT.restoreTeleportResume=function()
 if type(readfile)~="function" then return false,"no_readfile" end
 local ok,text=pcall(readfile,"KGHUB_v683_resume.json")
 if not ok or type(text)~="string" or text=="" then return false,"no_resume" end
 if type(delfile)=="function" then pcall(delfile,"KGHUB_v683_resume.json") end
 local ok2,data=pcall(function() return HttpService:JSONDecode(text) end)
 if not ok2 or type(data)~="table" then log("TP_RESUME_INVALID | json"); return false,"bad_json" end
 local age=os.time()-(tonumber(data.savedAt) or 0)
 if tonumber(data.placeId)~=game.PlaceId or age<0 or age>300 then log("TP_RESUME_STALE | age="..tostring(age).." | place="..tostring(data.placeId)); return false,"stale" end
 RT.autoRoll=data.autoRoll==true; RT.busy=false; RT.nextRollAt=0
 local wantBuy=data.autoBuy==true
 RT.autoBuy=wantBuy and enabledRuleCount()>0 or false
 RT.traderAuto=data.traderAuto==true; RT.traderBusy=false; RT.traderPending=nil; if RT.clone then RT.clone.enabled=data.autoClone==true; RT.clone.busy=false; RT.clone.nextActionAt=os.clock() end
 local nowEvent=tostring(WS:GetAttribute("MutationEvent") or "")
 if nowEvent==tostring(data.eventCurrent or "") then RT.eventPotion.lastHandled=data.eventLastHandled; RT.eventPotion.lastResult=tostring(data.eventLastResult or RT.eventPotion.lastResult) end
 log("TP_RESUME_RESTORED | age="..tostring(age).." | roll="..tostring(RT.autoRoll).." | buy="..tostring(RT.autoBuy).." | trader="..tostring(RT.traderAuto).." | clone="..tostring(RT.clone and RT.clone.enabled).." | event="..nowEvent)
 if wantBuy and not RT.autoBuy then log("TP_RESUME_BUY_SKIPPED | reason=no_enabled_rules") end
 if RT.traderAuto then task.defer(function() requestTraderStock("teleport_resume") end) end
 if RT.refreshCloneUI then RT.refreshCloneUI() end
 refresh("Teleport resume | Roll "..(RT.autoRoll and "ON" or "OFF").." | Buy "..(RT.autoBuy and "ON" or "OFF").." | Trader "..(RT.traderAuto and "ON" or "OFF").." | Clone "..((RT.clone and RT.clone.enabled) and "ON" or "OFF"))
 return true,"restored"
end
local tpResumeOK,tpResumeNote=RT.restoreTeleportResume()
RT.rerunResumePending=ENV.__KGHUB_RERUN_RESUME; ENV.__KGHUB_RERUN_RESUME=nil
RT.restoreRerunResume=function(data)
 if type(data)~="table" then return false,"no_resume" end
 local age=os.time()-(tonumber(data.savedAt) or 0)
 if tonumber(data.placeId)~=game.PlaceId or age<0 or age>30 then log("RERUN_RESUME_STALE | age="..tostring(age).." | place="..tostring(data.placeId)); return false,"stale" end
 RT.autoRoll=data.autoRoll==true; RT.busy=false; RT.nextRollAt=0; RT.rollBuyHold=false; RT.rollBuyBatch=nil
 local wantBuy=data.autoBuy==true
 RT.autoBuy=wantBuy and enabledRuleCount()>0 or false
 RT.traderAuto=data.traderAuto==true; RT.traderBusy=false; RT.traderPending=nil; if RT.clone then RT.clone.enabled=data.autoClone==true; RT.clone.busy=false; RT.clone.nextActionAt=os.clock() end
 local nowEvent=tostring(WS:GetAttribute("MutationEvent") or "")
 if nowEvent==tostring(data.eventCurrent or "") then RT.eventPotion.lastHandled=data.eventLastHandled; RT.eventPotion.lastResult=tostring(data.eventLastResult or RT.eventPotion.lastResult) end
 log("RERUN_RESUME_RESTORED | age="..tostring(age).." | roll="..tostring(RT.autoRoll).." | buy="..tostring(RT.autoBuy).." | trader="..tostring(RT.traderAuto).." | clone="..tostring(RT.clone and RT.clone.enabled).." | event="..nowEvent)
 if wantBuy and not RT.autoBuy then log("RERUN_RESUME_BUY_SKIPPED | reason=no_enabled_rules") end
 if RT.traderAuto then task.defer(function() requestTraderStock("rerun_resume") end) end
 if RT.refreshCloneUI then RT.refreshCloneUI() end
 refresh("Rerun resume | Roll "..(RT.autoRoll and "ON" or "OFF").." | Buy "..(RT.autoBuy and "ON" or "OFF").." | Trader "..(RT.traderAuto and "ON" or "OFF").." | Clone "..((RT.clone and RT.clone.enabled) and "ON" or "OFF"))
 return true,"restored"
end
local rerunResumeOK=false
if not tpResumeOK and type(RT.rerunResumePending)=="table" then
 local okResume=RT.restoreRerunResume(RT.rerunResumePending)
 rerunResumeOK=okResume==true
end
RT.restoreAutoStateFallback=function()
 local data,readErr=RT.readAutoState()
 if type(data)~="table" then log("AUTOSTATE_SKIP | reason="..tostring(readErr)); return false,readErr end
 local age=os.time()-(tonumber(data.savedAt) or 0)
 local oldJob=tostring(data.jobId or ""); local newJob=tostring(game.JobId or "")
 if data.armed~=true then log("AUTOSTATE_SKIP | reason=disarmed"); return false,"disarmed" end
 if tonumber(data.placeId)~=game.PlaceId then log("AUTOSTATE_SKIP | reason=place_mismatch"); return false,"place_mismatch" end
 if age<0 or age>180 then log("AUTOSTATE_SKIP | reason=stale | age="..tostring(age)); return false,"stale" end
 if oldJob=="" or oldJob==newJob then log("AUTOSTATE_SKIP | reason=same_job"); return false,"same_job" end
 RT.autoRoll=data.autoRoll==true; RT.busy=false; RT.nextRollAt=0; RT.rollBuyHold=false; RT.rollBuyBatch=nil
 local wantBuy=data.autoBuy==true; RT.autoBuy=wantBuy and enabledRuleCount()>0 or false
 RT.traderAuto=data.traderAuto==true; RT.traderBusy=false; RT.traderPending=nil
 if RT.clone then RT.clone.enabled=data.autoClone==true; RT.clone.busy=false; RT.clone.nextActionAt=os.clock() end
 log("AUTOSTATE_RESTORED | age="..tostring(age).." | oldJob="..oldJob.." | newJob="..newJob.." | roll="..tostring(RT.autoRoll).." | buy="..tostring(RT.autoBuy).." | trader="..tostring(RT.traderAuto).." | clone="..tostring(RT.clone and RT.clone.enabled))
 if wantBuy and not RT.autoBuy then log("AUTOSTATE_BUY_SKIPPED | reason=no_enabled_rules") end
 if RT.traderAuto then task.defer(function() requestTraderStock("autostate_resume") end) end
 if RT.refreshCloneUI then RT.refreshCloneUI() end
 refresh("Server resume | Roll "..(RT.autoRoll and "ON" or "OFF").." | Buy "..(RT.autoBuy and "ON" or "OFF").." | Trader "..(RT.traderAuto and "ON" or "OFF").." | Clone "..((RT.clone and RT.clone.enabled) and "ON" or "OFF"))
 return true,"restored"
end
local autoStateFallbackOK=false
if not tpResumeOK and not rerunResumeOK then autoStateFallbackOK=select(1,RT.restoreAutoStateFallback()) end
RT.rerunResumePending=nil
RT.autoStateReady=true
if RT.writeAutoState then pcall(function() RT.writeAutoState("startup_final",true) end) end
task.spawn(function()
 while RT.alive do
  task.wait(1)
  if RT.alive and RT.writeAutoState then RT.writeAutoState("heartbeat",true) end
 end
end)
log("START | version=ui-v6.9.3-color-tags | pool="..#charCatalog.." | mutations="..#mutCatalog.." | rules="..#RT.rules.." | delay="..delayNow().." | config="..CONFIG_FILE.." | rulesFile="..RULES_FILE.." | traderCatalog="..TRADER_CATALOG)
refresh("Responsive UI + Event Potion | F5 Trader | F6 Roll | F7 Auto Buy")
print("[อาซ้อฟ่างKGHUB ui-v6.9.3-color-tags] loaded | pool="..#charCatalog.." mutations="..#mutCatalog.." log="..LOG)
end
startRuntime()
