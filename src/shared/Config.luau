-- Config.luau
-- Shared settings used by both the server and the client.
-- Gameplay numbers for animals and zones live in Animals.luau,
-- prices and formulas in Economy.luau.

local Config = {}

-- CollectionService tags used by the map (see README).
Config.Tags = {
	ZoneArea = "ZoneArea", -- ground part of a zone (attribute "Zone")
	RescueSpot = "RescueSpot", -- invisible part where an animal in trouble can appear (attribute "Zone")
	ZoneGate = "ZoneGate", -- wall that blocks a locked zone (attribute "Zone" = zone it unlocks)
	ShelterPlot = "ShelterPlot", -- a player's shelter (attribute "PlotIndex")
	-- Added at runtime by the server, used by client effects:
	RainbowPart = "RainbowPart",
}

-- DataStore settings. Change the "_v1" suffix to start everyone from scratch.
Config.DataStoreName = "AnimalRescueData_v1"
Config.LeaderboardStoreName = "AnimalRescueTopRescuers_v1"
Config.DataStoreRetries = 3
Config.AutosaveInterval = 120

-- What a brand new player starts with.
Config.DefaultData = {
	Money = 0,
	TotalRescued = 0,
	NextId = 1, -- id for the next rescued animal
	Animals = {}, -- { { id = number, s = speciesId, m = mutationId }, ... }
	Zones = { "Forest" }, -- unlocked zones
	Upgrades = { Speed = 0, Shelter = 0, Luck = 0 },
	LuckBoostUntil = 0, -- os.time() when the paid personal luck boost ends
	LastSeen = 0, -- os.time() of the last save (for offline income)
	Purchases = {}, -- recent Robux purchase ids (prevents double rewards)
}

-- Rescue spawning
Config.AnimalsPerZone = 8 -- animals in trouble waiting in every zone
Config.SpawnInterval = 2 -- seconds between spawn checks
Config.AnimalLifetime = 180 -- seconds before an unrescued animal is replaced
Config.RescueDistance = 14 -- max studs between player and animal (anti-exploit)
Config.HoldTolerance = 0.3 -- seconds of network slack allowed on hold timing

-- Auto rescue (gamepass)
Config.AutoRescueRange = 22 -- studs around the player
Config.AutoRescueSlowdown = 1.5 -- auto rescue takes this much longer than by hand

-- Storm event
Config.StormInterval = 600 -- seconds between storms
Config.StormWarning = 10 -- seconds of warning before a storm
Config.StormDuration = 60 -- seconds a storm lasts
Config.StormAnimals = 20 -- extra animals that appear during a storm
Config.StormLuck = 2 -- rarer animals are this much more likely in a storm

-- Offline income
Config.OfflineIncomeShare = 0.25 -- part of normal income earned while offline
Config.OfflineIncomeMaxHours = 8

-- Remote request cooldowns (seconds)
Config.ActionCooldown = 0.25
Config.SyncCooldown = 1

-- Global leaderboard
Config.LeaderboardSize = 10
Config.LeaderboardRefreshInterval = 60

-- Robux items. Create them on create.roblox.com (README, "Monetization")
-- and paste the ids here. Items with id 0 show as "Coming soon".
Config.GamePasses = {
	DoubleMoney = 0, -- x2 money from all animals
	AutoRescue = 0, -- rescues nearby animals automatically
	FastHands = 0, -- rescue twice as fast
	BigShelter = 0, -- +10 shelter slots
}
Config.Products = {
	LuckBoost = 0, -- x2 personal luck for 15 minutes
	ServerLuck = 0, -- rarer animals for the whole server for 10 minutes
	SummonStorm = 0, -- start a storm right away
	CashSmall = 0, -- 10 minutes of income
	CashMedium = 0, -- 1 hour of income
	CashLarge = 0, -- 6 hours of income
}
Config.LuckBoostDuration = 15 * 60
Config.ServerLuckDuration = 10 * 60
Config.ServerLuckMultiplier = 2
Config.CashMinutes = { CashSmall = 10, CashMedium = 60, CashLarge = 360 }
Config.CashMinimum = { CashSmall = 500, CashMedium = 3000, CashLarge = 20000 }

return Config
