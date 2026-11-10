-- Checkpoints.luau
-- Stage progress, respawning at the last checkpoint, the run timer
-- and finishing the obby. Everything here is decided on the server:
-- the client only displays what the server sends.
--
-- Map setup (in Studio):
--   * Parts tagged "Checkpoint" with a number attribute "Stage".
--     Stage 0 is the start; then 1, 2, 3... with no gaps.
--   * One or more parts tagged "Finish", placed after the highest stage.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Format = require(ReplicatedStorage.Shared.Format)
local PlayerData = require(script.Parent.PlayerData)
local TouchUtil = require(script.Parent.Parent.Lib.TouchUtil)
local RateLimiter = require(script.Parent.Parent.Lib.RateLimiter)
local Tagged = require(script.Parent.Parent.Lib.Tagged)

local Checkpoints = {}

local checkpointParts: { [number]: BasePart } = {} -- stage number -> part
local maxStage = 0

-- Limits for repeated warnings so touch spam does not flood the player.
local warnLimiter = RateLimiter.new(3)
local resetLimiter = RateLimiter.new(Config.ResetCooldown)

local function now(): number
	return workspace:GetServerTimeNow()
end

local function recomputeMaxStage()
	maxStage = 0
	for stage in checkpointParts do
		maxStage = math.max(maxStage, stage)
	end
end

-- Logs missing stage numbers so map mistakes are easy to spot.
local function validateStages()
	for stage = 0, maxStage do
		if not checkpointParts[stage] then
			warn(string.format("[Checkpoints] No part tagged 'Checkpoint' with Stage = %d. Stages must go 0, 1, 2... without gaps.", stage))
		end
	end
end

-- Starts a new timed run for the player.
local function startRun(player: Player)
	local session = PlayerData.getSession(player)
	if not session then
		return
	end
	session.runStart = now()
	session.lastAdvance = now()
end

-- Teleports the character to the checkpoint the player has reached.
local function placeCharacter(player: Player, character: Model)
	local data = PlayerData.get(player)
	if not data then
		return
	end

	-- Saved stage may be higher than the map has (e.g. map was changed).
	if data.Stage > maxStage then
		data.Stage = maxStage
	end

	-- Fall back to the closest lower checkpoint if one is missing.
	local stage = data.Stage
	local part = checkpointParts[stage]
	while not part and stage > 0 do
		stage -= 1
		part = checkpointParts[stage]
	end
	if not part then
		return -- no checkpoints in the map: use the normal SpawnLocation
	end

	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	task.wait() -- let Roblox finish its own spawn positioning first

	-- Stand on top of the part, facing the same way (yaw only).
	local _, yaw, _ = part.CFrame:ToOrientation()
	local position = part.Position + Vector3.new(0, part.Size.Y / 2 + 3, 0)
	character:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
end

local function onCharacterAdded(player: Player, character: Model)
	local data = PlayerData.get(player)
	if not data then
		return -- data still loading; ProfileLoaded will place the character
	end
	-- Spawning at the very start begins a new timed run.
	if data.Stage == 0 then
		startRun(player)
		PlayerData.changed(player)
	end
	placeCharacter(player, character)
end

local function onCheckpointTouched(part: BasePart, stage: number, hit: BasePart)
	local player, _, _, root = TouchUtil.getLivingPlayer(hit)
	if not player then
		return
	end
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return
	end
	if stage <= data.Stage then
		return -- already reached
	end
	if not TouchUtil.isNear(root, part, Config.MaxTouchDistance) then
		return -- touched from too far away: likely an exploit
	end

	if stage > data.Stage + 1 then
		-- Skipping checkpoints is not allowed.
		if warnLimiter:check(player) then
			PlayerData.notify(player, string.format("You skipped a checkpoint! Go back to Stage %d.", data.Stage + 1), "error")
		end
		return
	end

	-- Reaching checkpoints impossibly fast means teleporting / speed hacking.
	local t = now()
	if session.lastAdvance and t - session.lastAdvance < Config.MinSecondsPerStage then
		return
	end

	data.Stage = stage
	session.lastAdvance = t
	PlayerData.changed(player)
	PlayerData.notify(player, string.format("Checkpoint %d reached!", stage), "success")
end

