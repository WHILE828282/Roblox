-- Shop.luau
-- Upgrades bought with in-game money, gamepasses and Robux products.
-- Robux purchases go through MarketplaceService.ProcessReceipt, which
-- remembers every purchase id so a reward is never given twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local Bases = require(script.Parent.Bases)
local Eggs = require(script.Parent.Eggs)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)

local Shop = {}

local announceRemote = Remotes.get("Announce")
local upgradeLimiter = RateLimiter.new(Config.ActionCooldown)

local function onBuyUpgrade(player: Player, upgradeId: any)
	if not upgradeLimiter:check(player) or type(upgradeId) ~= "string" or not Economy.Upgrades[upgradeId] then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	local level = data.Upgrades[upgradeId]
	local cost = Economy.upgradeCost(upgradeId, level)
	if not cost then
		PlayerData.notify(player, "Already maxed out!", "info")
		return
	end
	if data.Money < cost then
		PlayerData.notify(player, "Not enough money!", "error")
		return
	end
	data.Money -= cost
	data.Upgrades[upgradeId] = level + 1
	PlayerData.notify(
		player,
		Economy.Upgrades[upgradeId].name .. " upgraded to level " .. (level + 1) .. "!",
		"success"
	)
	Bases.refresh(player)
end

---------------------------------------------------------------------------
-- Gamepasses
---------------------------------------------------------------------------

local passById = {}
for name, id in Config.GamePasses do
	if id ~= 0 then
		passById[id] = name
	end
end

local function loadPasses(player: Player)
	local session = PlayerData.getSession(player)
	if not session then
		return
	end
	for name, id in Config.GamePasses do
		if id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok and owns then
				session.passes[name] = true
			elseif not ok then
				warn("[Shop] Gamepass check failed for " .. name .. ": " .. tostring(owns))
			end
		end
	end
	Bases.refresh(player)
end

---------------------------------------------------------------------------
-- Developer products (can be bought many times)
---------------------------------------------------------------------------

local function grantCash(player: Player, productName: string)
	local data = PlayerData.get(player)
	local amount = math.max(
		Config.CashMinimum[productName],
		math.floor(Bases.income(player) * 60 * Config.CashMinutes[productName])
	)
	data.Money += amount
	PlayerData.notify(player, "+" .. Format.money(amount) .. "!", "coin")
end

-- Each handler gives the reward; it must not yield for long.
local productHandlers = {
	InstantHatch = function(player: Player)
		if Bases.hatchReady(player, true, 1) == 0 then
			-- Nothing to hatch (bought in a race): compensate with cash.
			grantCash(player, "CashSmall")
		end
	end,
	HatchAll = function(player: Player)
		if Bases.hatchReady(player, true) == 0 then
			grantCash(player, "CashSmall")
		end
	end,
	ServerLuck = function(player: Player)
		Eggs.boostServerLuck(Config.ServerLuckDuration)
		announceRemote:FireAllClients(
			player.DisplayName .. " boosted egg luck for EVERYONE for 10 minutes!",
			Color3.fromRGB(120, 255, 140)
		)
	end,
	BigEruption = function(player: Player)
		Eggs.triggerBigEruption()
		announceRemote:FireAllClients(
			player.DisplayName .. " woke up the volcano! BIG ERUPTION soon!",
			Color3.fromRGB(255, 120, 40)
		)
	end,
	CashSmall = function(player: Player)
		grantCash(player, "CashSmall")
	end,
	CashLarge = function(player: Player)
		grantCash(player, "CashLarge")
	end,
}

local handlerById = {}
for name, id in Config.Products do
	if id ~= 0 then
		handlerById[id] = productHandlers[name]
	end
end

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local data = player and PlayerData.get(player)
	if not player or not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries later
	end
	if table.find(data.Purchases, receipt.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already rewarded
	end
	local handler = handlerById[receipt.ProductId]
	if not handler then
		warn("[Shop] Unknown product id " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, err = pcall(handler, player)
	if not ok then
		warn("[Shop] Product handler failed: " .. tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	table.insert(data.Purchases, receipt.PurchaseId)
	while #data.Purchases > 50 do
		table.remove(data.Purchases, 1)
	end
	PlayerData.changed(player)
	-- Only confirm once the purchase id is safely saved. If saving fails,
	-- Roblox retries and the purchase id above prevents a double reward.
	if PlayerData.canSave(player) and not PlayerData.save(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Shop.start()
	Remotes.get("BuyUpgrade").OnServerEvent:Connect(onBuyUpgrade)

	PlayerData.addStateProvider(function(player, state)
		local session = PlayerData.getSession(player)
		state.passes = if session then session.passes else {}
	end)

	PlayerData.ProfileLoaded:Connect(loadPasses)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		local name = passById[passId]
		local session = PlayerData.getSession(player)
		if purchased and name and session then
			session.passes[name] = true
			PlayerData.notify(player, "Thanks for your purchase!", "success")
			Bases.refresh(player)
		end
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	Players.PlayerRemoving:Connect(function(player)
		upgradeLimiter:forget(player)
	end)
end

return Shop
