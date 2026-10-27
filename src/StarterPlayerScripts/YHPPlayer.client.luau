-- First-person player port of BP_FirstPersonCharacter: input, walking/running, the spring-arm
-- camera with look tilt, footfall and ambient camera shakes, and the vignette pass.
-- Per frame it follows the source order: controller input, Blueprint Tick, character movement,
-- spring arm, then camera shakes in the camera manager.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local YHP = ReplicatedStorage:WaitForChild("YHP")
local Config = require(YHP:WaitForChild("Config"))
local Unreal = require(YHP:WaitForChild("Unreal"))
local SpringArm = require(YHP:WaitForChild("SpringArm"))
local Movement = require(YHP:WaitForChild("Movement"))
local CameraShake = require(YHP:WaitForChild("CameraShake"))
local LensEffects = require(YHP:WaitForChild("LensEffects"))

local player = Players.LocalPlayer

-- Default controls are switched off while this script owns the player. Newer places expose
-- StarterPlayer.PlayerModule with a ControlModule.Enabled flag; older ones a per-player
-- PlayerModule whose ControlModule.moveFunction can be replaced.
local controlModule
local legacyControls, defaultMoveFunction
do
	local StarterPlayer = game:GetService("StarterPlayer")
	local shared = StarterPlayer:FindFirstChild("PlayerModule")
	local ok, api = pcall(require, shared or player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10))
	if ok and type(api) == "table" then
		if type(api.ControlModule) == "table" and api.ControlModule.Enabled ~= nil then
			controlModule = api.ControlModule
		elseif type(api.GetControls) == "function" then
			legacyControls = api:GetControls()
			defaultMoveFunction = legacyControls.moveFunction
		end
	end
end

local function setDefaultControls(enabled)
	if controlModule then
		controlModule.Enabled = enabled
	elseif legacyControls then
		legacyControls.moveFunction = enabled and defaultMoveFunction or function() end
	end
end

local MOVE_KEYS = {
	[Enum.KeyCode.W] = Vector2.new(0, 1),
	[Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.S] = Vector2.new(0, -1),
	[Enum.KeyCode.Down] = Vector2.new(0, -1),
	[Enum.KeyCode.D] = Vector2.new(1, 0),
	[Enum.KeyCode.Right] = Vector2.new(1, 0),
	[Enum.KeyCode.A] = Vector2.new(-1, 0),
	[Enum.KeyCode.Left] = Vector2.new(-1, 0),
}
local moveStick = Vector2.zero

-- IA_Move as (right, forward)
local function readMove(): Vector2
	if legacyControls then
		local v = legacyControls:GetMoveVector()
		return Vector2.new(v.X, -v.Z)
	end
	local move = moveStick
	if not UserInputService:GetFocusedTextBox() then
		for key, direction in MOVE_KEYS do
			if UserInputService:IsKeyDown(key) then
				move += direction
			end
		end
	end
	return move.Magnitude > 1 and move.Unit or move
end

local CM = Config.CentimetersPerStud
local footfall = Instance.new("BindableEvent")
footfall.Name = "Footfall" -- fires (material, running) so footstep audio can hook in
footfall.Parent = script

local function attribute(name, default)
	local value = YHP:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

-- Controller and Blueprint state
local controlPitch, controlYaw = 0, 0
local cameraTilt = 0
local running, forward = false, false
local lastStepPos = Vector3.zero -- CDO default; BeginPlay never sets it
local shakeWait = 0 -- BeginPlay sets ShakeWait=0
local shakes = {}

local arm = SpringArm.new(Config)
local movement = Movement.new(Config)

local character, humanoid, root
local hiddenParts = {}
local active = false
local touchDelta = Vector2.zero
local stick = Vector2.zero

local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude

local vignetteGui = Instance.new("ScreenGui")
vignetteGui.Name = "YHPVignette"
vignetteGui.IgnoreGuiInset = true
vignetteGui.ScreenInsets = Enum.ScreenInsets.None
vignetteGui.ResetOnSpawn = false
vignetteGui.DisplayOrder = -10
local vignette = Instance.new("ImageLabel")
vignette.Size = UDim2.fromScale(1, 1)
vignette.BackgroundTransparency = 1
vignette.ScaleType = Enum.ScaleType.Stretch
vignette.ZIndex = 2
vignette.Parent = vignetteGui
vignetteGui.Parent = player:WaitForChild("PlayerGui")
local lens = LensEffects.new(YHP, vignetteGui)

