-- Places level 0's decoded static meshes in workspace.YHP_Level0.Objects.
-- Engine Plane/Cube shapes become Parts (tree cards get the game's tree textures); every other
-- mesh is cloned from a MeshPart imported from repo assets/level0_models/*.obj (Studio's 3D
-- Importer names it after the file). Run again after importing more models; it rebuilds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Unreal = require(ReplicatedStorage:WaitForChild("YHP"):WaitForChild("Unreal"))
local Placements = require(script.Parent.Placements)
local MeshInfo = require(script.Parent.MeshInfo)

local CM = 28
local PLANE_SIZE = 100 / CM

-- Override materials on the engine Plane that are tree cards, and their extracted textures
local TREE_TEXTURES = {
	BG_DeadTree1 = "rbxassetid://78516050744696",
	BG_DeadTree2 = "rbxassetid://120721244251662",
	BG_DeadTree3 = "rbxassetid://128685923824313",
	BG_Tree1_M = "rbxassetid://97221389717717",
	BG_Tree2 = "rbxassetid://89539813698059",
	BG_Tree3 = "rbxassetid://130789866824644",
	BackgroundTrees2_M = "rbxassetid://88125506628418",
	M0_BackgroundTrees1_M = "rbxassetid://135345118042093",
}
local FLAT_COLOURS = {
	M0Road = Color3.fromRGB(45, 45, 48),
	Driveway = Color3.fromRGB(70, 68, 66),
	Map5ParkingLot = Color3.fromRGB(55, 55, 58),
	AirVentBlack = Color3.fromRGB(15, 15, 15),
	BasicShapeMaterial = Color3.fromRGB(120, 120, 120),
}

local function findTemplate(name)
	for _, root in { game:GetService("ServerStorage"), workspace, ReplicatedStorage } do
		for _, d in root:GetDescendants() do
			if d:IsA("MeshPart") and (d.Name == name or (d.Parent and d.Parent.Name == name))
				and not d:IsDescendantOf(workspace:FindFirstChild("YHP_Level0") or Instance.new("Folder")) then
				return d
			end
		end
	end
	return nil
end

return function()
	local level = workspace:WaitForChild("YHP_Level0")
	local origin = level:GetAttribute("OriginRoblox")
	local start = level:GetAttribute("PlayerStartUnreal")
	local function toRoblox(loc)
		return origin + Vector3.new(loc[2] - start.Y, loc[3] - start.Z, -(loc[1] - start.X)) / CM
	end

	local old = level:FindFirstChild("Objects")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Objects"

	local templates, missing, placed = {}, {}, 0
	for _, p in Placements do
		local name, loc, rot, scale, materials = p[1], p[2], p[3], p[4], p[5]
		local s = Vector3.new(math.abs(scale[2]), math.abs(scale[3]), math.abs(scale[1]))
		local cf = CFrame.new(toRoblox(loc)) * Unreal.RotatorToCFrame(rot[1], rot[2], rot[3])
		local material = materials[1] or ""
		local part
		if name == "Plane" then
			part = Instance.new("Part")
			part.Size = Vector3.new(PLANE_SIZE * s.X, 0.05, PLANE_SIZE * s.Z)
			part.CFrame = cf
			local texture = TREE_TEXTURES[material]
			if texture then
				part.Transparency = 1
				part.CanCollide = false
				for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
					local decal = Instance.new("Decal")
					decal.Texture = texture
					decal.Face = face
					decal.Parent = part
				end
			else
				part.Color = FLAT_COLOURS[material] or Color3.fromRGB(90, 90, 90)
			end
		elseif name == "Cube" or name == "Shape_Cube" then
			local info = MeshInfo[name]
			part = Instance.new("Part")
			part.Size = (info.size * s):Max(Vector3.one * 0.05)
			part.CFrame = cf * CFrame.new(info.centre * s)
			part.Color = FLAT_COLOURS[material] or Color3.fromRGB(120, 120, 120)
		else
			local info = MeshInfo[name]
			if templates[name] == nil then
				templates[name] = findTemplate(name) or false
			end
			local template = templates[name]
			if template and info then
				part = template:Clone()
				part.Size = (info.size * s):Max(Vector3.one * 0.05)
				part.CFrame = cf * CFrame.new(info.centre * s)
			else
				missing[name] = (missing[name] or 0) + 1
			end
		end
		if part then
			part.Name = name
			part.Anchored = true
			part:SetAttribute("UnrealMaterial", material)
			part.Parent = folder
			placed += 1
		end
	end
	folder.Parent = level

	local list = {}
	for name, count in missing do
		table.insert(list, ("%s x%d"):format(name, count))
	end
	table.sort(list)
	return placed, list
end
