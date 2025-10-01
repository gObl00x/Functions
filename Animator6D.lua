-- // ANIMATOR 6D \\ --
-- Originally made by idk who & edited by gObl00x
local player = game.Players.LocalPlayer
local character = player.Character
local humanoid = character.Humanoid
--
-- Animation library
local function makeanimlibrary()
    local RunService = game:GetService("RunService")
    local __EasingStyles__ = Enum.EasingStyle
    local __EasingDirections__ = Enum.EasingDirection
    local __Enum__PoseEasingStyle__ = #'Enum.PoseEasingStyle.'
    local __Enum__PoseEasingDirection__ = #'Enum.PoseEasingDirection.'

    local function EasingStyleFix(style)
        local name = string.sub(tostring(style), __Enum__PoseEasingStyle__ + 1)
        local suc, res = pcall(function()
            return __EasingStyles__[name]
        end)
        return suc and res or Enum.EasingStyle.Linear
    end

    local function EasingDirectionFix(dir)
        local name = string.sub(tostring(dir), __Enum__PoseEasingDirection__ + 1)
        return __EasingDirections__[name] or Enum.EasingDirection.In
    end

    local function ConvertToTable(animationInstance)
        assert(animationInstance and animationInstance:IsA("KeyframeSequence"), "Requires KeyframeSequence")
        local keyframes, sequence = animationInstance:GetKeyframes(), {}
        for i, frame in ipairs(keyframes) do
            local entry = {Time = frame.Time, Data = {}}
            for _, child in ipairs(frame:GetDescendants()) do
                if child:IsA("Pose") and child.Weight > 0 then
                    entry.Data[child.Name] = {
                        CFrame = child.CFrame,
                        EasingStyle = EasingStyleFix(child.EasingStyle),
                        EasingDirection = EasingDirectionFix(child.EasingDirection),
                        Weight = child.Weight,
                    }
                end
            end
            sequence[i] = entry
        end
        table.sort(sequence, function(a,b) return a.Time < b.Time end)
        return sequence, animationInstance.Loop
    end

    local function AutoGetMotor6D(model, motorType)
        local motors = {}
        for _, aura in ipairs(model:GetDescendants()) do
            if aura:IsA("BasePart") then
                for _, joint in ipairs(aura:GetJoints()) do
                    if joint:IsA("Motor6D") and joint.Part1 == aura then
                        motors[aura.Name] = joint
                        break
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

    function AnimLibrary.new(target, keyframeSeq)
        local self = setmetatable({}, AnimLibrary)
        self.Looped, self.TimePosition, self.IsPlaying = false, 0, false
        self.Speed, self.Settings = 1, {}
        self.Motor6D = AutoGetMotor6D(target, "Motor6D")

        local seq, looped = ConvertToTable(keyframeSeq)
        self.Animation, self.Looped, self.Length = seq, looped, seq[#seq].Time
        return self
    end

    local function getSurrounding(seq, t)
        local prev, next = seq[1], seq[#seq]
        for i = 1, #seq-1 do
            if seq[i].Time <= t and seq[i+1].Time >= t then
                prev, next = seq[i], seq[i+1]
                break
            end
        end
        return prev, next
    end

    function AnimLibrary:Play()
        if self.IsPlaying then return end
        self.IsPlaying = true
        if self.TimePosition >= self.Length then self.TimePosition = 0 end

        self._conn = UpdateEvent:Connect(function(delta)
            if not self.IsPlaying then return end
            local dt = delta * (self.Speed or 1)
            local pos = self.TimePosition + dt

            if pos > self.Length then
                if self.Looped then pos = pos - self.Length
                else pos = self.Length self:Stop() return end
            end
            self.TimePosition = pos

            local prev, next = getSurrounding(self.Animation, pos)
            local span = next.Time - prev.Time
            local alpha = span > 0 and (pos - prev.Time) / span or 0
            for joint, prevData in pairs(prev.Data) do
                local nextData = next.Data[joint] or prevData
                local ease = game:GetService("TweenService"):GetValue(alpha, nextData.EasingStyle, nextData.EasingDirection)
                local cf = prevData.CFrame:Lerp(nextData.CFrame, ease)
                local motor = self.Motor6D[joint]
                if motor then motor.Transform = cf end
            end
        end)
    end

    function AnimLibrary:Stop()
        self.IsPlaying = false
        if self._conn then self._conn:Disconnect() self._conn = nil end
        for _, motor in pairs(self.Motor6D) do motor.Transform = cframe_zero end
    end

    return AnimLibrary
end

local animplayer = makeanimlibrary()
local rigTable = animplayer.AutoGetMotor6D(character, "Motor6D")

-- API global
function getgenv().playanim(animData, speed, looped)
    if not animData then return end
    if getgenv().currentanim then
        getgenv().currentanim:Stop()
    end
    local anim = animplayer.new(character, animData)
    anim.Speed = speed or 1
    anim.Looped = looped or false
    anim:Play()
    getgenv().currentanim = anim
end
