-- Format.luau
-- Small text formatting helpers shared by server and client.

local Format = {}

-- 83.456 -> "1:23.45"
function Format.time(seconds: number?): string
	if not seconds or seconds <= 0 then
		return "--:--.--"
	end
	local minutes = math.floor(seconds / 60)
	local rest = seconds - minutes * 60
	return string.format("%d:%05.2f", minutes, rest)
end

-- 1234567 -> "1,234,567"
function Format.number(value: number): string
	local text = tostring(math.floor(value))
	local result = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if result:sub(1, 1) == "," then
		result = result:sub(2)
	end
	return result
end

return Format
