-- // Animator6D Pro (R6 Universal + Blending Final) //
-- Made by gObl00x + GPT-5
-- Features: smooth transitions, universal rig support, safe CFrame restoring
-- Ya sorry, I don't think I'll die from writing this shit on a shitty phone for 90 years, thanks GPT

if getgenv().Animator6DLoadedPro then return end
getgenv().Animator6DLoadedPro = true

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local animCache = {}

------------------------------------------------------------
-- here u can get all the limbs
------------------------------------------------------------
local R6Map = {
	["Head"] = "Neck",
	["Torso"] = "RootJoint",
	["Right Arm"] = "Right Shoulder",
	["Left Arm"] = "Left Shoulder",
	["Right Leg"] = "Right Hip",
	["Left Leg"] = "Left Hip"
}

------------------------------------------------------------
-- load anim from id or instance
------------------------------------------------------------
local function loadKeyframeSequence(idOrInstance)
	if typeof(idOrInstance) == "Instance" then
		if idOrInstance:IsA("KeyframeSequence") then
			return idOrInstance
		end
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

------------------------------------------------------------
-- kfs to frame table
------------------------------------------------------------
local function ConvertToTable(kfs)
	assert(kfs and kfs:IsA("KeyframeSequence"), "Expected KeyframeSequence")
	local frames = kfs:GetKeyframes()
	local seq = {}
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

------------------------------------------------------------
-- create Motor6D map
------------------------------------------------------------
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

------------------------------------------------------------
-- Search Motor6D with the poseName
------------------------------------------------------------
local function FindMotor(poseName, map, lower)
	local match = R6Map[poseName] or poseName
	if map[match] then return map[match] end
	local low = string.lower(match)
	if lower[low] then return lower[low] end
	return nil
end

local function LerpCFrame(cf1, cf2, t)
	return cf1:Lerp(cf2, t)
end

------------------------------------------------------------
-- have control in the anim
------------------------------------------------------------
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, kfs)
	local self = setmetatable({}, AnimPlayer)
	self.rig = rig
	self.seq, self.looped = ConvertToTable(kfs)
	self.map, self.lower = BuildMotorMap(rig)
	self.time = 0
	self.playing = false
	self.length = self.seq[#self.seq].Time
	self.speed = 1
	self.motorsC0 = {}
	for _,m in pairs(self.map) do
		self.motorsC0[m] = m.C0
	end
	return self
end

------------------------------------------------------------
-- PLAY 
------------------------------------------------------------
function AnimPlayer:Play(speed, loop)
	if self.playing then return end
	self.playing = true
	self.speed = speed or 1
	self.looped = (loop == nil) and true or loop

	self.conn = RunService.Heartbeat:Connect(function(dt)
		if not self.playing then return end
		self.time += dt * self.speed

		if self.time > self.length then
			if self.looped then
				self.time -= self.length
			else
				self:Stop()
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
					motor.C0 = self.motorsC0[motor] * cf
				end)
			end
		end
	end)
end

------------------------------------------------------------
-- STOP and resets the body to normal
------------------------------------------------------------
function AnimPlayer:Stop()
	self.playing = false
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	for _,m in pairs(self.map) do
		pcall(function()
			m.C0 = self.motorsC0[m]
			m.Transform = CFrame.new()
		end)
	end
end

------------------------------------------------------------
-- Disable roblox anims while is the kfs
------------------------------------------------------------
local function disableDefaultAnimations(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
	local animateScript = char:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = true
	end
end

------------------------------------------------------------
-- API Global
------------------------------------------------------------
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
			getgenv().currentAnimator6D:Stop()
		end)
	end

	local anim = AnimPlayer.new(character, kfs)
	getgenv().currentAnimator6D = anim
	anim:Play(speed or 1, looped)
end

getgenv().Animator6DStop = function()
	if getgenv().currentAnimator6D then
		pcall(function()
			getgenv().currentAnimator6D:Stop()
		end)
		getgenv().currentAnimator6D = nil
	end

	--  reset anim
	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = false
	end
end

warn("[Animator6D Pro] ✅ Loaded successfully (Universal + Stable Blend Edition)")

--[[
Instructions (please, if ur down here, look at ts)
If u want to play the anim outside ts loadstring, then:
getgenv().Animator6D(1234567890, 1, true) -- idOrInstance, Speed, Looped? --

If u don't put an id, and u want it to be an instance, then:
local anim = game:GetObjects("rbxassetid://ID")[1].. -- replace ID with the id, and replace.. with the path
getgenv().Animator6D(anim, 1, true?

If u want to stop the anim outside ts loadstring, then:
getgenv().Animator6DStop()
--]]
