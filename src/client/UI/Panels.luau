-- Panels.luau
-- Pop-up windows opened from the menu: Dinos, Upgrades, Shop and Odds.
-- Contents are rebuilt from the latest server data whenever it changes.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)
local Style = require(script.Parent.Style)

local Panels = {}
Panels.__index = Panels

local player = Players.LocalPlayer

-- What each Robux item does, shown in the Shop.
local SHOP_ITEMS = {
	{ kind = "pass", key = "DoubleMoney", name = "x2 Money", description = "All your dinosaurs earn twice as much" },
	{ kind = "pass", key = "DoubleGrowth", name = "x2 Growth", description = "Dinosaurs grow up twice as fast" },
	{ kind = "pass", key = "ExtraNests", name = "+3 Nests", description = "Hatch more eggs at once" },
	{
		kind = "pass",
		key = "SaddleLock",
		name = "Saddle Lock",
		description = "If you die, only you can saddle your dinosaur for 5 min",
	},
	{ kind = "product", key = "InstantHatch", name = "Instant Hatch", description = "Hatch your next egg right now" },
	{ kind = "product", key = "HatchAll", name = "Hatch All", description = "Hatch every egg in your nests" },
	{
		kind = "product",
		key = "ServerLuck",
		name = "Server Luck",
		description = "Rarer eggs for EVERYONE for 10 minutes",
	},
	{
		kind = "product",
		key = "BigEruption",
		name = "Big Eruption",
		description = "Wake the volcano: big eruption in 15 s",
	},
	{ kind = "product", key = "CashSmall", name = "Cash Pack", description = "10 minutes of your income" },
	{ kind = "product", key = "CashLarge", name = "Big Cash Pack", description = "2 hours of your income" },
}

local priceCache: { [string]: string } = {}

local function corner(): UICorner
	return Create("UICorner", { CornerRadius = Theme.Corner })
end

