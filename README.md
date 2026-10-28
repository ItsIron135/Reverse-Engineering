# Your Happy Place → Roblox

A Luau port of the first-person camera, movement, camera shakes and post-processing look from *Your Happy Place* (an Unreal Engine 5.1 game), rebuilt from values and behaviour decoded out of the shipped build. See [docs/source-values.md](docs/source-values.md) for every number, where it came from and what could not be carried over.

## Layout

```
src/ReplicatedStorage/YHP/      ModuleScripts (Config, Unreal, UnrealPerlin, CameraShake, SpringArm, Movement)
src/StarterPlayerScripts/       YHPPlayer.client.luau, the LocalScript that runs it all
install/Install.luau            Command Bar installer generated from src/
install/Restore.luau            Removes the port and restores the place's own camera/lighting
assets/vignette.png             Unreal vignette mask baked at intensity 0.32
tools/                          Installer builder and vignette generator
default.project.json            Rojo project
```

## Install

Either sync the scripts with Rojo (`rojo serve`; this does not apply the lighting effects or `StarterPlayer.EnableMouseLockOption=false`), or paste `install/Install.luau` into Studio's Command Bar in Edit mode. The installer backs up the place's lighting to `ServerStorage.YHP_RestoreBackup` the first time, so `install/Restore.luau` can undo it. After editing `src/`, run `python tools/build_installer.py` to regenerate the installer.

## Settings

Attributes on `ReplicatedStorage.YHP`, editable live during Play:

| Attribute | Default | Effect |
|---|---|---|
| Enabled | true | Turn the whole controller off and hand back the default camera and controls |
| Suspended | false | Set true while a cutscene or other system owns the camera |
| SourceMovement | true | Source walk/run speeds and acceleration; false keeps the Humanoid's WalkSpeed |
| MouseSensitivityScale | 1 | Multiplier on the source's 0.131°/pixel |
| ShakeScale | 1 | Multiplier on all camera shakes |
| VignetteEnabled | false | Show the vignette overlay |
| LensDirtEnabled | true | Show the lens-smudge overlay |
| LensDirtBase / LensDirtMax | 0.03 / 0.15 | Smudge opacity with no light in view / facing a bright light |
| MotionBlurEnabled | true | Blur while the camera turns |
| MotionBlurAmount | 1 | Source MotionBlurAmount |
| ConstantBlurScale | 4.23 | Multiplier on the source depth-of-field blur (always on) |
| SharpenRimEnabled / SharpenRimStrength / SharpenRimColor | false / 0.85 / light blue-white | Light outline around dark silhouettes from the game's sharpening |

Controls match the source: WASD or arrow keys to move, LeftShift to run (only while moving forward), mouse to look, no jump.
