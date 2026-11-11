-- Economy.luau
-- Prices and formulas shared by server and client, so the UI always
-- shows exactly what the server will charge or pay.

local Animals = require(script.Parent.Animals)

local Economy = {}

-- Upgrades bought with in-game money.
Economy.Upgrades = {
	Speed = { name = "Rescue Speed", maxLevel = 10, baseCost = 300, growth = 3 },
	Shelter = { name = "Shelter Size", maxLevel = 20, baseCost = 500, growth = 2.2 },
	Luck = { name = "Luck", maxLevel = 10, baseCost = 1000, growth = 3 },
}
Economy.UpgradeOrder = { "Speed", "Shelter", "Luck" }

Economy.BaseCapacity = 8
Economy.CapacityPerLevel = 2
Economy.BigShelterBonus = 10
Economy.SpeedPerLevel = 0.9 -- rescue time multiplier per Speed level
Economy.LuckPerLevel = 0.15 -- +15% luck per Luck level
Economy.SellSeconds = 60 -- an animal sells for this many seconds of its income

-- Cost of the next level, or nil when maxed.
function Economy.upgradeCost(upgradeId: string, level: number): number?
	local upgrade = Economy.Upgrades[upgradeId]
	if not upgrade or level >= upgrade.maxLevel then
		return nil
	end
	return math.floor(upgrade.baseCost * upgrade.growth ^ level)
end

-- Money per second earned by one animal (before gamepass multipliers).
function Economy.animalIncome(speciesId: string, mutationId: string, zoneId: string?): number
	local species = Animals.Species[speciesId]
	local mutation = Animals.Mutations[mutationId] or Animals.Mutations.Normal
	if not species then
		return 0
	end
	local zone = Animals.ZoneById[zoneId or species.zone or "Forest"] or Animals.Zones[1]
	return Animals.Rarities[species.rarity].income * zone.multiplier * mutation.multiplier
end

function Economy.sellPrice(speciesId: string, mutationId: string, zoneId: string?): number
	return Economy.animalIncome(speciesId, mutationId, zoneId) * Economy.SellSeconds
end

function Economy.capacity(shelterLevel: number, hasBigShelter: boolean): number
	return Economy.BaseCapacity + shelterLevel * Economy.CapacityPerLevel + (if hasBigShelter then Economy.BigShelterBonus else 0)
end

-- Seconds a player must hold to rescue an animal of this rarity.
function Economy.rescueTime(rarityId: string, speedLevel: number, hasFastHands: boolean): number
	local rarity = Animals.Rarities[rarityId] or Animals.Rarities.Common
	local time = rarity.rescueTime * Economy.SpeedPerLevel ^ speedLevel
	if hasFastHands then
		time *= 0.5
	end
	return time
end

-- Personal luck multiplier (1 = no bonus).
function Economy.personalLuck(luckLevel: number, boosted: boolean): number
	local luck = 1 + luckLevel * Economy.LuckPerLevel
	if boosted then
		luck *= 2
	end
	return luck
end

return Economy
