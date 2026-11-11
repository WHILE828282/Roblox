-- DinoModel.luau
-- Builds blocky dinosaur and egg Models from the definitions in Dinos.luau.
-- No 3D files needed: everything is made of Parts.
-- A dinosaur's pivot is the ground point under its center and it faces -Z,
-- so `model:PivotTo(CFrame.new(position))` places it on the ground.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)
local Dinos = require(script.Parent.Dinos)

local DinoModel = {}

local BLACK = Color3.fromRGB(25, 25, 30)
local WHITE = Color3.fromRGB(245, 245, 240)
local GOLD = Color3.fromRGB(255, 200, 40)

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material?
)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = CFrame.new(position)
	part.Parent = model
	return part
end

local function addEyes(model: Model, headCenter: Vector3, headSize: Vector3, s: number)
	for _, side in { -1, 1 } do
		local position = headCenter + Vector3.new(side * (headSize.X / 2 + 0.02), headSize.Y * 0.2, -headSize.Z * 0.2)
		makePart(model, "Eye", Vector3.new(0.08, 0.25, 0.25) * s, position, BLACK)
	end
end

-- Two-legged dinosaur (Raptor, T-Rex). Returns the height of its back.
local function buildBiped(model: Model, species, s: number): number
	for _, side in { -1, 1 } do
		makePart(
			model,
			"Leg",
			Vector3.new(0.6, 1.6, 0.7) * s,
			Vector3.new(side * 0.5 * s, 0.8 * s, 0.2 * s),
			species.color
		)
		makePart(
			model,
			"Arm",
			Vector3.new(0.25, 0.6, 0.25) * s,
			Vector3.new(side * 0.55 * s, 2.0 * s, -1.0 * s),
			species.color
		)
	end
	local bodySize = Vector3.new(1.4, 1.3, 2.4) * s
	local bodyY = 1.6 * s + bodySize.Y / 2
	makePart(model, "Body", bodySize, Vector3.new(0, bodyY, 0), species.color)
	makePart(model, "Belly", Vector3.new(1.0, 0.9, 1.6) * s, Vector3.new(0, bodyY - 0.25 * s, -0.1 * s), species.accent)
	makePart(
		model,
		"Tail",
		Vector3.new(0.6, 0.6, 2.6) * s,
		Vector3.new(0, bodyY + 0.05 * s, bodySize.Z / 2 + 1.2 * s),
		species.color
	)
	makePart(
		model,
		"TailTip",
		Vector3.new(0.35, 0.35, 1.2) * s,
		Vector3.new(0, bodyY - 0.05 * s, bodySize.Z / 2 + 3.1 * s),
		species.color
	)
	makePart(model, "Neck", Vector3.new(0.8, 1.0, 0.8) * s, Vector3.new(0, bodyY + 0.6 * s, -1.2 * s), species.color)

	local headSize = (if species.bigHead then Vector3.new(1.4, 1.1, 1.9) else Vector3.new(1.0, 0.8, 1.4)) * s
	local head = Vector3.new(0, bodyY + 1.1 * s, -1.4 * s - headSize.Z / 2)
	makePart(model, "Head", headSize, head, species.color)
	makePart(
		model,
		"Jaw",
		Vector3.new(headSize.X * 0.85, 0.3 * s, headSize.Z * 0.85),
		head + Vector3.new(0, -headSize.Y / 2 - 0.12 * s, -0.05 * s),
		species.accent
	)
	makePart(
		model,
		"Teeth",
		Vector3.new(headSize.X * 0.8, 0.12 * s, 0.1 * s),
		head + Vector3.new(0, -headSize.Y / 2 + 0.02, -headSize.Z / 2 + 0.1 * s),
		WHITE
	)
	addEyes(model, head, headSize, s)
	return bodyY + bodySize.Y / 2
end

-- Four-legged dinosaur (Triceratops, Stegosaurus). Returns the height of its back.
local function buildQuad(model: Model, species, s: number): number
	for _, x in { -0.6, 0.6 } do
		for _, z in { -0.9, 0.9 } do
			makePart(model, "Leg", Vector3.new(0.6, 1.2, 0.6) * s, Vector3.new(x * s, 0.6 * s, z * s), species.color)
		end
	end
	local bodySize = Vector3.new(1.8, 1.4, 3.0) * s
	local bodyY = 1.2 * s + bodySize.Y / 2
	makePart(model, "Body", bodySize, Vector3.new(0, bodyY, 0), species.color)
	makePart(model, "Belly", Vector3.new(1.4, 0.5, 2.4) * s, Vector3.new(0, bodyY - 0.5 * s, 0), species.accent)
	makePart(
		model,
		"Tail",
		Vector3.new(0.6, 0.5, 2.4) * s,
		Vector3.new(0, bodyY - 0.1 * s, bodySize.Z / 2 + 1.1 * s),
		species.color
	)

	local headSize = Vector3.new(1.1, 1.0, 1.4) * s
	local head = Vector3.new(0, bodyY - 0.1 * s, -bodySize.Z / 2 - headSize.Z / 2 + 0.1 * s)
	makePart(model, "Head", headSize, head, species.color)
	makePart(
		model,
		"Beak",
		Vector3.new(0.6, 0.5, 0.4) * s,
		head + Vector3.new(0, -0.2 * s, -headSize.Z / 2 - 0.15 * s),
		species.accent
	)
	addEyes(model, head, headSize, s)

	if species.frill then
		makePart(
			model,
			"Frill",
			Vector3.new(2.3, 1.7, 0.3) * s,
			head + Vector3.new(0, 0.6 * s, headSize.Z / 2),
			species.accent
		)
		for _, x in { -0.3, 0.3 } do
			makePart(
				model,
				"Horn",
				Vector3.new(0.2, 0.2, 1.0) * s,
				head + Vector3.new(x * s, 0.45 * s, -headSize.Z / 2 - 0.4 * s),
				WHITE
			)
		end
		makePart(
			model,
			"Horn",
			Vector3.new(0.2, 0.2, 0.6) * s,
			head + Vector3.new(0, 0, -headSize.Z / 2 - 0.45 * s),
			WHITE
		)
	end
	if species.plates then
		for i = -2, 2 do
			makePart(
				model,
				"Plate",
				Vector3.new(0.2, 0.9, 0.7) * s,
				Vector3.new(0, bodyY + bodySize.Y / 2 + 0.4 * s, i * 0.6 * s),
				species.accent
			)
		end
		for _, x in { -0.3, 0.3 } do
			makePart(
				model,
				"Spike",
				Vector3.new(0.15, 0.15, 0.8) * s,
				Vector3.new(x * s, bodyY + 0.2 * s, bodySize.Z / 2 + 2.2 * s),
				WHITE
			)
		end
	end
	return bodyY + bodySize.Y / 2