local function setHidden(hidden)
	if hidden and character then
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and hiddenParts[part] == nil then
				hiddenParts[part] = part.LocalTransparencyModifier
				part.LocalTransparencyModifier = 1
			end
		end
	else
		for part, value in hiddenParts do
			if part.Parent then
				part.LocalTransparencyModifier = value
			end
		end
		table.clear(hiddenParts)
	end
end

local function capsuleCenter()
	-- The Unreal actor location is the capsule centre, CapsuleHalfHeight above the floor.
	local legs = humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or humanoid.HipHeight
	local floor = root.Position - Vector3.new(0, legs + root.Size.Y / 2, 0)
	return floor + Vector3.new(0, Config.CapsuleHalfHeight / CM, 0)
end

local function release()
	if not active then
		return
	end
	active = false
	setDefaultControls(true)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
		humanoid.WalkSpeed = humanoid:GetAttribute("YHPOriginalWalkSpeed") or 16
		humanoid.AutoRotate = true
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	vignette.Visible = false
	lens:Release()
	setHidden(false)
end

local function acquire()
	active = true
	setDefaultControls(false)
	if humanoid:GetAttribute("YHPOriginalWalkSpeed") == nil then
		humanoid:SetAttribute("YHPOriginalWalkSpeed", humanoid.WalkSpeed)
	end
	humanoid.AutoRotate = false
	-- JumpZVelocity is 0 in the source movement component and no Jump event is bound.
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, Config.JumpZVelocity > 0)
	humanoid.MaxSlopeAngle = Config.WalkableFloorAngle
	local look = workspace.CurrentCamera.CFrame.LookVector
	controlYaw = -math.deg(math.atan2(-look.X, -look.Z))
	controlPitch = 0
	cameraTilt = 0
	arm:Reset()
	movement.velocity = Vector3.zero
end

local function onCharacter(newCharacter)
	release()
	setHidden(false)
	character = newCharacter
	humanoid = newCharacter:WaitForChild("Humanoid")
	root = newCharacter:WaitForChild("HumanoidRootPart")
	ray.FilterDescendantsInstances = { newCharacter }
	humanoid.Died:Once(release)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Touch and not processed then
		touchDelta += Vector2.new(input.Delta.X, input.Delta.Y)
	elseif input.KeyCode == Enum.KeyCode.Thumbstick2 then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		stick = p.Magnitude > 0.2 and p or Vector2.zero -- IMC deadzone modifier
	elseif input.KeyCode == Enum.KeyCode.Thumbstick1 then
		local p = Vector2.new(input.Position.X, input.Position.Y)
		moveStick = p.Magnitude > 0.2 and p or Vector2.zero
	end
end)

local function playShake(profile)
	table.insert(shakes, CameraShake.new(profile))
end

