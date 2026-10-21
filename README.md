<div align="center">
  <img src="docs/orbitdrop-icon.png" alt="OrbitDrop logo" width="118" />

  # OrbitDrop

  **A privacy-first desktop file converter, compressor, and image toolkit for macOS and Windows.**

  Select files in Finder or File Explorer, hold your chosen key, move onto an action, and release. No uploads. No browser detour. No account.

  [**Download OrbitDrop**](https://orbitdropapp.vercel.app/#download) · [Live website](https://orbitdropapp.vercel.app) · [Latest release](https://github.com/sasukefrontenddev/orbitdrop/releases/latest) · [Help](https://orbitdropapp.vercel.app/help)

  [![Native builds](https://github.com/sasukefrontenddev/orbitdrop/actions/workflows/build.yml/badge.svg)](https://github.com/sasukefrontenddev/orbitdrop/actions/workflows/build.yml)
  [![Latest release](https://img.shields.io/github/v/release/sasukefrontenddev/orbitdrop?color=cfff46&label=release)](https://github.com/sasukefrontenddev/orbitdrop/releases/latest)
  [![macOS 13+](https://img.shields.io/badge/macOS-13%2B-8b78ff?logo=apple&logoColor=white)](https://orbitdropapp.vercel.app/requirements)
  [![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-8b78ff?logo=windows11&logoColor=white)](https://orbitdropapp.vercel.app/requirements)
  [![Privacy: local processing](https://img.shields.io/badge/privacy-local%20processing-cfff46?logo=shield&logoColor=111)](PRIVACY.md)
</div>

![OrbitDrop transparent radial command wheel on the desktop](docs/orbitdrop-wheel.png)

## File tools without the upload

Most online file converters ask you to leave your workflow and send a document to somebody else’s server. OrbitDrop brings the tools to the file instead.

- **Desktop-native:** AppKit on macOS and WPF on Windows—not a website wrapped as an app.
- **Private by architecture:** conversions, compression, archives, and image edits run locally.
- **Fast by interaction:** one configurable hold key opens a transparent radial command wheel.
- **Safe by default:** new outputs are written beside the source; originals are not intentionally overwritten.
- **Useful offline:** file actions keep working without an internet connection after installation.
- **Easy to maintain:** verified in-place updates replace the installed copy and can roll back after a failed replacement.

## What OrbitDrop can do

| Convert | Optimize and organize | Edit images |
| --- | --- | --- |
| Documents and images → **PDF** | Create **ZIP** archives | **Resize** to 50% |
| Images → **PNG** | Adaptive **Shrink** | **Rotate** 90° |
| Images → **JPG** | Create a **safe copy** | **Flip** horizontally |
| Images → **TIFF** | Maximum-compression ZIP for documents and folders | Convert to **grayscale** |
| Images → **BMP** | Collision-safe output names | Preserve the source file |

OrbitDrop supports common document inputs such as DOCX, RTF, TXT, and HTML for PDF output, plus the image formats supported by each operating system. Windows uses Microsoft Word for the highest-fidelity DOCX-to-PDF result when Word is available.

## How it works

1. Select one or more files in Finder or File Explorer.
2. Hold your trigger key for about a quarter of a second. **Space** is the default. Choose **Record trigger key** and press the physical key you want—letters, numbers, punctuation, arrows, modifiers, Space, and function keys are supported without a dropdown.
3. Keep holding while you move the pointer onto an action.
4. Release the key to run it, or press Escape to cancel.

The chosen trigger is stored only on the computer. On macOS, the menu must say **Keyboard: ready ✓** before the gesture can work. OrbitDrop performs a harmless local self-test to confirm it can capture and suppress the trigger before Finder receives it; use **Run keyboard self-test…** at any time. Processing and result states appear directly in the wheel.

## Download and install

Use the [official OrbitDrop download page](https://orbitdropapp.vercel.app/#download) for the correct build, current file size, and SHA-256 checksum. Release files are also available directly from [GitHub Releases](https://github.com/sasukefrontenddev/orbitdrop/releases/latest).

### macOS

1. Download and unzip the universal macOS package.
2. Move `OrbitDrop.app` to Applications.
3. Because this early release is not notarized, Control-click OrbitDrop, choose **Open**, and confirm.
4. Grant Accessibility access when macOS asks. OrbitDrop uses it to intercept the configured hold key so Finder does not jump to a filename beginning with that letter. If the menu shows **Keyboard: access required**, choose **Repair Keyboard Access…**, remove any stale OrbitDrop entry, add the copy in Applications, enable it, and reopen OrbitDrop.

Supports macOS 13 Ventura or later on Apple Silicon and Intel Macs.

### Windows

1. Download the Windows x64 executable.
2. Compare its SHA-256 value with the [official checksum directory](https://orbitdropapp.vercel.app/checksums).
3. Because this early release is not Authenticode-signed, SmartScreen may appear. Choose **More info** and **Run anyway** only after the checksum matches.

Supports 64-bit Windows 10 and Windows 11. The executable is self-contained.

## Private, verified updates

OrbitDrop checks the public GitHub release feed shortly after launch and every six hours while running. The request contains no file, filename, account, advertising identifier, or conversion history.

From version 0.6.1 onward, **Install Update** downloads the release to temporary storage, verifies its published SHA-256 checksum and version, replaces the current app, reopens OrbitDrop, and removes the temporary files. A recovery copy restores the previous version if replacement fails.

> Versions older than 0.6.1 need one final manual installation. Future releases then update in place.

Read the complete [privacy promise](PRIVACY.md), [security policy](SECURITY.md), and [release history](https://orbitdropapp.vercel.app/releases).

## Build from source

### macOS

Requirements: macOS 13+, Xcode Command Line Tools, and Swift.

```bash
zsh macos/test.sh
zsh macos/build.sh
```

The universal application is created at `macos/build/OrbitDrop.app`.

### Windows

Requirements: Windows 10/11 and the .NET 8 SDK.

```powershell
powershell -ExecutionPolicy Bypass -File windows/build.ps1
```

The self-contained x64 executable is created under `windows/build/win-x64`.

## Release integrity and automation

Every pull request and change to `main` builds both native apps and runs platform checks. An accepted version change triggers a release pipeline that:

1. validates matching macOS and Windows versions;
2. rebuilds on the native operating systems;
3. generates SHA-256 checksums;
4. publishes build-provenance attestations; and
5. uploads the packages to GitHub Releases.

The [OrbitDrop website](https://github.com/sasukefrontenddev/orbitdrop-website) reads that verified release automatically, so its download buttons, version, file sizes, and checksum page stay current.

## Contributing and support

- Found a bug? [Open an issue](https://github.com/sasukefrontenddev/orbitdrop/issues) with the operating system, file type, and steps to reproduce it.
- Have a focused improvement? Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Found a vulnerability? Follow [SECURITY.md](SECURITY.md) and use private vulnerability reporting when available.
- Want to help others discover private desktop tools? Star the repository and share the [official website](https://orbitdropapp.vercel.app).

## License

OrbitDrop is source-available for inspection, security review, education, and portfolio evaluation. It is **not an open-source license**: copying, modification, redistribution, sublicensing, sale, and derivative works require prior written permission. See [LICENSE](LICENSE).

<div align="center">
  <strong>Your files stay on your computer.</strong><br />
  <sub>Built for macOS and Windows · No uploads · No tracking · No account</sub>
</div>
