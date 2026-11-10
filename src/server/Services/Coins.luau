-- Coins.luau
-- Parts tagged "Coin" give coins when a player touches them.
-- The coin hides for everyone and comes back after Config.CoinRespawnTime.
-- Optional number attribute "Value" sets how many coins a part gives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerData = require(script.Parent.PlayerData)
local TouchUtil = require(script.Parent.Parent.Lib.TouchUtil)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Coins = {}

local function getValue(part: BasePart): number
	local value = part:GetAttribute(Config.CoinValueAttribute)
	if type(value) == "number" and value >= 1 then
		return math.floor(value)
	end
	return Config.CoinValue
end

local function setupCoin(part: BasePart)
	local originalTransparency = part.Transparency
	local available = true

	local function setVisible(visible: boolean)
		part.Transparency = if visible then originalTransparency else 1
		for _, child in part:GetDescendants() do
			if child:IsA("Decal") or child:IsA("Texture") then
				child.Transparency = if visible then 0 else 1
			elseif child:IsA("ParticleEmitter") or child:IsA("Light") or child:IsA("BillboardGui") then
				child.Enabled = visible
			end
		end
	end

	return part.Touched:Connect(function(hit)
		if not available then
			return
		end
		local player, _, _, root = TouchUtil.getLivingPlayer(hit)
		if not player or not PlayerData.get(player) then
			return
		end
		if not TouchUtil.isNear(root, part, Config.MaxTouchDistance) then
			return
		end

		-- Mark as taken BEFORE giving coins so two touches in the
		-- same frame cannot both pay out.
		available = false
		local value = getValue(part)
		PlayerData.addCoins(player, value)
		PlayerData.notify(player, string.format("+%d coin%s", value, if value == 1 then "" else "s"), "coin")

		setVisible(false)
		task.delay(Config.CoinRespawnTime, function()
			if part.Parent then
				setVisible(true)
				available = true
			end
		end)
	end)
end

function Coins.start()
	Tagged(Config.Tags.Coin, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Coins] 'Coin' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		return setupCoin(instance)
	end)
end

return Coins
