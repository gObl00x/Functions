   -- Camera Shaker
    local RunService = game:GetService("RunService")
    local Camera = game.Workspace.CurrentCamera
    local shakeIntensity = 0.5
    local shakeSpeed = 20

      local function shakeCamera(dt)
            local shakeX = math.random(-3, 1)
            local shakeY = math.random(-1, 3)
          Camera.CFrame = Camera.CFrame * CFrame.new(shakeX, shakeY, 0)
      end

      local function startShake()
             local connection
          connection = RunService.RenderStepped:Connect(function(dt)
        shakeCamera(dt)
    end)
    wait(0.38)
    connection:Disconnect()
    Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, 0)
end
startShake()
