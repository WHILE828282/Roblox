-- Bases.luau
-- Every player gets a base: nests where eggs hatch and a pen where
-- dinosaurs live, grow and earn money. Handles plot assignment, spawning
-- at home, the 3D display, income, growth, hatching, the base lock and
-- guard dinosaurs that push thieves away.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local DinoModel = require(ReplicatedStorage.Shared.DinoModel)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Bases = {}

-- Other services plug in here (avoids circular requires):
--   onSteal(thief, owner, egg) -> boolean   give the stolen egg to the thief
--   onGuardHit(thief)                       a guard dinosaur hit a thief
Bases.hooks = {}

local MAX_NEST_SLOTS = 14

-- bases[i] = { part, frame (CFrame facing the volcano), owner, folder, label,
--              nests = { CFrame }, lockedUntil, lockCooldownUntil, dome }
local bases = {}
local playerBase: { [Player]: any } = {}
local baseRemote = Remotes.get("BaseChanged")
local announceRemote = Remotes.get("Announce")
local knockbackRemote = Remotes.get("Knockback")
local sellLimiter = RateLimiter.new(Config.ActionCooldown)
local lockLimiter = RateLimiter.new(1)
local fullWarned: { [Player]: number } = {}

local root = Instance.new("Folder")
root.Name = "Bases"
root.Parent = workspace

local function now(): number
	return os.time()
end

local function flat(position: Vector3): Vector3
	return Vector3.new(position.X, 0, position.Z)
end

---------------------------------------------------------------------------
-- Queries used by other services
---------------------------------------------------------------------------

function Bases.getBase(player: Player)
	return playerBase[player]
end

-- True if `position` is inside the player's own base.
function Bases.isHome(player: Player, position: Vector3): boolean
	local base = playerBase[player]
	return base ~= nil and (flat(position) - flat(base.frame.Position)).Magnitude <= Config.BaseRadius
end

-- The player who owns the base at `position`, or nil.
function Bases.ownerAt(position: Vector3): Player?
	for _, base in bases do
		if base.owner and (flat(position) - flat(base.frame.Position)).Magnitude <= Config.BaseRadius then
			return base.owner
		end
	end
	return nil
end

function Bases.isLocked(player: Player): boolean
	local base = playerBase[player]
	return base ~= nil and (base.lockedUntil or 0) > now()
end

function Bases.nestCount(player: Player): number
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return 0
	end
	return math.min(MAX_NEST_SLOTS, Economy.nests(data.Upgrades.Nests, session.passes.ExtraNests == true))
end

function Bases.freeNests(player: Player): number
	local data = PlayerData.get(player)
	return if data then Bases.nestCount(player) - #data.Eggs else 0
end

function Bases.penSize(player: Player): number
	local data = PlayerData.get(player)
	return if data then Economy.penSize(data.Upgrades.Pen) else 0
end

function Bases.income(player: Player): number
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return 0
	end
	local total = 0
	for _, dino in data.Dinos do
		total += Economy.dinoIncome(dino)
	end
	if session.passes.DoubleMoney then
		total *= 2
	end
	return total
end

function Bases.findDino(player: Player, dinoId: number)
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	for index, dino in data.Dinos do
		if dino.id == dinoId then
			return dino, index
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function updateSign(base)
	if base.owner then
		local text = string.format("%s's Base\n%s/s", base.owner.DisplayName, Format.money(Bases.income(base.owner)))
		if (base.lockedUntil or 0) > now() then
			text ..= "\nLOCKED"
		end
		base.label.Text = text
	else
		base.label.Text = "Free Base"
	end
end

local function makeBillboard(parent: Instance, text: string, color: Color3, offset: number, name: string?)
	local gui = Instance.new("BillboardGui")
	gui.Name = name or "Label"
	gui.Size = UDim2.fromOffset(180, 46)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.MaxDistance = 80
	gui.Parent = parent
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	return gui
end