local function text(parent: Instance, props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = parent,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Create("TextLabel", defaults)
end

local function smallButton(parent: Instance, props, onClick)
	local defaults = {
		BackgroundColor3 = Theme.Accent,
		Font = Theme.BoldFont,
		TextColor3 = Theme.Text,
		TextSize = 14,
		Parent = parent,
	}
	for key, value in props do
		defaults[key] = value
	end
	local instance = Create("TextButton", defaults, { corner() })
	Style.button(instance)
	instance.Activated:Connect(onClick)
	return instance
end

-- A row frame inside the list.
local function row(list: Instance, order: number, height: number?)
	return Create("Frame", {
		Size = UDim2.new(1, -6, 0, height or 56),
		BackgroundColor3 = Theme.Panel,
		LayoutOrder = order,
		Parent = list,
	}, { corner() })
end

-- actions = { sell(id), ride(id), buyUpgrade(id) }
function Panels.new(screenGui: ScreenGui, actions)
	local self = setmetatable({}, Panels)
	self.actions = actions
	self.current = nil
	self.state = nil
	self.dinos = {}
	self.eggs = {}

	self.frame = Create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.new(0, 440, 0.7, 0),
		BackgroundColor3 = Theme.Background,
		Visible = false,
		Parent = screenGui,
	}, {
		corner(),
		Create("UIStroke", { Color = Color3.fromRGB(12, 14, 22), Thickness = 3 }),
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 175, 205)),
		}),
		Create("UISizeConstraint", { MaxSize = Vector2.new(440, 560) }),
	})
	self.title = text(self.frame, {
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(1, -60, 0, 32),
		Font = Theme.BoldFont,
		TextSize = 22,
	})
	smallButton(self.frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.new(0, 34, 0, 34),
		Text = "X",
		BackgroundColor3 = Theme.Error,
	}, function()
		self:close()
	end)
	self.list = Create("ScrollingFrame", {
		Position = UDim2.new(0, 10, 0, 48),
		Size = UDim2.new(1, -20, 1, -58),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = self.frame,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	return self
end

function Panels:open(name: string)
	if self.current == name then
		self:close()
		return
	end
	self.current = name
	self.frame.Visible = true
	Style.popIn(self.frame)
	self.list.CanvasPosition = Vector2.zero
	self:refresh()
end

function Panels:close()
	self.current = nil
	self.frame.Visible = false
end

function Panels:setState(state)
	self.state = state
	if self.current then
		self:refresh()
	end
end

function Panels:setBase(dinos, eggs)
	self.dinos = dinos or {}
	self.eggs = eggs or {}
	if self.current then
		self:refresh()
	end
end

function Panels:refresh()
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.title.Text = self.current or ""
	if not self.state then
		return
	end
	if self.current == "Dinos" then
		self:buildDinos()
	elseif self.current == "Upgrades" then
		self:buildUpgrades()
	elseif self.current == "Shop" then
		self:buildShop()
	elseif self.current == "Odds" then
		self:buildOdds()
	end
end

function Panels:buildDinos()
	local state = self.state
	local order = 0
	local now = workspace:GetServerTimeNow()

	if #self.eggs > 0 then
		order += 1
		text(
			self.list,
			{ Text = "Eggs in your nests", Font = Theme.BoldFont, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order }
		)
		for _, egg in self.eggs do
			order += 1
			local left = egg.hatchAt - now
			local tier = Dinos.TierById[egg.t]
			text(self.list, {
				Text = Dinos.displayName(egg.s, egg.t, egg.m) .. " egg - " .. (if left > 0
					then "hatches in " .. Format.duration(left)
					else "ready (pen full?)"),
				TextColor3 = tier.color,
				Size = UDim2.new(1, 0, 0, 20),
				LayoutOrder = order,
			})
		end
	end

	order += 1
	text(self.list, {
		Text = string.format("Your dinosaurs (%d/%d)", #self.dinos, state.penSize or 0),
		Font = Theme.BoldFont,
		Size = UDim2.new(1, 0, 0, 24),
		LayoutOrder = order,
	})
	if #self.dinos == 0 then
		order += 1
		text(self.list, {
			Text = "No dinosaurs yet! Grab eggs that fly out of the volcano and bring them to your nests.",
			TextColor3 = Theme.MutedText,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = order,
		})
		return
	end

	local sorted = table.clone(self.dinos)
	table.sort(sorted, function(a, b)
		return Economy.dinoIncome(a) > Economy.dinoIncome(b)
	end)
	local busy = state.riding ~= nil or state.mountOut
	for _, dino in sorted do
		order += 1
		local item = row(self.list, order, 62)
		local tier = Dinos.TierById[dino.t]
		local stage = Economy.stage(dino.t, dino.g)
		local stageText = Dinos.Stages[stage].id
		if stage < 3 then
			local step = if state.passes and state.passes.DoubleGrowth then 2 else 1
			stageText ..= " - grows in " .. Format.duration(Economy.growthLeft(dino.t, dino.g) / step)
		end
		text(item, {
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -170, 0, 22),
			Font = Theme.BoldFont,
			TextColor3 = tier.color,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = Dinos.displayName(dino.s, dino.t, dino.m),
		})
		text(item, {
			Position = UDim2.new(0, 10, 0, 28),
			Size = UDim2.new(1, -170, 0, 30),
			TextSize = 13,
			TextColor3 = Theme.MutedText,
			Text = stageText .. "\n" .. Format.money(Economy.dinoIncome(dino)) .. "/s",
		})
		local canRide = stage == 3 and not busy
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -90, 0.5, 0),
			Size = UDim2.new(0, 70, 0, 36),
			Text = "Ride",
			BackgroundColor3 = if canRide then Theme.Success else Theme.Panel,
			TextColor3 = if canRide then Theme.Text else Theme.MutedText,
		}, function()
			if canRide then
				self.actions.ride(dino.id)
				self:close()
			end
		end)
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 76, 0, 36),
			Text = "Sell " .. Format.money(Economy.sellPrice(dino)),
			TextScaled = true,
			BackgroundColor3 = Theme.Error,
		}, function()
			self.actions.sell(dino.id)
		end)
	end
end

