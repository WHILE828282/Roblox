-- Remotes.luau
-- One place that defines every RemoteEvent used by the game.
-- The server creates them inside ReplicatedStorage.Remotes;
-- the client waits for them to exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

local Remotes = {}

-- Server -> client
--   StateChanged(state)        full player state for the HUD
--   Notify(message, kind)      short toast message
--   RunFinished(result)        finish popup data
--   LeaderboardChanged(list)   global top players by coins
-- Client -> server (always validated on the server!)
--   RequestSync()              "send me my current state"
--   RequestReset()             "restart the obby from the beginning"
Remotes.Names = {
	StateChanged = "StateChanged",
	Notify = "Notify",
	RunFinished = "RunFinished",
	LeaderboardChanged = "LeaderboardChanged",
	RequestSync = "RequestSync",
	RequestReset = "RequestReset",
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