local function onStealTriggered(owner: Player, eggId: number, thief: Player, startedAt: { [Player]: number })
	if thief == owner then
		return
	end
	local started = startedAt[thief]
	if not started or os.clock() - started < Config.StealHoldTime - 0.3 then
		return -- hold was not long enough: exploit or lag
	end
	if Bases.isLocked(owner) then
		PlayerData.notify(thief, "This base is locked!", "error")
		return
	end
	local data = PlayerData.get(owner)
	local character = thief.Character
	local thiefRoot = character and character:FindFirstChild("HumanoidRootPart")
	local base = playerBase[owner]
	if not data or not thiefRoot or not base then
		return
	end
	if (thiefRoot.Position - base.frame.Position).Magnitude > Config.BaseRadius + 15 then
		return
	end
	for index, egg in data.Eggs do
		if egg.id == eggId then
			if Bases.hooks.onSteal and Bases.hooks.onSteal(thief, owner, egg) then
				table.remove(data.Eggs, index)
				PlayerData.notify(
					owner,
					thief.DisplayName .. " stole your " .. Dinos.displayName(egg.s, egg.t, egg.m) .. " egg!",
					"error"
				)
				Bases.refresh(owner)
			end
			return
		end
	end
end

-- Rebuilds the eggs and dinosaurs shown on the player's base.
local function refreshDisplay(player: Player)
	local base = playerBase[player]
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not base or not data or not session then
		return
	end
	base.folder:ClearAllChildren()

	-- Nest eggs, each with a hatch timer and a "Steal" prompt for others.
	for index, egg in data.Eggs do
		local nest = base.nests[index]
		if not nest then
			break
		end
		local model = DinoModel.buildEgg(egg.s, egg.t, egg.m)
		model:PivotTo(nest * CFrame.new(0, 2.2, 0))
		model:SetAttribute("HatchAt", egg.hatchAt)
		model:SetAttribute("OwnerId", player.UserId)
		model:SetAttribute("Label", Dinos.displayName(egg.s, egg.t, egg.m))
		local tier = Dinos.TierById[egg.t]
		makeBillboard(model.PrimaryPart, "", tier.color, 3, "Timer")

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Steal"
		prompt.ObjectText = Dinos.displayName(egg.s, egg.t, egg.m) .. " Egg"
		prompt.HoldDuration = Config.StealHoldTime
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = not Bases.isLocked(player)
		prompt.Parent = model.PrimaryPart
		local startedAt = {}
		prompt.PromptButtonHoldBegan:Connect(function(thief)
			startedAt[thief] = os.clock()
		end)
		prompt.Triggered:Connect(function(thief)
			onStealTriggered(player, egg.id, thief, startedAt)
		end)
		model.Name = "NestEgg"
		model.Parent = base.folder
	end

	-- Dinosaurs in the pen, best first, in a grid behind the nests.
	local sorted = {}
	for _, dino in data.Dinos do
		if dino.id ~= session.mountedId then
			table.insert(sorted, dino)
		end
	end
	table.sort(sorted, function(a, b)
		return Economy.dinoIncome(a) > Economy.dinoIncome(b)
	end)
	local columns, spacing = 7, 8.5
	for index, dino in sorted do
		local column = (index - 1) % columns
		local row = (index - 1) // columns
		local x = (column - (columns - 1) / 2) * spacing
		local z = -4 + row * 8
		local stage = Economy.stage(dino.t, dino.g)
		local model = DinoModel.build(dino.s, dino.t, dino.m, stage)
		model:PivotTo(base.frame * CFrame.new(x, 0, z))
		model.Parent = base.folder
	end
	updateSign(base)
end

function Bases.refresh(player: Player)
	refreshDisplay(player)
	local data = PlayerData.get(player)
	if data then
		baseRemote:FireClient(player, data.Dinos, data.Eggs)
	end
	PlayerData.changed(player)
end

---------------------------------------------------------------------------
-- Changing eggs and dinosaurs
---------------------------------------------------------------------------

-- Puts a delivered egg into a free nest. Returns false if nests are full.
function Bases.addEgg(player: Player, egg): boolean
	local data = PlayerData.get(player)
	if not data or Bases.freeNests(player) <= 0 then
		return false
	end
	table.insert(data.Eggs, {
		id = data.NextId,
		s = egg.s,
		t = egg.t,
		m = egg.m,
		hatchAt = now() + Economy.hatchTime(egg.t),
	})
	data.NextId += 1
	Bases.refresh(player)
	return true
end

