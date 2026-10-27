-- USpringArmComponent::UpdateDesiredArmLocation with TargetArmLength=0, no collision test,
-- location and rotation lag, and the native substepping defaults.
-- Positions are Roblox studs; rotators are Unreal degrees {pitch, yaw, roll}.
local Unreal = require(script.Parent.Unreal)

local SpringArm = {}
SpringArm.__index = SpringArm

function SpringArm.new(config)
	return setmetatable({
		config = config,
		previousRot = nil,
		previousLoc = nil,
	}, SpringArm)
end

function SpringArm:Reset()
	self.previousRot = nil
	self.previousLoc = nil
end

local function rotatorCFrame(r)
	return Unreal.RotatorToCFrame(r.X, r.Y, r.Z)
end

local function toRotator(cf)
	return Vector3.new(Unreal.CFrameToRotator(cf))
end

-- desiredRot: Vector3(pitch, yaw, roll); armOrigin: Vector3 in studs.
-- Returns the camera CFrame (before camera shakes).
function SpringArm:Update(dt: number, desiredRot: Vector3, armOrigin: Vector3): CFrame
	local c = self.config
	local maxStep = c.CameraLagMaxTimeStep
	local studsPerCm = 1 / c.CentimetersPerStud

	if not self.previousRot or dt <= 0 then
		self.previousRot = desiredRot
		self.previousLoc = armOrigin
		return CFrame.new(armOrigin) * rotatorCFrame(desiredRot)
	end

	-- Rotation lag
	local rot
	if dt > maxStep and c.CameraRotationLagSpeed > 0 then
		local prev = self.previousRot
		local delta = desiredRot - prev
		local step = Vector3.new(Unreal.NormalizeAxis(delta.X), Unreal.NormalizeAxis(delta.Y), Unreal.NormalizeAxis(delta.Z)) / dt
		local lerpTarget = prev
		local remaining = dt
		while remaining > 1e-4 do
			local amount = math.min(maxStep, remaining)
			lerpTarget += step * amount
			remaining -= amount
			prev = toRotator(Unreal.QInterpTo(rotatorCFrame(prev), rotatorCFrame(lerpTarget), amount, c.CameraRotationLagSpeed))
		end
		rot = prev
	else
		rot = toRotator(Unreal.QInterpTo(rotatorCFrame(self.previousRot), rotatorCFrame(desiredRot), dt, c.CameraRotationLagSpeed))
	end
	self.previousRot = rot

	-- Location lag
	local loc
	if dt > maxStep and c.CameraLagSpeed > 0 then
		local prev = self.previousLoc
		local step = (armOrigin - prev) / dt
		local lerpTarget = prev
		local remaining = dt
		while remaining > 1e-4 do
			local amount = math.min(maxStep, remaining)
			lerpTarget += step * amount
			remaining -= amount
			prev = Unreal.VInterpTo(prev, lerpTarget, amount, c.CameraLagSpeed)
		end
		loc = prev
	else
		loc = Unreal.VInterpTo(self.previousLoc, armOrigin, dt, c.CameraLagSpeed)
	end
	local maxDistance = c.CameraLagMaxDistance * studsPerCm
	local fromOrigin = loc - armOrigin
	if fromOrigin.Magnitude > maxDistance then
		loc = armOrigin + fromOrigin.Unit * maxDistance
	end
	self.previousLoc = loc

	return CFrame.new(loc) * rotatorCFrame(rot)
end

return SpringArm
