-- Combat.luau
-- Hitting other players, mount abilities and deaths. All on the server:
-- the client only says "I attack" / "I use my ability", the server picks
-- the target, checks range and cooldowns and applies the damage.
--
-- Rules:
--   * A hit makes the target drop every egg they carry.
--   * You can't hurt players standing in their own base (home is safe).
--   * Brand new players are protected for Config.NewPlayerProtection seconds
--     (until they attack someone).
--   * Dying drops your eggs and leaves your mount with an EMPTY SADDLE (Mounts.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Economy = require(ReplicatedStorage.Shared.Economy)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local Mounts = require(script.Parent.Mounts)
local Eggs = require(script.Parent.Eggs)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Combat = {}

local knockbackRemote = Remotes.get("Knockback")
local attackLimiter = RateLimiter.new(Config.AttackCooldown)
local abilityReadyAt: { [Player]: number } = {}
local protectedUntil: { [Player]: number } = {}
local lastAttacker: { [Player]: { player: Player, at: number } } = {}

local function alive(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and rootPart then
		return humanoid, rootPart :: BasePart
	end
	return nil, nil
end

local function isProtected(player: Player): boolean
	return (protectedUntil[player] or 0) > os.clock()
end

local function canHurt(attacker: Player, target: Player): boolean
	if attacker == target or isProtected(target) then
		return false
	end
	local _, targetRoot = alive(target)
	if not targetRoot then
		return false
	end
	return not Bases.isHome(target, targetRoot.Position)
end

-- Damages and pushes `target`; `direction` is where they fly.
local function hit(attacker: Player, target: Player, damage: number, direction: Vector3, force: number)
	local humanoid, targetRoot = alive(target)
	if not humanoid or not targetRoot then
		return
	end
	local ride = Mounts.getRide(target)
	local armor = if ride then (Dinos.Species[ride.dino.s].armor or 0) else 0
	if damage > 0 then
		humanoid:TakeDamage(damage * (1 - armor))
	end
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = Vector3.new(0, 0, 1)
	end
	knockbackRemote:FireClient(target, flatDirection.Unit * force + Vector3.new(0, force * 0.45, 0))
	Eggs.dropCarried(target)
	lastAttacker[target] = { player = attacker, at = os.clock() }
end

-- Players within `range` of `origin`; with `facing`, only those in front.
local function playersNear(attacker: Player, origin: CFrame, range: number, facingOnly: boolean)
	local found = {}
	for _, other in Players:GetPlayers() do
		local _, otherRoot = alive(other)
		if otherRoot and canHurt(attacker, other) then
			local offset = otherRoot.Position - origin.Position
			local distance = offset.Magnitude
			local inFront = distance < 4 or origin.LookVector:Dot(offset.Unit) > 0.25
			if distance <= range and (not facingOnly or inFront) then
				table.insert(found, { player = other, distance = distance, direction = offset })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.distance < b.distance
	end)
	return found
end

local function onAttack(attacker: Player)
	if not attackLimiter:check(attacker) then
		return
	end
	local _, rootPart = alive(attacker)
	local data = PlayerData.get(attacker)
	if not rootPart or not data then
		return
	end
	protectedUntil[attacker] = nil -- attacking ends new-player protection
	local ride = Mounts.getRide(attacker)
	local range = if ride then Config.MountedAttackRange else Config.AttackRange
	local target = playersNear(attacker, rootPart.CFrame, range, true)[1]
	if not target then
		return
	end
	local damage = Config.BaseDamage + data.Upgrades.Strength * Config.DamagePerStrength
	if ride then
		damage += Economy.mountDamage(ride.dino)
	end
	hit(attacker, target.player, damage, target.direction, Config.Knockback)
end

local ABILITIES = {
	Sprint = function(player: Player, _rootPart: BasePart, humanoid: Humanoid)
		humanoid.WalkSpeed = Mounts.walkSpeed(player) * 1.7
		task.delay(3, function()
			if humanoid.Parent and Mounts.getRide(player) then
				humanoid.WalkSpeed = Mounts.walkSpeed(player)
			end
		end)
	end,
	Ram = function(player: Player, rootPart: BasePart)
		for _, target in playersNear(player, rootPart.CFrame, 14, true) do
			hit(player, target.player, 30, target.direction, 95)
		end
	end,
	TailSpin = function(player: Player, rootPart: BasePart)
		for _, target in playersNear(player, rootPart.CFrame, 13, false) do
			hit(player, target.player, 15, target.direction, 85)
		end
	end,
	Roar = function(player: Player, rootPart: BasePart)
		for _, target in playersNear(player, rootPart.CFrame, 24, false) do
			hit(player, target.player, 0, target.direction, 35)
		end
	end,
}

local function onAbility(player: Player)
	local humanoid, rootPart = alive(player)
	local ride = Mounts.getRide(player)
	if not humanoid or not rootPart or not ride then
		return
	end
	if (abilityReadyAt[player] or 0) > os.clock() then
		return
	end
	abilityReadyAt[player] = os.clock() + Config.AbilityCooldown
	protectedUntil[player] = nil
	local abilityId = Dinos.Species[ride.dino.s].ability
	local ability = ABILITIES[abilityId]
	if ability then
		ability(player, rootPart, humanoid)
	end
	PlayerData.changed(player)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			return
		end
		local ground = rootPart.Position - Vector3.new(0, humanoid.HipHeight + rootPart.Size.Y / 2, 0)
		Eggs.dropCarried(player, rootPart.Position)
		Mounts.onDeath(player, ground)
		local credit = lastAttacker[player]
		if credit and os.clock() - credit.at < 10 and credit.player.Parent == Players then
			PlayerData.notify(credit.player, "You knocked out " .. player.DisplayName .. "!", "success")
		end
		lastAttacker[player] = nil
	end)
end

function Combat.start()
	PlayerData.addStateProvider(function(player, state)
		state.protectedLeft = math.max(0, math.floor((protectedUntil[player] or 0) - os.clock()))
		state.abilityReadyIn = math.max(0, (abilityReadyAt[player] or 0) - os.clock())
	end)

	PlayerData.ProfileLoaded:Connect(function(player)
		local data = PlayerData.get(player)
		if data and data.Hatched == 0 and #data.Dinos == 0 then
			protectedUntil[player] = os.clock() + Config.NewPlayerProtection
			PlayerData.notify(player, "You are protected for 10 minutes while you learn the game.", "info")
		end
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		attackLimiter:forget(player)
		abilityReadyAt[player] = nil
		protectedUntil[player] = nil
		lastAttacker[player] = nil
	end)

	Remotes.get("Attack").OnServerEvent:Connect(onAttack)
	Remotes.get("UseAbility").OnServerEvent:Connect(onAbility)
end

return Combat
