-- Animals.luau
-- Every zone, rarity, mutation and animal species in the game,
-- plus the random rolls used when an animal appears.
-- Add a new animal by adding one entry to Animals.Species.

local Animals = {}

local rgb = Color3.fromRGB

-- Rarity: how often it appears, how much it earns, how long a rescue takes.
Animals.Rarities = {
	Common = { order = 1, weight = 60, income = 1, rescueTime = 1.5, color = rgb(210, 210, 215) },
	Uncommon = { order = 2, weight = 25, income = 3, rescueTime = 2.5, color = rgb(90, 205, 110) },
	Rare = { order = 3, weight = 11, income = 8, rescueTime = 4, color = rgb(80, 150, 255) },
	Epic = { order = 4, weight = 4, income = 25, rescueTime = 6, color = rgb(185, 95, 255) },
	Mythic = { order = 5, weight = 0, income = 200, rescueTime = 10, color = rgb(255, 75, 75) }, -- storms only
}
Animals.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Mythic" }

-- Mutations: a rare variant that earns more.
Animals.Mutations = {
	Normal = { order = 1, multiplier = 1, chance = 0 },
	Golden = { order = 2, multiplier = 3, chance = 1 / 50, color = rgb(255, 200, 40) },
	Rainbow = { order = 3, multiplier = 10, chance = 1 / 500 },
}
Animals.MutationOrder = { "Normal", "Golden", "Rainbow" }

-- Zones in unlock order. `multiplier` scales the income of animals from that zone.
Animals.Zones = {
	{ id = "Forest", name = "Forest", multiplier = 1, cost = 0, trouble = "Stuck in a trap!" },
	{ id = "Beach", name = "Beach", multiplier = 10, cost = 15000, trouble = "Tangled in a net!" },
	{ id = "Mountains", name = "Mountains", multiplier = 100, cost = 150000, trouble = "Trapped by rocks!" },
	{ id = "Jungle", name = "Jungle", multiplier = 1000, cost = 1500000, trouble = "Caught in vines!" },
	{ id = "Arctic", name = "Arctic", multiplier = 10000, cost = 15000000, trouble = "Frozen in ice!" },
}
Animals.ZoneById = {}
for index, zone in Animals.Zones do
	zone.index = index
	Animals.ZoneById[zone.id] = zone
end

-- Species. `kind` picks the body shape (quad, bird, blob), the rest is looks.
-- Mythic animals have no zone: they appear in any zone during a storm.
Animals.Species = {
	-- Forest
	Bunny = { name = "Bunny", zone = "Forest", rarity = "Common", kind = "quad", scale = 0.6, color = rgb(245, 245, 245), accent = rgb(255, 170, 190), ears = "long" },
	Fox = { name = "Fox", zone = "Forest", rarity = "Uncommon", kind = "quad", scale = 0.8, color = rgb(235, 120, 40), accent = rgb(255, 255, 255), ears = "pointy" },
	Deer = { name = "Deer", zone = "Forest", rarity = "Rare", kind = "quad", scale = 1.1, color = rgb(160, 105, 60), accent = rgb(240, 220, 190), ears = "pointy", antlers = true },
	Owl = { name = "Owl", zone = "Forest", rarity = "Epic", kind = "bird", scale = 0.8, color = rgb(130, 90, 55), accent = rgb(240, 210, 150) },
	-- Beach
	Crab = { name = "Crab", zone = "Beach", rarity = "Common", kind = "blob", scale = 0.7, color = rgb(230, 70, 50), accent = rgb(255, 140, 110), claws = true },
	Turtle = { name = "Turtle", zone = "Beach", rarity = "Uncommon", kind = "blob", scale = 0.9, color = rgb(120, 180, 90), accent = rgb(90, 120, 60), shell = true },
	Seal = { name = "Seal", zone = "Beach", rarity = "Rare", kind = "quad", scale = 1, color = rgb(150, 160, 175), accent = rgb(200, 205, 215), legs = 0.3 },
	Flamingo = { name = "Flamingo", zone = "Beach", rarity = "Epic", kind = "bird", scale = 1, color = rgb(255, 130, 170), accent = rgb(255, 190, 210), tall = true },
	-- Mountains
	Goat = { name = "Goat", zone = "Mountains", rarity = "Common", kind = "quad", scale = 0.9, color = rgb(235, 230, 220), accent = rgb(120, 110, 100), horns = true },
	Eagle = { name = "Eagle", zone = "Mountains", rarity = "Uncommon", kind = "bird", scale = 0.9, color = rgb(110, 75, 45), accent = rgb(250, 250, 250) },
	Bear = { name = "Bear", zone = "Mountains", rarity = "Rare", kind = "quad", scale = 1.4, color = rgb(105, 70, 45), accent = rgb(150, 110, 80), ears = "round" },
	RedPanda = { name = "Red Panda", zone = "Mountains", rarity = "Epic", kind = "quad", scale = 0.8, color = rgb(200, 80, 40), accent = rgb(250, 240, 230), ears = "round" },
	-- Jungle
	Frog = { name = "Frog", zone = "Jungle", rarity = "Common", kind = "blob", scale = 0.6, color = rgb(80, 200, 80), accent = rgb(200, 255, 150) },
	Monkey = { name = "Monkey", zone = "Jungle", rarity = "Uncommon", kind = "quad", scale = 0.8, color = rgb(130, 90, 60), accent = rgb(230, 200, 160), ears = "round" },
	Parrot = { name = "Parrot", zone = "Jungle", rarity = "Rare", kind = "bird", scale = 0.8, color = rgb(230, 40, 40), accent = rgb(40, 120, 255) },
	Tiger = { name = "Tiger", zone = "Jungle", rarity = "Epic", kind = "quad", scale = 1.3, color = rgb(245, 140, 30), accent = rgb(30, 30, 30), ears = "round" },
	-- Arctic
	Penguin = { name = "Penguin", zone = "Arctic", rarity = "Common", kind = "bird", scale = 0.8, color = rgb(35, 35, 45), accent = rgb(250, 250, 250) },
	ArcticFox = { name = "Arctic Fox", zone = "Arctic", rarity = "Uncommon", kind = "quad", scale = 0.8, color = rgb(250, 250, 255), accent = rgb(200, 220, 240), ears = "pointy" },
	PolarBear = { name = "Polar Bear", zone = "Arctic", rarity = "Rare", kind = "quad", scale = 1.5, color = rgb(245, 245, 240), accent = rgb(40, 40, 40), ears = "round" },
	IceWolf = { name = "Ice Wolf", zone = "Arctic", rarity = "Epic", kind = "quad", scale = 1.2, color = rgb(160, 210, 255), accent = rgb(230, 245, 255), ears = "pointy" },
	-- Mythic (storms only)
	Unicorn = { name = "Unicorn", rarity = "Mythic", kind = "quad", scale = 1.3, color = rgb(255, 255, 255), accent = rgb(255, 150, 230), ears = "pointy", horn = true },
	Phoenix = { name = "Phoenix", rarity = "Mythic", kind = "bird", scale = 1.2, color = rgb(255, 90, 20), accent = rgb(255, 220, 60), glow = true },
	Dragon = { name = "Dragon", rarity = "Mythic", kind = "quad", scale = 1.6, color = rgb(60, 170, 90), accent = rgb(255, 210, 60), wings = true, horns = true },
}

