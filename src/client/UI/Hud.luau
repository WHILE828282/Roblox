-- Hud.luau
-- The always-visible UI:
--   top center  - big counters: Money, Income per second, Speed
--   below them  - what you carry, toasts and the alert banner that slides in
--   bottom      - Dash, Drop Egg and Lock Base (with timers)
--   left        - compact icon tiles: Trails, Shop, Index
-- It only DISPLAYS server data and sends requests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)
local Style = require(script.Parent.Style)
local Icons = require(script.Parent.Icons)

local Hud = {}
Hud.__index = Hud

local OUTLINE = Color3.fromRGB(12, 14, 22)

local function corner(radius: number?): UICorner
	return Create("UICorner", { CornerRadius = UDim.new(0, radius or 14) })
end

-- A rounded "pill" with an icon and a big number.
local function counter(parent: Instance, order: number, icon: string, color: Color3, width: number): TextLabel
	local pill = Create("Frame", {
		Name = "Counter",
		Size = UDim2.fromOffset(width, 46),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.1,
		LayoutOrder = order,
		Parent = parent,
	}, { corner(23), Create("UIStroke", { Color = OUTLINE, Thickness = 2.5 }) })
	Create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = icon,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.fromOffset(36, 36),
		Parent = pill,
	})
	local label = Create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 46, 0, 0),
		Size = UDim2.new(1, -56, 1, 0),
		Font = Theme.BoldFont,
		TextSize = 24,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "0",
		Parent = pill,
	})
	Style.text(label, 2)
	return label
end

