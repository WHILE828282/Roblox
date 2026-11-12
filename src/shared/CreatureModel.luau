-- CreatureModel.luau
-- Builds sea creatures, eggs and guardians out of smooth rounded shapes.
-- Every model looks along -Z and its pivot is its center.

local Sea = require(script.Parent.Sea)

local CreatureModel = {}

local BLACK = Color3.fromRGB(20, 22, 34)
local WHITE = Color3.fromRGB(255, 255, 255)

local function shape(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, meshType: Enum.MeshType?, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if meshType then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = meshType
		mesh.Parent = part
	end
	part.Parent = model
	return part
end

local function eyes(model: Model, front: number, height: number, spread: number, size: number)
	for _, side in { -1, 1 } do
		local at = CFrame.new(side * spread, height, front)
		shape(model, "Eye", Vector3.one * size, at, WHITE, Enum.MeshType.Sphere)
		shape(model, "Pupil", Vector3.one * size * 0.55, at * CFrame.new(side * size * 0.12, 0, -size * 0.32), BLACK, Enum.MeshType.Sphere)
	end
end

local function fin(model: Model, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?)
	local part = shape(model, "Fin", size, cframe, color, nil, material)
	part.Shape = Enum.PartType.Wedge
	return part
end

local BUILDERS = {}

-- Classic fish: oval body, tail, back fin.
function BUILDERS.fish(model, s, c, a, mat)
	shape(model, "Body", Vector3.new(1.5, 1.8, 3.4) * s, CFrame.new(), c, Enum.MeshType.Sphere, mat)
	shape(model, "Belly", Vector3.new(1.3, 1.1, 2.6) * s, CFrame.new(0, -0.35 * s, -0.1 * s), a, Enum.MeshType.Sphere, mat)
	fin(model, Vector3.new(0.25, 1.9, 1.3) * s, CFrame.new(0, 0, 2.1 * s) * CFrame.Angles(math.rad(90), 0, 0), a, mat)
	fin(model, Vector3.new(0.25, 1.9, 1.3) * s, CFrame.new(0, 0, 2.1 * s) * CFrame.Angles(math.rad(-90), 0, math.rad(180)), a, mat)
	fin(model, Vector3.new(0.2, 0.9, 1.4) * s, CFrame.new(0, 1.2 * s, 0.2 * s), a, mat)
	eyes(model, -1.15 * s, 0.25 * s, 0.6 * s, 0.5 * s)
end

-- Round body with spikes (puffer, angler).
function BUILDERS.round(model, s, c, a, mat)
	shape(model, "Body", Vector3.new(2.6, 2.5, 2.8) * s, CFrame.new(), c, Enum.MeshType.Sphere, mat)
	for i = 1, 10 do
		local direction = CFrame.Angles(0, i * 2.4, 0) * CFrame.Angles(math.rad(-60 + (i % 4) * 40), 0, 0)
		local spike = shape(model, "Spike", Vector3.new(0.3, 0.3, 0.9) * s, direction * CFrame.new(0, 0, -1.45 * s), a, nil, mat)
		spike.Shape = Enum.PartType.Block
	end
	fin(model, Vector3.new(0.2, 1.1, 0.9) * s, CFrame.new(0, 0, 1.6 * s) * CFrame.Angles(math.rad(90), 0, 0), a, mat)
	eyes(model, -1.05 * s, 0.4 * s, 0.75 * s, 0.6 * s)
end

-- Long snake-like body made of shrinking balls.
function BUILDERS.long(model, s, c, a, mat)
	for i = 0, 6 do
		local size = (1.5 - i * 0.16) * s
		shape(model, if i == 0 then "Body" else "Segment", Vector3.one * size,
			CFrame.new(math.sin(i * 0.9) * 0.45 * s, math.sin(i * 0.7) * 0.2 * s, i * 0.95 * s),
			if i % 2 == 0 then c else a, Enum.MeshType.Sphere, mat)
	end
	fin(model, Vector3.new(0.2, 0.8, 1.2) * s, CFrame.new(0, 0.9 * s, 0.6 * s), a, mat)
	eyes(model, -0.6 * s, 0.25 * s, 0.45 * s, 0.45 * s)
end

-- Wide flat body (crab, turtle, manta).
function BUILDERS.flat(model, s, c, a, mat)
	shape(model, "Body", Vector3.new(3.4, 1.2, 2.8) * s, CFrame.new(), c, Enum.MeshType.Sphere, mat)
	shape(model, "Shell", Vector3.new(2.4, 1.0, 2.0) * s, CFrame.new(0, 0.35 * s, 0.1 * s), a, Enum.MeshType.Sphere, mat)
	for _, side in { -1, 1 } do
		shape(model, "Flipper", Vector3.new(1.6, 0.35, 1.0) * s,
			CFrame.new(side * 2.1 * s, -0.1 * s, -0.5 * s) * CFrame.Angles(0, side * 0.5, side * -0.3), c, Enum.MeshType.Sphere, mat)
		shape(model, "Flipper", Vector3.new(1.1, 0.3, 0.8) * s,
			CFrame.new(side * 1.7 * s, -0.15 * s, 1.1 * s) * CFrame.Angles(0, side * -0.5, side * -0.3), c, Enum.MeshType.Sphere, mat)
	end
	shape(model, "Head", Vector3.new(1.2, 1.0, 1.2) * s, CFrame.new(0, 0.15 * s, -1.6 * s), c, Enum.MeshType.Sphere, mat)
	eyes(model, -2.0 * s, 0.35 * s, 0.38 * s, 0.4 * s)
end

-- Dome with hanging tentacles (jellyfish, squid).
function BUILDERS.jelly(model, s, c, a, mat)
	local dome = shape(model, "Body", Vector3.new(2.8, 2.2, 2.8) * s, CFrame.new(0, 0.6 * s, 0), c, Enum.MeshType.Sphere, mat)
	dome.Transparency = 0.2
	shape(model, "Core", Vector3.new(1.5, 1.2, 1.5) * s, CFrame.new(0, 0.6 * s, 0), a, Enum.MeshType.Sphere, Enum.Material.Neon)
	for i = 1, 7 do
		local angle = i * math.pi * 2 / 7
		local length = (1.8 + (i % 3) * 0.5) * s
		shape(model, "Tentacle", Vector3.new(0.28 * s, length, 0.28 * s),
			CFrame.new(math.cos(angle) * 0.85 * s, -0.3 * s - length / 2, math.sin(angle) * 0.85 * s), a, nil, mat)
	end
	eyes(model, -1.2 * s, 0.6 * s, 0.5 * s, 0.5 * s)
end

local function finish(model: Model, glowColor: Color3?, range: number?)
	local body = model:FindFirstChild("Body") :: Part
	model.PrimaryPart = body
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if glowColor then
		local light = Instance.new("PointLight")
		light.Color = glowColor
		light.Range = range or 12
		light.Brightness = 1.5
		light.Shadows = false
		light.Parent = body
	end
end

-- A sea creature. `scale` 1 is about 3 studs long.
function CreatureModel.build(creatureId: string, scale: number?): Model
	local creature = Sea.Creatures[creatureId]
	assert(creature, "Unknown creature: " .. tostring(creatureId))
	local model = Instance.new("Model")
	model.Name = creatureId
	local material = if creature.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	BUILDERS[creature.shape](model, scale or 1, creature.color, creature.accent, material)
	finish(model, if creature.glow then creature.color else nil, 10)
	model:SetAttribute("Creature", creatureId)
	return model
end

-- A glowing egg; rarer eggs are bigger.
function CreatureModel.buildEgg(creatureId: string): Model
	local creature = Sea.Creatures[creatureId]
	local rarity = Sea.rarityOf(creatureId)
	local size = 2.2 + rarity.index * 0.35
	local model = Instance.new("Model")
	model.Name = "Egg"
	local shell = shape(model, "Body", Vector3.new(size, size * 1.3, size), CFrame.new(), rarity.color, Enum.MeshType.Sphere, Enum.Material.Neon)
	shell.Transparency = 0.1
	-- Spots in the color of the creature inside.
	for i = 1, 5 do
		local direction = CFrame.Angles(0, i * 1.3, 0) * CFrame.Angles(math.rad(-40 + i * 18), 0, 0)
		shape(model, "Spot", Vector3.new(0.45, 0.45, 0.12) * size, direction * CFrame.new(0, 0, -size * 0.49), creature.color, Enum.MeshType.Sphere)
	end
	finish(model, rarity.color, 10 + rarity.index * 3)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(rarity.color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 + rarity.index * 0.12), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Speed = NumberRange.new(1, 3)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 2 + rarity.index * 3
	sparks.Parent = shell
	model:SetAttribute("Creature", creatureId)
	return model
end

-- The huge guardian of a zone: a different monster for every depth.
function CreatureModel.buildGuard(zoneIndex: number): Model
	local zone = Sea.Zones[zoneIndex]
	local model = Instance.new("Model")
	model.Name = zone.guard
	local s = 4 + zoneIndex * 0.7
	local dark = zone.water:Lerp(BLACK, 0.45)
	local shapes = { "flat", "fish", "round", "jelly", "long" }
	BUILDERS[shapes[zoneIndex]](model, s, dark, zone.glow, Enum.Material.SmoothPlastic)
	-- Angry glowing eyes and teeth.
	for _, part in model:GetChildren() do
		if part.Name == "Pupil" then
			part.Color = zone.glow
			part.Material = Enum.Material.Neon
		end
	end
	for i = -2, 2 do
		local tooth = shape(model, "Tooth", Vector3.new(0.28, 0.6, 0.28) * s, CFrame.new(i * 0.32 * s, -0.35 * s, -1.3 * s), WHITE)
		tooth.Shape = Enum.PartType.Block
	end
	finish(model, zone.glow, 30)
	model:SetAttribute("Zone", zoneIndex)
	return model
end

-- Welds everything to the body and unanchors it, so it can be carried.
function CreatureModel.makeCarryable(model: Model)
	local primary = model.PrimaryPart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			if part ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
end

return CreatureModel
