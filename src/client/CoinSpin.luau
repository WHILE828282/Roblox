-- CoinSpin.luau
-- Purely visual: spins every "Coin" part on this client only.
-- It does not affect gameplay; coins are still collected on the server.
-- Set the attribute "Spin" to false on a coin to keep it still.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local DEGREES_PER_SECOND = 120

local CoinSpin = {}

function CoinSpin.start()
	local coins: { [BasePart]: CFrame } = {} -- part -> original CFrame

	local function add(instance: Instance)
		if instance:IsA("BasePart") and instance.Anchored and instance:GetAttribute("Spin") ~= false then
			coins[instance] = instance.CFrame
		end
	end
	for _, instance in CollectionService:GetTagged(Config.Tags.Coin) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Coin):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.Coin):Connect(function(instance)
		coins[instance] = nil
	end)

	local angle = 0
	RunService.RenderStepped:Connect(function(dt)
		angle = (angle + math.rad(DEGREES_PER_SECOND) * dt) % (2 * math.pi)
		local spin = CFrame.Angles(0, angle, 0)
		for part, original in coins do
			if part.Parent then
				-- Rotate around the world Y axis without moving the coin.
				part.CFrame = CFrame.new(original.Position) * spin * original.Rotation
			else
				coins[part] = nil
			end
		end
	end)
end

return CoinSpin