local function onFinishTouched(part: BasePart, hit: BasePart)
	local player, _, _, root = TouchUtil.getLivingPlayer(hit)
	if not player then
		return
	end
	local data = PlayerData.get(player)
	local session = PlayerData.getSession(player)
	if not data or not session then
		return
	end
	if not TouchUtil.isNear(root, part, Config.MaxTouchDistance) then
		return
	end
	-- Just finished and still standing on the pad: stay quiet.
	if session.finishedAt and now() - session.finishedAt < Config.FinishRespawnDelay + 1 then
		return
	end
	if maxStage < 1 or data.Stage < maxStage then
		if warnLimiter:check(player) then
			PlayerData.notify(player, "Reach every checkpoint before the finish!", "error")
		end
		return
	end

	local t = now()
	local runTime = if session.runStart then t - session.runStart else nil

	-- Reject impossible times (only for timed runs; untimed runs had to
	-- pass the per-stage speed check on every checkpoint).
	if runTime and runTime < Config.MinRunTime then
		warn(string.format("[Checkpoints] %s finished in %.2fs (below MinRunTime). Run rejected.", player.Name, runTime))
		data.Stage = 0
		session.runStart = nil
		PlayerData.changed(player)
		PlayerData.notify(player, "That run was too fast to be real. Try again!", "error")
		player:LoadCharacter()
		return
	end

	-- Reward and records. Stage goes back to 0 right away, so a second
	-- touch of the finish cannot give the reward twice.
	local newBest = false
	if runTime and (data.BestTime == 0 or runTime < data.BestTime) then
		data.BestTime = runTime
		newBest = true
	end
	data.Coins += Config.FinishReward
	data.Wins += 1
	data.Stage = 0
	session.runStart = nil
	session.finishedAt = t
	PlayerData.changed(player)

	Remotes.get("RunFinished"):FireClient(player, {
		time = runTime,
		reward = Config.FinishReward,
		newBest = newBest,
		bestTime = data.BestTime,
	})
	print(string.format("[Checkpoints] %s finished in %s", player.Name, Format.time(runTime)))

	-- Save now: finishing is the most valuable moment to keep.
	task.spawn(PlayerData.save, player)

	task.delay(Config.FinishRespawnDelay, function()
		if player.Parent == Players then
			player:LoadCharacter()
		end
	end)
end

-- Client asked to restart from the beginning. No arguments are trusted.
local function onResetRequested(player: Player)
	if not resetLimiter:check(player) then
		return
	end
	local data = PlayerData.get(player)
	if not data then
		return
	end
	data.Stage = 0
	PlayerData.changed(player)
	player:LoadCharacter() -- CharacterAdded starts a fresh timed run
end

function Checkpoints.start()
	PlayerData.getMaxStage = function()
		return maxStage
	end

	Tagged(Config.Tags.Checkpoint, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Checkpoints] 'Checkpoint' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		local stage = instance:GetAttribute(Config.StageAttribute)
		if type(stage) ~= "number" or stage < 0 or stage % 1 ~= 0 then
			warn(string.format("[Checkpoints] %s needs a whole-number attribute '%s' (0, 1, 2...).", instance:GetFullName(), Config.StageAttribute))
			return nil
		end
		if checkpointParts[stage] and checkpointParts[stage] ~= instance then
			warn(string.format("[Checkpoints] Two checkpoints use Stage %d: %s and %s", stage, checkpointParts[stage]:GetFullName(), instance:GetFullName()))
		end
		checkpointParts[stage] = instance
		recomputeMaxStage()

		local connection = instance.Touched:Connect(function(hit)
			onCheckpointTouched(instance, stage, hit)
		end)
		return function()
			connection:Disconnect()
			if checkpointParts[stage] == instance then
				checkpointParts[stage] = nil
				recomputeMaxStage()
			end
		end
	end)

	Tagged(Config.Tags.Finish, function(instance)
		if not instance:IsA("BasePart") then
			warn("[Checkpoints] 'Finish' tag must be on a Part, not " .. instance:GetFullName())
			return nil
		end
		return instance.Touched:Connect(function(hit)
			onFinishTouched(instance, hit)
		end)
	end)

	validateStages()
	print(string.format("[Checkpoints] Loaded stages 0-%d", maxStage))

	-- Place characters at their checkpoint every time they spawn.
	local function watchPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end

	-- If the character spawned before the data finished loading, fix it now.
	PlayerData.ProfileLoaded:Connect(function(player)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		warnLimiter:forget(player)
		resetLimiter:forget(player)
	end)

	Remotes.get("RequestReset").OnServerEvent:Connect(onResetRequested)
end

return Checkpoints
