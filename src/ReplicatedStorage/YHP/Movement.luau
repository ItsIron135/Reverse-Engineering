-- UCharacterMovementComponent::CalcVelocity and ApplyVelocityBraking for MOVE_Walking,
-- run in centimetres per second on the horizontal plane.
local Movement = {}
Movement.__index = Movement

local BRAKING_SUBSTEP = 1 / 33
local BRAKE_TO_STOP_VELOCITY = 10

function Movement.new(config)
	return setmetatable({ config = config, velocity = Vector3.zero }, Movement)
end

local function applyBraking(velocity: Vector3, dt: number, friction: number, deceleration: number): Vector3
	if velocity.Magnitude < 1e-4 or (friction == 0 and deceleration == 0) then
		return velocity
	end
	local old = velocity
	local zeroFriction = friction == 0
	local reverse = deceleration == 0 and Vector3.zero or -deceleration * velocity.Unit
	local remaining = dt
	while remaining >= 1e-6 do
		local step = (remaining > BRAKING_SUBSTEP and not zeroFriction) and math.min(BRAKING_SUBSTEP, remaining * 0.5) or remaining
		remaining -= step
		velocity += (-friction * velocity + reverse) * step
		if velocity:Dot(old) <= 0 then
			return Vector3.zero
		end
	end
	local sq = velocity:Dot(velocity)
	if sq <= 1e-4 or (deceleration ~= 0 and sq <= BRAKE_TO_STOP_VELOCITY * BRAKE_TO_STOP_VELOCITY) then
		return Vector3.zero
	end
	return velocity
end

-- input: world-space horizontal input vector (magnitude <= 1); maxSpeed in cm/s.
function Movement:Step(dt: number, input: Vector3, maxSpeed: number): Vector3
	local c = self.config
	local v = self.velocity
	if input.Magnitude > 1 then
		input = input.Unit
	end
	local acceleration = input * c.MaxAcceleration
	local zeroAccel = acceleration.Magnitude < 1e-8
	-- AnalogInputModifier scales the speed cap by input magnitude
	maxSpeed *= math.clamp(input.Magnitude, 0, 1)
	local overMax = v.Magnitude > maxSpeed * 1.01

	if zeroAccel or overMax then
		local old = v
		v = applyBraking(v, dt, c.GroundFriction * c.BrakingFrictionFactor, c.BrakingDecelerationWalking)
		if overMax and v.Magnitude < maxSpeed and acceleration:Dot(old) > 0 then
			v = old.Unit * maxSpeed
		end
	else
		local speed = v.Magnitude
		v -= (v - acceleration.Unit * speed) * math.min(dt * c.GroundFriction, 1)
	end

	if not zeroAccel then
		local cap = v.Magnitude > maxSpeed * 1.01 and v.Magnitude or maxSpeed
		v += acceleration * dt
		if v.Magnitude > cap then
			v = v.Unit * cap
		end
	end

	self.velocity = v
	return v
end

return Movement
