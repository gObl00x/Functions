-- Minimal / robust Animator6D (copy into your loadstring)
if getgenv().Animator6DLoaded then return end
getgenv().Animator6DLoaded = true

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildOfClass("Humanoid")

local animCache = {} -- cache for GetObjects

-- Load KeyframeSequence from id or instance (returns KeyframeSequence or nil)
local function loadKeyframeSequence(idOrInstance)
	-- instance path
	if typeof(idOrInstance) == "Instance" then
		local inst = idOrInstance
		if inst:IsA("KeyframeSequence") then return inst end
		if inst:IsA("ObjectValue") and inst.Value and inst.Value:IsA("KeyframeSequence") then
			return inst.Value
		end
		local k = inst:FindFirstChildOfClass("KeyframeSequence")
		if k then return k end
		if inst:FindFirstChild("AnimSaves") then
			k = inst.AnimSaves:FindFirstChildOfClass("KeyframeSequence")
			if k then return k end
		end
		if inst:FindFirstChild("Animations") then
			k = inst.Animations:FindFirstChildOfClass("KeyframeSequence")
			if k then return k end
		end
		for _,v in ipairs(inst:GetDescendants()) do
			if v:IsA("KeyframeSequence") then return v end
		end
		return nil
	end

	-- id path (string/number)
	local idStr = tostring(idOrInstance)
	if animCache[idStr] then
		return animCache[idStr]
	end

	local ok, obj = pcall(function()
		return game:GetObjects("rbxassetid://" .. idStr)[1]
	end)
	if not ok or not obj then
		warn("[Animator6D] game:GetObjects failed for id:", idStr)
		return nil
	end

	-- try common places
	if obj:IsA("KeyframeSequence") then
		animCache[idStr] = obj
		return obj
	end
	local kfs = obj:FindFirstChildOfClass("KeyframeSequence")
	if kfs then animCache[idStr] = kfs return kfs end
	if obj:FindFirstChild("AnimSaves") then
		kfs = obj.AnimSaves:FindFirstChildOfClass("KeyframeSequence")
		if kfs then animCache[idStr] = kfs return kfs end
	end
	if obj:FindFirstChild("Animations") then
		kfs = obj.Animations:FindFirstChildOfClass("KeyframeSequence")
		if kfs then animCache[idStr] = kfs return kfs end
	end
	for _,v in ipairs(obj:GetDescendants()) do
		if v:IsA("KeyframeSequence") then
			animCache[idStr] = v
			return v
		end
	end

	warn("[Animator6D] No KeyframeSequence found inside asset id:", idStr)
	return nil
end

-- Convert KeyframeSequence -> table (simple, safe)
local function ConvertToTable(kfs)
	assert(kfs and kfs:IsA("KeyframeSequence"), "ConvertToTable needs KeyframeSequence")
	local frames = kfs:GetKeyframes()
	local seq = {}
	for i, frame in ipairs(frames) do
		local entry = { Time = frame.Time, Data = {} }
		for _, desc in ipairs(frame:GetDescendants()) do
			if desc:IsA("Pose") and desc.Weight > 0 then
				entry.Data[desc.Name] = {
					CFrame = desc.CFrame,
					-- ignore easing in this minimal version (could be added later) vruh
				}
			end
		end
		seq[i] = entry
	end
	table.sort(seq, function(a,b) return a.Time < b.Time end)
	return seq, kfs.Loop
end

-- Build motor maps with multiple keys for maximum compatibility
local function BuildMotorMaps(rig)
	local map = {}
	local mapLower = {}
	for _, v in ipairs(rig:GetDescendants()) do
		if v:IsA("Motor6D") then
			-- map by motor name and by connected part names
			map[v.Name] = v
			mapLower[string.lower(v.Name)] = v
			if v.Part0 then
				map[v.Part0.Name] = v
				mapLower[string.lower(v.Part0.Name)] = v
			end
			if v.Part1 then
				map[v.Part1.Name] = v
				mapLower[string.lower(v.Part1.Name)] = v
			end
		end
	end
	return map, mapLower
end

-- find best motor for a given pose name using heuristics
local function FindMotorForPose(poseName, map, mapLower)
	if map[poseName] then return map[poseName] end
	local low = string.lower(poseName)
	if mapLower[low] then return mapLower[low] end
	-- try compacted (remove spaces/underscores)
	local compact = low:gsub("[%s_]", "")
	if mapLower[compact] then return mapLower[compact] end
	-- substring match (loose)
	for k,v in pairs(mapLower) do
		if k:find(compact, 1, true) or compact:find(k, 1, true) then
			return v
		end
	end
	return nil
