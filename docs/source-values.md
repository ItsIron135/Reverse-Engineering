# Source behaviour and how it maps to Roblox

The source is the shipped Windows build of *Your Happy Place* (UE 5.1.1-23901901, project `VHSLiminal`). Assets are in an unencrypted IoStore container compressed with Oodle. Values below were decoded from the cooked assets and the executable's native reflection tables. Nothing here was copied from Unreal source; the formulas are re-implemented from the engine behaviour they describe.

All conversions use 28 cm per stud.

## Movement (`Movement.luau`)

`BP_FirstPersonCharacter` sets `MaxWalkSpeed` from its own variables. The `CharacterMovementComponent` delta was decoded against the executable's 155-entry property table.

| Property | Source | Roblox |
|---|---:|---:|
| WalkSpeed | 150 cm/s | 5.36 studs/s |
| Run (LeftShift and last move input forward) | 300 cm/s | 10.71 studs/s |
| MaxAcceleration | 256 cm/s² | ramp to walk in 0.59 s |
| BrakingDecelerationWalking | 512 cm/s² | stop from walk in 0.28 s |
| GroundFriction | 0.5 | direction-change friction |
| BrakingFrictionFactor | 0 | braking is pure deceleration |
| JumpZVelocity | 0 | jumping disabled (no Jump event is bound either) |
| WalkableFloorAngle | 65.6° | Humanoid.MaxSlopeAngle |

`IA_Run` pressed sets `Running=true` and, only if `Forward` (the last non-zero move input had Y > 0), doubles `MaxWalkSpeed`. Releasing sets walk speed and `Running=false`. Running backwards therefore keeps walk speed but still plays the run shake.

Velocity follows `CalcVelocity`: friction pulls velocity toward the input direction, acceleration is added and capped at max speed, and with no input (or above max speed after releasing Shift) velocity brakes at 512 cm/s² with Unreal's 10 cm/s brake-to-stop cutoff. The Roblox Humanoid is driven with `WalkSpeed = |v|` and `Move(v.Unit)` so the physical speed follows this curve. Measured in a Studio playtest: 0→150 cm/s in ~0.6 s, 150→300 cm/s in ~0.6 s, 300→0 in ~0.55 s.

## Camera (`SpringArm.luau`, `YHPPlayer.client.luau`)

