-- Hud.luau
-- Builds the main HUD: stats panel, run timer, restart button,
-- toast notifications and the "finished" popup.
-- The HUD only DISPLAYS data from the server; it never decides anything.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

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
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
	}
	for key, value in props do
		defaults[key] = value
	end
	return Create("TextLabel", defaults)
end

-- screenGui: the ScreenGui to build into.
-- onResetRequested: called when the player confirms "Restart".
function Hud.new(screenGui: ScreenGui, onResetRequested: () -> ())
	local self = setmetatable({}, Hud)
	self.state = nil
	self.timerFrozenText = nil

	-- Stats panel (top-left)
	local stats = Create("Frame", {
		Name = "Stats",
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.new(0, 12, 0, 12),
		Size = UDim2.new(0, 210, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Parent = screenGui,
	}, {
		corner(),
		padding(10),
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.levelLabel = label({ Text = "Level -", TextSize = 20, Font = Theme.BoldFont, LayoutOrder = 1, Parent = stats })
	self.coinsLabel = label({ Text = "Coins: 0", TextColor3 = Theme.Gold, LayoutOrder = 2, Parent = stats })
	self.bestLabel = label({ Text = "Best: --:--.--", TextColor3 = Theme.MutedText, TextSize = 16, LayoutOrder = 3, Parent = stats })
	self.winsLabel = label({ Text = "Wins: 0", TextColor3 = Theme.MutedText, TextSize = 16, LayoutOrder = 4, Parent = stats })
	self.saveLabel = label({
		Text = "Progress is not being saved",
		TextColor3 = Theme.Error,
		TextSize = 14,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		LayoutOrder = 5,
		Parent = stats,
	})

	-- Timer (top-center)
	self.timerLabel = Create("TextLabel", {
		Name = "Timer",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.new(0, 200, 0, 48),
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Font = Theme.BoldFont,
		TextColor3 = Theme.Text,
		TextSize = 30,
		Text = "--:--.--",
		Parent = screenGui,
	}, { corner() })

	-- Restart button (bottom-left). Needs two clicks to avoid accidents.
	local resetButton = Create("TextButton", {
		Name = "Restart",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12),
		Size = UDim2.new(0, 170, 0, 40),
		BackgroundColor3 = Theme.Panel,
		Font = Theme.BoldFont,
		TextColor3 = Theme.Text,
		TextSize = 16,
		Text = "Restart obby",
		AutoButtonColor = true,
		Parent = screenGui,
	}, { corner() })
	local confirming = false
	resetButton.Activated:Connect(function()
		if not confirming then
			confirming = true
			resetButton.Text = "Click again to confirm"
			resetButton.BackgroundColor3 = Theme.Error
			task.delay(3, function()
				confirming = false
				resetButton.Text = "Restart obby"
				resetButton.BackgroundColor3 = Theme.Panel
			end)
			return
		end
		confirming = false
		resetButton.Text = "Restart obby"
		resetButton.BackgroundColor3 = Theme.Panel
		onResetRequested()
	end)

	-- Toast list (center, below the timer)
	self.toasts = Create("Frame", {
		Name = "Toasts",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.new(0, 360, 0, 200),
		BackgroundTransparency = 1,
		Parent = screenGui,
	}, {
		Create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	self.toastCount = 0

	-- Finish popup (center of the screen, hidden until a run ends)
	self.finishFrame = Create("Frame", {
		Name = "FinishPopup",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 320, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screenGui,
	}, {
		corner(),
		padding(18),
		Create("UIStroke", { Color = Theme.Gold, Thickness = 2 }),
		Create("UIListLayout", {
			Padding = UDim.new(0, 6),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	label({ Text = "Obby complete!", Font = Theme.BoldFont, TextSize = 28, TextColor3 = Theme.Gold, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 1, Parent = self.finishFrame })
	self.finishTime = label({ TextXAlignment = Enum.TextXAlignment.Center, TextSize = 22, LayoutOrder = 2, Parent = self.finishFrame })
	self.finishReward = label({ TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Gold, LayoutOrder = 3, Parent = self.finishFrame })
	self.finishBest = label({ TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = Theme.Success, LayoutOrder = 4, Parent = self.finishFrame })

	-- Update the timer every frame from the server's start time.
	RunService.RenderStepped:Connect(function()
		self:_updateTimer()
	end)

	return self
end

function Hud:_updateTimer()
	if self.timerFrozenText then
		self.timerLabel.Text = self.timerFrozenText
		return
	end
	local state = self.state
	if state and state.runStart then
		self.timerLabel.Text = Format.time(workspace:GetServerTimeNow() - state.runStart)
	elseif state and state.stage > 0 then
		self.timerLabel.Text = "Not timed"
	else
		self.timerLabel.Text = "--:--.--"
	end
end

-- Called whenever the server sends a new state.
function Hud:setState(state)
	self.state = state
	-- A new run started: stop showing the frozen finish time.
	if state.runStart then
		self.timerFrozenText = nil
	end
	local totalLevels = state.maxStage + 1
	local level = math.min(state.stage + 1, totalLevels)
	self.levelLabel.Text = string.format("Level %d / %d", level, totalLevels)
	self.coinsLabel.Text = "Coins: " .. Format.number(state.coins)
	self.bestLabel.Text = "Best: " .. Format.time(state.bestTime)
	self.winsLabel.Text = "Wins: " .. Format.number(state.wins)
	self.saveLabel.Visible = not state.saving
end

local TOAST_COLORS = {
	info = Theme.Text,
	success = Theme.Success,
	error = Theme.Error,
	coin = Theme.Gold,
}

-- Shows a short message that fades out after a few seconds.
function Hud:notify(message: string, kind: string?)
	self.toastCount += 1
	local toast = label({
		Text = message,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = TOAST_COLORS[kind or "info"] or Theme.Text,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Size = UDim2.new(0, 0, 0, 32),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = self.toastCount,
		Parent = self.toasts,
	})
	corner().Parent = toast
	padding(6).Parent = toast

	-- Keep at most 4 toasts on screen.
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

	task.delay(2.5, function()
		if not toast.Parent then
			return
		end
		local tween = TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, BackgroundTransparency = 1 })
		tween:Play()
		tween.Completed:Wait()
		toast:Destroy()
	end)
end

-- Shows the "Obby complete" popup with the server-calculated result.
function Hud:showFinish(result)
	local timeText = if result.time then Format.time(result.time) else "Not timed"
	self.timerFrozenText = timeText
	self.finishTime.Text = "Time: " .. timeText
	self.finishReward.Text = string.format("+%d coins", result.reward or 0)
	self.finishBest.Text = if result.newBest then "New personal best!" else "Best: " .. Format.time(result.bestTime)
	self.finishFrame.Visible = true
	task.delay(5, function()
		self.finishFrame.Visible = false
	end)
end

return Hud
