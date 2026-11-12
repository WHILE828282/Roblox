-- Terraform.luau
-- Turns the simple blocks of the generated map into real Roblox terrain when
-- the server starts: grass with blades, sand, mud, smooth hills, rivers with
-- real water, round mountains with snow and a volcano of basalt and lava.
-- The generated parts only describe WHERE things are; this makes them pretty.

local Terraform = {}

local ServerStorage = game:GetService("ServerStorage")

local terrain = workspace.Terrain
local M = Enum.Material

local GROUND = {
	JungleGround = M.Grass,
	DesertGround = M.Sand,
	SwampGround = M.Mud,
	CanyonGround = M.Sandstone,
}

local COLORS = {
	[M.Grass] = Color3.fromRGB(96, 168, 62),
	[M.LeafyGrass] = Color3.fromRGB(78, 150, 58),
	[M.Sand] = Color3.fromRGB(236, 208, 150),
	[M.Mud] = Color3.fromRGB(84, 98, 62),
	[M.Sandstone] = Color3.fromRGB(196, 124, 84),
	[M.Basalt] = Color3.fromRGB(52, 46, 50),
	[M.CrackedLava] = Color3.fromRGB(255, 96, 24),
	[M.Rock] = Color3.fromRGB(112, 104, 100),
	[M.Ground] = Color3.fromRGB(150, 112, 74),
	[M.Snow] = Color3.fromRGB(244, 246, 250),
	[M.Limestone] = Color3.fromRGB(168, 96, 66), -- canyon cliffs
}

-- Canyon blocks that become smooth cliffs.
local CLIFFS = {
	GorgeWall = true,
	GorgeWallTop = true,
	GorgeArch = true,
	Spire = true,
	SpireTop = true,
	ArchLeg = true,
	ArchTop = true,
}

-- Which pretty models replace the simple tree trunks of each biome.
local TREES = {
	Jungle = { "JungleTree1", "JungleTree2", "TallTree1", "TallTree2", "JungleTree1", "BirchTree2" },
	Swamp = { "PineTree1", "PineTree3", "TallerPineTree2", "BirchTree1" },
	Desert = { "BirchTree4" },
	Canyon = { "BirchTree4", "PineTree3" },
}
local SMALL_PLANTS = {
	Jungle = { "Fern1", "Fern2", "Grass1", "Grass2", "LargeMushroon" },
	Swamp = { "Fern2", "Grass1", "Grass2", "MushroomCluster3" },
	Desert = { "Grass2" },
	Canyon = { "Grass1" },
}
local TINT = {
	Swamp = Color3.fromRGB(150, 175, 140),
	Desert = Color3.fromRGB(235, 215, 150),
	Canyon = Color3.fromRGB(225, 190, 150),
}
local ROCK_COLOR = {
	Jungle = Color3.fromRGB(128, 138, 126),
	Swamp = Color3.fromRGB(96, 110, 98),
	Desert = Color3.fromRGB(206, 170, 120),
	Canyon = Color3.fromRGB(170, 104, 76),
}

local function biomeMaterial(position: Vector3): Enum.Material
	if position.X >= 0 and position.Z >= 0 then
		return M.Grass
	elseif position.X < 0 and position.Z >= 0 then
		return M.Sand
	elseif position.X < 0 then
		return M.Mud
	end
	return M.Sandstone
end

local function mountainMaterial(position: Vector3): Enum.Material
	local material = biomeMaterial(position)
	if material == M.Grass then
		return M.LeafyGrass
	elseif material == M.Sand or material == M.Sandstone then
		return M.Sandstone
	end
	return M.Rock
end

-- Height of an upright cylinder part and its radius.
local function cylinderShape(part: BasePart): (number, number)
	return part.Size.X, part.Size.Y / 2
end

-- Puts a copy of `template` with its bottom at `position`, `height` studs tall.
local function place(template: Model, position: Vector3, height: number, random: Random, tint: Color3?): Model
	local model = template:Clone()
	local size = model:GetExtentsSize()
	model:ScaleTo(math.clamp(height / math.max(size.Y, 0.1), 0.2, 6))
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, random:NextNumber() * math.pi * 2, 0))
	local box, boxSize = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(0, position.Y - (box.Position.Y - boxSize.Y / 2), 0))
	if tint then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Color = part.Color:Lerp(tint, 0.45)
			end
		end
	end
	return model
end

