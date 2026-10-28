-- Dreamcore scene: huge rolling hills of plain bright green grass under a pure light-blue sky.
-- Run in Studio's Command Bar in Edit mode. Replaces the current terrain and sky; save the old
-- scene first (install/SaveScene.luau) if you want it back.
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

local SKY_SIDE = "rbxassetid://83076061752375" -- light blue, faint fade toward the horizon
local SKY_UP = "rbxassetid://140010124223000"
local SKY_DOWN = "rbxassetid://81339791160592"
local GRASS = "rbxassetid://72793147229433" -- tileable lawn texture
local HALF, BOTTOM, TOP, RES, CHUNK, SEED = 2000, -120, 124, 4, 128, 17.3

-- Grass texture on Ground, which (unlike Grass) never grows decoration blades
local variant = MaterialService:FindFirstChild("DreamGrass") or Instance.new("MaterialVariant")
variant.Name = "DreamGrass"
variant.BaseMaterial = Enum.Material.Ground
variant.ColorMap = GRASS
variant.StudsPerTile = 24
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
for _, face in { "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt" } do
	sky[face] = SKY_SIDE
end
sky.SkyboxUp = SKY_UP
sky.SkyboxDn = SKY_DOWN
sky.CelestialBodiesShown = false
sky.StarCount = 0
sky:SetAttribute("YHPManaged", true)
sky.Parent = Lighting

Lighting.ClockTime = 13
Lighting.GeographicLatitude = 30
Lighting.Brightness = 2.2
Lighting.ExposureCompensation = 0
Lighting.Ambient = Color3.fromRGB(110, 130, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 185, 210)
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 0.3
Lighting.ColorShift_Top = Color3.fromRGB(255, 255, 250)
Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
local grade = Lighting:FindFirstChild("YHP_ColorGrade")
if grade then
	grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor = 0.02, 0.05, -0.05, Color3.new(1, 1, 1)
end
local bloom = Lighting:FindFirstChild("YHP_Bloom")
if bloom then
	bloom.Threshold, bloom.Intensity, bloom.Size = 1.2, 0.6, 40
end

local function height(x, z)
	return 95 * math.noise(x / 650, SEED, z / 650)
		+ 30 * math.noise(x / 260, SEED + 5.1, z / 260)
		+ 6 * math.noise(x / 120, SEED + 9.7, z / 120)
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
				local top = height(cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES)
				for iy = 1, ny do
					local fill = math.clamp((top - (BOTTOM + (iy - 1) * RES)) / RES, 0, 1)
					if fill > 0 then
						materials[ix][iy][iz] = Enum.Material.Ground
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