function Panels:buildUpgrades()
	local state = self.state
	for order, upgradeId in Economy.UpgradeOrder do
		local upgrade = Economy.Upgrades[upgradeId]
		local level = state.upgrades and state.upgrades[upgradeId] or 0
		local cost = Economy.upgradeCost(upgradeId, level)
		local item = row(self.list, order, 64)
		text(item, {
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -130, 0, 24),
			Font = Theme.BoldFont,
			Text = string.format("%s  (Lv %d/%d)", upgrade.name, level, upgrade.maxLevel),
		})
		text(item, {
			Position = UDim2.new(0, 10, 0, 30),
			Size = UDim2.new(1, -130, 0, 28),
			TextSize = 13,
			TextColor3 = Theme.MutedText,
			Text = upgrade.description,
		})
		local affordable = cost ~= nil and (state.money or 0) >= cost
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 110, 0, 40),
			Text = if cost then Format.money(cost) else "MAX",
			BackgroundColor3 = if affordable then Theme.Success else Theme.Panel,
		}, function()
			if cost then
				self.actions.buyUpgrade(upgradeId)
			end
		end)
	end
end

local function loadPrice(kind: string, id: number, onLoaded: () -> ())
	local key = kind .. id
	if priceCache[key] then
		return
	end
	priceCache[key] = "..."
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(
				id,
				if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
			)
		end)
		priceCache[key] = if ok and info and info.PriceInRobux then "R$ " .. info.PriceInRobux else "Buy"
		onLoaded()
	end)
end

function Panels:buildShop()
	local passes = self.state.passes or {}
	for order, entry in SHOP_ITEMS do
		local id = if entry.kind == "pass" then Config.GamePasses[entry.key] else Config.Products[entry.key]
		local owned = entry.kind == "pass" and passes[entry.key]
		local item = row(self.list, order, 60)
		text(item, {
			Position = UDim2.new(0, 10, 0, 4),
			Size = UDim2.new(1, -120, 0, 22),
			Font = Theme.BoldFont,
			TextColor3 = if entry.kind == "pass" then Theme.Gold else Theme.Text,
			Text = entry.name,
		})
		text(item, {
			Position = UDim2.new(0, 10, 0, 28),
			Size = UDim2.new(1, -120, 0, 28),
			TextSize = 13,
			TextColor3 = Theme.MutedText,
			Text = entry.description,
		})
		local label
		if owned then
			label = "Owned"
		elseif id == 0 then
			label = "Coming soon"
		else
			loadPrice(entry.kind, id, function()
				if self.current == "Shop" then
					self:refresh()
				end
			end)
			label = priceCache[entry.kind .. id] or "Buy"
		end
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 100, 0, 38),
			Text = label,
			BackgroundColor3 = if owned or id == 0 then Theme.Panel else Theme.Success,
		}, function()
			if owned or id == 0 then
				return
			end
			if entry.kind == "pass" then
				MarketplaceService:PromptGamePassPurchase(player, id)
			else
				MarketplaceService:PromptProductPurchase(player, id)
			end
		end)
	end
end

-- Exact chances, as required by Roblox rules for paid random items.
function Panels:buildOdds()
	local luck = if (self.state.serverLuckLeft or 0) > 0 then Config.ServerLuckMultiplier else 1
	local order = 0
	local function line(value: string, color: Color3?, bold: boolean?)
		order += 1
		text(self.list, {
			Text = value,
			TextColor3 = color or Theme.Text,
			Font = if bold then Theme.BoldFont else Theme.Font,
			Size = UDim2.new(1, 0, 0, 20),
			LayoutOrder = order,
		})
	end
	line(
		"Eggs closer to the volcano are rarer." .. (if luck > 1 then " Server luck is ON (x2)." else ""),
		Theme.MutedText
	)
	local ringNames = {
		Outer = "Outer ring (far from the volcano)",
		Middle = "Middle ring",
		Inner = "Inner ring (next to the volcano)",
		Big = "Big eruption special egg",
	}
	for _, ring in Dinos.RingOrder do
		line(ringNames[ring], Theme.Gold, true)
		for _, entry in Dinos.tierOdds(ring, luck) do
			line("   " .. entry.id .. ": " .. Format.percent(entry.chance), Dinos.TierById[entry.id].color)
		end
	end
	line("Mutations (any egg)", Theme.Gold, true)
	for _, entry in Dinos.mutationOdds(luck) do
		line("   " .. entry.id .. ": " .. Format.percent(entry.chance))
	end
	line("Species: each of the " .. #Dinos.SpeciesOrder .. " species has an equal chance.", Theme.MutedText)
end

return Panels