-- Adds a dinosaur directly (stolen mounts). Ignores the pen limit so a
-- stolen dinosaur is never lost; the player just can't hatch more until they sell.
function Bases.addDino(player: Player, dino)
	local data = PlayerData.get(player)
	if not data then
		return nil
	end
	local entry = { id = data.NextId, s = dino.s, t = dino.t, m = dino.m, g = dino.g or 0 }
	data.NextId += 1
	table.insert(data.Dinos, entry)
	Bases.refresh(player)
	return entry
end

function Bases.removeDino(player: Player, dinoId: number)
	local data = PlayerData.get(player)
	local dino, index = Bases.findDino(player, dinoId)
	if data and dino then
		table.remove(data.Dinos, index)
		Bases.refresh(player)
	end
	return dino
end

local function hatchEgg(player: Player, data, index: number)
	local egg = table.remove(data.Eggs, index)
	local dino = { id = data.NextId, s = egg.s, t = egg.t, m = egg.m, g = 0 }
	data.NextId += 1
	data.Hatched += 1
	table.insert(data.Dinos, dino)
	local name = Dinos.displayName(dino.s, dino.t, dino.m)
	PlayerData.notify(player, "Your egg hatched: " .. name .. "!", "success")
	if Dinos.TierById[dino.t].index >= Config.RareEggAnnounceTier then
		announceRemote:FireAllClients(player.DisplayName .. " hatched a " .. name .. "!", Dinos.TierById[dino.t].color)
	end
end

-- Hatches eggs whose timer ran out (or all of them with `force`).
-- Returns how many hatched.
function Bases.hatchReady(player: Player, force: boolean?, limit: number?): number
	local data = PlayerData.get(player)
	if not data then
		return 0
	end
	local hatched = 0
	table.sort(data.Eggs, function(a, b)
		return a.hatchAt < b.hatchAt
	end)
	local index = 1
	while index <= #data.Eggs do
		if limit and hatched >= limit then
			break
		end
		local egg = data.Eggs[index]
		if force or egg.hatchAt <= now() then
			if #data.Dinos >= Bases.penSize(player) then
				if (fullWarned[player] or 0) < os.clock() then
					fullWarned[player] = os.clock() + 30
					PlayerData.notify(player, "Your pen is full! Sell a dinosaur or buy a Bigger Pen.", "error")
				end
				break
			end
			hatchEgg(player, data, index)
			hatched += 1
		else
			index += 1
		end
	end
	if hatched > 0 then
		Bases.refresh(player)
	end
	return hatched
end

local function onSell(player: Player, dinoId: any)
	if not sellLimiter:check(player) or type(dinoId) ~= "number" then
		return
	end
	local session = PlayerData.getSession(player)
	local data = PlayerData.get(player)
	if not session or not data or session.mountedId == dinoId then
		return
	end
	local dino = Bases.removeDino(player, dinoId)
	if dino then
		local price = Economy.sellPrice(dino)
		data.Money += price
		PlayerData.notify(
			player,
			"Sold " .. Dinos.displayName(dino.s, dino.t, dino.m) .. " for " .. Format.money(price),
			"coin"
		)
		PlayerData.changed(player)
	end
end

---------------------------------------------------------------------------
-- Lock and guards
---------------------------------------------------------------------------

local function setPromptsEnabled(base, enabled: boolean)
	for _, prompt in base.folder:GetDescendants() do
		if prompt:IsA("ProximityPrompt") then
			prompt.Enabled = enabled
		end
	end
end

local function onLock(player: Player)
	if not lockLimiter:check(player) then
		return
	end
	local base = playerBase[player]
	if not base then
		return
	end
	local t = now()
	if (base.lockCooldownUntil or 0) > t then
		PlayerData.notify(player, "Lock is recharging: " .. Format.duration(base.lockCooldownUntil - t), "error")
		return
	end
	base.lockedUntil = t + Config.LockDuration
	base.lockCooldownUntil = t + Config.LockCooldown
	setPromptsEnabled(base, false)

	local dome = Instance.new("Part")
	dome.Name = "LockDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(1, 1, 1) * Config.BaseRadius * 2
	dome.CFrame = base.frame
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanTouch = false
	dome.CanQuery = false
	dome.Material = Enum.Material.ForceField
	dome.Color = Color3.fromRGB(90, 170, 255)
	dome.Parent = root
	base.dome = dome
	updateSign(base)
	PlayerData.notify(player, "Base locked for " .. Config.LockDuration .. " seconds!", "success")
	PlayerData.changed(player)

	task.delay(Config.LockDuration, function()
		if base.dome == dome then
			dome:Destroy()
			base.dome = nil
			setPromptsEnabled(base, true)
			updateSign(base)
		end
	end)