- Camera height: capsule half-height 96 cm plus spring-arm offset (20, 0, 60) cm, so the eye sits 156 cm (5.57 studs) above the floor and 20 cm in front of the capsule centre.
- Horizontal FOV 110°, converted to Roblox's vertical FOV for the current aspect ratio every frame.
- Spring arm: arm length 0, no collision, location lag 15, rotation lag 5, max lag distance 100 cm, substepping at 1/60 s. Interpolation uses Unreal's `clamp(dt*speed, 0, 1)` alpha, not exponential damping.
- Pitch is limited to -60°/+50°.
- Mouse: Mouse2D axis sensitivity 0.07 × CameraSensitivity 0.75 × InputYawScale 2.5 = 0.131 degrees per pixel (Roblox's own mouse-sensitivity setting multiplies this, as it does every Roblox camera).
- Look tilt: each frame `CameraTilt += lookX` (the post-0.07 mouse value), then `CameraTilt = clamp(CameraTilt - CameraTilt*25*dt, -5, 5)`. The roll is added to the spring arm's target rotation, so it passes through the rotation lag.

## Camera shakes (`CameraShake.luau`)

The walk and run shakes are not continuous head-bob. Tick measures distance from `LastStepPos`; past 100 cm it traces 150 cm down from the actor, and on a hit stores the position and plays one 1-second `RunCamShake` or `WalkCamShake`. Instances overlap. At source speeds this is 1.5 footfalls per second walking and 3 running, which the playtest reproduced exactly. A miss skips the ambient check for that frame.

The ambient `CameraShake` (300 s) starts on the first tick and is replayed every 300 s (150 s if running when it fires).

| | Walk | Run | Ambient |
|---|---|---|---|
| Duration / blend in / out (s) | 1 / 0.3 / 0.7 | 1 / 0.3 / 1 | 300 / 1 / 1 |
| Pitch amp / freq | 2 / 2 | 3 / 4 | 3 / 0.2 |
| Yaw | 0.7 / 3.5 | 1.5 / 3.5 | 4 / 0.3 |
| Roll | 2 / 2 | 4 / 3 | 1 / 0.5 |
| Location X (cm) | 0.25 / 2 | 0.4 / 2 | 0.5 / 0.5 |
| Location Y | 0.25 / 2 | 0.4 / 2 | 1 / 0.5 |
| Location Z | 5 / 2 | 7 / 3 | 1.5 / 0.5 |

Every axis is Perlin noise: each starts at a random phase in 0..2π, advances by `dt * frequency` and samples Unreal's 1D improved Perlin (`UnrealPerlin.luau`, whose permutation table matches the executable). Blend weight is the minimum of the linear blend-in and blend-out ramps. Offsets are applied in camera space after the spring arm.

## Post-processing and lighting

Every level's PostProcessVolume shares these active settings: contrast 1.2, shadow/midtone gamma 1.48, bloom 250 with the `lensDirt11` dirt mask at 400, vignette 0.32, chromatic aberration 1.56, film grain 1, motion blur 1, depth-of-field focus 40 cm, plus three post-process materials (LensDistortion intensity 0.3, Sharpen2 intensity 5, DigiClamp). The camera overrides shutter speed to 1.

What carries over to Roblox:

- **Vignette**: `assets/vignette.png` is baked by `tools/make_vignette.py` from Unreal's vignette mask at intensity 0.32 and shown as a full-screen overlay. Unreal applies it before tonemapping; the overlay uses the display-space equivalent, so it is close but not identical.
- **Colour grade, bloom, depth of field**: darker and contrastier with blown-out lights (exposure -0.6, contrast 0.35, bloom intensity 2 / size 56 / threshold 0.7, far depth-of-field 0.3). Unreal's numbers are in different units, so these are tuned by eye toward the source's look rather than converted.
- **Lens dirt**: `lensDirt11` is converted by `tools/make_lens_dirt_overlay.py` (colour kept, luminance as alpha, sensor noise cut) and shown full-screen by `LensEffects.luau`. In Unreal it only appears where bloom is bright, so its opacity rises from `LensDirtBase` to `LensDirtMax` as the camera faces the sun, Light instances, Neon parts or parts tagged `YHPGlare`.
- **Motion blur and softness**: Roblox has no per-pixel motion blur. A camera `BlurEffect` holds a constant `BaseBlur` and adds half the on-screen streak length of this frame's camera rotation (MotionBlurAmount 1), capped by `MotionBlurMax`. It blurs uniformly rather than along the motion.
- **Sun colour**: Map6's directional light is 4687 K; `Lighting.ColorShift_Top` is set to that colour temperature.

What does not carry over: Lumen GI, local exposure, chromatic aberration, lens distortion, sharpening, DigiClamp and the source's film grain.

## Source textures

`lensDirt11` (2064×1161 bloom dirt mask) and `Cloud` (1000×662, input to the Map6 cloud material) were decoded from their BGRA mips and uploaded to Roblox. The installer stores their asset IDs as attributes on `ReplicatedStorage.YHP` and as Decals under `ReplicatedStorage.YHP.SourceTextures`. The lens dirt is shown through the converted overlay above; the cloud texture is not used. The PNGs are not committed here because they are the game's own artwork.

## Known differences

- Physical gamepad and touch input were not tested. In places using the newer `StarterPlayer.PlayerModule`, the default touch thumbstick is switched off with the rest of the default controls, so mobile movement is not supported yet.
- Gamepad look in the source is applied once per frame; here it is normalised to 60 FPS.
- While airborne (falling off a ledge) the Humanoid keeps its last velocity rather than Unreal's 0.05 air control.
- The character is hidden locally; the source's first-person arms mesh is not recreated.
- Footstep sounds and running wind are not ported. The `Footfall` BindableEvent under the `YHPPlayer` script fires `(material, running)` on every source footfall so audio can be added.