local function step(dt)
	local camera = workspace.CurrentCamera
	local wanted = attribute("Enabled", true) and not attribute("Suspended", false)
	local alive = humanoid and root and humanoid.Health > 0 and root.Parent
	if not (wanted and alive) then
		release()
		return
	end
	if not active then
		acquire()
	end
	dt = math.min(dt, 0.25)

	-- Controller input -> ControlRotation, and IA_Look's tilt accumulation
	local sensitivity = Config.CameraSensitivity * Config.CameraSensitivityMult * attribute("MouseSensitivityScale", 1)
	local mouse = UserInputService:GetMouseDelta() + touchDelta
	touchDelta = Vector2.zero
	-- Mouse2D after the axis sensitivity and IA_Look's Y negate (positive Y = mouse moved down)
	local look = mouse * Config.MouseAxisSensitivity
	-- Gamepad_Right2D is consumed once per source frame; normalised here to 60 Hz
	look += Vector2.new(stick.X, stick.Y) * dt * 60
	controlYaw = Unreal.NormalizeAxis(controlYaw + look.X * sensitivity * Config.InputYawScale)
	controlPitch = math.clamp(controlPitch + look.Y * sensitivity * Config.InputPitchScale, Config.ViewPitchMin, Config.ViewPitchMax)
	cameraTilt += look.X

	-- IA_Move / IA_Run
	local move = readMove()
	local moveRight, moveForward = move.X, move.Y
	if move.Magnitude > 0 then
		forward = moveForward > 0
	end
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	local maxWalkSpeed = Config.WalkSpeed
	if shift then
		running = true
		if forward then
			maxWalkSpeed = Config.WalkSpeed * Config.RunSpeedMult
		end
	else
		running = false
	end

	-- Blueprint Tick: tilt recovery and clamp, then spring-arm target rotation
	cameraTilt = math.clamp(cameraTilt - cameraTilt * Config.CameraTiltRecover * dt, -Config.CameraMaxTilt, Config.CameraMaxTilt)
	local desiredRot = Vector3.new(controlPitch, controlYaw, cameraTilt)

	-- Blueprint Tick: footfall shakes every StepDist of travel, then the ambient shake timer
	local actorLocation = capsuleCenter()
	local skipAmbient = false
	if (actorLocation - lastStepPos).Magnitude > Config.StepDist / CM then
		local hit = workspace:Raycast(actorLocation, Vector3.new(0, -Config.StepTraceRange / CM, 0), ray)
		if hit then
			lastStepPos = actorLocation
			playShake(running and Config.Shakes.Run or Config.Shakes.Walk)
			footfall:Fire(hit.Material, running)
		else
			skipAmbient = true
		end
	end
	if not skipAmbient then
		if shakeWait <= 0 then
			playShake(Config.Shakes.Ambient)
			shakeWait = running and Config.AmbientShakeWait / Config.RunSpeedMult or Config.AmbientShakeWait
		else
			shakeWait -= dt
		end
	end

	-- Character movement: actor yaw follows the controller, velocity from CalcVelocity
	local yawFrame = Unreal.RotatorToCFrame(0, controlYaw, 0)
	root.CFrame = CFrame.new(root.Position) * yawFrame
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if attribute("SourceMovement", true) then
		if grounded then
			local input = yawFrame:VectorToWorldSpace(Vector3.new(moveRight, 0, -moveForward))
			local v = movement:Step(dt, Vector3.new(input.X, 0, input.Z), maxWalkSpeed)
			-- Walls stop the source capsule; adopt the physical velocity when it is lower.
			local actual = root.AssemblyLinearVelocity * Vector3.new(1, 0, 1) * CM
			if v.Magnitude > 1 and actual.Magnitude < v.Magnitude * 0.5 and humanoid.MoveDirection.Magnitude > 0 then
				movement.velocity = actual
				v = actual
			end
			humanoid.WalkSpeed = v.Magnitude / CM
			humanoid:Move(v.Magnitude > 1e-3 and v.Unit or Vector3.zero, false)
		end
	else
		humanoid.WalkSpeed = humanoid:GetAttribute("YHPOriginalWalkSpeed") or 16
		humanoid:Move(yawFrame:VectorToWorldSpace(Vector3.new(moveRight, 0, -moveForward)), false)
	end

	-- Spring arm: component sits at SpringArmOffset from the capsule centre in the actor frame
	local armOrigin = actorLocation + yawFrame:VectorToWorldSpace(Unreal.LocalToRoblox(Config.SpringArmOffset) / CM)
	local pose = arm:Update(dt, desiredRot, armOrigin)

	-- Camera manager: apply every playing shake in camera space
	local scale = attribute("ShakeScale", 1)
	for i = #shakes, 1, -1 do
		local rot, loc = shakes[i]:Update(dt)
		if rot then
			rot *= scale
			pose = CFrame.new(pose.Position + pose:VectorToWorldSpace(Unreal.LocalToRoblox(loc * scale) / CM))
				* pose.Rotation
				* Unreal.RotatorToCFrame(rot.X, rot.Y, rot.Z)
		else
			table.remove(shakes, i)
		end
	end

	camera.CameraType = Enum.CameraType.Scriptable
	local viewport = camera.ViewportSize
	local aspect = viewport.Y > 0 and viewport.X / viewport.Y or 16 / 9
	camera.FieldOfView = math.deg(2 * math.atan(math.tan(math.rad(Config.HorizontalFOV / 2)) / aspect))
	camera.CFrame = pose
	camera.Focus = pose
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	setHidden(true)

	local image = YHP:GetAttribute("VignetteImage")
	vignette.Visible = attribute("VignetteEnabled", true) and image ~= nil and image ~= ""
	vignette.Image = image or ""
	lens:Update(dt, camera, pose)
end

RunService:BindToRenderStep("YHPPlayer", Enum.RenderPriority.Camera.Value + 1, step)
