-- Style.luau
-- Shared "juice" for the UI: gradients, outlines, soft shadows and small
-- hover / press animations, so every button and panel looks the same.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Style = {}

local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOUNCE = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local clickSound = Instance.new("Sound")
clickSound.Name = "UiClick"
clickSound.SoundId = "rbxasset://sounds/button.wav"
clickSound.Volume = 0.35
clickSound.Parent = SoundService

-- Dark outline + top-to-bottom shine, like buttons in popular simulators.
function Style.surface(instance: GuiObject, strokeColor: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = strokeColor or Color3.fromRGB(12, 14, 22)
	stroke.Thickness = thickness or 2.5
	stroke.Parent = instance
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 235, 240)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(165, 165, 185)),
	})
	gradient.Parent = instance
	return stroke
end

-- Thick readable text with an outline.
function Style.text(label: TextLabel | TextButton, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Color = Color3.fromRGB(12, 14, 22)
	stroke.Thickness = thickness or 1.6
	stroke.Parent = label
end

-- A glossy button that grows on hover and squashes on press.
function Style.button(button: TextButton)
	button.AutoButtonColor = false
	Style.surface(button)
	local textStroke = Instance.new("UIStroke")
	textStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textStroke.Color = Color3.fromRGB(12, 14, 22)
	textStroke.Thickness = 1.6
	textStroke.Parent = button
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local function to(value: number, info: TweenInfo)
		TweenService:Create(scale, info, { Scale = value }):Play()
	end
	button.MouseEnter:Connect(function()
		to(1.06, QUICK)
	end)
	button.MouseLeave:Connect(function()
		to(1, QUICK)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.92, QUICK)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.04, BOUNCE)
	end)
	button.Activated:Connect(function()
		clickSound:Play()
	end)
end

-- Pops a panel or toast in with a little bounce.
function Style.popIn(instance: GuiObject)
	local scale = instance:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = instance
	TweenService:Create(scale, BOUNCE, { Scale = 1 }):Play()
end

-- Quick "punch" used when a number changes (money going up).
function Style.punch(instance: GuiObject)
	local scale = instance:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = instance
	scale.Scale = 1.18
	TweenService:Create(scale, BOUNCE, { Scale = 1 }):Play()
end

return Style
