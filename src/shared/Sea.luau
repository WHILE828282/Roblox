-- Sea.luau
-- Game content: depth zones, rarities, sea creatures and trails.

local Sea = {}

local rgb = Color3.fromRGB

-- weight: walk speed multiplier while carrying the egg (rarer = heavier).
Sea.Rarities = {
	{ id = "Common", weight = 0.85, hatch = 15, color = rgb(210, 214, 222) },
	{ id = "Uncommon", weight = 0.76, hatch = 30, color = rgb(96, 220, 110) },
	{ id = "Rare", weight = 0.67, hatch = 60, color = rgb(70, 160, 255) },
	{ id = "Epic", weight = 0.58, hatch = 120, color = rgb(190, 100, 255) },
	{ id = "Legendary", weight = 0.5, hatch = 240, color = rgb(255, 190, 40) },
	{ id = "Mythic", weight = 0.42, hatch = 480, color = rgb(255, 70, 110) },
}
Sea.RarityById = {}
for index, rarity in Sea.Rarities do
	rarity.index = index
	Sea.RarityById[rarity.id] = rarity
end

-- Depth zones, from the surface down. speed = recommended run speed,
-- guardSpeed = how fast the guardian chases.
Sea.Zones = {
	{ name = "Coral Reef", depth = 50, speed = 16, guardSpeed = 15, guard = "Giant Crab",
		water = rgb(70, 200, 220), glow = rgb(255, 120, 170) },
	{ name = "Sunken Fleet", depth = 150, speed = 30, guardSpeed = 27, guard = "Ghost Shark",
		water = rgb(40, 130, 190), glow = rgb(120, 255, 220) },
	{ name = "Ruins of Atlantis", depth = 300, speed = 50, guardSpeed = 45, guard = "Stone Titan",
		water = rgb(28, 84, 160), glow = rgb(90, 200, 255) },
	{ name = "Jellyfish Cave", depth = 500, speed = 80, guardSpeed = 72, guard = "Jelly Queen",
		water = rgb(40, 34, 120), glow = rgb(210, 120, 255) },
	{ name = "Mariana Abyss", depth = 1000, speed = 120, guardSpeed = 108, guard = "The Kraken",
		water = rgb(8, 8, 30), glow = rgb(255, 60, 90) },
}

-- Creatures. chance = weight inside its zone, income = money per second.
-- shape: "fish", "round", "long", "flat" or "jelly" (see CreatureModel.luau).
Sea.Creatures = {
	Clownfish = { zone = 1, rarity = "Common", chance = 60, income = 2, shape = "fish", color = rgb(255, 130, 40), accent = rgb(255, 255, 255) },
	Seahorse = { zone = 1, rarity = "Uncommon", chance = 30, income = 5, shape = "long", color = rgb(255, 210, 70), accent = rgb(255, 150, 60) },
	Pufferfish = { zone = 1, rarity = "Rare", chance = 10, income = 12, shape = "round", color = rgb(250, 230, 120), accent = rgb(180, 130, 60) },
	Crab = { zone = 2, rarity = "Uncommon", chance = 60, income = 10, shape = "flat", color = rgb(235, 80, 60), accent = rgb(255, 180, 150) },
	Swordfish = { zone = 2, rarity = "Rare", chance = 30, income = 28, shape = "fish", color = rgb(80, 130, 220), accent = rgb(220, 230, 255) },
	GhostShark = { name = "Ghost Shark", zone = 2, rarity = "Epic", chance = 10, income = 70, shape = "fish", color = rgb(190, 255, 240), accent = rgb(120, 220, 210), glow = true },
	SeaTurtle = { name = "Sea Turtle", zone = 3, rarity = "Rare", chance = 60, income = 60, shape = "flat", color = rgb(90, 180, 110), accent = rgb(60, 110, 70) },
	TridentEel = { name = "Trident Eel", zone = 3, rarity = "Epic", chance = 30, income = 160, shape = "long", color = rgb(70, 220, 255), accent = rgb(255, 240, 120), glow = true },
	GoldenManta = { name = "Golden Manta", zone = 3, rarity = "Legendary", chance = 10, income = 420, shape = "flat", color = rgb(255, 205, 60), accent = rgb(255, 250, 200), glow = true },
	MoonJelly = { name = "Moon Jelly", zone = 4, rarity = "Epic", chance = 60, income = 350, shape = "jelly", color = rgb(200, 160, 255), accent = rgb(255, 255, 255), glow = true },
	LanternAngler = { name = "Lantern Angler", zone = 4, rarity = "Legendary", chance = 30, income = 950, shape = "round", color = rgb(70, 60, 110), accent = rgb(255, 240, 120), glow = true },
	PrismSquid = { name = "Prism Squid", zone = 4, rarity = "Legendary", chance = 10, income = 1500, shape = "jelly", color = rgb(255, 120, 220), accent = rgb(120, 255, 255), glow = true },
	AbyssSerpent = { name = "Abyss Serpent", zone = 5, rarity = "Legendary", chance = 60, income = 3000, shape = "long", color = rgb(60, 40, 120), accent = rgb(255, 60, 90), glow = true },
	KrakenSpawn = { name = "Kraken Spawn", zone = 5, rarity = "Mythic", chance = 30, income = 9000, shape = "jelly", color = rgb(160, 30, 70), accent = rgb(255, 150, 60), glow = true },
	Leviathan = { zone = 5, rarity = "Mythic", chance = 10, income = 25000, shape = "fish", color = rgb(20, 20, 50), accent = rgb(255, 60, 90), glow = true },
}
Sea.CreatureOrder = {
	"Clownfish", "Seahorse", "Pufferfish", "Crab", "Swordfish", "GhostShark", "SeaTurtle", "TridentEel",
	"GoldenManta", "MoonJelly", "LanternAngler", "PrismSquid", "AbyssSerpent", "KrakenSpawn", "Leviathan",
}
for id, creature in Sea.Creatures do
	creature.id = id
	creature.name = creature.name or id
