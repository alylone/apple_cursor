# Apple Cursor

![Apple Cursor](https://github.com/ful1e5/apple_cursor/assets/24286590/ad260d52-6534-441b-902d-440cb368b5c9)

Open source macOS Cursors for `Windows` and `Linux` with _HiDPI Support_ .

[![Build](https://github.com/ful1e5/apple_cursor/workflows/build/badge.svg)](https://github.com/ful1e5/apple_cursor/actions?query=workflow%3Abuild)

## Fork Purpose / 本 Fork 用途

> This is the personal Windows-focused fork at
> [`alylone/apple_cursor`](https://github.com/alylone/apple_cursor), based on
> [`ful1e5/apple_cursor`](https://github.com/ful1e5/apple_cursor). The fork was
> created to preserve the upstream macOS appearance while making cursor sizing
> and the working-in-background behavior feel correct on a DPI-scaled Windows
> desktop.

这是一份面向 Windows 日常使用的个人留档。修改工作的基线是上游提交
`fe044a42b4e9cea16ea762d2ed9004f6d7b35543`，主要适配环境如下：

| Item | Target |
| --- | --- |
| Operating system | Windows 10/11 |
| Display | 2560x1440 (2K), primarily 16:9; also suitable for 16:10 |
| Display scaling | 125% (120 DPI) |
| Windows cursor base size | 32 |
| Recommended fork profile | `Balanced` |
| Fork work recorded | 2026-07-23 |

### Why this fork exists

The upstream Regular Windows package uses nominal CUR resource sizes of
22/32/43/64/86/171 pixels. Some entries contain PNG canvases larger than their
nominal CUR dimensions. Windows chooses cursors by resource dimensions, so at
125% scaling it can select larger artwork than intended. In practice, Regular
can look closer to Large on a 2K display.

This fork adds
[`tools/New-CompactWindowsTheme.ps1`](./tools/New-CompactWindowsTheme.ps1) to
build standard Windows resource canvases without changing the upstream cursor
style. It produces independent schemes and does not overwrite or activate the
upstream themes.

| Profile | Artwork sizes | CUR canvas sizes | Purpose |
| --- | --- | --- | --- |
| `Compact` | 22/32/43/64/86/171 | 32/48/64/96/128/256 | Exact upstream Regular artwork, corrected resource selection |
| `Balanced` | 27/40/54/81/108/216 | 32/48/64/96/128/256 | Recommended perceptual size for 2K at 125% scaling |

`Compact` requires an extracted or installed upstream Regular Windows theme.
Its default source is
`C:\Windows\Cursors\macOS-Regular Cursors`; pass `-SourceDirectory` when the
source exists elsewhere. `Balanced` is rebuilt directly from this repository's
SVG sources and rendered PNGs.

### Balanced Work.ani design

The upstream `left_ptr_watch` artwork uses a reduced arrow and a blue
four-section disc. This fork's Balanced `Work.ani` is composed during the
Windows build instead of replacing the upstream SVG files:

- The regular `left_ptr.png` is independently scaled exactly like
  `Pointer.cur`; the arrow is not compressed as part of a combined image.
- The six-blade gradient artwork from the repository's `wait-*.png` frames is
  used as a separate foreground layer. No frames are copied from another
  cursor package.
- The composition is visually inspired by the working-in-background style in
  [`antiden/macOS-cursors-for-Windows`](https://github.com/antiden/macOS-cursors-for-Windows),
  while retaining this project's own shapes, gradients, pointer, and shadow.
- At the 32-pixel Balanced size, `Pointer.cur` and every `Work.ani` frame use
  hotspot `(8,4)`.
- The pointer body ends at `x=18`; the visible color wheel occupies
  `x=19...30, y=9...20`. The two elements are adjacent without covering each
  other, and the wheel does not touch the canvas edge.
- The wheel is the foreground layer. This is intentional: do not move it
  behind the pointer, where the arrow would cut into the color disc.
- `Work.ani` has 40 unique frames at 1 jiffy per frame, approximately 0.67
  seconds per revolution.
- `Busy.ani` remains the repository's standalone wait animation at 2 jiffies
  per frame.

### Maintenance invariants

Future changes, including automated changes made by an AI coding agent, should
preserve these decisions unless the fork owner explicitly requests otherwise:

1. Keep the macOS visual style and upstream static SVG artwork intact.
2. Keep Balanced Pointer artwork at 27 pixels on the 32-pixel Windows canvas.
3. Build Work from the same independently scaled pointer used by Pointer.cur.
4. Keep the Work pointer hotspot identical to Pointer.cur.
5. Keep the Work color wheel on the right as a foreground layer, outside the
   opaque pointer body, with no clipping at any rotation angle.
6. Do not replace Work.ani with the ANI file from the reference repository.
7. Keep generated themes independently installable; do not overwrite or
   automatically activate another Windows cursor scheme.
8. Treat `bitmaps/`, `themes/`, and `bin/` as generated output. They are ignored
   by Git and must be rebuilt after a fresh clone.

### Rebuild the recommended theme

Run these commands from the repository root in PowerShell:

```powershell
npx cbmp render.json
powershell -ExecutionPolicy Bypass -File tools/New-CompactWindowsTheme.ps1 -Profile Balanced
```

The result is written to:

```text
themes/macOS-Balanced-Windows
```

Install `themes/macOS-Balanced-Windows/install.inf`, then select
`macOS-Balanced Cursors` in **Control Panel > Mouse > Pointers**. When replacing
an already active build, switch to another scheme and apply it before switching
back; Windows otherwise may continue displaying a cached ANI file.

To rebuild Compact from a non-default source directory:

```powershell
powershell -ExecutionPolicy Bypass -File tools/New-CompactWindowsTheme.ps1 `
  -Profile Compact `
  -SourceDirectory 'D:\path\to\macOS-Regular Cursors'
```

### Publish a GitHub Release

[`release-balanced-windows.yml`](./.github/workflows/release-balanced-windows.yml)
builds and publishes the installable Balanced theme on a Windows GitHub-hosted
runner. The workflow renders from the locked dependencies, builds the theme
twice to check determinism, runs
[`Test-BalancedWindowsTheme.ps1`](./tools/Test-BalancedWindowsTheme.ps1), and
then creates a GitHub Release.

A pushed `v*` tag publishes automatically:

```bash
git tag v2.0.1-balanced.1
git push origin v2.0.1-balanced.1
```

The same workflow can be started from **Actions > Release Balanced Windows >
Run workflow**. Enter a unique `v*` tag and optionally mark it as a prerelease.
A manual run can create the tag at the selected branch commit. Re-running an
existing release replaces its assets.

Each release contains:

- `apple-cursor-balanced-windows-<tag>.zip`, with the cursor files,
  `install.inf`, this README, the license, and build metadata.
- `apple-cursor-balanced-windows-<tag>.zip.sha256`, for archive verification.

Releases appear at
[`alylone/apple_cursor/releases`](https://github.com/alylone/apple_cursor/releases).
The workflow declares `contents: write`. If release creation returns HTTP 403,
check **Settings > Actions > General > Workflow permissions** for repository or
organization restrictions on `GITHUB_TOKEN`.

### Validation snapshot

The archived Balanced build was checked with the following invariants:

| Check | Result |
| --- | --- |
| Static cursor files | 19 |
| ANI files | 2 (`Work.ani`, `Busy.ani`) |
| Native Windows cursor loads | 21/21 passed |
| Work frame count | 40/40, all unique |
| Work canvas and hotspot | 32x32, `(8,4)` |
| Pointer body preservation | 85/85 opaque pointer pixels preserved in every frame |
| Work color-wheel bounds | `x=19...30, y=9...20` in every frame |
| Work frame rate | 1 jiffy per frame |
| Busy frame rate | 2 jiffies per frame |
| Deterministic regeneration | Passed |
| Archived Work.ani SHA-256 | `E9FC00E8189977ABAF72BD8A6511024023767F7A4CD8DCEB1CCE5B54502909AA` |

The SHA-256 value records the build produced in the environment above. A
different rasterizer or dependency version may legitimately change PNG
encoding while preserving the pixel-level design invariants.

## Notes

-   All cursor's SVG files are found in [svg](./svg) directory or you can also find them on [Figma](https://www.figma.com/file/OZw8Ylb9xPFw9h1uZYSMFa/apple_cursor?type=design&node-id=73%3A2&mode=design&t=dLILPgJJrLKeAcTE-1).

<!-- If you're interested, you can learn more about "sponsor-spotlight" on
 https://dev.to/ful1e5/lets-give-recognition-to-those-supporting-our-work-on-github-sponsors-b00 -->

![shoutout-sponsors](https://sponsor-spotlight.vercel.app/sponsor?login=ful1e5)

-   **2024-04-26**: c684a72e967b58d85492fae5fa68040beae47c10 Partitioned cursor build configuration into multiple files according to platform:
    `build.toml` -> `configs/win_lg.build.toml`, `configs/win_rg.build.toml`, `configs/win_xl.build.toml`, `configs/x.build.toml`.
-   **2024-02-23**: 07767c24b0c5dbf912cf37350b86adc11671a18e `bitmaps` directory removed, and `macOS Monterey` cursors deprecated.

---

![macOS](https://github.com/ful1e5/apple_cursor/assets/24286590/07018988-36ee-4913-adc7-365854629a20)
![macOS white](https://github.com/ful1e5/apple_cursor/assets/24286590/1d2bcdf5-d3d7-420a-8dae-68c31b191216)

## Cursor Sizes

### Xcursor Sizes:

<kbd>16</kbd>
<kbd>20</kbd>
<kbd>22</kbd>
<kbd>24</kbd>
<kbd>28</kbd>
<kbd>32</kbd>
<kbd>40</kbd>
<kbd>48</kbd>
<kbd>56</kbd>
<kbd>64</kbd>
<kbd>72</kbd>
<kbd>80</kbd>
<kbd>88</kbd>
<kbd>96</kbd>

### Windows Cursor Size:

| size | Regular (× ²⁄₃) | Large (× ⁴⁄₅) | Extra-Large (× 1) |
| ---: | --------------: | ------------: | ----------------: |
|   32 |     21.333 → 22 |     25.6 → 26 |                32 |
|   48 |              32 |     38.4 → 39 |                48 |
|   64 |     42.666 → 43 |     51.2 → 52 |                64 |
|   96 |              64 |     76.8 → 77 |                96 |
|  128 |     85.333 → 86 |   102.4 → 103 |               128 |
|  256 |   170.666 → 171 |   204.8 → 205 |               256 |

## Colors

### Default

-   Base Color - `#000000` (Black)
-   Outline Color - `#FFFFFF` (White)

### White

-   Base Color - `#FFFFFF` (White)
-   Outline Color - `#000000` (Black)

## How to get it

You can download latest `stable` & `development` releases from
[Release Page](https://github.com/ful1e5/apple_cursor/releases).

### Packages

> **Note**
> If you're having trouble with the packages please submit a request to the package maintainer
> before creating an issue.

#### Arch Linux/Manjaro

Arch Linux/Manjaro users can install from the [AUR](https://aur.archlinux.org/packages/apple_cursor)
currently maintained by [_ful1e5_](https://aur.archlinux.org/account/ful1e5) &
[_Grelek_](https://aur.archlinux.org/account/Grelek) .
Can be installed via Pamac (preinstalled in Manjaro), Paru or any other
[AUR helper](https://wiki.archlinux.org/index.php/AUR_helpers).

```bash
paru -S apple_cursor
```

#### openSUSE Tumbleweed

openSUSE Tumbleweed users can install with `1 CLick Install` on [openSUSE Software](https://software.opensuse.org/package/apple_cursor?search_term=apple_cursor)
or by adding the repository and installing the `apple_cursor` package, maintained by [_astra_](https://build.opensuse.org/users/astra)

```bash
sudo zypper addrepo https://download.opensuse.org/repositories/home:/astra/openSUSE_Tumbleweed home:astra/Tumbleweed
sudo zyper install apple_cursor
```

## Installing Apple Cursor

#### Linux/X11

**Installation:**

```bash
tar -xvf macOS.tar.gz                      # extract `.tar.gz`
mv macOS* ~/.icons/                        # Install to local users
sudo mv macOS* /usr/share/icons/           # Install to all users
```

**Uninstallation:**

```bash
rm ~/.icons/macOS*                         # Remove from local users
sudo rm /usr/share/icons/macOS*            # Remove from all users
```

#### Windows

**Installation:**

1. Unzip `.zip` file
2. Open unziped directory in Explorer, and **right click** on `install.inf`.
3. Click 'Install' from the context menu, and authorize the modifications to your system.
4. Open Control Panel > Personalization and Appearance > Change mouse pointers,
   and select **macOS Cursors**.
5. Click '**Apply**'.

**Uninstallation:**

Run the `uninstall.bat` script packed with the `.zip` archive

**OR** follow these steps:

1. Go to **Registry Editor** by typing the same in the _start search box_.
2. Expand `HKEY_CURRENT_USER` folder and expand `Control Panel` folder.
3. Go to `Cursors` folder and click on `Schemes` folder - all the available custom cursors that are
   installed will be listed here.
4. **Right Click** on the name of cursor file you want to uninstall; for eg.: _macOS Cursors_ and
   click `Delete`.
5. Click '**yes**' when prompted.

## Build From Source

### Prerequisites

-   Python version 3.7 or higher
-   [clickgen](https://github.com/ful1e5/clickgen)>=2.2.2 (`pip install clickgen`)
-   [yarn](https://github.com/yarnpkg/yarn)

### Quick start

1. Install [build prerequisites](#prerequisites) on your system
2. `git clone https://github.com/ful1e5/apple_cursor`
3. `cd apple_cursor`
4. `yarn install`
5. `yarn generate`
6. See [Installing Apple Cursor](#installing-apple-cursor).

### Getting Started

Once you have the [build prerequisites](#prerequisites) installed, You can personalize colors,
customize sizes, change target platforms, and more. This process involves using external tools,
as this repository only contains SVG files and configuration for these tools:

-   [cbmp](https://github.com/ful1e5/cbmp): Used for customizing colors and generating PNG files.
-   [ctgen](https://github.com/ful1e5/clickgen): Used for customizing sizes and building XCursor and Windows Cursors.

You can refer to the README of each tool for more information on their command-line options.

#### Crafting Your Apple Cursor

The process of creating custom cursor themes involves two main steps:

1. Rendering SVG files to PNG files.
2. Building cursor themes from PNG files.

#### Customize Colors

`cbmp` provides three options for changing colors:

1. `-bc`: Base color, which replaces the `#00FF00` color in the SVG.
2. `-oc`: Outlined color, which replaces the `#0000FF` color in the SVG.
3. `-wc` (optional): Watch Background color, which replaces the `#FF0000` color in the SVG.

```bash
npx cbmp [...] -bc '<hex>' -oc '<hex>' -wc '<hex>'
```

Alternatively, you can provide a JSON configuration file to render SVG files, which contains a sequence of `cbmp` commands:

```bash
npx cbmp render.json
```

#### Customize Sizes

##### Customize Windows Cursor size

To build Windows cursor with size `16`:

```bash
ctgen build.toml -s 16 -p windows -d "bitmaps/macOS" -n "macOS" -c "macOS Cursors with size 16"
```

You can also customize output directory with `-o` option:

```bash
ctgen build.toml -s 16 -p windows -d "bitmaps/macOS" -o "out" -n "macOS" -c "macOS Cursors with size 16"
```

##### Customize XCursor size

To build XCursor with size `16`:

```bash
ctgen build.toml -s 16 -p x11 -d "bitmaps/macOS" -n "macOS" -c "macOS XCursors with size 16"
```

You can also assign multiple sizes to `ctgen` for XCursors build:

```bash
ctgen build.toml -s 16 24 32 -p x11 -d "bitmaps/macOS" -n "macOS" -c "Custom Sizes macOS XCursors"
```

#### Examples

Lets generate macOS cursor with green and black colors:

```bash
npx cbmp -d "svg" -o "bitmaps/macOS-Hacker" -bc "#00FE00" -oc "#000000"
```

After rendering custom color you have to build cursor through `ctgen`:

```bash
ctgen build.toml -d "bitmaps/macOS-Hacker" -n "macOS-Hacker" -c "Green and Black macOS cursors."
```

Afterwards, Generated theme can be found in the `themes` directory.

###### macOS Gruvbox

```bash
npx cbmp -d "svg" -o "bitmaps/macOS-Gruvbox" -bc "#282828" -oc "#EBDBB2" -wc "#000000"
ctgen build.toml -d "bitmaps/macOS-Gruvbox" -n "macOS-Gruvbox" -c "Groovy macOS cursors."
```

###### macOS Solarized Dark

```bash
npx cbmp -d "svg" -o "bitmaps/macOS-Solarized-Dark" -bc "#002b36" -oc "#839496" -wc "#000000"
ctgen build.toml -d "bitmaps/macOS-Solarized-Dark" -n "macOS-Solarized-Dark" -c "Solarized Dark macOS cursors."
```

###### macOS Solarized Light

```bash
npx cbmp -d "svg" -o "bitmaps/macOS-Solarized-Light" -bc "#839496" -oc "#002b36"
ctgen build.toml -d "bitmaps/macOS-Solarized-Light" -n "macOS-Solarized-Light" -c "Solarized Light macOS cursors."
```

###### macOS Dracula

```bash
npx cbmp -d "svg" -o "bitmaas/macOS-Dracula" -bc "#282a36" -oc "#f8f8f2"
ctgen build.toml -d "bitmaps/macOS-Dracula" -n "macOS-Dracula" -c "Dracula macOS cursors."
```

## Testing Cursor

There are several websites that allow you to test your cursor states by hovering over buttons. This can be very useful when developing or verifying the behavior of a cursor. The following websites cover many of the most commonly used cursors, although they may not include all available options.

-   [Cursor-Test](https://vibhorjaiswal.github.io/Cursor-Test/)
-   [Mozilla CSS Cursor](https://developer.mozilla.org/en-US/docs/Web/CSS/cursor)

For a blueprint for creating XCursors, you may also want to refer to [Cursor-demo](https://wiki.tcl-lang.org/page/Cursor+demo).

## Credit

[Adwaita](https://github.com/GNOME/adwaita-icon-theme) ·
[Dmz](https://github.com/GalliumOS/dmz-cursor-theme) ·
[Yaru](https://github.com/ubuntu/yaru)
