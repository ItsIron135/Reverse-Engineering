-- Conversions between Unreal's left-handed Z-up frame and Roblox's right-handed Y-up frame,
-- plus the engine interpolation helpers the spring arm and movement code rely on.
local Unreal = {}

-- Unreal (X forward, Y right, Z up) relative to a yaw-only Roblox frame.
function Unreal.LocalToRoblox(v: Vector3): Vector3
	return Vector3.new(v.Y, v.Z, -v.X)
end

-- FRotator(pitch, yaw, roll) in degrees -> Roblox rotation. Unreal applies yaw, then pitch, then roll.
-- Positive yaw turns right, positive pitch looks up, positive roll drops the right side.
function Unreal.RotatorToCFrame(pitch: number, yaw: number, roll: number): CFrame
	return CFrame.fromEulerAnglesYXZ(math.rad(pitch), math.rad(-yaw), math.rad(-roll))
end

function Unreal.CFrameToRotator(cf: CFrame): (number, number, number)
	local rx, ry, rz = cf:ToEulerAnglesYXZ()
	return math.deg(rx), -math.deg(ry), -math.deg(rz)
end

function Unreal.NormalizeAxis(angle: number): number
	angle %= 360
	if angle > 180 then
		angle -= 360
	end
	return angle
end

-- FMath::VInterpTo
function Unreal.VInterpTo(current: Vector3, target: Vector3, dt: number, speed: number): Vector3
	if speed <= 0 then
		return target
	end
	local dist = target - current
	if dist:Dot(dist) < 1e-8 then
		return target
	end
	return current + dist * math.clamp(dt * speed, 0, 1)
end

-- FMath::QInterpTo (quaternion slerp by a clamped dt*speed alpha)
function Unreal.QInterpTo(current: CFrame, target: CFrame, dt: number, speed: number): CFrame
	if speed <= 0 then
		return target
	end
	return current:Lerp(target, math.clamp(dt * speed, 0, 1))
end

return Unreal