end

-- Pushes `target` away from the base center.
local function pushOut(base, target: Player)
	local character = target.Character
	local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		return
	end
	local away = flat(targetRoot.Position) - flat(base.frame.Position)
	if away.Magnitude < 0.1 then
		away = base.frame.LookVector
	end
	knockbackRemote:FireClient(target, away.Unit * Config.Knockback * 1.3 + Vector3.new(0, 30, 0))
end

local function guardTick()
	for _, base in bases do
		local owner = base.owner
		local data = owner and PlayerData.get(owner)
		local session = owner and PlayerData.getSession(owner)
		if data and session then
			local locked = (base.lockedUntil or 0) > now()
			local adults = 0
			for _, dino in data.Dinos do
				if dino.id ~= session.mountedId and Economy.stage(dino.t, dino.g) == 3 then
					adults += 1
				end
			end
			-- More adult dinosaurs = more likely to catch a thief each tick.
			-- Never 100%, so stealing stays possible. A locked base always pushes.
			local chance = if locked then 1 else math.min(0.1 + adults * 0.08, 0.75)
			if adults > 0 or locked then
				for _, other in Players:GetPlayers() do
					local character = other.Character
					local otherRoot = character and character:FindFirstChild("HumanoidRootPart")
					if
						other ~= owner
						and otherRoot
						and Bases.isHome(owner, otherRoot.Position)
						and math.random() < chance
					then
						pushOut(base, other)
						if Bases.hooks.onGuardHit then
							Bases.hooks.onGuardHit(other)
						end
						if not locked then
							PlayerData.notify(other, owner.DisplayName .. "'s dinosaurs chased you away!", "error")
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Plots, spawning and the game loop
---------------------------------------------------------------------------

local function spawnAtBase(player: Player, character: Model)
	local base = playerBase[player]
	if not base then
		return
	end
	local characterRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not characterRoot or playerBase[player] ~= base then
		return
	end
	task.wait()
	character:PivotTo(base.frame * CFrame.new(0, 4, -Config.BaseRadius + 6))
end

local function assignBase(player: Player)
	for _, base in bases do
		if not base.owner then
			base.owner = player
			playerBase[player] = base
			base.part:SetAttribute("OwnerId", player.UserId)
			refreshDisplay(player)
			if player.Character then
				task.spawn(spawnAtBase, player, player.Character)
			end
			return
		end
	end
	warn("[Bases] No free base for " .. player.Name .. ". Set the server size to the number of BasePlot parts.")
end

local function releaseBase(player: Player)
	local base = playerBase[player]
	playerBase[player] = nil
	if base then
		base.owner = nil
		base.folder:ClearAllChildren()
		base.part:SetAttribute("OwnerId", nil)
		if base.dome then
			base.dome:Destroy()
			base.dome = nil
		end
		base.lockedUntil = nil
		base.lockCooldownUntil = nil
		updateSign(base)
	end
end