local function button(props: { [string]: any }, icon: string, tile: boolean, onClick: () -> ()): TextButton
	local defaults = { Font = Theme.BoldFont, TextColor3 = Theme.Text, TextSize = 17, BackgroundColor3 = Theme.Panel }
	for key, value in props do
		defaults[key] = value
	end
	local instance = Create("TextButton", defaults, { corner() })
	Style.button(instance)
	local image = Create("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, Parent = instance })
	if tile then
		image.AnchorPoint = Vector2.new(0.5, 0)
		image.Position = UDim2.new(0.5, 0, 0, 4)
		image.Size = UDim2.new(0.64, 0, 0.64, 0)
		instance.TextYAlignment = Enum.TextYAlignment.Bottom
		Create("UIPadding", { PaddingBottom = UDim.new(0, 4), Parent = instance })
	else
		image.AnchorPoint = Vector2.new(0, 0.5)
		image.Position = UDim2.new(0, -38, 0.5, 0)
		image.Size = UDim2.fromOffset(34, 34)
		Create("UIPadding", { PaddingLeft = UDim.new(0, 44), PaddingRight = UDim.new(0, 8), Parent = instance })
	end
	instance.Activated:Connect(onClick)
	return instance
end

-- actions = { openPanel(name), dash(), drop(), lock() }
function Hud.new(screenGui: ScreenGui, actions)
	local self = setmetatable({}, Hud)

	-- Counters (top center)
	local top = Create("Frame", {
		Name = "Counters",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.moneyLabel = counter(top, 1, Icons.Coin, Theme.Gold, 150)
	self.incomeLabel = counter(top, 2, Icons.Shop, Theme.Success, 140)
	self.speedLabel = counter(top, 3, Icons.Ability, Color3.fromRGB(120, 220, 255), 130)

	-- Status line under the counters
	self.statusLabel = Create("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 60),
		Size = UDim2.new(0.9, 0, 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.BoldFont,
		TextSize = 20,
		TextColor3 = Theme.Gold,
		Text = "",
		Parent = screenGui,
	})
	Style.text(self.statusLabel, 2)

	-- Alert banner: hidden above the screen, slides down when needed.
	self.banner = Create("TextLabel", {
		Name = "Alert",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -90),
		Size = UDim2.new(0.86, 0, 0, 58),
		BackgroundColor3 = Color3.fromRGB(230, 50, 60),
		Font = Theme.BoldFont,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = "",
		ZIndex = 5,
		Parent = screenGui,
	}, {
		corner(16),
		Create("UIStroke", { Color = OUTLINE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Create("UISizeConstraint", { MaxSize = Vector2.new(640, 58) }),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8) }),
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 150, 160)) }),
	})
	Style.text(self.banner, 2)
	self.bannerVersion = 0

	-- Toasts
	self.toasts = Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0, 420, 0, 160),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.toastCount = 0

	-- Menu tiles (left)
	local menu = Create("Frame", {
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(70, 240),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, { Create("UIListLayout", { Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local tiles = {
		{ "Trails", Icons.Ability, Color3.fromRGB(190, 110, 255) },
		{ "Shop", Icons.Shop, Theme.Gold },
		{ "Index", Icons.Egg, Theme.Accent },
	}
	for order, tile in tiles do
		button({ Name = tile[1], Text = tile[1], TextSize = 14, BackgroundColor3 = tile[3], Size = UDim2.fromOffset(70, 74), LayoutOrder = order, Parent = menu }, tile[2], true, function()
			actions.openPanel(tile[1])
		end)
	end

	-- Action buttons (bottom center)
	local bottom = Create("Frame", {
		Name = "Actions",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.dashButton = button({ Name = "Dash", Text = "DASH", BackgroundColor3 = Theme.Accent, Size = UDim2.fromOffset(140, 56), LayoutOrder = 1, Parent = bottom }, Icons.Upgrades, false, actions.dash)
	self.dropButton = button({ Name = "Drop", Text = "DROP EGG", BackgroundColor3 = Theme.Error, Size = UDim2.fromOffset(160, 56), LayoutOrder = 2, Visible = false, Parent = bottom }, Icons.Exit, false, actions.drop)
	self.lockButton = button({ Name = "Lock", Text = "LOCK BASE", BackgroundColor3 = Theme.Success, Size = UDim2.fromOffset(170, 56), LayoutOrder = 3, Parent = bottom }, Icons.Lock, false, actions.lock)
	return self
end

function Hud:setState(state)
	local money = state.money or 0
	local gained = money - (self.lastMoney or money)
	self.lastMoney = money
	self.moneyLabel.Text = Format.money(money)
	if gained > 0 then
		Style.punch(self.moneyLabel)
	end
	self.incomeLabel.Text = "+" .. Format.short(state.income or 0) .. "/s"
	local speed = math.floor((state.speed or 0) * 10) / 10
	self.speedLabel.Text = tostring(if speed >= 100 then math.floor(speed) else speed)

	if state.carrying then
		self.statusLabel.Text = string.format("Carrying a %s egg (%d%% speed) - run to your base!", state.carrying.rarity, math.floor(state.carrying.weight * 100 + 0.5))
		self.statusLabel.TextColor3 = if state.chased then Theme.Error else Theme.Gold
	elseif not state.saving then
		self.statusLabel.Text = "Progress is not being saved"
		self.statusLabel.TextColor3 = Theme.Error
	else
		self.statusLabel.Text = ""
	end
	self.dropButton.Visible = state.carrying ~= nil

	local dashLeft = state.dashLeft or 0
	self.dashButton.Text = if dashLeft > 0 then "DASH " .. math.ceil(dashLeft) .. "s" else "DASH"
	self.dashButton.BackgroundColor3 = if dashLeft > 0 then Theme.Panel else Theme.Accent

	if (state.lockedLeft or 0) > 0 then
		self.lockButton.Text = "LOCKED " .. Format.duration(state.lockedLeft)
		self.lockButton.BackgroundColor3 = Theme.Accent
	elseif (state.lockCooldownLeft or 0) > 0 then
		self.lockButton.Text = "LOCK " .. Format.duration(state.lockCooldownLeft)
		self.lockButton.BackgroundColor3 = Theme.Panel
	else
		self.lockButton.Text = "LOCK BASE"
		self.lockButton.BackgroundColor3 = Theme.Success
	end
end

local TOAST_COLORS = { info = Theme.Text, success = Theme.Success, error = Theme.Error, coin = Theme.Gold }

function Hud:notify(message: string, kind: string?)
	self.toastCount += 1
	local toast = Create("TextLabel", {
		Text = message,
		Font = Theme.BoldFont,
		TextSize = 17,
		TextColor3 = TOAST_COLORS[kind or "info"] or Theme.Text,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.1,
		Size = UDim2.new(0, 0, 0, 30),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = self.toastCount,
		Parent = self.toasts,
	}, {
		corner(12),
		Create("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	Style.text(toast, 1.5)
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
	for i = 1, #all - 3 do
		all[i]:Destroy()
	end
	task.delay(2.6, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

-- Big warning that slides down from the top of the screen.
function Hud:alert(message: string)
	self.bannerVersion += 1
	local version = self.bannerVersion
	self.banner.Text = "⚠️ " .. message
	local slide = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(self.banner, slide, { Position = UDim2.new(0.5, 0, 0, 112) }):Play()
	task.delay(4, function()
		if self.bannerVersion == version then
			TweenService:Create(self.banner, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
		end
	end)
end

return Hud
