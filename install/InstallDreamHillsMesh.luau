-- Swap the terrain hills for the smooth mesh hills (tools/make_dream_hills_mesh.py, uploaded as
-- model 99673034223018). Run in Studio's Command Bar in Edit mode after ReplicatedStorage.YHP.DreamHeight
-- and ServerScriptService.YHPHillCollision are installed. Terrain is then only collision near players.
local InsertService = game:GetService("InsertService")
local height = require(game.ReplicatedStorage.YHP.DreamHeight)

local HALF, TILE, STEP = 2000, 250, 10
local GRASS = {
	ColorMap = "rbxassetid://13554789665",
	NormalMap = "rbxassetid://13554789669",
	RoughnessMap = "rbxassetid://13554789647",
}

local function tileCentreY(i, j)
	-- Each tile's vertices are relative to the centre of its own height range
	local lo, hi = math.huge, -math.huge
	for a = 0, TILE, STEP do
		for b = 0, TILE, STEP do
			local h = height(-HALF + i * TILE + a, -HALF + j * TILE + b)
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
	end
	return (lo + hi) / 2
end

local old = workspace:FindFirstChild("DreamHills")
if old then
	old:Destroy()
end
local model = InsertService:LoadAsset(99673034223018)
local folder = Instance.new("Folder")
folder.Name = "DreamHills"
for _, part in model:GetDescendants() do
	local i, j = part.Name:match("^Hill_(%d+)_(%d+)$")
	if part:IsA("MeshPart") and i then
		i, j = tonumber(i), tonumber(j)
		-- The importer turns the glTF scene 180 degrees about Y, so turn each tile back
		part.CFrame = CFrame.new(-HALF + (i + 0.5) * TILE, tileCentreY(i, j), -HALF + (j + 0.5) * TILE)
			* CFrame.Angles(0, math.pi, 0)
		part.Anchored = true
		part.CanCollide, part.CanTouch = false, false
		part.Material = Enum.Material.Ground
		part.Color = Color3.new(1, 1, 1)
		part.RenderFidelity = Enum.RenderFidelity.Precise
		local look = Instance.new("SurfaceAppearance")
		for key, id in GRASS do
			look[key] = id
		end
		look.Parent = part
		part.Parent = folder
	end
end
model:Destroy()
folder.Parent = workspace

local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if spawn then
	spawn.Position = Vector3.new(0, height(0, 0) + spawn.Size.Y / 2 - 0.2, 0)
end
workspace.Terrain:Clear() -- YHPHillCollision builds collision around players at run time
return "Mesh hills installed"
