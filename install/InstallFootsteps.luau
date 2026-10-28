-- Grass footsteps: four free Creator Store grass footstep sounds (Half-Life 2 grass set) in ReplicatedStorage.YHP.Footsteps,
-- played by StarterPlayerScripts.YHPFootsteps (src/StarterPlayerScripts/YHPFootsteps.client.luau)
-- on each YHPPlayer footfall. Run in the Command Bar in Edit mode, then add the LocalScript.
local folder = game.ReplicatedStorage.YHP:FindFirstChild("Footsteps") or Instance.new("Folder")
folder.Name = "Footsteps"
folder.Parent = game.ReplicatedStorage.YHP
for name, id in {
	Grass1 = "rbxassetid://105277634319381",
	Grass2 = "rbxassetid://98069158661569",
	Grass3 = "rbxassetid://135182192451997",
	Grass4 = "rbxassetid://116425333836106",
} do
	local sound = folder:FindFirstChild(name) or Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = folder
end
return "Footstep sounds installed"
