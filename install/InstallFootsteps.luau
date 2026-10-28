-- Grass footsteps: four free Creator Store grass footstep sounds in ReplicatedStorage.YHP.Footsteps,
-- played by StarterPlayerScripts.YHPFootsteps (src/StarterPlayerScripts/YHPFootsteps.client.luau)
-- on each YHPPlayer footfall. Run in the Command Bar in Edit mode, then add the LocalScript.
local folder = game.ReplicatedStorage.YHP:FindFirstChild("Footsteps") or Instance.new("Folder")
folder.Name = "Footsteps"
folder.Parent = game.ReplicatedStorage.YHP
for name, id in {
	Grass1 = "rbxassetid://129956418693357",
	Grass2 = "rbxassetid://78534941650081",
	Grass3 = "rbxassetid://110522236020035",
	Grass4 = "rbxassetid://135037154891351",
} do
	local sound = folder:FindFirstChild(name) or Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = folder
end
return "Footstep sounds installed"
