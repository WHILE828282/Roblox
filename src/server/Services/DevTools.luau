-- DevTools.luau
-- Test commands for Roblox Studio ONLY. On a live server this module does
-- nothing (RunService:IsStudio() is false there and cannot be faked by clients).
--
-- In Studio, while the game is running, switch the command bar to the server
-- and call for example:
--   local dev = game.ServerScriptService.DevCommand
--   dev:Invoke("fast", 20)                              -- hatch and grow 20x faster
--   dev:Invoke("money", game.Players.YourName, 100000)
--   dev:Invoke("nestEgg", game.Players.YourName, "TRex", "Legendary", "Golden")
--   dev:Invoke("giveDino", game.Players.YourName, "Raptor", "Common", "Normal", 9999)
--   dev:Invoke("erupt", true)                           -- big eruption now

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Dinos = require(ReplicatedStorage.Shared.Dinos)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local Eggs = require(script.Parent.Eggs)
local Mounts = require(script.Parent.Mounts)
local Combat = require(script.Parent.Combat)

local DevTools = {}

local originalTimes = nil

local commands = {}

-- Divides every hatch and growth time by `factor` (1 restores the real values).
function commands.fast(factor: number)
	if not originalTimes then
		originalTimes = {}
		for _, tier in Dinos.Tiers do
			originalTimes[tier.id] = { hatch = tier.hatch, grow = tier.grow }
		end
	end
	for _, tier in Dinos.Tiers do
		tier.hatch = math.max(1, originalTimes[tier.id].hatch / factor)
		tier.grow = math.max(1, originalTimes[tier.id].grow / factor)
	end
	return true
end

function commands.money(player: Player, amount: number)
	local data = PlayerData.get(player)
	data.Money += amount
	PlayerData.changed(player)
	return data.Money
end

-- Egg in the player's hands.
function commands.giveEgg(player: Player, species: string, tier: string, mutation: string?)
	Eggs.carry(player, { s = species, t = tier, m = mutation or "Normal" })
	return Eggs.carryCount(player)
end

-- Egg straight into a nest.
function commands.nestEgg(player: Player, species: string, tier: string, mutation: string?)
	return Bases.addEgg(player, { s = species, t = tier, m = mutation or "Normal" })
end

function commands.giveDino(player: Player, species: string, tier: string, mutation: string?, growth: number?)
	local entry = Bases.addDino(player, { s = species, t = tier, m = mutation or "Normal", g = growth or 0 })
	return entry and entry.id
end

function commands.erupt(big: boolean?)
	Eggs.eruptNow(big == true)
	return true
end

function commands.unprotect(player: Player)
	Combat.clearProtection(player)
	return true
end

function commands.save(player: Player)
	return PlayerData.save(player)
end

-- True if the player's data would survive a save + load unchanged.
function commands.roundTrip(player: Player)
	return PlayerData.roundTripOk(player)
end

-- A text summary of what the server knows about the player.
function commands.state(player: Player)
	local data = PlayerData.get(player)
	if not data then
		return "no profile"
	end
	local ride = Mounts.getRide(player)
	local dinos = {}
	for _, dino in data.Dinos do
		table.insert(dinos, string.format("#%d %s/%s/%s g=%d", dino.id, dino.s, dino.t, dino.m, dino.g))
	end
	local eggs = {}
	for _, egg in data.Eggs do
		table.insert(eggs, string.format("#%d %s/%s/%s in %ds", egg.id, egg.s, egg.t, egg.m, egg.hatchAt - os.time()))
	end
	return string.format(
		"money=%d income=%.1f hatched=%d carrying=%d riding=%s stolen=%s canSave=%s\n dinos: %s\n eggs: %s",
		data.Money,
		Bases.income(player),
		data.Hatched,
		Eggs.carryCount(player),
		if ride then ride.dino.s else "-",
		tostring(ride ~= nil and ride.stolen),
		tostring(PlayerData.canSave(player)),
		table.concat(dinos, ", "),
		table.concat(eggs, ", ")
	)
end

function DevTools.start()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DevCommand"
	bindable.OnInvoke = function(command: string, ...)
		local handler = commands[command]
		if not handler then
			return "Unknown dev command: " .. tostring(command)
		end
		return handler(...)
	end
	bindable.Parent = ServerScriptService
end

return DevTools
