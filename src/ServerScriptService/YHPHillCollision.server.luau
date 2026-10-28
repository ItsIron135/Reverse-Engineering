-- Walkable ground for the dream hills. The hills you see are smooth MeshParts (Workspace.DreamHills,
-- no collision) because far-away terrain is drawn from coarser voxels and shows rings. Terrain is
-- only used for collision, and only near players: it sits just under the mesh, so the close-up
-- terrain stays hidden and never reaches the distance where it would be simplified.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local height = require(ReplicatedStorage.YHP.DreamHeight)

local RES, CHUNK = 4, 32
local KEEP_RADIUS, DROP_RADIUS = 96, 144 -- studs from a player to build / clear a chunk
-- Terrain draws its surface about 2 studs above the occupancy fill level; this puts the
-- surface 0.35 studs under the mesh.
local SINK = 2.35
local LIMIT = 2000 -- the mesh covers -2000..2000 on X and Z

local terrain = workspace.Terrain
local built = {}

local function key(cx, cz)
	return cx .. "," .. cz
end

local function buildChunk(cx, cz)
	local n = CHUNK / RES
	local tops, lo, hi = {}, math.huge, -math.huge
	for ix = 1, n do
		tops[ix] = {}
		for iz = 1, n do
			local top = height(cx + (ix - 0.5) * RES, cz + (iz - 0.5) * RES) - SINK
			tops[ix][iz] = top
			lo, hi = math.min(lo, top), math.max(hi, top)
		end
	end
	local bottom = math.floor((lo - 8) / RES) * RES
	local ceiling = math.ceil((hi + 4) / RES) * RES
	local ny = (ceiling - bottom) / RES
	local materials, occupancy = {}, {}
	for ix = 1, n do
		materials[ix], occupancy[ix] = {}, {}
		for iy = 1, ny do
			materials[ix][iy], occupancy[ix][iy] = table.create(n, Enum.Material.Air), table.create(n, 0)
		end
		for iz = 1, n do
			for iy = 1, ny do
				local fill = math.clamp((tops[ix][iz] - (bottom + (iy - 1) * RES)) / RES, 0, 1)
				if fill > 0 then
					materials[ix][iy][iz] = Enum.Material.Ground
					occupancy[ix][iy][iz] = fill
				end
			end
		end
	end
	terrain:WriteVoxels(Region3.new(Vector3.new(cx, bottom, cz), Vector3.new(cx + CHUNK, ceiling, cz + CHUNK)), RES, materials, occupancy)
	return Region3.new(Vector3.new(cx, bottom, cz), Vector3.new(cx + CHUNK, ceiling, cz + CHUNK))
end

local function centres()
	local list = {}
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(list, Vector2.new(root.Position.X, root.Position.Z))
		end
	end
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if #list == 0 and spawn then
		table.insert(list, Vector2.new(spawn.Position.X, spawn.Position.Z))
	end
	return list
end

local function nearest(list, cx, cz)
	local mid, best = Vector2.new(cx + CHUNK / 2, cz + CHUNK / 2), math.huge
	for _, p in list do
		best = math.min(best, (p - mid).Magnitude)
	end
	return best
end

terrain:Clear()
while true do
	local list = centres()
	for k, region in built do
		local cx, cz = string.match(k, "(-?%d+),(-?%d+)")
		if nearest(list, tonumber(cx), tonumber(cz)) > DROP_RADIUS then
			terrain:FillRegion(region, RES, Enum.Material.Air)
			built[k] = nil
		end
	end
	for _, p in list do
		for cx = math.floor((p.X - KEEP_RADIUS) / CHUNK) * CHUNK, p.X + KEEP_RADIUS, CHUNK do
			for cz = math.floor((p.Y - KEEP_RADIUS) / CHUNK) * CHUNK, p.Y + KEEP_RADIUS, CHUNK do
				local k = key(cx, cz)
				if not built[k] and cx >= -LIMIT and cx < LIMIT and cz >= -LIMIT and cz < LIMIT and nearest({ p }, cx, cz) <= KEEP_RADIUS then
					built[k] = buildChunk(cx, cz)
				end
			end
		end
	end
	task.wait(0.2)
end
