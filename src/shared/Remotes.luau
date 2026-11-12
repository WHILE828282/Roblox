-- Remotes.luau
-- One place that defines every RemoteEvent used by the game.
-- The server creates them inside ReplicatedStorage.Remotes; the client waits for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

-- Server -> client
--   StateChanged(state)      everything the HUD and panels show
--   Notify(message, kind)    short toast
--   Alert(message)           big warning banner sliding in from the top
--   Knockback(velocity)      push the local character
--   OpenPanel(name)          open a window (the trail stand on the pier)
-- Client -> server (always validated on the server!)
--   RequestSync, Dash, DropEgg, LockBase, BuyTrail(id), EquipTrail(id),
--   UpgradeTreadmill, UpgradeAquarium, SellCreature(id)
Remotes.Names = {
	StateChanged = true,
	Notify = true,
	Alert = true,
	Knockback = true,
	OpenPanel = true,
	RequestSync = true,
	Dash = true,
	DropEgg = true,
	LockBase = true,
	BuyTrail = true,
	EquipTrail = true,
	UpgradeTreadmill = true,
	UpgradeAquarium = true,
	SellCreature = true,
}

function Remotes.get(name: string): RemoteEvent
	assert(Remotes.Names[name], "Unknown remote: " .. tostring(name))
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "Remotes"
			folder.Parent = ReplicatedStorage
		end
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		return remote :: RemoteEvent
	end
	return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name) :: RemoteEvent
end

-- Server only: create every remote up front so clients never wait forever.
function Remotes.createAll()
	for name in Remotes.Names do
		Remotes.get(name)
	end
end

return Remotes
