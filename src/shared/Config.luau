-- Config.luau
-- Shared settings used by both the server and the client.
-- Change gameplay numbers here instead of editing the scripts.

local Config = {}

-- CollectionService tags. Put these tags on parts in Studio (see README).
Config.Tags = {
	Checkpoint = "Checkpoint", -- BasePart with a whole-number attribute "Stage" (0 = start)
	Finish = "Finish", -- BasePart at the end of the last level
	Coin = "Coin", -- BasePart that gives coins when touched
	KillPart = "KillPart", -- BasePart that kills the player on touch (lava, spikes)
	Spinner = "Spinner", -- BasePart that keeps rotating (optional attribute "Speed", degrees/second)
	FadingPlatform = "FadingPlatform", -- BasePart that disappears shortly after a player steps on it
}

-- Name of the number attribute that every Checkpoint part must have.
Config.StageAttribute = "Stage"
-- Optional number attribute on Coin parts that overrides CoinValue.
Config.CoinValueAttribute = "Value"

-- DataStore settings. Bump the "_v1" suffix to start everyone from scratch.
Config.DataStoreName = "ObbyPlayerData_v1"
Config.LeaderboardStoreName = "ObbyCoinsLeaderboard_v1"
Config.DataStoreRetries = 3 -- attempts for every load/save call
Config.AutosaveInterval = 120 -- seconds between automatic saves

-- What a brand new player starts with. Every key here is saved.
Config.DefaultData = {
	Coins = 0,
	Stage = 0, -- highest checkpoint reached in the current run
	BestTime = 0, -- best completion time in seconds (0 = no record yet)
	Wins = 0, -- how many times the player finished the obby
}

-- Rewards
Config.FinishReward = 50 -- coins for finishing the obby
Config.CoinValue = 1 -- default coins per Coin part
Config.CoinRespawnTime = 10 -- seconds before a collected coin comes back

-- Anti-exploit limits (checked on the server)
Config.MaxTouchDistance = 12 -- studs between the player and a touched part
Config.MinSecondsPerStage = 1 -- a new checkpoint cannot be reached faster than this
Config.MinRunTime = 20 -- full runs faster than this are rejected as cheating
Config.ResetCooldown = 5 -- seconds between "restart" requests
Config.SyncCooldown = 1 -- seconds between "send me my state" requests

-- Global leaderboard
Config.LeaderboardSize = 10
Config.LeaderboardRefreshInterval = 60 -- seconds

-- Obstacles
Config.SpinnerDefaultSpeed = 90 -- degrees per second when a Spinner has no "Speed" attribute
Config.FadeDelay = 0.7 -- seconds a FadingPlatform stays solid after being touched
Config.FadeRespawnTime = 3 -- seconds a FadingPlatform stays gone

-- Seconds before the player is sent back to the start after finishing
Config.FinishRespawnDelay = 4

return Config
