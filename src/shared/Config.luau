-- Config.luau
-- Shared settings for Dino Raiders, used by both the server and the client.
-- Dinosaur species, rarities and odds live in Dinos.luau,
-- prices and formulas in Economy.luau.

local Config = {}

-- CollectionService tags used by the map (see README).
Config.Tags = {
	Volcano = "Volcano", -- top part of the volcano: eggs fly out of it
	BasePlot = "BasePlot", -- a player's base (attribute "BaseIndex")
	-- Added at runtime by the server, used by client effects:
	RainbowPart = "RainbowPart",
	FlyingEgg = "FlyingEgg", -- an egg in the air (clients animate the arc)
	NestEgg = "NestEgg", -- an egg in a nest (clients show the hatch timer)
	PenDino = "PenDino", -- a dinosaur standing in a pen
}

-- DataStore settings. Change the "_v1" suffix to start everyone from scratch.
Config.DataStoreName = "DinoRaidersData_v1"
Config.LeaderboardStoreName = "DinoRaidersTopHatched_v1"
Config.DataStoreRetries = 3
Config.AutosaveInterval = 120

-- What a brand new player starts with.
Config.DefaultData = {
	Money = 0,
	Hatched = 0, -- total dinosaurs hatched (leaderboard)
	NextId = 1,
	Dinos = {}, -- { { id, s = species, t = tier, m = mutation, g = growth seconds }, ... }
	Eggs = {}, -- eggs in nests: { { id, s, t, m, hatchAt = os.time() }, ... }
	Upgrades = { Nests = 0, Pen = 0, Strength = 0 },
	LastSeen = 0,
	Purchases = {}, -- recent Robux purchase ids (prevents double rewards)
}

-- Volcano and eggs
Config.EruptionInterval = 45 -- seconds between normal eruptions
Config.MaxPlayers = 20 -- server size; the map has this many bases
Config.EggsPerEruption = 25 -- on a full server
Config.EggsPerEruptionMin = 12 -- with a single player (scales in between)
Config.BigEruptionInterval = 600 -- seconds between big eruptions
Config.BigEruptionEggs = 50
Config.BigEruptionEggsMin = 25
Config.BigEruptionWarning = 15 -- seconds of warning before a big eruption
Config.MaxWildEggs = 150
Config.WildEggLifetime = 240 -- seconds before an untouched egg crumbles
Config.EggFlightTime = 1.4 -- seconds in the air, plus distance / EggFlightSpeed
Config.EggFlightSpeed = 220
Config.FieldInnerRadius = 105 -- eggs never land closer to the volcano than this
Config.FieldOuterRadius = 530 -- ...or farther than this
Config.RingRadii = { Inner = 240, Middle = 400 } -- beyond Middle = Outer ring
Config.GrabHoldTime = 0.5
Config.CarryOnFoot = 1 -- eggs a player can carry without a dinosaur
Config.RareEggAnnounceTier = 4 -- announce eggs of this tier (Legendary) or rarer

-- Bases
Config.BaseRadius = 46 -- radius of the round base floor: inside it you are "home"
Config.StealHoldTime = 3 -- seconds to steal an egg from someone's nest
Config.LockDuration = 60
Config.LockCooldown = 180
Config.GuardInterval = 2 -- seconds between guard dinosaur attacks on thieves
Config.NewPlayerProtection = 600 -- seconds a brand new player cannot be hurt

-- Combat
Config.AttackCooldown = 0.6
Config.AttackRange = 9
Config.MountedAttackRange = 13
Config.BaseDamage = 20
Config.DamagePerStrength = 5
Config.Knockback = 55 -- studs/second push on a hit
Config.AbilityCooldown = 8

-- Stolen mounts
Config.ClaimHoldTime = 5 -- seconds to saddle a dinosaur whose rider died
Config.LooseMountTimeout = 120 -- an unclaimed loose mount returns home after this
Config.SaddleLockTime = 300 -- gamepass: only the owner can saddle it for this long

-- Offline income
Config.OfflineIncomeShare = 0.25
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
	DoubleMoney = 0, -- x2 money from all dinosaurs
	DoubleGrowth = 0, -- dinosaurs grow twice as fast
	ExtraNests = 0, -- +3 nests
	SaddleLock = 0, -- after you die, only you can saddle your dinosaur for 5 minutes
}
Config.Products = {
	InstantHatch = 0, -- hatch the next egg right now
	HatchAll = 0, -- hatch every egg in your nests
	ServerLuck = 0, -- rarer eggs for the whole server for 10 minutes
	BigEruption = 0, -- start a big eruption right away
	CashSmall = 0, -- 10 minutes of income
	CashLarge = 0, -- 2 hours of income
}
Config.ServerLuckDuration = 10 * 60
Config.ServerLuckMultiplier = 2
Config.CashMinutes = { CashSmall = 10, CashLarge = 120 }
Config.CashMinimum = { CashSmall = 500, CashLarge = 10000 }

return Config
