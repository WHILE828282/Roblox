-- Hud.luau
-- The always-visible UI: money and base stats, event timers, the big
-- announcement banner, toasts, menu buttons and the action buttons
-- (Hit, Ability, Get Off, Lock Base). It only DISPLAYS server data and
-- sends requests; the server decides everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Dinos = require(ReplicatedStorage.Shared.Dinos)
local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)
local Style = require(script.Parent.Style)

local Hud = {}
Hud.__index = Hud

local function corner(): UICorner
	return Create("UICorner", { CornerRadius = Theme.Corner })
end

local function padding(px: number): UIPadding
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Font,
		TextColor3 = Theme.Text,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 20),
	}
	for key, value in props do
		defaults[key] = value
	end
	return Create("TextLabel", defaults)
end

local function button(props: { [string]: any }, onClick: () -> ()): TextButton
	local defaults = {
		BackgroundColor3 = Theme.Panel,
		Font = Theme.BoldFont,
		TextColor3 = Theme.Text,
		TextSize = 16,
		AutoButtonColor = true,
	}
	for key, value in props do
		defaults[key] = value
	end
	local instance = Create("TextButton", defaults, { corner() })
	Style.button(instance)
	instance.Activated:Connect(onClick)
	return instance
end

-- actions = { openPanel(name), attack(), ability(), dismount(), lock() }
function Hud.new(screenGui: ScreenGui, actions)
	local self = setmetatable({}, Hud)
	self.state = nil

	-- Left column: stats on top, menu buttons under them. It sits in the
	-- middle of the left edge so it never covers the Roblox chat window.
	local column = Create("Frame", {
		Name = "LeftColumn",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.55, 0),
		Size = UDim2.new(0, 220, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	local stats = Create("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		LayoutOrder = 1,
		Parent = column,
	}, {
		Create("UIStroke", { Color = Color3.fromRGB(12, 14, 22), Thickness = 2.5 }),
		corner(),
		padding(10),
		Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.moneyLabel = label({
		Text = "$0",
		TextSize = 32,
		Size = UDim2.new(1, 0, 0, 36),
		Font = Theme.BoldFont,
		TextColor3 = Theme.Gold,
		LayoutOrder = 1,
		Parent = stats,
	})
	self.incomeLabel = label({ Text = "+$0/s", TextColor3 = Theme.Success, LayoutOrder = 2, Parent = stats })
	self.baseLabel = label({ Text = "", TextColor3 = Theme.MutedText, TextSize = 14, LayoutOrder = 3, Parent = stats })
	self.carryLabel = label({
		Text = "",
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 4,
		Parent = stats,
	})
	self.saveLabel = label({
		Text = "Progress is not being saved",
		TextColor3 = Theme.Error,
		TextSize = 13,
		Visible = false,
		LayoutOrder = 5,
		Parent = stats,
	})

	-- Menu buttons (under the stats)
	local menu = Create("Frame", {
		Name = "Menu",
		Size = UDim2.new(0, 150, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = column,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for order, name in { "Dinos", "Upgrades", "Shop", "Odds" } do
		local colors = { Theme.Success, Theme.Accent, Theme.Gold, Color3.fromRGB(190, 110, 255) }
		button({
			Name = name,
			Text = name,
			TextSize = 19,
			BackgroundColor3 = colors[order],
			Size = UDim2.new(1, 0, 0, 44),
			LayoutOrder = order,
			Parent = menu,
		}, function()
			actions.openPanel(name)
		end)
	end

	-- Event timers (top-center)
	self.eventLabel = Create("TextLabel", {
		Name = "Events",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Font = Theme.BoldFont,
		TextSize = 16,
		TextColor3 = Theme.Text,
		Text = "",
		Parent = screenGui,
	}, { corner(), padding(6) })

	-- Announcement banner
	self.banner = Create("TextLabel", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.new(0.8, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = Theme.BoldFont,
		TextScaled = true,
		TextColor3 = Theme.Gold,
		TextStrokeTransparency = 0.2,
		Text = "",
		Visible = false,
		Parent = screenGui,
	})
	self.bannerVersion = 0

	-- Toasts (center)
	self.toasts = Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 104),
		Size = UDim2.new(0, 420, 0, 200),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create(
			"UIListLayout",
			{
				Padding = UDim.new(0, 6),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}
		),
	})
	self.toastCount = 0

	-- Action buttons (bottom-right)
	local actionsFrame = Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.new(0, 170, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create(
			"UIListLayout",
			{
				Padding = UDim.new(0, 6),
				VerticalAlignment = Enum.VerticalAlignment.Bottom,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}
		),
	})
	self.lockButton = button(
		{ Name = "Lock", Text = "Lock Base", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 1, Parent = actionsFrame },
		actions.lock
	)
	self.dismountButton = button(
		{ Name = "GetOff", Text = "Get Off", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Visible = false, Parent = actionsFrame },
		actions.dismount
	)
	self.abilityButton = button(
		{
			Name = "Ability",
			Text = "Ability [F]",
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = 3,
			Visible = false,
			BackgroundColor3 = Theme.Accent,
			Parent = actionsFrame,
		},
		actions.ability
	)
	self.hitButton = button(
		{
			Name = "Hit",
			Text = "HIT [Click]",
			Size = UDim2.new(1, 0, 0, 56),
			LayoutOrder = 4,
			BackgroundColor3 = Theme.Error,
			TextSize = 20,
			Parent = actionsFrame,
		},
		actions.attack
	)

	return self
end

function Hud:setState(state)
	self.state = state
	-- The money label "punches" when you get a lump of money (a sale, a gift),
	-- not on every normal income tick.
	local money = state.money or 0
	local gained = money - (self.lastMoney or money)
	self.lastMoney = money
	self.moneyLabel.Text = Format.money(money)
	if gained > (state.income or 0) * 2 + 1 then
		Style.punch(self.moneyLabel)
	end
	self.incomeLabel.Text = "+" .. Format.money(state.income or 0) .. "/s"
	self.baseLabel.Text = string.format(
		"Dinos %d/%d   Nests %d/%d",
		state.dinoCount or 0,
		state.penSize or 0,
		state.eggCount or 0,
		state.nests or 0
	)
	self.saveLabel.Visible = not state.saving

	local carrying = state.carrying or 0
	if carrying > 0 then
		self.carryLabel.Text =
			string.format("Carrying %d/%d eggs - bring them HOME!", carrying, state.carryCapacity or 1)
		self.carryLabel.TextColor3 = Theme.Gold
	elseif state.riding and state.riding.stolen then
		self.carryLabel.Text = "Riding a STOLEN dinosaur - get to your base to keep it!"
		self.carryLabel.TextColor3 = Theme.Error
	elseif state.mountOut then
		self.carryLabel.Text = "Your dinosaur is out there with an empty saddle! Get it back!"
		self.carryLabel.TextColor3 = Theme.Error
	else
		self.carryLabel.Text = ""
	end

	-- Event line
	local parts = {}
	if (state.bigEruptionIn or 0) > 0 then
		table.insert(parts, "Big eruption in " .. Format.duration(state.bigEruptionIn))
	end
	if (state.serverLuckLeft or 0) > 0 then
		table.insert(parts, "Server luck x2: " .. Format.duration(state.serverLuckLeft))
	end
	if (state.protectedLeft or 0) > 0 then
		table.insert(parts, "Protected: " .. Format.duration(state.protectedLeft))
	end
	self.eventLabel.Text = table.concat(parts, "   |   ")
	self.eventLabel.Visible = #parts > 0

	-- Riding buttons
	local riding = state.riding
	self.abilityButton.Visible = riding ~= nil
	self.dismountButton.Visible = riding ~= nil and not riding.stolen
	if riding then
		local ability = Dinos.Abilities[Dinos.Species[riding.s].ability]
		local ready = (state.abilityReadyIn or 0) <= 0
		self.abilityButton.Text = if ready
			then ability.name .. " [F]"
			else ability.name .. " " .. math.ceil(state.abilityReadyIn) .. "s"
		self.abilityButton.BackgroundColor3 = if ready then Theme.Accent else Theme.Panel
	end

	if (state.lockedLeft or 0) > 0 then
		self.lockButton.Text = "Locked " .. Format.duration(state.lockedLeft)
		self.lockButton.BackgroundColor3 = Theme.Accent
	elseif (state.lockCooldownLeft or 0) > 0 then
		self.lockButton.Text = "Lock in " .. Format.duration(state.lockCooldownLeft)
		self.lockButton.BackgroundColor3 = Theme.Panel
	else
		self.lockButton.Text = "Lock Base"
		self.lockButton.BackgroundColor3 = Theme.Success
	end
end

local TOAST_COLORS = {
	info = Theme.Text,
	success = Theme.Success,
	error = Theme.Error,
	coin = Theme.Gold,
}

function Hud:notify(message: string, kind: string?)
	self.toastCount += 1
	local toast = label({
		Text = message,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = TOAST_COLORS[kind or "info"] or Theme.Text,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Size = UDim2.new(0, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = self.toastCount,
		Parent = self.toasts,
	})
	corner().Parent = toast
	padding(6).Parent = toast
	Style.text(toast, 1.4)
	Style.popIn(toast)

	local all = {}
	for _, child in self.toasts:GetChildren() do
		if child:IsA("TextLabel") then
			table.insert(all, child)
		end
	end
	table.sort(all, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #all - 4 do
		all[i]:Destroy()
	end

	task.delay(3, function()
		if not toast.Parent then
			return
		end
		local tween =
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

-- Big message for everyone (rare eggs, eruptions, thefts).
function Hud:announce(message: string, color: Color3?)
	self.bannerVersion += 1
	local version = self.bannerVersion
	self.banner.Text = message
	self.banner.TextColor3 = color or Theme.Gold
	self.banner.Visible = true
	Style.popIn(self.banner)
	task.delay(5, function()
		if self.bannerVersion == version then
			self.banner.Visible = false
		end
	end)
end

return Hud
