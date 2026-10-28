-- Screen-space parts of the source camera look that Roblox has no post-process for:
--   * lens dirt: Unreal adds lensDirt11 on top of bloom, so it shows where bright light is in view.
--     Here its opacity follows how directly the camera faces the sun and nearby lights.
--   * depth of field: focus at 40 cm with a 30 mm sensor leaves everything past arm's length
--     defocused by a near-constant amount, so it becomes a constant blur radius. ConstantBlurScale
--     (default 2) widens it toward the softer look of the running game.
--   * motion blur: Unreal blurs along per-pixel motion. Roblox only has a uniform BlurEffect, so
--     its radius follows the camera's rotation using Unreal's velocity scaling.
--   * sharpening rim: the game's Sharpen2 material adds 5x the luminance difference between each
--     pixel and four neighbours 0.005 of the screen away, which draws a bright rim on the sky side
--     of every dark silhouette. A Highlight on the whole workspace outlines that same silhouette.
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local LensEffects = {}
LensEffects.__index = LensEffects

local LIGHT_SCAN_INTERVAL = 1
local LIGHT_RANGE = 150

function LensEffects.new(settings: Instance, gui: ScreenGui, config)
	local dirt = Instance.new("ImageLabel")
	dirt.Name = "LensDirt"
	dirt.Size = UDim2.fromScale(1, 1)
	dirt.BackgroundTransparency = 1
	dirt.ScaleType = Enum.ScaleType.Crop
	dirt.ImageTransparency = 1
	dirt.ZIndex = 1
	dirt.Parent = gui

	-- Fully transparent parts (including the hidden local character) are not outlined
	local rim = Instance.new("Highlight")
	rim.Name = "YHP_SharpenRim"
	rim.Adornee = workspace
	rim.FillTransparency = 1
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	rim.Enabled = false

	return setmetatable({
		settings = settings,
		config = config,
		dirt = dirt,
		rim = rim,
		blur = nil,
		glare = 0,
		lights = {},
		scanTimer = 0,
		lastRotation = nil,
	}, LensEffects)
end

function LensEffects:_setting(name, default)
	local value = self.settings:GetAttribute(name)
	if value == nil then
		return default
	end
	return value
end

function LensEffects:_scanLights(origin: Vector3)
	table.clear(self.lights)
	for _, light in workspace:GetDescendants() do
		local part = light.Parent
		if light:IsA("Light") and light.Enabled and light.Brightness > 0 and part and part:IsA("BasePart") then
			if (part.Position - origin).Magnitude < LIGHT_RANGE then
				table.insert(self.lights, { part = part, brightness = light.Brightness })
			end
		elseif light:IsA("BasePart") and light.Material == Enum.Material.Neon and light.Transparency < 0.5 then
			if (light.Position - origin).Magnitude < LIGHT_RANGE then
				table.insert(self.lights, { part = light, brightness = 1 })
			end
		end
	end
	for _, tagged in CollectionService:GetTagged("YHPGlare") do
		if tagged:IsA("BasePart") then
			table.insert(self.lights, { part = tagged, brightness = tagged:GetAttribute("GlareBrightness") or 2 })
		end
	end
end

-- 0..1: how much bright light the lens is facing.
function LensEffects:_glare(dt: number, pose: CFrame): number
	self.scanTimer -= dt
	if self.scanTimer <= 0 then
		self.scanTimer = LIGHT_SCAN_INTERVAL
		self:_scanLights(pose.Position)
	end
	local look = pose.LookVector
	local glare = 0
	local sun = Lighting:GetSunDirection()
	if sun.Y > 0 then
		glare += math.max(0, look:Dot(sun)) ^ 6 * math.min(1, sun.Y * 4)
	end
	for _, light in self.lights do
		local offset = light.part.Position - pose.Position
		local distance = offset.Magnitude
		if distance > 0 then
			local facing = math.max(0, look:Dot(offset / distance)) ^ 8
			glare += facing * light.brightness / (1 + distance / 20)
		end
	end
	return math.clamp(glare, 0, 1)
end

function LensEffects:Update(dt: number, camera: Camera, pose: CFrame)
	-- Lens dirt
	local image = self.settings:GetAttribute("LensDirtOverlayImage")
	local dirtOn = self:_setting("LensDirtEnabled", true) and image ~= nil and image ~= ""
	self.dirt.Visible = dirtOn
	if dirtOn then
		self.dirt.Image = image
		local target = self:_glare(dt, pose)
		-- Glare builds faster than it fades so a light sweeping past still flashes the dirt
		local rate = target > self.glare and 6 or 3
		self.glare += (target - self.glare) * math.min(1, dt * rate)
		local base, peak = self:_setting("LensDirtBase", 0.04), self:_setting("LensDirtMax", 0.3)
		self.dirt.ImageTransparency = 1 - (base + (peak - base) * self.glare)
	end

	-- Sharpening rim
	local rimOn = self:_setting("SharpenRimEnabled", false)
	if rimOn and self.rim.Parent ~= camera then
		self.rim.Parent = camera
	end
	self.rim.Enabled = rimOn
	self.rim.OutlineColor = self:_setting("SharpenRimColor", Color3.fromRGB(220, 232, 255))
	self.rim.OutlineTransparency = 1 - self:_setting("SharpenRimStrength", 0.85)

	-- Depth-of-field softness and motion blur
	if not self.blur or self.blur.Parent ~= camera then
		if self.blur then
			self.blur:Destroy()
		end
		self.blur = Instance.new("BlurEffect")
		self.blur.Name = "YHP_MotionBlur"
		self.blur.Parent = camera
	end
	local c = self.config
	local width = camera.ViewportSize.X
	-- Thin-lens circle of confusion for a subject at infinity. The source focuses at 40 cm, so
	-- anything past about a metre is close to this size.
	local focalLength = (c.DepthOfFieldSensorWidth / 2) / math.tan(math.rad(c.HorizontalFOV / 2))
	local focus = c.DepthOfFieldFocalDistance * 10
	local coc = focalLength * focalLength / (c.DepthOfFieldFstop * (focus - focalLength))
	local focusRadius = coc / 2 / c.DepthOfFieldSensorWidth * width * self:_setting("ConstantBlurScale", 2)
	local motionRadius = 0
	local rotation = pose.Rotation
	if self.lastRotation and dt > 0 and self:_setting("MotionBlurEnabled", true) then
		local _, angle = (self.lastRotation:Inverse() * rotation):ToAxisAngle()
		local pixelsPerRadian = width / (2 * math.tan(math.rad(c.HorizontalFOV / 2)))
		-- Unreal scales velocity to MotionBlurTargetFPS and blurs half of it each way.
		local pixelsPerSecond = math.abs(angle) / dt * pixelsPerRadian
		motionRadius = 0.5 * self:_setting("MotionBlurAmount", c.MotionBlurAmount) * pixelsPerSecond / c.MotionBlurTargetFPS
		motionRadius = math.min(motionRadius, width * 0.5 * c.MotionBlurMax / 100)
	end
	self.lastRotation = rotation
	self.blur.Size = math.min(math.sqrt(focusRadius ^ 2 + motionRadius ^ 2), 56)
	self.blur.Enabled = true
end

function LensEffects:Release()
	self.dirt.Visible = false
	self.rim.Enabled = false
	self.lastRotation = nil
	if self.blur then
		self.blur.Enabled = false
	end
end

return LensEffects
