-- Dreamcore scene: huge rolling hills of plain bright green grass under a pure light-blue sky.
-- Run in Studio's Command Bar in Edit mode. Replaces the current terrain and sky; save the old
-- scene first (install/SaveScene.luau) if you want it back.
local Lighting = game:GetService("Lighting")
local MaterialService = game:GetService("MaterialService")

-- Textures from tools/make_dream_assets.py: deep-blue gradient sky with a few small clouds
-- near the horizon, and two tileable lawns with soft light/dark patches.
local SKY = {
	SkyboxFt = "rbxassetid://101108003078443", SkyboxBk = "rbxassetid://99055442711002",
	SkyboxLf = "rbxassetid://95078890060473", SkyboxRt = "rbxassetid://122857354846539",
	SkyboxUp = "rbxassetid://111848448630466", SkyboxDn = "rbxassetid://71599569048732",
}
local LAWN_A = "rbxassetid://113694141862193"
local LAWN_B = "rbxassetid://82569286786333"
local HALF, BOTTOM, TOP, RES, CHUNK, SEED = 2000, -120, 124, 4, 128, 17.3

-- Lawn textures on Ground and Mud, which (unlike Grass) never grow decoration blades. Two
-- variants painted in large patches give the hills slight colour variation.
for base, info in { [Enum.Material.Ground] = { "DreamGrass", LAWN_A }, [Enum.Material.Mud] = { "DreamGrassB", LAWN_B } } do
	local variant = MaterialService:FindFirstChild(info[1]) or Instance.new("MaterialVariant")
	variant.Name = info[1]
	variant.BaseMaterial = base
	variant.ColorMap = info[2]
	variant.StudsPerTile = 40
	variant.Parent = MaterialService
	MaterialService:SetBaseMaterialOverride(base, info[1])
	workspace.Terrain:SetMaterialColor(base, Color3.new(1, 1, 1))
end

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
	grade.Brightness, grade.Contrast, grade.Saturation, grade.TintColor = 0, 0.05, -0.12, Color3.new(1, 1, 1)
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

local function patch(x, z)
	local n = math.noise(x / 220, SEED + 31.7, z / 220) + 0.4 * math.noise(x / 90, SEED + 44.1, z / 90)
	return n > 0.12 and Enum.Material.Mud or Enum.Material.Ground
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
				local top, material = height(x, z), patch(x, z)
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
