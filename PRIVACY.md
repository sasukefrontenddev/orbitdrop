# Privacy

OrbitDrop is designed so private files never need to leave the user's computer.

## Desktop application

- Files are converted, compressed, archived, copied, and edited locally.
- There is no file-upload service or cloud conversion backend.
- The app makes a small, anonymous request to the official GitHub Releases API at startup and every six hours while running to learn whether a newer version exists. It sends no files, filenames, analytics identifiers, or account data. Core file tools continue to work offline if the request fails.
- There are no accounts, advertising identifiers, analytics SDKs, or telemetry events.
- OrbitDrop does not sell, rent, profile, or share user data.
- Original files are not overwritten; outputs are created beside them.

## Platform permissions

On macOS, Accessibility permission is required to recognize the Finder right-click gesture. OrbitDrop also reads the paths of files currently selected in Finder so it can perform the requested local action. On Windows, the app reads the current File Explorer selection for the same purpose.

These permissions are used only on the device and do not transmit file contents or file names to an OrbitDrop service.

## Website

The separate [OrbitDrop website](https://github.com/sasukefrontenddev/orbitdrop-website) provides downloads and documentation. It does not include accounts, analytics, cookies, tracking pixels, or an upload feature.
