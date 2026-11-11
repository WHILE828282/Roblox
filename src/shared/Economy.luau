-- Economy.luau
-- Prices and formulas shared by server and client, so the UI always
-- shows exactly what the server will charge or pay.

local Dinos = require(script.Parent.Dinos)

local Economy = {}

Economy.Upgrades = {
	Nests = { name = "More Nests", description = "+1 nest for eggs", maxLevel = 7, baseCost = 400, growth = 6 },
	Pen = { name = "Bigger Pen", description = "+2 dinosaur slots", maxLevel = 15, baseCost = 600, growth = 3.2 },
	Strength = { name = "Strength", description = "+5 hit damage", maxLevel = 10, baseCost = 800, growth = 4 },
}
Economy.UpgradeOrder = { "Nests", "Pen", "Strength" }

Economy.BaseNests = 3
Economy.ExtraNestsPass = 3
Economy.BasePen = 6
Economy.PenPerLevel = 2
Economy.SellSeconds = 120 -- a dinosaur sells for this many seconds of its income

function Economy.upgradeCost(upgradeId: string, level: number): number?
	local upgrade = Economy.Upgrades[upgradeId]
	if not upgrade or level >= upgrade.maxLevel then
		return nil
	end
	return math.floor(upgrade.baseCost * upgrade.growth ^ level)
end

function Economy.nests(level: number, hasExtraNests: boolean): number
	return Economy.BaseNests + level + (if hasExtraNests then Economy.ExtraNestsPass else 0)
end

function Economy.penSize(level: number): number
	return Economy.BasePen + level * Economy.PenPerLevel
end

-- 1 = baby, 2 = teen, 3 = adult
function Economy.stage(tierId: string, growth: number): number
	local tier = Dinos.TierById[tierId] or Dinos.Tiers[1]
	if growth >= tier.grow * 2 then
		return 3
	elseif growth >= tier.grow then
		return 2
	end
	return 1
end

-- Seconds of growth left until the next stage (0 when adult).
function Economy.growthLeft(tierId: string, growth: number): number
	local tier = Dinos.TierById[tierId] or Dinos.Tiers[1]
	if growth >= tier.grow * 2 then
		return 0
	elseif growth >= tier.grow then
		return tier.grow * 2 - growth
	end
	return tier.grow - growth
end

-- Money per second from one dinosaur (before the x2 Money pass).
function Economy.dinoIncome(dino): number
	local species = Dinos.Species[dino.s]
	local tier = Dinos.TierById[dino.t]
	local mutation = Dinos.Mutations[dino.m] or Dinos.Mutations.Normal
	if not species or not tier then
		return 0
	end
	local stage = Dinos.Stages[Economy.stage(dino.t, dino.g or 0)]
	return math.floor(species.income * tier.income * mutation.multiplier * stage.income * 10 + 0.5) / 10
end

function Economy.sellPrice(dino): number
	return math.floor(Economy.dinoIncome(dino) * Economy.SellSeconds)
end

function Economy.hatchTime(tierId: string): number
	local tier = Dinos.TierById[tierId] or Dinos.Tiers[1]
	return tier.hatch
end

-- Riding speed: species base + 1.5 per tier above Common.
function Economy.mountSpeed(dino): number
	local species = Dinos.Species[dino.s]
	local tier = Dinos.TierById[dino.t] or Dinos.Tiers[1]
	return (species and species.speed or 20) + (tier.index - 1) * 1.5
end

-- Extra damage a mounted rider deals.
function Economy.mountDamage(dino): number
	local tier = Dinos.TierById[dino.t] or Dinos.Tiers[1]
	return (tier.index - 1) * 4
end

return Economy
