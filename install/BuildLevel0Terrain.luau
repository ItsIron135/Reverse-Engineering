-- Rebuilds level 0's landscape as Roblox Terrain. Run in the Command Bar in Edit mode.
-- The heightmap image (rbxassetid below) was produced by tools/export_landscape.py: R/G are the
-- 16-bit landscape height, B the dominant paint layer. Landscape: 505x505 vertices, 50 cm apart,
-- origin (-12600, -12600.59, 100) cm; the game's PlayerStart lands on this place's SpawnLocation.
local AssetService = game:GetService("AssetService")
local HEIGHTMAP = "rbxassetid://127901869413620"
local PLAYER_START = Vector3.new(3687.5179680353485, 1953.8422851564517, 191.67219570044668 - 92)
local LAYER = { [0] = Enum.Material.Ground, [1] = Enum.Material.Grass, [2] = Enum.Material.Rock, [3] = Enum.Material.Mud, [4] = Enum.Material.LeafyGrass }
local RES, CHUNK, CM = 4, 64, 28

local level = workspace:FindFirstChild("YHP_Level0") or Instance.new("Folder")
level.Name = "YHP_Level0"
level.Parent = workspace
local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
local origin = level:GetAttribute("OriginRoblox") or (spawn and spawn.Position + Vector3.new(0, spawn.Size.Y / 2, 0)) or Vector3.zero
level:SetAttribute("OriginRoblox", origin)
level:SetAttribute("PlayerStartUnreal", PLAYER_START)
local P = PLAYER_START

local img = AssetService:CreateEditableImageAsync(Content.fromUri(HEIGHTMAP))
local W = img.Size.X
local buf = img:ReadPixelsBuffer(Vector2.zero, img.Size)
img:Destroy()
local function at(x, y)
	local o = (y * W + x) * 4
	return buffer.readu8(buf, o) * 256 + buffer.readu8(buf, o + 1), buffer.readu8(buf, o + 2)
end
local function sample(gx, gy)
	gx, gy = math.clamp(gx, 0, W - 1.001), math.clamp(gy, 0, W - 1.001)
	local x0, y0 = math.floor(gx), math.floor(gy)
	local fx, fy = gx - x0, gy - y0
	local h00, h10, h01, h11 = at(x0, y0), at(x0 + 1, y0), at(x0, y0 + 1), at(x0 + 1, y0 + 1)
	local h = (h00 * (1 - fx) + h10 * fx) * (1 - fy) + (h01 * (1 - fx) + h11 * fx) * fy
	local _, layer = at(math.floor(gx + 0.5), math.floor(gy + 0.5))
	return 100 + (h - 32768) / 128 * 50, LAYER[layer] or Enum.Material.Ground
end
local function toGrid(rx, rz)
	return (P.X - (rz - origin.Z) * CM + 12600) / 50, ((rx - origin.X) * CM + P.Y + 12600.59236928659) / 50
end
local function robloxY(z) return origin.Y + (z - P.Z) / CM end
local function snap(v) return math.floor(v / RES) * RES end

local x0, x1 = snap(origin.X + (-12600.59 - P.Y) / CM), snap(origin.X + (-12600.59 + 504 * 50 - P.Y) / CM) + RES
local z0, z1 = snap(origin.Z - (-12600 + 504 * 50 - P.X) / CM), snap(origin.Z - (-12600 - P.X) / CM) + RES
local y0 = snap(robloxY(100 + (30943 - 32768) / 128 * 50) - 12)
local y1 = snap(robloxY(100 + (36179 - 32768) / 128 * 50)) + RES * 2
local ny = (y1 - y0) / RES

for cx = x0, x1 - 1, CHUNK do
	for cz = z0, z1 - 1, CHUNK do
		local nx, nz = math.min(CHUNK, x1 - cx) / RES, math.min(CHUNK, z1 - cz) / RES
		local materials, occupancy = {}, {}
		for ix = 1, nx do
			materials[ix], occupancy[ix] = {}, {}
			for iy = 1, ny do
				materials[ix][iy], occupancy[ix][iy] = table.create(nz, Enum.Material.Air), table.create(nz, 0)
			end
			for iz = 1, nz do
				local gx, gy = toGrid(cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES)
				if gx >= 0 and gx <= W - 1 and gy >= 0 and gy <= W - 1 then
					local z, mat = sample(gx, gy)
					local top = robloxY(z)
					for iy = 1, ny do
						local base = y0 + (iy - 1) * RES
						local fill = math.clamp((top - base) / RES, 0, 1)
						if fill > 0 then
							materials[ix][iy][iz] = top - base > RES * 2.5 and Enum.Material.Ground or mat
							occupancy[ix][iy][iz] = fill
						end
					end
				end
			end
		end
		workspace.Terrain:WriteVoxels(Region3.new(Vector3.new(cx, y0, cz), Vector3.new(cx + nx * RES, y1, cz + nz * RES)), RES, materials, occupancy)
		task.wait()
	end
end
return "Level 0 terrain built"