-- Swaps the generated block decorations for mesh models (trees, ferns, rocks).
local function decorate(map: Instance)
	local assets = ServerStorage:FindFirstChild("MapAssets")
	local nature = assets and assets:FindFirstChild("Nature")
	local decor = map:FindFirstChild("Decor")
	if not nature or not decor then
		return -- models are missing: keep the simple blocks
	end
	local random = Random.new(2024)
	local function pick(names: { string }): Model?
		local found = nature:FindFirstChild(names[random:NextInteger(1, #names)])
		return if found and found:IsA("Model") then found else nil
	end
	local rocks = { "Rock1", "Rock2", "Rock3" }
	local props = assets:FindFirstChild("Props")
	local function prop(name: string): Model?
		local found = props and props:FindFirstChild(name)
		return if found and found:IsA("Model") then found else nil
	end
	-- Block pieces that a single mesh model replaces.
	local SKELETON = { Spine = true, Rib = true, Jaw = true, Horn = true, Leg = true }
	local RUIN = { Column = true, Capital = true, Lintel = true, ArchPillar = true, FallenColumn = true, BrokenWall = true }

	for _, folder in decor:GetChildren() do
		local biome = folder.Name
		local trees, plants = TREES[biome], SMALL_PLANTS[biome]
		if not trees then
			continue
		end
		for _, part in folder:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local name = part.Name
			if CLIFFS[name] then
				terrain:FillBlock(part.CFrame, part.Size, M.Limestone)
				part:Destroy()
			elseif name == "Trunk" then
				-- The trunk stays as an invisible collider; the model is only for looks.
				local height = part.Size.X
				local base = part.Position - Vector3.new(0, height / 2, 0)
				local template = if height > 55 and biome == "Jungle"
					then pick({ "JungleTree1", "JungleTree2" })
					else pick(trees)
				if template then
					place(template, base, height * 1.45, random, TINT[biome]).Parent = folder
					part.Transparency = 1
					part.CastShadow = false
				end
			elseif name == "Leaves" or name == "Root" then
				part:Destroy()
			elseif name == "Cactus" and prop("Cactus") then
				local height = part.Size.X
				place(prop("Cactus") :: Model, part.Position - Vector3.new(0, height / 2, 0), height * 1.15, random, nil).Parent =
					folder
				part.Transparency = 1
				part.CastShadow = false
			elseif name == "DeadTrunk" and prop("DeadTree") then
				local height = part.Size.X
				place(prop("DeadTree") :: Model, part.Position - Vector3.new(0, height / 2, 0), height * 1.2, random, nil).Parent =
					folder
				part.Transparency = 1
				part.CastShadow = false
			elseif (name == "CactusArm" and prop("Cactus")) or (name == "DeadBranch" and prop("DeadTree")) then
				part:Destroy()
			elseif name == "Moss" and (prop("DeadTree") or prop("Ruins")) then
				part:Destroy()
			elseif name == "Skull" and prop("Skeleton") then
				local bottom = part.Position - Vector3.new(0, part.Size.Y * 1.7, 0)
				place(prop("Skeleton") :: Model, bottom, part.Size.Y * 6, random, nil).Parent = folder
				part:Destroy()
			elseif SKELETON[name] and prop("Skeleton") then
				part:Destroy()
			elseif name == "RuinFloor" and prop("Ruins") then
				place(prop("Ruins") :: Model, part.Position - Vector3.new(0, 0.6, 0), 26, random, nil).Parent = folder
				part:Destroy()
			elseif RUIN[name] and prop("Ruins") then
				part:Destroy()
			elseif name == "Bush" or name == "Reed" then
				local template = pick(plants)
				if template then
					local bottom = part.Position - Vector3.new(0, part.Size.Y * 0.4, 0)
					place(template, bottom, random:NextNumber(2.5, 6), random, TINT[biome]).Parent = folder
				end
				part:Destroy()
			elseif name == "Rock" then
				local template = pick(rocks)
				if template then
					local bottom = part.Position - Vector3.new(0, part.Size.Y * 0.5, 0)
					local rock = place(template, bottom, part.Size.Y * 1.5, random, nil)
					for _, piece in rock:GetDescendants() do
						if piece:IsA("BasePart") then
							piece.Color = ROCK_COLOR[biome]
							piece.Material = Enum.Material.Slate
							piece.CanCollide = true
							piece.CanQuery = true
						end
					end
					rock.Parent = folder
					part:Destroy()
				end
			end
		end
	end
end

function Terraform.run()
	local map = workspace:FindFirstChild("Map")
	if not map or map:GetAttribute("Terraformed") then
		return
	end
	map:SetAttribute("Terraformed", true)
	for material, color in COLORS do
		terrain:SetMaterialColor(material, color)
	end

	-- Ground, hills and paths.
	local ground = map:FindFirstChild("Ground")
	if ground then
		for _, part in ground:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			if GROUND[part.Name] then
				terrain:FillBlock(part.CFrame, part.Size, GROUND[part.Name])
				part:Destroy()
			elseif part.Name == "LavaField" then
				local height, radius = cylinderShape(part)
				terrain:FillCylinder(CFrame.new(part.Position), height, radius, M.Basalt)
				part:Destroy()
			elseif part.Name == "Hill" then
				terrain:FillBall(part.Position, part.Size.X / 2, biomeMaterial(part.Position))
				part:Destroy()
			elseif part.Name == "Path" then
				local size = part.Size
				terrain:FillBlock(part.CFrame * CFrame.new(0, -2, 0), Vector3.new(size.X, 4, size.Z), M.Ground)
				part:Destroy()
			end
		end
	end

	-- Rivers: a sandy bed with real water on top.
	local water = map:FindFirstChild("Water")
	if water then
		for _, part in water:GetChildren() do
			if part.Name == "RiverBed" and part:IsA("BasePart") then
				local swampy = part.Material == M.Mud
				local size = part.Size
				local center = Vector3.new(part.Position.X, 0, part.Position.Z)
				terrain:FillBlock(
					CFrame.new(center + Vector3.new(0, -5.5, 0)),
					Vector3.new(size.X + 4, 5, size.Z + 4),
					if swampy then M.Mud else M.Sand
				)
				terrain:FillBlock(CFrame.new(center + Vector3.new(0, -1.75, 0)), Vector3.new(size.X, 2.5, size.Z), M.Water)
				part:Destroy()
			elseif part.Name == "River" then
				part:Destroy()
			end
		end
	end

	-- Volcano: basalt cone with lava running down its sides.
	local volcano = map:FindFirstChild("Volcano")
	if volcano then
		local lava = {}
		for _, part in volcano:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			if string.sub(part.Name, 1, 4) == "Tier" then
				local height, radius = cylinderShape(part)
				terrain:FillCylinder(CFrame.new(part.Position), height + 2, radius, M.Basalt)
				if part:HasTag("Volcano") then
					-- Keep the tagged part (eggs fly out of it), just hide it.
					part.Transparency = 1
					part.CanCollide = false
					part.CanQuery = false
				else
					part:Destroy()
				end
			elseif part.Name == "LavaFall" or part.Name == "LavaFlow" then
				table.insert(lava, part)
			elseif part.Name == "RimRock" then
				terrain:FillBall(part.Position, part.Size.X * 0.7, M.Basalt)
				part:Destroy()
			end
		end
		for _, part in lava do
			terrain:FillBlock(part.CFrame, part.Size + Vector3.new(3, 2, 2), M.CrackedLava)
			part:Destroy()
		end
		local crater = volcano:FindFirstChild("Crater")
		if crater and crater:IsA("BasePart") then
			local _, radius = cylinderShape(crater)
			terrain:FillCylinder(CFrame.new(crater.Position - Vector3.new(0, 2, 0)), 5, radius, M.CrackedLava)
		end
	end

	decorate(map)

	-- Mountains: round rocky masses with snowy tops instead of boxes.
	local mountains = map:FindFirstChild("Mountains")
	if mountains then
		for _, part in mountains:GetChildren() do
			if not part:IsA("BasePart") then
				continue
			end
			local position, size = part.Position, part.Size
			local material = mountainMaterial(position)
			if part.Name == "Mountain" then
				local radius = size.X * 0.62
				terrain:FillBall(Vector3.new(position.X, size.Y * 0.1, position.Z), radius * 1.15, material)
				terrain:FillBall(Vector3.new(position.X, size.Y * 0.5, position.Z), radius * 0.9, M.Rock)
				terrain:FillBall(Vector3.new(position.X, size.Y * 0.85, position.Z), radius * 0.62, M.Rock)
			elseif part.Name == "MountainPeak" then
				terrain:FillBall(position, size.X * 0.5, M.Rock)
			elseif part.Name == "SnowCap" then
				terrain:FillBall(position, size.X * 0.42, M.Snow)
			elseif part.Name == "Foothill" then
				terrain:FillBall(Vector3.new(position.X, 2, position.Z), size.X * 0.42, material)
			end
			part:Destroy()
		end
	end
end

return Terraform
