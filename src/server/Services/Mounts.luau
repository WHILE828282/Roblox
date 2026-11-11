-- Mounts.luau
-- Riding adult dinosaurs, and stealing them:
--   * Ride an adult dinosaur from your base (Ride remote, must be at home).
--   * If a rider dies, the dinosaur stays behind with an EMPTY SADDLE.
--   * Anyone can saddle it by holding the prompt for Config.ClaimHoldTime.
--   * A thief must ride it to their OWN base: then it becomes theirs.
--   * The owner can win it back by saddling it first.
--   * Unclaimed loose dinosaurs walk back home after Config.LooseMountTimeout.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Economy = require(ReplicatedStorage.Shared.Economy)
local DinoModel = require(ReplicatedStorage.Shared.DinoModel)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Mounts = {}

local DEFAULT_WALK_SPEED = 16

-- rides[player] = { model, dino = {s,t,m,g}, owner = Player, ownerDinoId = number, stolen = boolean }
local rides: { [Player]: any } = {}
-- loose[model] = { dino, owner, ownerDinoId, createdAt, lockedUntil }
local loose: { [Model]: any } = {}

local announceRemote = Remotes.get("Announce")
local rideLimiter = RateLimiter.new(1)

local looseFolder = Instance.new("Folder")
looseFolder.Name = "LooseMounts"
looseFolder.Parent = workspace

function Mounts.getRide(player: Player)
	return rides[player]
end

-- How many eggs the player can carry right now.
function Mounts.carryCapacity(player: Player): number
	local ride = rides[player]
	if ride then
		return Dinos.Species[ride.dino.s].carry
	end
	return Config.CarryOnFoot
end

-- Normal walking speed for the player (mount speed when riding).
function Mounts.walkSpeed(player: Player): number
	local ride = rides[player]
	return if ride then Economy.mountSpeed(ride.dino) else DEFAULT_WALK_SPEED
end

