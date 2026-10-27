-- One playing instance of a ULegacyCameraShake with Perlin oscillators.
-- Instances are independent (bSingleInstance=false), so callers keep a list and sum them.
local PerlinNoise1D = require(script.Parent.UnrealPerlin)

local CameraShake = {}
CameraShake.__index = CameraShake

local random = Random.new()

local function newAxes(spec)
	local axes = table.create(3)
	for i, axis in spec do
		-- FFOscillator::Initialize with EOO_OffsetRandom
		axes[i] = { amplitude = axis[1], frequency = axis[2], offset = random:NextNumber() * 2 * math.pi }
	end
	return axes
end

function CameraShake.new(profile)
	return setmetatable({
		profile = profile,
		elapsed = 0,
		rotation = newAxes(profile.Rotation),
		location = newAxes(profile.Location),
	}, CameraShake)
end

local function advance(axes, dt)
	local a, b, c = axes[1], axes[2], axes[3]
	a.offset += dt * a.frequency
	b.offset += dt * b.frequency
	c.offset += dt * c.frequency
	return a.amplitude * PerlinNoise1D(a.offset), b.amplitude * PerlinNoise1D(b.offset), c.amplitude * PerlinNoise1D(c.offset)
end

-- Returns blend-weighted (pitch, yaw, roll) degrees and (x, y, z) cm, or nil once finished.
function CameraShake:Update(dt)
	local p = self.profile
	self.elapsed += dt
	if self.elapsed >= p.Duration then
		return nil
	end
	local weight = 1
	if p.BlendIn > 0 and self.elapsed < p.BlendIn then
		weight = self.elapsed / p.BlendIn
	end
	local remaining = p.Duration - self.elapsed
	if p.BlendOut > 0 and remaining < p.BlendOut then
		weight = math.min(weight, remaining / p.BlendOut)
	end
	local pitch, yaw, roll = advance(self.rotation, dt)
	local x, y, z = advance(self.location, dt)
	return Vector3.new(pitch, yaw, roll) * weight, Vector3.new(x, y, z) * weight
end

return CameraShake
