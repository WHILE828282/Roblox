-- Panels.luau
-- Pop-up windows: Trails (the trail shop), Shop (upgrades and selling
-- creatures) and Index (every creature you have discovered).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Sea = require(ReplicatedStorage.Shared.Sea)
local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)
local Style = require(script.Parent.Style)

local Panels = {}
Panels.__index = Panels

local OUTLINE = Color3.fromRGB(12, 14, 22)
local TITLES = { Trails = "Trail Shop", Shop = "Shop", Index = "Sea Index" }

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
	local defaults = { BackgroundColor3 = Theme.Success, Font = Theme.BoldFont, TextColor3 = Theme.Text, TextSize = 15, Parent = parent }
	for key, value in props do
		defaults[key] = value
	end
	local instance = Create("TextButton", defaults, { corner() })
	Style.button(instance)
	instance.Activated:Connect(onClick)
	return instance
end

local function row(list: Instance, order: number, height: number)
	return Create("Frame", {
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = Theme.Panel,
		LayoutOrder = order,
		Parent = list,
	}, { corner(), Create("UIStroke", { Color = OUTLINE, Thickness = 2 }) })
end

-- actions = { buyTrail(id), equipTrail(id), upgradeTreadmill(), upgradeAquarium(), sell(id) }
function Panels.new(screenGui: ScreenGui, actions)
	local self = setmetatable({}, Panels)
	self.actions = actions
	self.current = nil
	self.state = nil

	self.frame = Create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.92, 0, 0.72, 0),
		BackgroundColor3 = Theme.Background,
		Visible = false,
		ZIndex = 3,
		Parent = screenGui,
	}, {
		corner(),
		Create("UIStroke", { Color = OUTLINE, Thickness = 3 }),
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 178, 215)) }),
		Create("UISizeConstraint", { MaxSize = Vector2.new(470, 560) }),
	})
	self.title = text(self.frame, { Position = UDim2.new(0, 16, 0, 8), Size = UDim2.new(1, -70, 0, 36), Font = Theme.BoldFont, TextSize = 26 })
	Style.text(self.title, 2)
	smallButton(self.frame, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(38, 38),
		Text = "X",
		BackgroundColor3 = Theme.Error,
	}, function()
		self:close()
	end)
	self.list = Create("ScrollingFrame", {
		Position = UDim2.new(0, 10, 0, 52),
		Size = UDim2.new(1, -20, 1, -62),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = self.frame,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		Create("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3) }),
	})
	return self
end

function Panels:open(name: string, keepOpen: boolean?)
	if self.current == name and not keepOpen then
		self:close()
		return
	end
	self.current = name
	self.frame.Visible = true
	self.list.CanvasPosition = Vector2.zero
	Style.popIn(self.frame)
	self:refresh()
end

function Panels:close()
	self.current = nil
	self.frame.Visible = false
end

function Panels:setState(state)
	local old = self.state
	self.state = state
	-- Rebuild only when something shown in the open window changed.
	if self.current and (not old or self:signature(old) ~= self:signature(state)) then
		self:refresh()
	end
end

function Panels:signature(state): string
	local parts = { self.current, math.floor(state.money or 0) }
	if self.current == "Trails" then
		table.insert(parts, #(state.trails or {}))
		table.insert(parts, tostring(state.trail))
	elseif self.current == "Shop" then
		table.insert(parts, state.treadmill)
		table.insert(parts, state.aquarium)
		table.insert(parts, #(state.creatures or {}))
	else
		local count = 0
		for _ in state.index or {} do
			count += 1
		end
		parts = { self.current, count }
	end
	return table.concat(parts, "|")
end

function Panels:refresh()
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	self.title.Text = TITLES[self.current] or ""
	if not self.state then
		return
	end
	if self.current == "Trails" then
		self:buildTrails()
	elseif self.current == "Shop" then
		self:buildShop()
	elseif self.current == "Index" then
		self:buildIndex()
	end
end

function Panels:buildTrails()
	local state = self.state
	text(self.list, {
		Text = "Trails glow behind you and make the treadmill train Speed faster.",
		TextColor3 = Theme.MutedText,
		Size = UDim2.new(1, -8, 0, 36),
		LayoutOrder = 0,
	})
	for order, trail in Sea.Trails do
		local owned = table.find(state.trails or {}, trail.id) ~= nil
		local equipped = state.trail == trail.id
		local item = row(self.list, order, 66)
		-- Preview stripe in the trail's colors.
		Create("Frame", {
			Position = UDim2.new(0, 10, 0.5, -22),
			Size = UDim2.fromOffset(44, 44),
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = item,
		}, {
			corner(),
			Create("UIStroke", { Color = OUTLINE, Thickness = 2 }),
			Create("UIGradient", { Rotation = 45, Color = ColorSequence.new(trail.colors[1], trail.colors[2]) }),
		})
		text(item, { Position = UDim2.new(0, 64, 0, 8), Size = UDim2.new(1, -200, 0, 24), Font = Theme.BoldFont, TextSize = 19, Text = trail.name })
		text(item, {
			Position = UDim2.new(0, 64, 0, 34),
			Size = UDim2.new(1, -200, 0, 22),
			TextColor3 = Theme.Gold,
			Text = "Treadmill x" .. trail.multiplier,
		})
		local affordable = (state.money or 0) >= trail.price
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(118, 44),
			Text = if equipped then "EQUIPPED" elseif owned then "EQUIP" else Format.money(trail.price),
			BackgroundColor3 = if equipped then Theme.Accent elseif owned or affordable then Theme.Success else Theme.Panel,
		}, function()
			if owned then
				self.actions.equipTrail(trail.id)
			else
				self.actions.buyTrail(trail.id)
			end
		end)
	end
end

function Panels:buildShop()
	local state = self.state
	local upgrades = {
		{
			name = "Treadmill",
			level = state.treadmill or 0,
			max = Config.TreadmillMaxLevel,
			cost = Config.treadmillCost(state.treadmill or 0),
			info = string.format("+%.2f Speed per second", Config.treadmillRate(state.treadmill or 0) * Sea.trailMultiplier(state.trail)),
			action = self.actions.upgradeTreadmill,
		},
		{
			name = "Aquarium",
			level = state.aquarium or 0,
			max = Config.AquariumMaxLevel,
			cost = Config.aquariumCost(state.aquarium or 0),
			info = "Holds " .. Config.aquariumSize(state.aquarium or 0) .. " creatures",
			action = self.actions.upgradeAquarium,
		},
	}
	for order, upgrade in upgrades do
		local item = row(self.list, order, 66)
		text(item, {
			Position = UDim2.new(0, 12, 0, 8),
			Size = UDim2.new(1, -150, 0, 24),
			Font = Theme.BoldFont,
			TextSize = 19,
			Text = string.format("%s  Lv %d/%d", upgrade.name, upgrade.level, upgrade.max),
		})
		text(item, { Position = UDim2.new(0, 12, 0, 34), Size = UDim2.new(1, -150, 0, 22), TextColor3 = Theme.MutedText, Text = upgrade.info })
		local affordable = upgrade.cost ~= nil and (state.money or 0) >= upgrade.cost
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(118, 44),
			Text = if upgrade.cost then Format.money(upgrade.cost) else "MAX",
			BackgroundColor3 = if affordable then Theme.Success else Theme.Panel,
		}, upgrade.action)
	end

	local creatures = state.creatures or {}
	text(self.list, {
		Text = string.format("Your aquarium (%d/%d)", #creatures, state.aquariumSize or 0),
		Font = Theme.BoldFont,
		TextSize = 18,
		Size = UDim2.new(1, -8, 0, 28),
		LayoutOrder = 10,
	})
	if #creatures == 0 then
		text(self.list, {
			Text = "Empty! Dive into the ocean, steal an egg and bring it to your base.",
			TextColor3 = Theme.MutedText,
			Size = UDim2.new(1, -8, 0, 40),
			LayoutOrder = 11,
		})
	end
	local sorted = table.clone(creatures)
	table.sort(sorted, function(a, b)
		return Sea.Creatures[a.c].income > Sea.Creatures[b.c].income
	end)
	for order, entry in sorted do
		local creature = Sea.Creatures[entry.c]
		local item = row(self.list, 20 + order, 52)
		text(item, {
			Position = UDim2.new(0, 12, 0, 4),
			Size = UDim2.new(1, -150, 0, 24),
			Font = Theme.BoldFont,
			TextSize = 17,
			TextColor3 = Sea.RarityById[creature.rarity].color,
			Text = creature.name,
		})
		text(item, {
			Position = UDim2.new(0, 12, 0, 27),
			Size = UDim2.new(1, -150, 0, 20),
			TextSize = 13,
			TextColor3 = Theme.MutedText,
			Text = creature.rarity .. "  -  " .. Format.money(creature.income) .. "/s",
		})
		smallButton(item, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(118, 36),
			Text = "SELL " .. Format.money(creature.income * Config.SellSeconds),
			TextSize = 13,
			BackgroundColor3 = Theme.Error,
		}, function()
			self.actions.sell(entry.id)
		end)
	end