local function getHumanoid(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil, nil
	end
	return humanoid, rootPart :: BasePart
end

-- Builds the dinosaur under the character and welds it on.
local function attach(player: Player, dino, owner: Player, ownerDinoId: number, stolen: boolean): boolean
	local humanoid, rootPart = getHumanoid(player)
	if not humanoid or not rootPart or rides[player] then
		return false
	end
	local session = PlayerData.getSession(player)
	if not session then
		return false
	end

	local model = DinoModel.build(dino.s, dino.t, dino.m, 3)
	DinoModel.makeCarryable(model)
	local backHeight = model:GetAttribute("BackHeight") or 3

	session.originalHipHeight = session.originalHipHeight or humanoid.HipHeight
	local hipHeight = session.originalHipHeight + backHeight
	humanoid.HipHeight = hipHeight
	humanoid.WalkSpeed = Economy.mountSpeed(dino)

	local groundOffset = hipHeight + rootPart.Size.Y / 2
	model:PivotTo(rootPart.CFrame * CFrame.new(0, -groundOffset, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = model.PrimaryPart
	weld.Parent = model.PrimaryPart
	model.Name = "Mount"
	model.Parent = player.Character

	rides[player] = { model = model, dino = dino, owner = owner, ownerDinoId = ownerDinoId, stolen = stolen }
	PlayerData.changed(player)
	return true
end

-- Removes the mount from under the player (no ownership changes).
local function detach(player: Player)
	local ride = rides[player]
	rides[player] = nil
	if not ride then
		return
	end
	if ride.model then
		ride.model:Destroy()
	end
	local session = PlayerData.getSession(player)
	local humanoid = getHumanoid(player)
	if humanoid and session and session.originalHipHeight then
		humanoid.HipHeight = session.originalHipHeight
		humanoid.WalkSpeed = DEFAULT_WALK_SPEED
	end
	PlayerData.changed(player)
end

-- The owner's dinosaur is home again (shown in the pen).
local function returnHome(owner: Player)
	local session = PlayerData.getSession(owner)
	if session then
		session.mountedId = nil
		Bases.refresh(owner)
	end
end

local function onRide(player: Player, dinoId: any)
	if not rideLimiter:check(player) or type(dinoId) ~= "number" then
		return
	end
	local session = PlayerData.getSession(player)
	local _, rootPart = getHumanoid(player)
	if not session or not rootPart or rides[player] or session.mountedId then
		if session and session.mountedId and not rides[player] then
			PlayerData.notify(player, "Your other dinosaur is still out there! Get it back first.", "error")
		end
		return
	end
	local dino = Bases.findDino(player, dinoId)
	if not dino then
		return
	end
	if Economy.stage(dino.t, dino.g) < 3 then
		PlayerData.notify(player, "Only adult dinosaurs can be ridden.", "error")
		return
	end
	if not Bases.isHome(player, rootPart.Position) then
		PlayerData.notify(player, "Go to your base to saddle a dinosaur.", "error")
		return
	end
	session.mountedId = dino.id
	if attach(player, dino, player, dino.id, false) then
		Bases.refresh(player)
	else
		session.mountedId = nil
	end
end

local function onDismount(player: Player)
	local ride = rides[player]
	local _, rootPart = getHumanoid(player)
	if not ride or not rootPart then
		return
	end
	if ride.stolen or not Bases.isHome(player, rootPart.Position) then
		PlayerData.notify(player, "You can only get off at your own base.", "error")
		return
	end
	detach(player)
	returnHome(player)
end

---------------------------------------------------------------------------
-- Empty saddles
---------------------------------------------------------------------------

local function removeLoose(model: Model)
	loose[model] = nil
	model:Destroy()
end

local function onClaim(model: Model, claimer: Player, startedAt: { [Player]: number })
	local info = loose[model]
	if not info then
		return
	end
	local started = startedAt[claimer]
	if not started or os.clock() - started < Config.ClaimHoldTime - 0.3 then
		return
	end
	local _, rootPart = getHumanoid(claimer)
	local session = PlayerData.getSession(claimer)
	if not rootPart or not session or rides[claimer] then
		return
	end
	if (rootPart.Position - model:GetPivot().Position).Magnitude > 16 then
		return
	end
	local isOwner = claimer == info.owner
	if not isOwner and (info.lockedUntil or 0) > os.time() then
		PlayerData.notify(claimer, "This saddle is locked for its owner for a while.", "error")
		return
	end
	if not isOwner and session.mountedId then
		PlayerData.notify(claimer, "Get your own dinosaur back first!", "error")
		return
	end
	removeLoose(model)
	attach(claimer, info.dino, info.owner, info.ownerDinoId, not isOwner)
	if isOwner then
		PlayerData.notify(claimer, "You got your dinosaur back! Ride it home.", "success")
	else
		PlayerData.notify(claimer, "Saddled! Ride it to YOUR base to keep it.", "success")
		PlayerData.notify(
			info.owner,
			claimer.DisplayName
				.. " is riding away on your "
				.. Dinos.displayName(info.dino.s, info.dino.t, info.dino.m)
				.. "!",
			"error"
		)
	end
end

-- The rider died: leave the dinosaur standing with an empty saddle.
local function leaveEmptySaddle(ride, position: Vector3)
	local owner: Player = ride.owner
	if owner.Parent ~= Players then
		return
	end
	local ownerSession = PlayerData.getSession(owner)
	local model = DinoModel.build(ride.dino.s, ride.dino.t, ride.dino.m, 3)
	model:PivotTo(CFrame.new(position))
	model.Name = "EmptySaddle"

	local info = {
		dino = ride.dino,
		owner = owner,
		ownerDinoId = ride.ownerDinoId,
		createdAt = os.time(),
		lockedUntil = if ownerSession and ownerSession.passes.SaddleLock then os.time() + Config.SaddleLockTime else 0,
	}
	loose[model] = info

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 50)
	gui.StudsOffset = Vector3.new(0, (model:GetAttribute("BackHeight") or 3) + 3, 0)
	gui.MaxDistance = 200
	gui.Parent = model.PrimaryPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Dinos.TierById[ride.dino.t].color
	label.TextStrokeTransparency = 0.3
	label.Text = "EMPTY SADDLE!\n" .. Dinos.displayName(ride.dino.s, ride.dino.t, ride.dino.m)
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Saddle"
	prompt.ObjectText = Dinos.displayName(ride.dino.s, ride.dino.t, ride.dino.m)
	prompt.HoldDuration = Config.ClaimHoldTime
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	local startedAt = {}
	prompt.PromptButtonHoldBegan:Connect(function(claimer)
		startedAt[claimer] = os.clock()
	end)
	prompt.Triggered:Connect(function(claimer)
		onClaim(model, claimer, startedAt)
	end)
	model.Parent = looseFolder

	if Dinos.TierById[ride.dino.t].index >= Config.RareEggAnnounceTier then
		announceRemote:FireAllClients(
			"A " .. Dinos.displayName(ride.dino.s, ride.dino.t, ride.dino.m) .. " lost its rider! Grab it!",
			Dinos.TierById[ride.dino.t].color
		)
	end
end

-- Called by Combat when a player dies.
function Mounts.onDeath(player: Player, position: Vector3)
	local ride = rides[player]
	if not ride then
		return
	end
	rides[player] = nil -- the welded model dies with the character
	leaveEmptySaddle(ride, position)
end

-- A thief reached their base on a stolen dinosaur: it changes owner.
local function completeTheft(thief: Player, ride)
	local victim: Player = ride.owner
	detach(thief)
	local dino = Bases.removeDino(victim, ride.ownerDinoId)
	if not dino then
		return -- victim sold it or left meanwhile
	end
	returnHome(victim)
	local entry = Bases.addDino(thief, dino)
	local name = Dinos.displayName(dino.s, dino.t, dino.m)
	PlayerData.notify(thief, "You stole a " .. name .. "! It lives in your pen now.", "success")
	PlayerData.notify(victim, thief.DisplayName .. " stole your " .. name .. "!", "error")
	if entry and Dinos.TierById[dino.t].index >= Config.RareEggAnnounceTier then
		announceRemote:FireAllClients(
			thief.DisplayName .. " stole " .. victim.DisplayName .. "'s " .. name .. "!",
			Dinos.TierById[dino.t].color
		)
	end
end

local function watchTick()
	local t = os.time()
	for player, ride in rides do
		local _, rootPart = getHumanoid(player)
		if ride.stolen and rootPart and Bases.isHome(player, rootPart.Position) then
			completeTheft(player, ride)
		end
	end
	for model, info in loose do
		if t - info.createdAt >= Config.LooseMountTimeout then
			removeLoose(model)
			returnHome(info.owner)
			PlayerData.notify(info.owner, "Your dinosaur found its way home.", "info")
		end
	end
end

function Mounts.start()
	PlayerData.addStateProvider(function(player, state)
		local ride = rides[player]
		local session = PlayerData.getSession(player)
		state.riding = if ride then { s = ride.dino.s, t = ride.dino.t, m = ride.dino.m, stolen = ride.stolen } else nil
		state.mountOut = session ~= nil and session.mountedId ~= nil and ride == nil
		state.carryCapacity = Mounts.carryCapacity(player)
	end)

	Remotes.get("Ride").OnServerEvent:Connect(onRide)
	Remotes.get("Dismount").OnServerEvent:Connect(onDismount)

	Players.PlayerRemoving:Connect(function(player)
		rideLimiter:forget(player)
		local ride = rides[player]
		rides[player] = nil
		if ride and ride.stolen and ride.owner.Parent == Players then
			-- Thief left: the dinosaur goes back to its owner.
			returnHome(ride.owner)
		end
		-- Owner left: their loose or stolen dinosaurs vanish (they keep them in their save).
		for model, info in loose do
			if info.owner == player then
				removeLoose(model)
			end
		end
		for rider, otherRide in rides do
			if otherRide.owner == player and rider ~= player then
				detach(rider)
				PlayerData.notify(rider, "The owner left, so their dinosaur went home.", "info")
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.25)
			watchTick()
		end
	end)
end

return Mounts