end

local function applyTierLook(model: Model, root: BasePart, tierId: string, mutationId: string)
	local tier = Dinos.TierById[tierId]
	local glowing = tier and tier.index >= 6 -- Secret and Divine glow
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and part ~= root and part.Name ~= "Eye" and part.Name ~= "Teeth" then
			if mutationId == "Golden" then
				part.Color = GOLD
				part.Material = Enum.Material.Foil
			elseif mutationId == "Rainbow" then
				part.Material = Enum.Material.Neon
				CollectionService:AddTag(part, Config.Tags.RainbowPart)
			elseif tierId == "Secret" then
				part.Color = part.Color:Lerp(Color3.fromRGB(20, 20, 30), 0.7)
			elseif tierId == "Divine" then
				part.Color = part.Color:Lerp(Color3.fromRGB(255, 250, 210), 0.6)
			end
			if
				glowing and (part.Name == "Belly" or part.Name == "Plate" or part.Name == "Frill" or part.Name == "Jaw")
			then
				part.Material = Enum.Material.Neon
				part.Color = tier.color
			end
		end
	end
	if mutationId ~= "Normal" or (tier and tier.index >= 4) then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = if mutationId == "Golden" then GOLD else (tier and tier.color or GOLD)
		sparkles.Parent = root
	end
end

-- Builds a dinosaur. `stage` is 1 (baby), 2 (teen) or 3 (adult).
-- The model gets attribute "BackHeight" (studs from the ground to its back).
function DinoModel.build(speciesId: string, tierId: string, mutationId: string?, stage: number?): Model
	local species = Dinos.Species[speciesId]
	assert(species, "Unknown species: " .. tostring(speciesId))
	mutationId = mutationId or "Normal"
	local stageInfo = Dinos.Stages[stage or 3]

	local model = Instance.new("Model")
	model.Name = speciesId
	local root = makePart(model, "Root", Vector3.new(1, 0.2, 1), Vector3.new(0, 0, 0), WHITE)
	root.Transparency = 1
	model.PrimaryPart = root

	local s = species.size * stageInfo.scale
	local backHeight = if species.kind == "quad" then buildQuad(model, species, s) else buildBiped(model, species, s)
	applyTierLook(model, root, tierId, mutationId)

	model:SetAttribute("BackHeight", backHeight)
	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Tier", tierId)
	model:SetAttribute("Mutation", mutationId)
	return model
end

-- Builds an egg. The pivot is the egg's center; it is about 3 studs tall.
function DinoModel.buildEgg(speciesId: string, tierId: string, mutationId: string?): Model
	local tier = Dinos.TierById[tierId] or Dinos.Tiers[1]
	local species = Dinos.Species[speciesId]
	mutationId = mutationId or "Normal"

	local model = Instance.new("Model")
	model.Name = "Egg"
	local size = 2 + tier.index * 0.15
	local egg = makePart(model, "Shell", Vector3.new(size, size, size), Vector3.new(0, 0, 0), tier.color)
	egg.Shape = Enum.PartType.Ball
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	model.PrimaryPart = egg

	-- Spots in the species' color hint at what is inside.
	for i = 1, 4 do
		local angle = i * math.pi / 2 + 0.4
		local spot = makePart(
			model,
			"Spot",
			Vector3.new(0.5, 0.5, 0.15) * size / 2,
			Vector3.new(math.cos(angle) * size * 0.48, (i % 2 - 0.5) * size * 0.5, math.sin(angle) * size * 0.48),
			species and species.color or BLACK
		)
		spot.CFrame = CFrame.lookAt(spot.Position, Vector3.new(0, spot.Position.Y, 0))
	end

	if mutationId == "Golden" then
		egg.Color = GOLD
		egg.Material = Enum.Material.Foil
	elseif mutationId == "Rainbow" then
		egg.Material = Enum.Material.Neon
		CollectionService:AddTag(egg, Config.Tags.RainbowPart)
	elseif tier.index >= 4 then
		egg.Material = Enum.Material.Neon
	end
	if tier.index >= 4 or mutationId ~= "Normal" then
		local light = Instance.new("PointLight")
		light.Color = tier.color
		light.Range = 10 + tier.index * 2
		light.Parent = egg
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = tier.color
		sparkles.Parent = egg
	end

	model:SetAttribute("Species", speciesId)
	model:SetAttribute("Tier", tierId)
	model:SetAttribute("Mutation", mutationId)
	return model
end

-- Turns every part of a built model into a welded, unanchored, massless
-- assembly so it can be attached to a character.
function DinoModel.makeCarryable(model: Model)
	local primary = model.PrimaryPart
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.Massless = true
			part.CanCollide = false
			if part ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
end

return DinoModel
