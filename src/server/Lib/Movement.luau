-- Movement.luau
-- The one place that sets a player's WalkSpeed:
--   trained Speed  x  weight of the carried egg  x  dash boost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local Movement = {}

local weight: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local dashUntil: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local getSpeed: ((Player) -> number?)? = nil

-- PlayerData is injected to avoid a circular require.
function Movement.setSpeedSource(source: (Player) -> number?)
	getSpeed = source
end

function Movement.apply(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local speed = (getSpeed and getSpeed(player)) or Config.StartSpeed
	speed *= weight[player] or 1
	if (dashUntil[player] or 0) > os.clock() then
		speed *= Config.DashMultiplier
	end
	humanoid.WalkSpeed = speed
end

-- 1 = nothing carried; 0.5 = a heavy egg halves the speed.
function Movement.setWeight(player: Player, multiplier: number?)
	weight[player] = multiplier
	Movement.apply(player)
end

function Movement.dash(player: Player)
	dashUntil[player] = os.clock() + Config.DashTime
	Movement.apply(player)
	task.delay(Config.DashTime + 0.05, function()
		Movement.apply(player)
	end)
end

return Movement
