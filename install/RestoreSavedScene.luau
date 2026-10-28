-- Restores a scene saved in ServerStorage.YHP_SavedScenes (default: Level0): its terrain region,
-- Lighting properties and children, workspace.YHP_Level0 folder and spawn position.
-- Run in Studio's Command Bar in Edit mode. Replaces the current terrain and lighting.
local NAME = "Level0"
local scene = game:GetService("ServerStorage").YHP_SavedScenes:FindFirstChild(NAME)
assert(scene, "No saved scene called " .. NAME)
local Lighting = game:GetService("Lighting")

local terrain = workspace.Terrain
terrain:Clear()
local corner = scene:GetAttribute("TerrainCorner")
terrain:PasteRegion(scene.Terrain, Vector3int16.new(corner.X, corner.Y, corner.Z), true)
-- The level 0 scene uses the stock Ground material, not the DreamGrass variant
game:GetService("MaterialService"):SetBaseMaterialOverride(Enum.Material.Ground, "")
game:GetService("MaterialService"):SetBaseMaterialOverride(Enum.Material.Mud, "")

local saved = scene.Lighting
for key, value in saved:GetAttributes() do
	Lighting[key] = value
end
for _, child in Lighting:GetChildren() do
	if child:IsA("PostEffect") or child:IsA("Sky") or child:IsA("Atmosphere") then
		child:Destroy()
	end
end
for _, child in saved:GetChildren() do
	child:Clone().Parent = Lighting
end

local old = workspace:FindFirstChild("YHP_Level0")
if old then
	old:Destroy()
end
local level = scene:FindFirstChild("YHP_Level0")
if level then
	level:Clone().Parent = workspace
end
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if spawn and scene:GetAttribute("SpawnCFrame") then
	spawn.CFrame = scene:GetAttribute("SpawnCFrame")
end
local settings = game:GetService("ReplicatedStorage"):FindFirstChild("YHP")
for key, value in scene:GetAttributes() do
	if settings and key:sub(1, 4) == "YHP_" then
		settings:SetAttribute(key:sub(5), value)
	end
end
return "Restored " .. NAME
