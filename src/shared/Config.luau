-- Config.luau
-- All settings of "Steal a Sea Monster", shared by the server and the client.
-- The layout numbers must match tools/generate_map.py.

local Config = {}

Config.MaxPlayers = 6

-- CollectionService tags (see README).
Config.Tags = {
	BasePlot = "BasePlot", -- invisible marker in the middle of a base (attribute BaseIndex)
	EggNest = "EggNest", -- a nest in the ocean (attribute Zone)
	GuardPost = "GuardPost", -- where a zone's guardian sleeps (attribute Zone)
	DepthArch = "DepthArch", -- glowing arch at the start of a zone (attribute Zone)
	TrailShop = "TrailShop", -- the stand on the pier
	-- Added by the server at runtime, used by client effects:
	Guard = "Guard",
	Sleeper = "Sleeper",
	NestEgg = "NestEgg",
	Creature = "Creature",
}

-- DataStore. This is a new game, so it has its own store.
Config.DataStoreName = "SeaMonstersData_v1"
Config.DataStoreRetries = 3
Config.AutosaveInterval = 120

-- Map layout
Config.OceanStartZ = 110 -- the pier (safe zone with the bases) ends here
Config.ZoneLength = 100
Config.CorridorHalfWidth = 35
Config.Slope = 0.4 -- studs down per stud forward
Config.BaseHalfWidth = 20 -- along the pier
Config.BaseHalfDepth = 18 -- from the entrance to the back wall

-- Height of the ocean floor at world Z.
function Config.floorY(z: number): number
	return if z <= Config.OceanStartZ then 0 else -(z - Config.OceanStartZ) * Config.Slope
end

-- Zone number (1-5) at world Z, or 0 on the pier.
function Config.zoneAt(z: number): number
	if z < Config.OceanStartZ then
		return 0
	end
	return math.clamp(math.floor((z - Config.OceanStartZ) / Config.ZoneLength) + 1, 1, 5)
end

-- Players
Config.StartSpeed = 16
Config.MaxSpeed = 300
Config.DashMultiplier = 2
Config.DashTime = 1.2
Config.DashCooldown = 6

-- Eggs
Config.GrabHoldTime = 0.6
Config.NestRespawn = 18 -- seconds until a taken egg appears again
Config.Incubators = 4
Config.StealHoldTime = 2.5 -- stealing from another player's incubator

-- Guardians
Config.GuardCatchDistance = 9
Config.GuardWakeDelay = 1.2 -- "!" time before the chase starts
Config.GuardKnockback = 70

-- Treadmill: speed gained per second = base + level * perLevel, times the trail multiplier.
Config.TreadmillBase = 0.25
Config.TreadmillPerLevel = 0.15
Config.TreadmillMaxLevel = 20
Config.TreadmillCost = 150 -- cost of level 1, grows by TreadmillCostGrowth
Config.TreadmillCostGrowth = 2.1

-- Aquarium
Config.AquariumBase = 6
Config.AquariumPerLevel = 2
Config.AquariumMaxLevel = 7
Config.AquariumCost = 400
Config.AquariumCostGrowth = 3
Config.SellSeconds = 90 -- a creature sells for this many seconds of its income

-- Base lock (water shield)
Config.LockDuration = 30
Config.LockCooldown = 120

Config.ActionCooldown = 0.25

function Config.treadmillCost(level: number): number?
	if level >= Config.TreadmillMaxLevel then
		return nil
	end
	return math.floor(Config.TreadmillCost * Config.TreadmillCostGrowth ^ level)
end

function Config.treadmillRate(level: number): number
	return Config.TreadmillBase + level * Config.TreadmillPerLevel
end

function Config.aquariumCost(level: number): number?
	if level >= Config.AquariumMaxLevel then
		return nil
	end
	return math.floor(Config.AquariumCost * Config.AquariumCostGrowth ^ level)
end

function Config.aquariumSize(level: number): number
	return Config.AquariumBase + level * Config.AquariumPerLevel
end

return Config
