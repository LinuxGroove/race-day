# Packaging

Race Day ships as the strictly confined snap `race-day`
(`snap/snapcraft.yaml`, core24, amd64 and arm64), and as Windows and macOS
zips attached to each release.

## What the build does

1. The **race-day part** downloads the Godot editor and export
   templates for the pinned version (`GODOT_VERSION` in the yaml, keep it in
   step with `project.godot` and the CI workflow), imports the project and
   runs `--export-release` with the `Linux` or `Linux ARM64` preset from
   `export_presets.cfg`. The binary and `.pck` go to `$SNAP/game`, the
   launcher to `$SNAP/bin`.
2. The version comes from `config/version` in `project.godot`, which CI
   stamps from `tools/version.sh` before building.
3. The app uses the **gnome extension**, which brings the GNOME runtime,
   Mesa through `gpu-2404`, and the desktop plugs (`wayland`, `x11`,
   `opengl`, `desktop`). The same snap runs on an Ubuntu desktop and on a
   handheld's gamepad shell.

Build locally with `snapcraft pack`.

## Workflows

| Workflow | When | What |
|---|---|---|
| CI (`.github/workflows/ci.yml`) | Every push to `main` and every pull request | Imports the project, checks every script compiles, runs the tests (including two bot runs of Saw Mill Sprint) |
| Snap (`.github/workflows/snap.yml`) | Every push to `main`, every pull request, and published releases | Builds the snap on amd64 and arm64 runners and uploads each as an artifact. Pushes to `main` go to the store's edge channel and releases to candidate, using the `STORE_LOGIN` secret |
| Windows and macOS (`.github/workflows/desktop.yml`) | Pushes to `main` and releases | Exports a single `.exe` and a universal, ad-hoc signed `.app`, zipped with the license and credits |
| Release (`.github/workflows/release.yml`) | Run by hand | Tags the next `vYYYY.WW.MINOR` and publishes a release with notes from `tools/release.sh` |

## Interfaces

The gnome extension's desktop plugs, plus `audio-playback`, `joystick`
(controllers) and `network` (the anonymous launch ping, and online features
to come). `joystick` is not auto-connected on desktops:

```sh
sudo snap connect race-day:joystick
```

## Where data lives

Settings, progress (`progress.cfg`) and best runs' ghosts (`ghosts/`) are in
`$SNAP_USER_DATA/.local/share/race-day`.

## Updating Godot

Change `GODOT_VERSION` in `snap/snapcraft.yaml`, `.github/workflows/ci.yml`
and `.github/workflows/desktop.yml` together.