end

function Panels:buildIndex()
	local index = self.state.index or {}
	local order = 0
	for zoneIndex, zone in Sea.Zones do
		order += 1
		text(self.list, {
			Text = string.format("-%dm  %s   (speed %d+)", zone.depth, zone.name, zone.speed),
			Font = Theme.BoldFont,
			TextSize = 18,
			TextColor3 = zone.glow,
			Size = UDim2.new(1, -8, 0, 28),
			LayoutOrder = order,
		})
		for _, id in Sea.CreatureOrder do
			local creature = Sea.Creatures[id]
			if creature.zone == zoneIndex then
				order += 1
				local found = index[id] == true
				local rarity = Sea.RarityById[creature.rarity]
				local item = row(self.list, order, 46)
				Create("Frame", {
					Position = UDim2.new(0, 10, 0.5, -14),
					Size = UDim2.fromOffset(28, 28),
					BackgroundColor3 = if found then creature.color else Color3.fromRGB(30, 32, 50),
					Parent = item,
				}, { Create("UICorner", { CornerRadius = UDim.new(1, 0) }), Create("UIStroke", { Color = OUTLINE, Thickness = 2 }) })
				text(item, {
					Position = UDim2.new(0, 48, 0, 0),
					Size = UDim2.new(0.5, -48, 1, 0),
					Font = Theme.BoldFont,
					TextSize = 17,
					TextColor3 = if found then rarity.color else Theme.MutedText,
					Text = if found then creature.name else "???",
				})
				text(item, {
					Position = UDim2.new(0.5, 0, 0, 0),
					Size = UDim2.new(0.5, -10, 1, 0),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Right,
					TextColor3 = Theme.MutedText,
					Text = string.format("%s  %s  %s/s", rarity.id, Format.percent(Sea.chance(id)), Format.money(creature.income)),
				})
			end
		end
	end
end

return Panels
