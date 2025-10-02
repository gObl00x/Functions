-- // MINIMAL ANIMATOR6D \\ --
-- Step 1: loadstring(game:HttpGet("https://raw.githubusercontent.com/gObl00x/Stuff/refs/heads/main/Animator6D.lua"))()
-- Step 2: getgenv().Animator6D(HERE_ANIM_ID, 1, true)

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

-- Convert KFS to table
local function ConvertToTable(animationInstance)
	assert(animationInstance and animationInstance:IsA("KeyframeSequence"),
		"ConvertToTable requires a KeyframeSequence")

	local keyframes = animationInstance:GetKeyframes()
	local sequence = {}
	for _, frame in ipairs(keyframes) do
		local entry = {Time = frame.Time, Data = {}}
		for _, child in ipairs(frame:GetDescendants()) do
			if child:IsA("Pose") and child.Weight > 0 then
				entry.Data[child.Name] = {
					CFrame = child.CFrame,
					EasingStyle = child.EasingStyle,
					EasingDirection = child.EasingDirection,
				}
			end
		end
		table.insert(sequence, entry)
	end
	table.sort(sequence, function(a,b) return a.Time < b.Time end)
	return sequence, animationInstance.Loop
end

-- Search Motor6D
local function AutoGetMotor6D(model)
	local motors = {}
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("Motor6D") then
			motors[part.Name] = part
			if part.Part1 then
				motors[part.Part1.Name] = part
			end
		end
	end
	return motors
end

-- AnimPlayer
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rig, keyframeSeq)
	local self = setmetatable({}, AnimPlayer)
	self.Motors = AutoGetMotor6D(rig)
	self.Animation, self.Looped = ConvertToTable(keyframeSeq)
	self.Length = self.Animation[#self.Animation].Time
	self.TimePosition = 0
	self.Playing = false
	return self
end

function AnimPlayer:Play(speed, looped)
	if self.Playing then return end
	self.Playing = true
	self.Speed = speed or 1
	self.Looped = looped ~= false

	self.Conn = game:GetService("RunService").Heartbeat:Connect(function(dt)
		if not self.Playing then return end
		self.TimePosition += dt * self.Speed
		if self.TimePosition > self.Length then
			if self.Looped then
				self.TimePosition -= self.Length
			else
				self:Stop()
				return
			end
		end

		-- Interpolación
		local prev, next = self.Animation[1], self.Animation[#self.Animation]
		for i=1,#self.Animation-1 do
			if self.Animation[i].Time <= self.TimePosition and self.Animation[i+1].Time >= self.TimePosition then
				prev, next = self.Animation[i], self.Animation[i+1]
				break
			end
		end

		local alpha = (self.TimePosition - prev.Time) / (next.Time - prev.Time)
		for joint, pose in pairs(prev.Data) do
			local nextPose = next.Data[joint] or pose
			local cf = pose.CFrame:Lerp(nextPose.CFrame, alpha)
			if self.Motors[joint] then
				self.Motors[joint].Transform = cf
			end
		end
	end)
end

function AnimPlayer:Stop()
	self.Playing = false
	if self.Conn then self.Conn:Disconnect() self.Conn = nil end
	for _,m in pairs(self.Motors) do
		m.Transform = CFrame.new()
	end
end

-- Loader
local function LoadAnimation(id)
	local obj = game:GetObjects("rbxassetid://"..id)[1]
	if obj:IsA("KeyframeSequence") then
		return obj
	else
		return obj:FindFirstChildOfClass("KeyframeSequence")
	end
end

-- API GLOBAL
local current
getgenv().Animator6D = function(id, speed, looped)
	if current then current:Stop() end
	local seq = LoadAnimation(id)
	if not seq then return warn("KeyframeSequence no encontrado:", id) end
	current = AnimPlayer.new(character, seq)
	current:Play(speed, looped)
end