end

-- AnimPlayer object
local AnimPlayer = {}
AnimPlayer.__index = AnimPlayer

function AnimPlayer.new(rigModel, keyframeSeq)
	local self = setmetatable({}, AnimPlayer)
	self.rig = rigModel
	self.keyframeSeq = keyframeSeq
	self.Animation, self.Looped = ConvertToTable(keyframeSeq)
	self.Length = self.Animation[#self.Animation].Time
	self.TimePosition = 0
	self.Playing = false
	self.map, self.mapLower = BuildMotorMaps(rigModel)
	return self
end

function AnimPlayer:Play(speed, looped)
	if self.Playing then return end
	self.Playing = true
	self.Speed = speed or 1
	self.Looped = (looped == nil) and true or looped

	-- debug: list how many poses and motors we have
	local posesSet = {}
	for _,frame in ipairs(self.Animation) do
		for pname,_ in pairs(frame.Data) do posesSet[pname] = true end
	end
	local poseCount, motorCount = 0, 0
	for _ in pairs(posesSet) do poseCount = poseCount + 1 end
	for _ in pairs(self.map) do motorCount = motorCount + 1 end
	warn(("[Animator6D] Playing animation: poses=%d motors=%d length=%.3f speed=%.2f"):format(poseCount, motorCount, self.Length, self.Speed))

	-- list missing poses (non-blocking)
	local missing = {}
	for pname,_ in pairs(posesSet) do
		if not FindMotorForPose(pname, self.map, self.mapLower) then
			table.insert(missing, pname)
		end
	end
	if #missing > 0 then
		warn("[Animator6D] No motors found for poses (examples):", table.concat(missing, ", ", 1, math.min(#missing,10)))
	end

	self._conn = RunService.PreSimulation:Connect(function(dt)
		if not self.Playing then return end
		local dtScaled = dt * (self.Speed or 1)
		local pos = self.TimePosition + dtScaled
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

		-- find surrounding frames
		local prev, next = self.Animation[1], self.Animation[#self.Animation]
		for i = 1, #self.Animation - 1 do
			if self.Animation[i].Time <= pos and self.Animation[i+1].Time >= pos then
				prev, next = self.Animation[i], self.Animation[i+1]
				break
			end
		end

		local span = next.Time - prev.Time
		local alpha = (span > 0) and ((pos - prev.Time) / span) or 0

		for jointName, prevData in pairs(prev.Data) do
			local nextData = next.Data[jointName] or prevData
			local motor = FindMotorForPose(jointName, self.map, self.mapLower)
			if motor and prevData.CFrame and nextData.CFrame then
				local cf = prevData.CFrame:Lerp(nextData.CFrame, alpha)
				-- apply to Motor6D.Transform
				local ok, err = pcall(function() motor.Transform = cf end)
				if not ok then
					-- if .Transform fails for some reason, ignore silently (but can warn)
					-- warn("[Animator6D] failed to set Transform for", motor.Name, err)
				end
			end
		end
	end)
end

function AnimPlayer:Stop()
	self.Playing = false
	if self._conn then self._conn:Disconnect() self._conn = nil end
	-- reset transforms to identity
	for _,m in pairs(self.map) do
		pcall(function() m.Transform = CFrame.new() end)
	end
end

-- public API: getgenv().Animator6D(idOrInstance, speed, looped)
getgenv().Animator6D = function(idOrInstance, speed, looped)
	if not player then player = Players.LocalPlayer end
	character = player.Character or player.CharacterAdded:Wait()
	humanoid = character:FindFirstChildOfClass("Humanoid")

	local kfs = loadKeyframeSequence(idOrInstance)
	if not kfs then
		warn("[Animator6D] No KeyframeSequence for", tostring(idOrInstance))
		return
	end

	-- stop previous
	if getgenv().currentAnimator6D and type(getgenv().currentAnimator6D.Stop) == "function" then
		pcall(function() getgenv().currentAnimator6D:Stop() end)
		getgenv().currentAnimator6D = nil
	end

	local playerObj = AnimPlayer.new(character, kfs)
	getgenv().currentAnimator6D = playerObj
	playerObj:Play(speed or 1, looped)
end

-- helper to stop
getgenv().Animator6DStop = function()
	if getgenv().currentAnimator6D then
		pcall(function() getgenv().currentAnimator6D:Stop() end)
		getgenv().currentAnimator6D = nil
	end
end

warn("[Animator6D] Loaded. Use getgenv().Animator6D(idOrInstance, speed, looped)")
