-- Format.luau
-- Small text formatting helpers shared by server and client.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

-- 1234 -> "1.2K", 15000000 -> "15M"
function Format.short(value: number): string
	value = math.floor(value)
	local index = 1
	local scaled = value
	while math.abs(scaled) >= 1000 and index < #SUFFIXES do
		scaled /= 1000
		index += 1
	end
	if index == 1 then
		return tostring(value)
	end
	local text = if math.abs(scaled) >= 100 then string.format("%d", scaled) else string.format("%.1f", scaled)
	text = text:gsub("%.0$", "")
	return text .. SUFFIXES[index]
end

function Format.money(value: number): string
	return "$" .. Format.short(value)
end

-- 0.0213 -> "2.13%", 0.0002 -> "0.02%"
function Format.percent(chance: number): string
	local value = chance * 100
	if value >= 10 then
		return string.format("%.1f%%", value)
	elseif value >= 0.1 then
		return string.format("%.2f%%", value)
	end
	return string.format("%.3f%%", value)
end

-- 125 -> "2:05"
function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

return Format
