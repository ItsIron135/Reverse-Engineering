-- Values recovered from the shipped UE 5.1 game (VHSLiminal / "Your Happy Place").
-- Units are Unreal's (centimetres, degrees, seconds) unless a name says otherwise.
-- docs/source-values.md lists where each number came from.
return {
	CentimetersPerStud = 28,

	-- BP_FirstPersonCharacter CDO
	WalkSpeed = 150,
	RunSpeedMult = 2,
	CameraSensitivity = 0.75,
	CameraSensitivityMult = 1, -- BeginPlay overwrites this from Mouse.sav when it exists
	CameraTiltRecover = 25,
	CameraMaxTilt = 5,
	StepDist = 100,
	StepTraceRange = 150,
	AmbientShakeWait = 300,

	-- CharacterMovementComponent deltas
	MaxAcceleration = 256,
	BrakingDecelerationWalking = 512,
	GroundFriction = 0.5,
	BrakingFrictionFactor = 0,
	JumpZVelocity = 0,
	WalkableFloorAngle = 65.645,

	-- Capsule and spring arm
	CapsuleHalfHeight = 96,
	SpringArmOffset = Vector3.new(20, 0, 60), -- Unreal X forward, Y right, Z up
	CameraLagSpeed = 15,
	CameraRotationLagSpeed = 5,
	CameraLagMaxDistance = 100,
	CameraLagMaxTimeStep = 1 / 60, -- native default, substepping enabled
	ViewPitchMin = -60,
	ViewPitchMax = 50,
	HorizontalFOV = 110,

	-- Input chain: DefaultInput.ini Mouse2D sensitivity, DefaultGame.ini PlayerController scales
	MouseAxisSensitivity = 0.07,
	InputYawScale = 2.5,
	InputPitchScale = -2.5,

	-- Legacy camera shakes. Rotation is {pitch, yaw, roll} degrees, location {x, y, z} cm,
	-- each axis {amplitude, frequency}; every axis uses Perlin noise.
	Shakes = {
		Walk = {
			Duration = 1, BlendIn = 0.3, BlendOut = 0.7,
			Rotation = { { 2, 2 }, { 0.7, 3.5 }, { 2, 2 } },
			Location = { { 0.25, 2 }, { 0.25, 2 }, { 5, 2 } },
		},
		Run = {
			Duration = 1, BlendIn = 0.3, BlendOut = 1,
			Rotation = { { 3, 4 }, { 1.5, 3.5 }, { 4, 3 } },
			Location = { { 0.4, 2 }, { 0.4, 2 }, { 7, 3 } },
		},
		Ambient = {
			Duration = 300, BlendIn = 1, BlendOut = 1,
			Rotation = { { 3, 0.2 }, { 4, 0.3 }, { 1, 0.5 } },
			Location = { { 0.5, 0.5 }, { 1, 0.5 }, { 1.5, 0.5 } },
		},
	},

	-- Active PostProcessVolume settings shared by the levels
	PostProcess = {
		VignetteIntensity = 0.32,
		ColorContrast = 1.2,
		ColorGammaShadowsMidtones = 1.48,
		BloomIntensity = 250,
		BloomDirtMaskIntensity = 400,
		SceneFringeIntensity = 1.56,
		DepthOfFieldFocalDistance = 40,
	},
	DepthOfFieldFocalDistance = 40, -- cm
	DepthOfFieldSensorWidth = 30, -- mm
	DepthOfFieldFstop = 4, -- engine default, not overridden
	MotionBlurAmount = 1,
	MotionBlurMax = 100, -- percent of screen
	MotionBlurTargetFPS = 30, -- engine default, not overridden
	FilmGrainTexelSize = 0.768, -- grain texel size in screen pixels

	-- Map6 DirectionalLight
	SunTemperature = 4687.2,
	SunPitch = -46,
}
