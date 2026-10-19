# Contributing

Thanks for helping improve OrbitDrop.

1. Open an issue describing the bug or proposed change.
2. Keep changes focused on native desktop behavior and local processing.
3. Do not add analytics, telemetry, cloud conversion, or upload dependencies.
4. Add or update tests when file-operation behavior changes.
5. Run the relevant platform build before opening a pull request.

macOS changes should pass `zsh macos/test.sh` and `zsh macos/build.sh`. Windows changes should publish successfully through `windows/build.ps1`.

Do not include private files, credentials, generated build directories, or signed distribution secrets in commits.