Animals.MythicIds = {}
for id, species in Animals.Species do
	species.id = id
	if species.rarity == "Mythic" then
		table.insert(Animals.MythicIds, id)
	end
end
table.sort(Animals.MythicIds)

-- All non-mythic species of a zone, sorted from common to rare.
function Animals.speciesInZone(zoneId: string)
	local list = {}
	for _, species in Animals.Species do
		if species.zone == zoneId then
			table.insert(list, species)
		end
	end
	table.sort(list, function(a, b)
		return Animals.Rarities[a.rarity].order < Animals.Rarities[b.rarity].order
	end)
	return list
end

-- Chance (0-1) of each species in a zone. `luck` >= 1 makes non-common animals likelier.
function Animals.speciesOdds(zoneId: string, luck: number)
	local list = Animals.speciesInZone(zoneId)
	local total = 0
	local weights = {}
	for i, species in list do
		local rarity = Animals.Rarities[species.rarity]
		local weight = rarity.weight
		if rarity.order > 1 then
			weight *= luck
		end
		weights[i] = weight
		total += weight
	end
	local odds = {}
	for i, species in list do
		table.insert(odds, { id = species.id, chance = weights[i] / total })
	end
	return odds
end

-- Chance (0-1) of each mutation. `luck` multiplies the mutation chances.
function Animals.mutationOdds(luck: number)
	local golden = math.min(Animals.Mutations.Golden.chance * luck, 0.5)
	local rainbow = math.min(Animals.Mutations.Rainbow.chance * luck, 0.1)
	return {
		{ id = "Rainbow", chance = rainbow },
		{ id = "Golden", chance = golden },
		{ id = "Normal", chance = 1 - golden - rainbow },
	}
end

-- Picks one entry from an odds list using `random` (a Random object).
local function pick(odds, random: Random)
	local roll = random:NextNumber()
	for _, entry in odds do
		roll -= entry.chance
		if roll <= 0 then
			return entry.id
		end
	end
	return odds[#odds].id
end

function Animals.rollSpecies(zoneId: string, luck: number, random: Random): string
	return pick(Animals.speciesOdds(zoneId, luck), random)
end

function Animals.rollMutation(luck: number, random: Random): string
	return pick(Animals.mutationOdds(luck), random)
end

-- Display name, e.g. "Golden Fox".
function Animals.displayName(speciesId: string, mutationId: string?): string
	local species = Animals.Species[speciesId]
	local name = species and species.name or speciesId
	if mutationId and mutationId ~= "Normal" then
		return mutationId .. " " .. name
	end
	return name
end

return Animals