local function setupBase(part: BasePart)
	local center = part.Position + Vector3.new(0, part.Size.Y / 2, 0)
	-- -Z of the base frame points at the volcano (the map center).
	local volcano = Vector3.new(0, center.Y, 0)
	local frame = if (volcano - center).Magnitude > 1 then CFrame.lookAt(center, volcano) else CFrame.new(center)

	local folder = Instance.new("Folder")
	folder.Name = "Base" .. tostring(part:GetAttribute("BaseIndex") or #bases + 1)
	folder.Parent = root

	-- Static nests in two rows at the front of the base.
	local nests = {}
	local nestFolder = Instance.new("Folder")
	nestFolder.Name = folder.Name .. "Nests"
	nestFolder.Parent = root
	for i = 1, MAX_NEST_SLOTS do
		local row = if i <= 7 then 0 else 1
		local column = (i - 1) % 7
		local nestFrame = frame * CFrame.new((column - 3) * 7, 0, -24 + row * 8)
		table.insert(nests, nestFrame)
		local nest = Instance.new("Part")
		nest.Name = "Nest"
		nest.Shape = Enum.PartType.Cylinder
		nest.Size = Vector3.new(0.8, 5, 5)
		nest.CFrame = nestFrame * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
		nest.Anchored = true
		nest.Material = Enum.Material.Grass
		nest.Color = Color3.fromRGB(140, 100, 55)
		nest.Parent = nestFolder
	end

	local anchor = Instance.new("Part")
	anchor.Name = "BaseSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = frame * CFrame.new(0, 14, -Config.BaseRadius)
	anchor.Parent = nestFolder
	local gui = makeBillboard(anchor, "Free Base", Color3.new(1, 1, 1), 0)
	gui.Size = UDim2.fromOffset(280, 90)
	gui.MaxDistance = 300

	local base = { part = part, frame = frame, owner = nil, folder = folder, label = gui.Text, nests = nests }
	table.insert(bases, base)
	table.sort(bases, function(a, b)
		return (a.part:GetAttribute("BaseIndex") or 0) < (b.part:GetAttribute("BaseIndex") or 0)
	end)
	updateSign(base)
	return nil
end

local function giveOfflineIncome(player: Player)
	local data = PlayerData.get(player)
	if not data or data.LastSeen <= 0 then
		return
	end
	local away = math.min(now() - data.LastSeen, Config.OfflineIncomeMaxHours * 3600)
	if away < 60 then
		return
	end
	local amount = math.floor(Bases.income(player) * away * Config.OfflineIncomeShare)
	if amount > 0 then
		data.Money += amount
		PlayerData.notify(player, "Your dinosaurs earned " .. Format.money(amount) .. " while you were away!", "coin")
	end
end

-- Runs every second: income, growth and hatching.
local function tick()
	for player, data in PlayerData.all() do
		local session = PlayerData.getSession(player)
		if session then
			data.Money += Bases.income(player)

			local growStep = if session.passes.DoubleGrowth then 2 else 1
			local grewUp = false
			for _, dino in data.Dinos do
				local before = Economy.stage(dino.t, dino.g)
				if before < 3 then
					dino.g += growStep
					local after = Economy.stage(dino.t, dino.g)
					if after > before then
						grewUp = true
						local name = Dinos.displayName(dino.s, dino.t, dino.m)
						if after == 3 then
							PlayerData.notify(
								player,
								"Your " .. name .. " is an adult! You can ride it now.",
								"success"
							)
						else
							PlayerData.notify(player, "Your " .. name .. " grew bigger!", "success")
						end
					end
				end
			end

			if Bases.hatchReady(player) == 0 and grewUp then
				Bases.refresh(player)
			else
				PlayerData.changed(player)
			end
		end
	end
end

function Bases.start()
	Tagged(Config.Tags.BasePlot, function(instance)
		if instance:IsA("BasePart") then
			return setupBase(instance)
		end
		warn("[Bases] 'BasePlot' tag must be on a Part: " .. instance:GetFullName())
		return nil
	end)

	PlayerData.addStateProvider(function(player, state)
		local data = PlayerData.get(player)
		local base = playerBase[player]
		state.income = Bases.income(player)
		state.nests = Bases.nestCount(player)
		state.penSize = Bases.penSize(player)
		state.dinoCount = if data then #data.Dinos else 0
		state.eggCount = if data then #data.Eggs else 0
		state.lockedLeft = if base then math.max(0, (base.lockedUntil or 0) - now()) else 0
		state.lockCooldownLeft = if base then math.max(0, (base.lockCooldownUntil or 0) - now()) else 0
	end)

	PlayerData.ProfileLoaded:Connect(function(player)
		giveOfflineIncome(player)
		assignBase(player)
		Bases.hatchReady(player)
		Bases.refresh(player)
	end)

	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawnAtBase(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releaseBase(player)
		sellLimiter:forget(player)
		lockLimiter:forget(player)
		fullWarned[player] = nil
	end)

	Remotes.get("SellDino").OnServerEvent:Connect(onSell)
	Remotes.get("LockBase").OnServerEvent:Connect(onLock)

	task.spawn(function()
		while true do
			task.wait(1)
			tick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.GuardInterval)
			guardTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, base in bases do
				updateSign(base)
			end
		end
	end)
end

return Bases
