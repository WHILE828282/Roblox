-- Remotes.luau
-- One place that defines every RemoteEvent used by the game.
-- The server creates them inside ReplicatedStorage.Remotes;
-- the client waits for them to exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Server -> client
--   StateChanged(state)        money, income, upgrades... for the HUD
--   ShelterChanged(animals)    the player's rescued animals
--   Notify(message, kind)      short toast message
--   Announce(message)          big banner for everyone (rare rescues, storms)
--   StormChanged(active, endsIn)
--   LeaderboardChanged(list)   global top rescuers
-- Client -> server (always validated on the server!)
--   RequestSync()              "send me my state"
--   BuyUpgrade(upgradeId)      buy the next level of an upgrade
--   SellAnimal(animalId)       sell one animal from the shelter
--   SetAutoRescue(enabled)     turn the auto rescue gamepass on/off
Remotes.Names = {
	StateChanged = "StateChanged",
	ShelterChanged = "ShelterChanged",
	Notify = "Notify",
	Announce = "Announce",
	StormChanged = "StormChanged",
	LeaderboardChanged = "LeaderboardChanged",
	RequestSync = "RequestSync",
	BuyUpgrade = "BuyUpgrade",
	SellAnimal = "SellAnimal",
	SetAutoRescue = "SetAutoRescue",
}

local function getFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		end
		return folder
	end
	return ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

-- Returns the RemoteEvent with the given name.
-- On the server it is created if it does not exist yet.
function Remotes.get(name: string): RemoteEvent
	assert(Remotes.Names[name], "Unknown remote: " .. tostring(name))
	local folder = getFolder()
	if RunService:IsServer() then
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Server only: create every remote up front so clients never wait forever.
function Remotes.createAll()
	assert(RunService:IsServer(), "Remotes.createAll must run on the server")
	for name in Remotes.Names do
		Remotes.get(name)
	end
end

return Remotes
