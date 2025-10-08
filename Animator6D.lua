-- // Animator6D Pro (R6 Universal) //
-- Made by gObl00x + GPT-5
-- Features: universal rig detection, restore system, safe playback
-- Ya sorry, I don't think I'll die from writing this shit on a shitty phone for 90 years, thanks GPT

if getgenv().Animator6DLoadedPro then return end
getgenv().Animator6DLoadedPro = true

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local is = newproxy(true)
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:WaitForChild("Humanoid")
local animCache = {}

local R6Map = {
	["Head"]="Neck",["Torso"]="RootJoint",
	["Right Arm"]="Right Shoulder",["Left Arm"]="Left Shoulder",
	["Right Leg"]="Right Hip",["Left Leg"]="Left Hip"
}

-- ========== LOAD SYSTEM ==========
local function loadKeyframeSequence(idOrInstance)
	if typeof(idOrInstance)=="Instance" then
		if idOrInstance:IsA("KeyframeSequence") then return idOrInstance end
		for _,v in ipairs(idOrInstance:GetDescendants()) do
			if v:IsA("KeyframeSequence") then return v end
		end
		return nil
	end
	local idStr=tostring(idOrInstance)
	if animCache[idStr] then return animCache[idStr] end
	local obj;local ok,result=pcall(function()return is:LoadLocalAsset(idStr)end)
	if ok and result then obj=result else
		local ok2,res2=pcall(function()return game:GetObjects("rbxassetid://"..idStr)[1]end)
		if ok2 and res2 then obj=res2 else return nil end
	end
	local kfs;for _,v in ipairs(obj:GetDescendants())do
		if v:IsA("KeyframeSequence")then kfs=v break end end
	if not kfs then return nil end
	animCache[idStr]=kfs return kfs
end

-- ========== PARSE KEYFRAMES ==========
local function ConvertToTable(kfs)
	local frames,seq=kfs:GetKeyframes(),{}
	for _,f in ipairs(frames)do
		local e={Time=f.Time,Data={}}
		for _,p in ipairs(f:GetDescendants())do
			if p:IsA("Pose")and p.Weight>0 then
				e.Data[p.Name]={CFrame=p.CFrame}
			end
		end
		table.insert(seq,e)
	end
	table.sort(seq,function(a,b)return a.Time<b.Time end)
	return seq,kfs.Loop
end

-- ========== RIG MOTOR MAP ==========
local function BuildMotorMap(rig)
	local map,lower={},{}
	for _,m in ipairs(rig:GetDescendants())do
		if m:IsA("Motor6D")then map[m.Name]=m lower[string.lower(m.Name)]=m end
	end
	return map,lower
end

local function FindMotor(poseName,map,lower)
	local match=R6Map[poseName]or poseName
	local motor=map[match]or lower[string.lower(match)]
	if not motor then
		for name,m in pairs(map)do
			if string.find(string.lower(name),string.lower(poseName),1,true)then motor=m break end
		end
	end
	return motor
end

-- ========== ANIM PLAYER ==========
local AnimPlayer={}AnimPlayer.__index=AnimPlayer

function AnimPlayer.new(rig,kfs)
	local self=setmetatable({},AnimPlayer)
	self.rig=rig self.seq,self.looped=ConvertToTable(kfs)
	self.map,self.lower=BuildMotorMap(rig)
	self.time,self.playing=0,false
	self.length=self.seq[#self.seq].Time
	self.speed=1 self.savedC0={}
	for _,m in pairs(self.map)do self.savedC0[m]=m.C0 end
	return self
end

function AnimPlayer:Play(speed,loop)
	if self.playing then return end
	self.playing=true self.speed=speed or 1
	self.looped=(loop==nil)and true or loop
	self.conn=RunService.Heartbeat:Connect(function(dt)
		if not self.playing then return end
		self.time+=dt*self.speed
		if self.time>self.length then
			if self.looped then self.time-=self.length else self:Stop(true)return end
		end
		local prev=self.seq[1]
		for i=1,#self.seq do if self.seq[i].Time<=self.time then prev=self.seq[i]else break end end
		local nextFrame
		for i=1,#self.seq do if self.seq[i].Time>self.time then nextFrame=self.seq[i]break end end
		if not nextFrame then nextFrame=self.seq[#self.seq]end
		local alpha=0 local delta=nextFrame.Time-prev.Time
		if delta>0 then alpha=(self.time-prev.Time)/delta end
		for joint,data in pairs(prev.Data)do
			local motor=FindMotor(joint,self.map,self.lower)
			if motor then
				local nextPose=nextFrame.Data[joint]
				local cf=data.CFrame
				if nextPose then cf=data.CFrame:Lerp(nextPose.CFrame,alpha)end
				pcall(function()motor.C0=self.savedC0[motor]*cf end)
			end
		end
	end)
end

function AnimPlayer:Stop(restore)
	self.playing=false
	if self.conn then self.conn:Disconnect()self.conn=nil end
	if restore then
		for m,c in pairs(self.savedC0)do pcall(function()m.C0=c end)end
	else
		for _,m in pairs(self.map)do pcall(function()m.Transform=CFrame.new()end)end
	end
end

-- ========== DISABLE DEFAULT ANIMS ==========
local function disableDefaultAnimations(char)
	if not hum then return end
	for _,t in ipairs(hum:GetPlayingAnimationTracks())do t:Stop(0)end
	local s=char:FindFirstChild("Animate")if s then s.Disabled=true end
	local a=hum:FindFirstChildOfClass("Animator")if a then a:Destroy()end
end

-- ========== UNIVERSAL INTERFACE ==========
getgenv().Animator6D=function(id,speed,looped)
	local kfs=loadKeyframeSequence(id)if not kfs then return end
	disableDefaultAnimations(character)
	if getgenv().currentAnimator6D then pcall(function()getgenv().currentAnimator6D:Stop(true)end)end
	local anim=AnimPlayer.new(character,kfs)getgenv().currentAnimator6D=anim
	anim:Play(speed or 1,looped)
end

getgenv().Animator6DStop=function()
	if getgenv().currentAnimator6D then
		pcall(function()getgenv().currentAnimator6D:Stop(true)end)
		getgenv().currentAnimator6D=nil
	end
end

game:GetService("StarterGui"):SetCore("SendNotification",{Title="Animator6D Pro",Text="loaded successfully👍",Duration=5.4})
--
--[[
(pls, If ur down here, read these instructions)
Instructions:
--
If u want to play the anim outside ts loadstring, then:
getgenv().Animator6D(1234567890, 1, true) -- idOrInstance, Speed, Looped? --
--
If u will be using an instance and not an ID, then:
local animInstance = game:GetObjects("rbxassetid://ID")[1]..Here the KeyframeSequence Path -- replace ID with the ID --
getgenv().Animator6D(animInstance, 1, true) -- or false if u want the anim to have a loop
--
If u want to stop the anim outside ts loadstring, then:
getgenv().Animator6DStop()
--]]
