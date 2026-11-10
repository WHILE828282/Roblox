-- RateLimiter.luau
-- Per-player cooldown for RemoteEvent requests.
-- Exploiters can fire remotes thousands of times per second;
-- every client -> server remote must pass through one of these.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(cooldownSeconds: number)
	local self = setmetatable({}, RateLimiter)
	self.cooldown = cooldownSeconds
	self.lastCall = {} :: { [Player]: number }
	return self
end

-- Returns true if the player is allowed to act now (and records the call).
function RateLimiter:check(player: Player): boolean
	local now = os.clock()
	local last = self.lastCall[player]
	if last and now - last < self.cooldown then
		return false
	end
	self.lastCall[player] = now
	return true
end

-- Call when the player leaves to avoid keeping references to them.
function RateLimiter:forget(player: Player)
	self.lastCall[player] = nil
end

return RateLimiter
