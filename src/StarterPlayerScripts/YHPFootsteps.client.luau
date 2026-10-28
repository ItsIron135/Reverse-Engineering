-- Grass footstep sounds, one per source footfall: the same event that starts the walk/run camera
-- shake (YHPPlayer's Footfall BindableEvent), so the sound lands on the camera bob.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local sounds = ReplicatedStorage:WaitForChild("YHP"):WaitForChild("Footsteps"):GetChildren()
local footfall = playerScripts:WaitForChild("YHPPlayer"):WaitForChild("Footfall")

-- Silence Roblox's default character sounds (running, jumping, landing...): stop the script that
-- drives them and remove the Sound objects it already created on the character.
local DEFAULT_SOUNDS = { "Climbing", "Died", "FreeFalling", "GettingUp", "Jumping", "Landing", "Running", "Splash", "Swimming" }
local function silence(character)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	local function strip(child)
		if child:IsA("Sound") and table.find(DEFAULT_SOUNDS, child.Name) then
			child.Volume = 0
			child:Destroy()
		end
	end
	for _, child in root:GetChildren() do
		strip(child)
	end
	root.ChildAdded:Connect(strip)
end
task.spawn(function()
	local default = playerScripts:WaitForChild("RbxCharacterSounds", 10)
	if default then
		default.Enabled = false
	end
end)
player.CharacterAdded:Connect(silence)
if player.Character then
	task.spawn(silence, player.Character)
end
local random = Random.new()
local last

footfall.Event:Connect(function(_material, running)
	if #sounds == 0 then
		return
	end
	-- Never repeat the previous sample back to back
	local pick
	repeat
		pick = sounds[random:NextInteger(1, #sounds)]
	until pick ~= last or #sounds == 1
	last = pick
	local sound = pick:Clone()
	sound.Volume = running and 0.4 or 0.25
	sound.PlaybackSpeed = (running and 1.08 or 1) * random:NextNumber(0.94, 1.06)
	sound.Parent = SoundService
	SoundService:PlayLocalSound(sound)
	task.delay(math.max(sound.TimeLength, 1) + 0.5, function()
		sound:Destroy()
	end)
end)
