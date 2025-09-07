 -- // ANIMATOR EDITED BY gObl00x \\ --
local Animator6D function()
local full = game:GetObjects("rbxassetid://107495486817639")[1]:Clone()
full.Parent = game:GetService("Workspace")
local fallback = game:GetObjects("rbxassetid://"..)[1].AnimSaves
	:FindFirstChildOfClass("KeyframeSequence")
fallback.Parent = full

--local is = game:GetService("InsertService")
--// userdata propaganda
local is = newproxy(true)
local function loadlocalasset(id)
	local id = tostring(id)
	local id = id:gsub("^rbxassetid://", "")
	local _, asset = pcall(function()
		return full[id]
	end)
	if not _ or not asset then
		asset = fallback
	end

	return asset:Clone()
end
getmetatable(is).__namecall = function(_, id)
	return loadlocalasset(id)
end

local randompart = IT("Part", game:GetService("RunService"))

local playbacktrack = true
local script = IT("LocalScript")
real = true
local timeposcur = 0
pcall(function()
	local OxideApi = loadstring(
		game:HttpGet(
			"https://raw.githubusercontent.com/somethingsimade/Utils/refs/heads/main/OxideApi"
		)
	)()
end)
if char:FindFirstChild("Animate") then
	char.Animate.Enabled = true
end
for i, v in pairs(Humanoid:GetPlayingAnimationTracks()) do
	v:Stop()
end
local h = char.Head
local t = char.Torso
local hrp = char.HumanoidRootPart
local RunService = game:GetService("RunService")


