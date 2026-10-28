-- Dreamcore scene: huge rolling hills of plain bright green grass under a pure light-blue sky.
-- Run in Studio's Command Bar in Edit mode. Replaces the current terrain and sky; save the old
-- scene first (install/SaveScene.luau) if you want it back.
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

-- Textures from tools/make_dream_assets.py: deep-blue gradient sky with a few small clouds
-- near the horizon, and two tileable lawns with soft light/dark patches.
local SKY = {
	SkyboxFt = "rbxassetid://70946309918786", SkyboxBk = "rbxassetid://103123887827375",
	SkyboxLf = "rbxassetid://83371402069156", SkyboxRt = "rbxassetid://119611060346122",
	SkyboxUp = "rbxassetid://111848448630466", SkyboxDn = "rbxassetid://71599569048732",
}
-- Photo-based PBR grass (free Creator Store material variant 130374226035894)
local GRASS = {
	ColorMap = "rbxassetid://13554789665",
	NormalMap = "rbxassetid://13554789669",
	RoughnessMap = "rbxassetid://13554789647",
}
local HALF, BOTTOM, TOP, RES, CHUNK, SEED = 2000, -120, 124, 4, 128, 17.3

-- Grass on Ground, which (unlike the Grass material) never grows decoration blades. A single
-- material keeps far terrain LOD green; the hills' lighting supplies the colour variation.
local variant = MaterialService:FindFirstChild("DreamGrass") or Instance.new("MaterialVariant")
variant.Name = "DreamGrass"
variant.BaseMaterial = Enum.Material.Ground
for key, id in GRASS do
	variant[key] = id
end
variant.StudsPerTile = 8
variant.Parent = MaterialService
MaterialService:SetBaseMaterialOverride(Enum.Material.Ground, "DreamGrass")
workspace.Terrain:SetMaterialColor(Enum.Material.Ground, Color3.new(1, 1, 1))

for _, child in Lighting:GetChildren() do
	if child:IsA("Sky") or child:IsA("Atmosphere") or child:IsA("Clouds") then
		child:Destroy()
	end
end
local sky = Instance.new("Sky")
sky.Name = "YHP_DreamSky"
for face, id in SKY do
	sky[face] = id
end
sky.CelestialBodiesShown = false
sky.StarCount = 0
sky:SetAttribute("YHPManaged", true)
sky.Parent = Lighting

Lighting.ClockTime = 16.3 -- low enough sun to shade the hills
Lighting.GeographicLatitude = 30
Lighting.Brightness = 2.6
Lighting.ExposureCompensation = 0
Lighting.Ambient = Color3.fromRGB(70, 80, 95)
Lighting.OutdoorAmbient = Color3.fromRGB(105, 125, 145)
Lighting.EnvironmentDiffuseScale = 0.6
Lighting.EnvironmentSpecularScale = 0.1
Lighting.ColorShift_Top = Color3.fromRGB(255, 255, 250)
Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
local grade = Lighting:FindFirstChild("YHP_ColorGrade")
if grade then
	grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor = 0, 0.1, -0.2, Color3.fromRGB(255, 251, 238)
end
local bloom = Lighting:FindFirstChild("YHP_Bloom")
if bloom then
	bloom.Threshold, bloom.Intensity, bloom.Size = 1.2, 0.6, 40
end

local function height(x, z)
	-- Only broad, smooth swells: no small-scale octave, so the slopes have no bumps
	return 95 * math.noise(x / 650, SEED, z / 650) + 22 * math.noise(x / 320, SEED + 5.1, z / 320)
end

local terrain = workspace.Terrain
terrain:Clear()
local ny = (TOP - BOTTOM) / RES
local n = CHUNK / RES
for cx = -HALF, HALF - 1, CHUNK do
	for cz = -HALF, HALF - 1, CHUNK do
		local materials, occupancy = {}, {}
		for ix = 1, n do
			materials[ix], occupancy[ix] = {}, {}
			for iy = 1, ny do
				materials[ix][iy], occupancy[ix][iy] = table.create(n, Enum.Material.Air), table.create(n, 0)
			end
			for iz = 1, n do
				local x, z = cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES
				local top, material = height(x, z), Enum.Material.Ground
				for iy = 1, ny do
					local fill = math.clamp((top - (BOTTOM + (iy - 1) * RES)) / RES, 0, 1)
					if fill > 0 then
						materials[ix][iy][iz] = material
						occupancy[ix][iy][iz] = fill
					end
				end
			end
		end
		terrain:WriteVoxels(Region3.new(Vector3.new(cx, BOTTOM, cz), Vector3.new(cx + CHUNK, TOP, cz + CHUNK)), RES, materials, occupancy)
		task.wait()
	end
end

local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
if spawn then
	spawn.Position = Vector3.new(0, height(0, 0) + spawn.Size.Y / 2 - 0.2, 0)
end
return "Dream hills built"
