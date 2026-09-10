-- KGHUB Public Router v8.0.5 • Auto Team intentionally excluded
local PERSIST=[==[
if not game:IsLoaded() then game.Loaded:Wait() end
local HUBS={[107653945083776]=true,[72769188242214]=true}
local RAIDS={[107431701292918]=true,[133207600268474]=true,[87737123573764]=true}
local MAIN="https://dpaste.com/A3YACEFEG.txt"
local AGENT="https://dpaste.com/4BF5VZ5G5.txt"
local UI="https://dpaste.com/4SW3EELVN.txt"
local urls
if HUBS[game.PlaceId] then urls={MAIN}
elseif RAIDS[game.PlaceId] then urls={AGENT,UI}
else return end
for _,url in ipairs(urls) do
 local ok,src=pcall(function() return game:HttpGet(url) end)
 if not ok or type(src)~="string" or #src<200 then warn("[KGHUB-PUBLIC] fetch failed",url,src); return end
 local fn,err=loadstring(src)
 if not fn then warn("[KGHUB-PUBLIC] compile failed",url,err); return end
 local ok2,err2=pcall(fn)
 if not ok2 then warn("[KGHUB-PUBLIC] run failed",url,err2); return end
 print("[KGHUB-PUBLIC-ROUTER]",game.PlaceId,url,true)
 task.wait(1.15)
end
]==]
if type(writefile)=="function" then pcall(writefile,"KGHUB_PUBLIC_ROUTER.lua",PERSIST) end
local fn,err=loadstring(PERSIST)
if not fn then error("[KGHUB-PUBLIC] router compile failed: "..tostring(err)) end
return fn()
