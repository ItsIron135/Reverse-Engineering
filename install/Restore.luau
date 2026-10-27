-- Removes the Your Happy Place port and restores the place's original camera and lighting.
-- Run in Studio's Command Bar in Edit mode.
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before restoring")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Lighting = game:GetService("Lighting")
local StarterPlayer = game:GetService("StarterPlayer")
local backup = game:GetService("ServerStorage"):FindFirstChild("YHP_RestoreBackup")
assert(backup, "No YHP_RestoreBackup in ServerStorage")

local recording = ChangeHistoryService:TryBeginRecording("Restore original camera and lighting")
for key, value in backup:GetAttributes() do
	if key == "LightingStyle" then
		Lighting.LightingStyle = Enum.LightingStyle[value]
	elseif key == "CameraMode" then
		StarterPlayer.CameraMode = Enum.CameraMode[value]
	elseif key == "EnableMouseLockOption" then
		StarterPlayer.EnableMouseLockOption = value
	elseif key ~= "PlaceId" then
		Lighting[key] = value
	end
end
for _, child in Lighting:GetChildren() do
	if child:GetAttribute("YHPManaged") then
		child:Destroy()
	end
end
local originals = backup:FindFirstChild("OriginalLightingEffects")
if originals then
	for _, child in originals:GetChildren() do
		child.Parent = Lighting
	end
end
local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
for _, name in { "YHPPlayer", "YHPRealisticCamera", "YHPFilmLook" } do
	local old = scripts and scripts:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
for _, name in { "YHP", "YHPCameraSettings", "YHPCameraDynamics" } do
	local old = game:GetService("ReplicatedStorage"):FindFirstChild(name)
	if old then
		old:Destroy()
	end
end
backup:Destroy()
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
return "Restored original camera mode, lighting properties and effects."
