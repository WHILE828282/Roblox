-- LeaderboardPanel.luau
-- "Top coins" panel on the right side of the screen.
-- Shows the global list the server sends; can be collapsed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Format = require(ReplicatedStorage.Shared.Format)
local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

local LeaderboardPanel = {}
LeaderboardPanel.__index = LeaderboardPanel

function LeaderboardPanel.new(screenGui: ScreenGui)
	local self = setmetatable({}, LeaderboardPanel)

	local frame = Create("Frame", {
		Name = "Leaderboard",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.new(0, 230, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Background,
		BackgroundTransparency = Theme.BackgroundTransparency,
		Parent = screenGui,
	}, {
		Create("UICorner", { CornerRadius = Theme.Corner }),
		Create("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	-- Header doubles as the collapse/expand button.
	local header = Create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Font = Theme.BoldFont,
		TextSize = 18,
		TextColor3 = Theme.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Top coins  [-]",
		LayoutOrder = 0,
		Parent = frame,
	})

	self.list = Create("Frame", {
		Name = "Rows",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		Parent = frame,
	}, {
		Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	header.Activated:Connect(function()
		self.list.Visible = not self.list.Visible
		header.Text = if self.list.Visible then "Top coins  [-]" else "Top coins  [+]"
	end)

	self:setEntries({})
	return self
end

-- entries: { { rank = number, name = string, coins = number }, ... }
function LeaderboardPanel:setEntries(entries)
	for _, child in self.list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	if type(entries) ~= "table" or #entries == 0 then
		Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Font = Theme.Font,
			TextSize = 14,
			TextColor3 = Theme.MutedText,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "No scores yet",
			Parent = self.list,
		})
		return
	end

	for index, entry in entries do
		local row = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			LayoutOrder = index,
			Parent = self.list,
		})
		Create("TextLabel", {
			Size = UDim2.new(0.7, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Theme.Font,
			TextSize = 15,
			TextColor3 = Theme.Text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Text = string.format("%d. %s", entry.rank, tostring(entry.name)),
			Parent = row,
		})
		Create("TextLabel", {
			Position = UDim2.new(0.7, 0, 0, 0),
			Size = UDim2.new(0.3, 0, 1, 0),
			BackgroundTransparency = 1,
			Font = Theme.BoldFont,
			TextSize = 15,
			TextColor3 = Theme.Gold,
			TextXAlignment = Enum.TextXAlignment.Right,
			Text = Format.number(tonumber(entry.coins) or 0),
			Parent = row,
		})
	end
end

return LeaderboardPanel
