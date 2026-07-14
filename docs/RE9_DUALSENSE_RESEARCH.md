# RE9 DualSense Reference Research

Date: 2026-06-25

Status: static metadata analysis only. No RE4R runtime changes were made.

## Inputs

- RE9 Object Explorer dump:
  `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL requiem BIOHAZARD requiem\il2cpp_dump.json`
- RE4R comparison dump:
  `C:\Program Files (x86)\Steam\steamapps\common\RESIDENT EVIL 4  BIOHAZARD RE4\il2cpp_dump.json`
- RE9 executable import table and executable strings.

## Main Finding

RE9 contains a new application-level device-feedback architecture that is not
present in RE4R.

RE4R exposes the older engine components:

- `soundlib.SoundVibrationManager`
- `via.hid.DualSenseDevice`
- `via.hid.VendorNativeDualSenseDevice`

RE9 still contains those engine types, but adds a larger routing layer:

- `app.DeviceFeedbackManager`
- `app.DeviceFeedbackProvider`
- `app.DualSenseVibrationProvider`
- `app.DeviceFeedbackConfig`
- `app.DeviceFeedbackDefinition`
- `app.DeviceFeedbackManagerSettings`
- `app.AdaptiveTriggerCatalog`
- `app.AdaptiveTriggerConfiguration`
- `app.SoundVibrationConfiguration`
- vibration and adaptive-trigger catalogs
- lightbar color animators
- motion-sensor input conditions and camera sensitivity data

The important architectural path appears to be:

```text
game vibration / trigger / illumination catalog
        |
        v
app.DeviceFeedbackManager
        |
        v
app.DeviceFeedbackProvider
        |
        +-- vibration
        +-- adaptive triggers
        +-- lightbar
        |
        v
app.DualSenseVibrationProvider
        |
        v
via.hid.DualSenseDevice / VendorNativeDualSenseDevice
```

This is substantially different from merely enabling RE4R's
`soundlib.SoundVibrationManager.IsTargetPlatform` flag.

## RE9 Device Feedback Evidence

`app.DeviceFeedbackManager` contains:

- vibration and adaptive-trigger catalogs;
- per-player vibration-wave-index assignment;
- vibration buses and volumes;
- compatible vibration and vibwav paths;
- provider selection and update logic;
- lightbar mute/pause state;
- adaptive-trigger mute and update state;
- DualSense-specific `fixVibration` overload;
- `initializeVibwavVibrationPort`;
- `playVibration`, `stopVibration`, pause and resume methods;
- `registerCatalog` overloads for vibration and adaptive-trigger catalogs;
- `updateAdaptiveTriggerStatus`;
- `updateLightBarStatus`;
- `setCompatibleVibwavVolume`.

`app.DeviceFeedbackProvider` combines all three relevant output groups:

- `_VibrationEnabled` and `_VibrationWaveIndex`;
- `_AdaptiveTriggerEnabled` and adaptive-trigger requests;
- `_LightBarEnabled`, color and illumination animator.

It exposes:

- `playVibration`;
- `setAdaptiveTrigger`;
- `set_LightBarIllumination`;
- `updateVibration`;
- `updateVibrationWaveIndex`;
- `updateAdaptiveTrigger`;
- `updateLightBar`.

`app.DualSenseVibrationProvider` owns a
`via.hid.DualSenseDevice` and manages its vibration-wave index.

## Sound / Audio Haptics Difference

RE4R's `soundlib.SoundVibrationManager` is platform-gated with
`IsTargetPlatform` and uses the older `VibrationInfo` list.

RE9's version:

- replaces `IsTargetPlatform` with `isHDVibrationPlatform`;
- uses `HDVibration` and `MotorVibration` records;
- has explicit audio initialization and termination;
- registers vibration game objects;
- tracks active vibration objects in a concurrent dictionary;
- retains WAV-driven vibration metadata through `SoundVibInfoByWav`;
- registers vibration-wave indices;
- processes post-vibration events through separate play/stop paths.

RE9 also adds `app.SoundVibrationConfiguration`, containing:

- `SoundVibInfoByWav` data;
- `SoundVibrationDefineInfo` data;
- vibration attenuation user data.

This supports the observation that RE9 has a complete authored
sound-to-vibration pipeline. The dump does not expose the actual WAV/catalog
contents, so runtime inspection is still required to map individual events.

## Adaptive Triggers

RE9 has a complete application layer that RE4R lacks:

- `app.AdaptiveTriggerCatalog`;
- `app.AdaptiveTriggerParam`;
- `app.AdaptiveTriggerParamApp`;
- `app.AdaptiveTriggerParamUserData`;
- `app.AdaptiveTriggerConfiguration`;
- trigger priorities and motor-bit definitions;
- `DeviceFeedbackManager.tryGetAdaptiveTriggerParam`;
- `DeviceFeedbackProvider.setAdaptiveTrigger`.

Both games contain basic `via.hid.DualSenseDevice` adaptive-trigger methods,
but RE9 adds the missing game-side catalog and routing system.

## Gyro / Motion Sensor

RE9 adds:

- `app.GameInputCondition_MotionSensorVec3`;
- `app.GameInputCondition_MotionSensorQuat`;
- `app.GameInputDefinition.MotionSensorInput`;
- `app.MotionSensorInputBits`;
- `app.MergedInputDeviceStatus.IMotionSensorInput`;
- `app.CameraInputUserData.MotionSensorSensitivityData`;
- separate pitch/yaw sensitivity;
- person-type and platform-type sensitivity selection.

