-- RateLimiter.luau
-- Per-player cooldown for RemoteEvent requests. Exploiters can fire remotes
-- thousands of times per second; every client -> server remote goes through one.

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(cooldownSeconds: number)
	return setmetatable({ cooldown = cooldownSeconds, lastCall = setmetatable({}, { __mode = "k" }) }, RateLimiter)
end

-- Returns true if the player may act now (and records the call).
function RateLimiter:check(player: Player): boolean
	local now = os.clock()
	local last = self.lastCall[player]
	if last and now - last < self.cooldown then
		return false
	end
	self.lastCall[player] = now
	return true
end

return RateLimiter