local function makeanimlibrary() --// yeah sorry im not going to edit and mix at least 1000 lines of modules together under 30 minutes
	local RunService = game:GetService("RunService")

	local __EasingStyles__ = Enum.EasingStyle
	local __EasingDirections__ = Enum.EasingDirection
	local __Enum__PoseEasingStyle__ = #"Enum.PoseEasingStyle."
	local __Enum__PoseEasingDirection__ = #"Enum.PoseEasingDirection."

	local function EasingStyleFix(style)
		local name = string.sub(tostring(style), __Enum__PoseEasingStyle__ + 1)
		return (function()
			local suc, res = pcall(function()
				return __EasingStyles__[name]
			end)
			if not suc then
				return Enum.EasingStyle.Linear
			else
				return res
			end
		end)()
	end

	local function EasingDirectionFix(dir)
		local name =
			string.sub(tostring(dir), __Enum__PoseEasingDirection__ + 1)
		return __EasingDirections__[name] or Enum.EasingDirection.In
	end

	local function ConvertToTable(animationInstance)
		assert(
			animationInstance
				and typeof(animationInstance) == "Instance"
				and animationInstance:IsA("KeyframeSequence"),
			"ConvertToTable requires a KeyframeSequence instance"
		)
		local keyframes = animationInstance:GetKeyframes()
		local sequence = {}
		for i, frame in ipairs(keyframes) do
			local entry = { Time = frame.Time, Data = {} }
			for _, child in ipairs(frame:GetDescendants()) do
				if child:IsA("Pose") and child.Weight > 0 then
					entry.Data[child.Name] = {
						CFrame = child.CFrame,
						EasingStyle = EasingStyleFix(child.EasingStyle),
						EasingDirection = EasingDirectionFix(
							child.EasingDirection
						),
						Weight = child.Weight,
					}
				end
			end
			sequence[i] = entry
		end
		table.sort(sequence, function(a, b)
			return a.Time < b.Time
		end)
		return sequence, animationInstance.Loop
	end

	local function AutoGetMotor6D(model, motorType)
		assert(
			model and typeof(model) == "Instance" and model:IsA("Model"),
			"AutoGetMotor6D requires a Model instance"
		)
		local useBone = false
		if motorType == "Bone" then
			useBone = true
		else
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("Bone") then
					useBone = true
					break
				end
			end
		end
		local motors = {}
		if useBone then
			for _, bone in ipairs(model:GetDescendants()) do
				if bone:IsA("Bone") then
					motors[bone.Name] = bone
				end
			end
		else
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					for _, joint in ipairs(part:GetJoints()) do
						if joint:IsA("Motor6D") and joint.Part1 == part then
							motors[part.Name] = joint
							break
						end
					end
				end
			end
		end
		return motors
	end

	local cframe_zero = CFrame.new()
	local UpdateEvent = RunService.PreSimulation

	local AnimLibrary = {}
	AnimLibrary.__index = AnimLibrary

	function AnimLibrary.new(target, keyframeSeq, settings, motorType)
		local self = setmetatable({}, AnimLibrary)
		self.Looped = false
		self.TimePosition = 0
		self.IsPlaying = false
		self.Speed = 1
		self.Settings = settings or {}

		if typeof(target) == "Instance" and target:IsA("Model") then
			self.Motor6D = AutoGetMotor6D(target, motorType)
		else
			self.Motor6D = target
		end

		assert(keyframeSeq, "Animation keyframe sequence required")
		if typeof(keyframeSeq) == "Instance" then
			local seq, looped = ConvertToTable(keyframeSeq)
			self.Animation = seq
			self.Looped = looped
		elseif type(keyframeSeq) == "table" then
			self.Animation = keyframeSeq
		else
			error("Invalid keyframe sequence format")
		end

		self.Length = self.Animation[#self.Animation].Time
		return self
	end

	local function getSurrounding(seq, t)
		local prev, next = seq[1], seq[#seq]
		for i = 1, #seq - 1 do
			if seq[i].Time <= t and seq[i + 1].Time >= t then
				prev, next = seq[i], seq[i + 1]
				break
			end
		end
		return prev, next
	end

	function AnimLibrary:Play()
		if self.IsPlaying then
			return
		end
		self.IsPlaying = true
		if self.TimePosition >= self.Length then
			self.TimePosition = 0
		end

		self._conn = UpdateEvent:Connect(function(delta)
			if not self.IsPlaying then
				return
			end
			local dt = delta * (self.Speed or 1)
			local pos = self.TimePosition + dt

			if pos > self.Length then
				if self.Looped then
					pos = pos - self.Length
				else
					pos = self.Length
					self:Stop()
					return
				end
			end
			self.TimePosition = pos

			local prev, next = getSurrounding(self.Animation, pos)
			local span = next.Time - prev.Time
			local alpha = span > 0 and (pos - prev.Time) / span or 0
			for joint, prevData in pairs(prev.Data) do
				local nextData = next.Data[joint] or prevData
				local ease = game:GetService("TweenService"):GetValue(
					alpha,
					nextData.EasingStyle,
					nextData.EasingDirection
				)
				local cf1, cf2 = prevData.CFrame, nextData.CFrame
				local cf = cf1:Lerp(cf2, ease)
				local motor = self.Motor6D[joint]
				if motor then
					motor.Transform = cf
				end
			end
		end)
	end

	function AnimLibrary:Stop()
		self.IsPlaying = false
		if self._conn then
			self._conn:Disconnect()
			self._conn = nil
		end
		for _, motor in pairs(self.Motor6D) do
			motor.Transform = cframe_zero
		end
	end

	AnimLibrary.AutoGetMotor6D = AutoGetMotor6D
	AnimLibrary.KeyFrameSequanceToTable = ConvertToTable
	return AnimLibrary
end

local animplayer = makeanimlibrary()

local currentanim = nil
local iscurrentadance = nil

local rigTable = animplayer.AutoGetMotor6D(char, "Motor6D")
local function playanim(id, speed, isDance, customInstance)
	speed = speed or 1

	local asset
	if customInstance then
		asset = customInstance
	else
		asset = is:LoadLocalAsset(id)
	end

	if currentanim then
		currentanim:Stop()
	end
	iscurrentadance = isDance

	local keyframeTable = animplayer.KeyFrameSequanceToTable(asset)

	currentanim = animplayer.new(rigTable, asset, nil, nil, "Motor6D")
	currentanim.Speed = speed
	currentanim.Looped = true
	currentanim:Play()
end
end) -- Close Animator Function
print("Animator Loaded (Only works on Epik R6 Dancezzz, Modify it if ur an editor..)")