RE4R has only isolated gyro-related gameplay types such as
`chainsaw.InventoryCameraController.GyroInfo` and
`chainsaw.PlayerBehaviorTreeAction_BT_ResetGyroCamera`; it does not contain
RE9's generic application-level motion-sensor input pipeline.

The RE9 architecture is useful as a design reference for future native gyro
tuning and prompt-handling ideas, but these application classes cannot simply
be called from RE4R because they are absent from the RE4R binary. RE4R's
current confirmed native gyro path uses external duaLib IMU reads plus mouse
injection instead of RE9-style in-engine motion input.

## libScePad Assessment

There is currently no evidence that the Windows RE9 build uses
`libScePad.dll` in the conventional form.

Confirmed:

- no `libScePad.dll` is present beside RE9;
- `re9.exe` has no normal or delay-load import for `libScePad.dll`;
- the executable contains no visible `scePad*` or `libScePad` strings;
- the executable directly imports Windows `HID.DLL` and `SETUPAPI.dll`.

The most likely implementation is Capcom's own `via.hid` Windows HID backend,
not duaLib or a dynamically linked Sony `libScePad.dll`.

This does not prove that Capcom never referenced Sony SDK behavior or report
formats internally, but replacing or supplying `libScePad.dll` is not the
mechanism visible in this PC build.

## Implications for RE4R

1. Forcing RE4R's old platform gate cannot recreate RE9 support because the
   larger `app.DeviceFeedbackManager` layer is missing.
2. RE9 is still valuable for understanding Capcom's intended event,
   catalog, provider and controller abstraction.
3. Porting RE9 managed types into RE4R is not a low-risk path. It would require
   reimplementing substantial native/game infrastructure.
4. Existing RE4R native haptics should remain untouched.
5. The current event-based controller-speaker bridge remains the practical
   RE4R audio solution.
6. Native gyro tuning should study RE9's input semantics, but keep using the
   independent RE4R-compatible duaLib backend rather than expecting the RE9
   classes to exist in RE4R.

## Recommended Runtime Inspection in RE9

Use Object Explorer while RE9 runs with a native USB DualSense:

1. Inspect `app.DeviceFeedbackManager` singleton.
2. Record:
   - `_IsInitialized`;
   - `_VibwavVibrationSupported`;
   - `_BnvibVibrationSupported`;
   - `_ApplicateVibration`;
   - `_ApplicateVibrationWaveIndex`;
   - `_ApplicateAdaptiveTrigger`;
   - `_ApplicateLightBar`;
   - `_VibrationPlayingType`;
   - registered catalog counts.
3. Inspect its `DeviceFeedbackProvider` for player 0.
4. Record the actual provider/device type and vibration-wave index.
5. Inspect `app.DualSenseVibrationProvider` and its
   `via.hid.DualSenseDevice`.
6. Inspect motion-sensor conditions while gyro aiming is enabled and disabled.
7. Do not modify fields or call output methods during the first pass.

## Runtime Confirmation

The read-only RE9 diagnostic confirmed the complete active chain with a USB
DualSense:

```text
app.DeviceFeedbackManager
  -> app.DeviceFeedbackProvider
  -> app.MergedFeedbackDevice
  -> app.ManagedGamePad
  -> app.DualSenseVibrationProvider
  -> via.hid.VendorNativeDualSenseDevice
```

Observed runtime state:

- vibration, vibration-wave-index, adaptive-trigger and lightbar application
  were enabled;
- vibwav support and its audio port were initialized;
- player 0 had vibration-wave index `0`;
- the vibration catalog contained 268 entries;
- the adaptive-trigger catalog contained 13 entries;
- the controller was detected as a native USB DualSense, not Bluetooth.

Passive hooks also confirmed that gameplay effects enter through
`app.DeviceFeedbackManager.playVibration`. Initial isolated captures produced:

- gunshot: vibration ID `1649794317`;
- reload sequence: `2043334035`, `3599789787`, `3633224381`;
- knife/axe hit sample: `1958182305` plus `22708584`;
- grab/damage/melee samples included `1525354855`, `1661683706`,
  `1685867591`, `1958182305`, `2209133360`, `2525083249`, and `4166249104`.

These IDs belong to RE9's catalogs and are not directly reusable in RE4R.
Their main value is confirming Capcom's event/catalog architecture, not
providing portable haptic assets or hooks.

## Practical Research Boundary

RE9 does not provide a low-risk drop-in implementation for RE4R:

- the application-level feedback classes and catalogs are absent from RE4R;
- RE9 vibration IDs have no corresponding RE4R catalog entries;
- the dump does not contain the authored vibration wave resources;
- copying the architecture would mean reimplementing a large feedback system.

For the current RE4R mod, the useful conclusions are:

1. Keep RE4R's confirmed native haptics untouched in native mode.
2. Keep the event-based extracted-WAV speaker bridge.
3. Keep the confirmed native lightbar, duaLib adaptive triggers, and native
   gyro path scoped to native mode; do not mix them with DSX ownership.
4. Treat future native-feedback tuning as part of the independent duaLib/direct
   HID research boundary. Use `DUALIB_HID_BRANCH.md` as its handoff.
5. Do not spend further time mapping every RE9 vibration ID unless a future
   task specifically investigates RE9 resource/catalog extraction.
