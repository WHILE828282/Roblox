-- Effects.luau
-- Purely visual client effects (no gameplay decisions):
--   * rainbow color cycling for Rainbow-mutation parts
--   * hatch timers above eggs in nests
--   * hiding the "Steal" prompt on your own nest eggs
--   * applying knockback sent by the server to your own character

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)

local Effects = {}

local player = Players.LocalPlayer

local function startRainbow()
	local hue = 0
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 then
			return
		end
		hue = (hue + elapsed * 0.25) % 1
		elapsed = 0
		for _, part in CollectionService:GetTagged(Config.Tags.RainbowPart) do
			if part:IsA("BasePart") then
				part.Color = Color3.fromHSV(hue, 0.8, 1)
			end
		end
	end)
end

local function startNestTimers()
	task.spawn(function()
		local basesFolder = workspace:WaitForChild("Bases")
		while true do
			local now = workspace:GetServerTimeNow()
			for _, model in basesFolder:GetDescendants() do
				if model:IsA("Model") and model.Name == "NestEgg" then
					local hatchAt = model:GetAttribute("HatchAt")
					local primary = model.PrimaryPart
					local timer = primary and primary:FindFirstChild("Timer")
					local label = timer and timer:FindFirstChild("Text")
					if hatchAt and label then
						local left = hatchAt - now
						label.Text = (model:GetAttribute("Label") or "Egg")
							.. "\n"
							.. (if left > 0 then Format.duration(left) else "Hatching!")
					end
					-- Your own eggs can't be stolen by you: hide the prompt.
					if model:GetAttribute("OwnerId") == player.UserId and primary then
						local prompt = primary:FindFirstChildOfClass("ProximityPrompt")
						if prompt and prompt.Enabled then
							prompt.Enabled = false
						end
					end
				end
			end
			task.wait(0.5)
		end
	end)
end

-- The server can't move a character it doesn't simulate, so it asks us.
function Effects.knockback(velocity: Vector3)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or typeof(velocity) ~= "Vector3" then
		return
	end
	if velocity.Magnitude > 200 then
		velocity = velocity.Unit * 200
	end
	humanoid.PlatformStand = true
	rootPart.AssemblyLinearVelocity = velocity
	task.delay(0.6, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
		end
	end)
end

function Effects.start()
	startRainbow()
	startNestTimers()
end

return Effects
