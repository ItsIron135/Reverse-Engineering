-- Grass footsteps: four free Creator Store grass footstep sounds (old CS:GO grass set) in ReplicatedStorage.YHP.Footsteps,
-- played by StarterPlayerScripts.YHPFootsteps (src/StarterPlayerScripts/YHPFootsteps.client.luau)
-- on each YHPPlayer footfall. Run in the Command Bar in Edit mode, then add the LocalScript.
local folder = game.ReplicatedStorage.YHP:FindFirstChild("Footsteps") or Instance.new("Folder")
folder.Name = "Footsteps"
folder.Parent = game.ReplicatedStorage.YHP
for name, id in {
	Grass1 = "rbxassetid://74613570357402",
	Grass2 = "rbxassetid://115467805684506",
	Grass3 = "rbxassetid://139667774868914",
	Grass4 = "rbxassetid://96838481971398",
	Grass5 = "rbxassetid://113824261411922",
	Grass6 = "rbxassetid://86401198855272",
} do
	local sound = folder:FindFirstChild(name) or Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Parent = folder
end
return "Footstep sounds installed"
