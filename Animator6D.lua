-- // Animator6D Pro (R6 Universal + Blending Final) //
-- Made by gObl00x + GPT-5
-- Features: smooth blending, universal rig detection, restore system, safe playback
-- Ya sorry, I don't think I'll die from writing this shit on a shitty phone for 90 years, thanks GPT

if getgenv().Animator6DLoadedPro then return end
getgenv().Animator6DLoadedPro = true

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hum = character:FindFirstChildOfClass("Humanoid")

local animCache, lastMotors = {}, {}

local R6Map = {
	["Head"] = "Neck",
	["Torso"] = "RootJoint",
	["Right Arm"] = "Right Shoulder",
	["Left Arm"] = "Left Shoulder",
	["Right Leg"] = "Right Hip",
	["Left Leg"] = "Left Hip"
}

-- ========== LOAD SYSTEM ==========
local function loadKeyframeSequence(idOrInstance)
	if typeof(idOrInstance) == "Instance" then
		if idOrInstance:IsA("KeyframeSequence") then return idOrInstance end
		for _,v in ipairs(idOrInstance:GetDescendants()) do
			if v:IsA("KeyframeSequence") then return v end
		end
		return nil
	end

	local idStr = tostring(idOrInstance)
	if animCache[idStr] then return animCache[idStr] end

	local obj
	local ok, result = pcall(function()
		return InsertService:LoadAsset(idStr)
	end)
	if ok and result then
		obj = result
	else
		local ok2, result2 = pcall(function()
			return game:GetObjects("rbxassetid://".. idStr)[1]
		end)
		if ok2 and result2 then
			obj = result2
		else
			warn("[Animator6D] ❌ Failed to load animation:", idStr)
			return nil
		end
	end

	local kfs
	for _,v in ipairs(obj:GetDescendants()) do
		if v:IsA("KeyframeSequence") then
			kfs = v
			break
		end
	end

	if not kfs then
		warn("[Animator6D] ⚠️ No KeyframeSequence found in asset:", idStr)
		return nil
	end

	animCache[idStr] = kfs
	return kfs
end

-- ========== PARSE KEYFRAMES ==========
local function ConvertToTable(kfs)
	assert(kfs and kfs:IsA("KeyframeSequence"), "Expected KeyframeSequence")
	local frames, seq = kfs:GetKeyframes(), {}
	for _, frame in ipairs(frames) do
		local entry = { Time = frame.Time, Data = {} }
		for _, pose in ipairs(frame:GetDescendants()) do
			if pose:IsA("Pose") and pose.Weight > 0 then
				entry.Data[pose.Name] = { CFrame = pose.CFrame }
			end
		end
		table.insert(seq, entry)
	end
	table.sort(seq, function(a,b) return a.Time < b.Time end)
	return seq, kfs.Loop
end

-- ========== RIG MOTOR MAP ==========
local function BuildMotorMap(rig)
	local map, lower = {}, {}
	for _,m in ipairs(rig:GetDescendants()) do
		if m:IsA("Motor6D") then
			map[m.Name] = m
			lower[string.lower(m.Name)] = m
		end
	end
	return map, lower
end

local function FindMotor(poseName, map, lower)
	local match = R6Map[poseName] or poseName
	return map[match] or lower[string.lower(match)]
end

local function LerpCFrame(cf1, cf2, t)
	return cf1:Lerp(cf2, t)
end

-- ========== ANIM PLAYER ==========
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, kfs)
	local self = setmetatable({}, AnimPlayer)
	self.rig = rig
	self.seq, self.looped = ConvertToTable(kfs)
	self.map, self.lower = BuildMotorMap(rig)
	self.time, self.playing = 0, false
	self.length = self.seq[#self.seq].Time
	self.speed = 1
	self.savedC0 = {}
	for _,m in pairs(self.map) do
		self.savedC0[m] = m.C0
	end
	return self
end

function AnimPlayer:Play(speed, loop)
	if self.playing then return end
	self.playing, self.speed = true, speed or 1
	self.looped = (loop == nil) and true or loop

	self.conn = RunService.Heartbeat:Connect(function(dt)
		if not self.playing then return end
		self.time += dt * self.speed

		if self.time > self.length then
			if self.looped then
				self.time -= self.length
			else
				self:Stop(true)
				return
			end
		end

		local prev, next = self.seq[1], self.seq[#self.seq]
		for i = 1, #self.seq - 1 do
			if self.seq[i].Time <= self.time and self.seq[i+1].Time >= self.time then
				prev, next = self.seq[i], self.seq[i+1]
				break
			end
		end

		local span = next.Time - prev.Time
		local alpha = (span > 0) and ((self.time - prev.Time) / span) or 0

		for joint, prevData in pairs(prev.Data) do
			local nextData = next.Data[joint] or prevData
			local motor = FindMotor(joint, self.map, self.lower)
			if motor then
				local cf = LerpCFrame(prevData.CFrame, nextData.CFrame, alpha)
				pcall(function()
					motor.C0 = self.savedC0[motor] * cf
				end)
			end
		end
	end)
end

function AnimPlayer:Stop(restore)
	self.playing = false
	if self.conn then self.conn:Disconnect() self.conn = nil end
	if restore then
		for motor, origC0 in pairs(self.savedC0) do
			pcall(function() motor.C0 = origC0 end)
		end
	else
		for _,m in pairs(self.map) do
			pcall(function() m.Transform = CFrame.new() end)
		end
	end
end

-- ========== DISABLE DEFAULT ANIMS ==========
local function disableDefaultAnimations(char)
	if not hum then return end
	for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
	local animScript = char:FindFirstChild("Animate")
	if animScript then animScript.Disabled = true end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then animator:Destroy() end
end

-- ========== UNIVERSAL INTERFACE ==========
getgenv().Animator6D = function(idOrInstance, speed, looped)
	local kfs = loadKeyframeSequence(idOrInstance)
	if not kfs then 
		warn("[Animator6D] ❌ Could not load animation for:", idOrInstance)
		return 
	end
	warn("[Animator6D] ✅ Loaded animation:", kfs.Name, #kfs:GetKeyframes(), "frames")
	disableDefaultAnimations(character)

	if getgenv().currentAnimator6D then
		pcall(function()
			getgenv().currentAnimator6D:Stop(true)
		end)
	end

	local anim = AnimPlayer.new(character, kfs)
	getgenv().currentAnimator6D = anim
	anim:Play(speed or 1, looped)
end

getgenv().Animator6DStop = function()
	if getgenv().currentAnimator6D then
		pcall(function() getgenv().currentAnimator6D:Stop(true) end)
		getgenv().currentAnimator6D = nil
	end
end

warn("[Animator6D Pro] ✅ Loaded successfully (Universal Final R6 Edition).")
game:GetService("StarterGui"):SetCore("SendNotification", {
    Title = "Animator6D Pro V3";
    Text = "Enjoy A6DPV3 API";
    Duration = 6;
})
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
