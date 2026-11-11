-- Dinos.luau
-- Dinosaur species, rarity tiers, mutations and egg odds.
-- Add a species by adding one entry to Dinos.Species.

local Dinos = {}

local rgb = Color3.fromRGB

-- Rarity tiers, from common to the rarest.
-- income: money multiplier, hatch: seconds in the nest,
-- grow: seconds per growth stage (baby -> teen -> adult needs 2x this).
Dinos.Tiers = {
	{ id = "Common", income = 1, hatch = 30, grow = 60, color = rgb(205, 205, 210) },
	{ id = "Rare", income = 6, hatch = 60, grow = 90, color = rgb(80, 150, 255) },
	{ id = "Epic", income = 40, hatch = 120, grow = 150, color = rgb(180, 90, 255) },
	{ id = "Legendary", income = 300, hatch = 300, grow = 240, color = rgb(255, 175, 30) },
	{ id = "Mythic", income = 2500, hatch = 600, grow = 360, color = rgb(255, 70, 70) },
	{ id = "Secret", income = 25000, hatch = 900, grow = 480, color = rgb(30, 30, 35) },
	{ id = "Divine", income = 300000, hatch = 1800, grow = 600, color = rgb(255, 245, 160) },
}
Dinos.TierById = {}
for index, tier in Dinos.Tiers do
	tier.index = index
	Dinos.TierById[tier.id] = tier
end

Dinos.Mutations = {
	Normal = { multiplier = 1, chance = 0 },
	Golden = { multiplier = 3, chance = 1 / 50, color = rgb(255, 200, 40) },
	Rainbow = { multiplier = 10, chance = 1 / 500 },
}

-- Growth stages: income share and model size.
Dinos.Stages = {
	{ id = "Baby", income = 0.25, scale = 0.45 },
	{ id = "Teen", income = 0.6, scale = 0.7 },
	{ id = "Adult", income = 1, scale = 1 },
}

-- Species. `ability` is used when riding (see Combat.luau).
Dinos.Species = {
	Raptor = {
		name = "Raptor",
		kind = "biped",
		size = 1,
		income = 1,
		speed = 30,
		carry = 1,
		ability = "Sprint",
		color = rgb(120, 160, 70),
		accent = rgb(230, 220, 160),
	},
	Triceratops = {
		name = "Triceratops",
		kind = "quad",
		size = 1.25,
		income = 1.2,
		speed = 24,
		carry = 2,
		ability = "Ram",
		frill = true,
		color = rgb(90, 130, 170),
		accent = rgb(240, 230, 200),
	},
	Stegosaurus = {
		name = "Stegosaurus",
		kind = "quad",
		size = 1.3,
		income = 1.1,
		speed = 22,
		carry = 2,
		ability = "TailSpin",
		plates = true,
		armor = 0.5,
		color = rgb(150, 110, 70),
		accent = rgb(220, 90, 50),
	},
	TRex = {
		name = "T-Rex",
		kind = "biped",
		size = 1.6,
		income = 1.5,
		speed = 26,
		carry = 3,
		ability = "Roar",
		bigHead = true,
		color = rgb(110, 85, 60),
		accent = rgb(210, 190, 150),
	},
}
Dinos.SpeciesOrder = { "Raptor", "Triceratops", "Stegosaurus", "TRex" }
for id, species in Dinos.Species do
	species.id = id
end

Dinos.Abilities = {
	Sprint = { name = "Sprint", description = "Run much faster for 3 seconds" },
	Ram = { name = "Ram", description = "Charge forward and knock players over" },
	TailSpin = { name = "Tail Spin", description = "Knock back everyone around you" },
	Roar = { name = "Roar", description = "Everyone nearby drops their eggs" },
}

-- Egg tier weights for each ring of the field (inner = closest to the volcano).
Dinos.RingOdds = {
	Outer = { Common = 70, Rare = 25, Epic = 5 },
	Middle = { Common = 40, Rare = 35, Epic = 18, Legendary = 6, Mythic = 1 },
	Inner = { Rare = 30, Epic = 35, Legendary = 22, Mythic = 9.5, Secret = 3, Divine = 0.5 },
	Big = { Legendary = 60, Mythic = 30, Secret = 8, Divine = 2 }, -- the guaranteed big-eruption egg
}
Dinos.RingOrder = { "Outer", "Middle", "Inner", "Big" }

-- Chance (0-1) of each tier in a ring. `luck` >= 1 favours rarer tiers.
function Dinos.tierOdds(ring: string, luck: number)
	local weights = Dinos.RingOdds[ring]
	local lowest = math.huge
	for tierId in weights do
		lowest = math.min(lowest, Dinos.TierById[tierId].index)
	end
	local list, total = {}, 0
	for _, tier in Dinos.Tiers do
		local weight = weights[tier.id]
		if weight then
			if tier.index > lowest then
				weight *= luck
			end
			table.insert(list, { id = tier.id, weight = weight })
			total += weight
		end
	end
	for _, entry in list do
		entry.chance = entry.weight / total
	end
	return list
end

function Dinos.mutationOdds(luck: number)
	local golden = math.min(Dinos.Mutations.Golden.chance * luck, 0.5)
	local rainbow = math.min(Dinos.Mutations.Rainbow.chance * luck, 0.1)
	return {
		{ id = "Rainbow", chance = rainbow },
		{ id = "Golden", chance = golden },
		{ id = "Normal", chance = 1 - golden - rainbow },
	}
end

local function pick(list, random: Random)
	local roll = random:NextNumber()
	for _, entry in list do
		roll -= entry.chance
		if roll <= 0 then
			return entry.id
		end
	end
	return list[#list].id
end

-- Rolls a full egg: species, tier and mutation.
function Dinos.rollEgg(ring: string, luck: number, random: Random)
	local species = Dinos.SpeciesOrder[random:NextInteger(1, #Dinos.SpeciesOrder)]
	return {
		s = species,
		t = pick(Dinos.tierOdds(ring, luck), random),
		m = pick(Dinos.mutationOdds(luck), random),
	}
end

-- "Golden Legendary T-Rex"
function Dinos.displayName(speciesId: string, tierId: string, mutationId: string?): string
	local species = Dinos.Species[speciesId]
	local name = (if tierId then tierId .. " " else "") .. (species and species.name or speciesId)
	if mutationId and mutationId ~= "Normal" then
		name = mutationId .. " " .. name
	end
	return name
end

return Dinos