end

-- Trails: bought with coins, multiply how fast the treadmill trains you.
Sea.Trails = {
	{ id = "Bubbles", name = "Bubbles", price = 500, multiplier = 1.5, colors = { rgb(200, 240, 255), rgb(120, 200, 255) }, particle = "bubbles" },
	{ id = "Starfish", name = "Starfish", price = 2500, multiplier = 2, colors = { rgb(255, 170, 80), rgb(255, 90, 120) }, particle = "stars" },
	{ id = "Neon", name = "Neon Current", price = 10000, multiplier = 3, colors = { rgb(60, 255, 200), rgb(60, 120, 255) } },
	{ id = "Kelp", name = "Kelp Rush", price = 40000, multiplier = 4, colors = { rgb(120, 255, 90), rgb(20, 140, 80) }, particle = "bubbles" },
	{ id = "Lightning", name = "Eel Lightning", price = 150000, multiplier = 6, colors = { rgb(255, 255, 140), rgb(120, 200, 255) }, particle = "sparks" },
	{ id = "Jelly", name = "Jelly Glow", price = 500000, multiplier = 8, colors = { rgb(255, 140, 255), rgb(140, 100, 255) }, particle = "stars" },
	{ id = "Abyss", name = "Abyss Fire", price = 2000000, multiplier = 12, colors = { rgb(255, 60, 90), rgb(90, 20, 160) }, particle = "fire" },
}
Sea.TrailById = {}
for _, trail in Sea.Trails do
	Sea.TrailById[trail.id] = trail
end

function Sea.trailMultiplier(trailId: string?): number
	local trail = trailId and Sea.TrailById[trailId]
	return if trail then trail.multiplier else 1
end

-- Picks a creature for a new egg in `zone`.
function Sea.rollCreature(zone: number, random: Random): string
	local total, list = 0, {}
	for _, id in Sea.CreatureOrder do
		local creature = Sea.Creatures[id]
		if creature.zone == zone then
			total += creature.chance
			table.insert(list, creature)
		end
	end
	local roll = random:NextNumber() * total
	for _, creature in list do
		roll -= creature.chance
		if roll <= 0 then
			return creature.id
		end
	end
	return list[#list].id
end

-- Chance (0-1) of a creature inside its own zone, for the Index.
function Sea.chance(creatureId: string): number
	local creature = Sea.Creatures[creatureId]
	local total = 0
	for _, other in Sea.Creatures do
		if other.zone == creature.zone then
			total += other.chance
		end
	end
	return creature.chance / total
end

function Sea.rarityOf(creatureId: string)
	return Sea.RarityById[Sea.Creatures[creatureId].rarity]
end

return Sea
