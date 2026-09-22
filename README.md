# CaptionPeel

Turn burned-in video captions into an editable SRT file — entirely on your Mac.

Open or drop a video, draw around its visible subtitles, extract them locally with Apple Vision, review the timed cues, and export a standard UTF-8 `.srt` file.

**GPLv3** · **Native macOS** · **No accounts or uploads**

CaptionPeel is a Fly Media project. It requires macOS 15 or later and runs on Apple silicon and Intel.

## Features

- Native SwiftUI interface and AVFoundation video playback
- Moveable, resizable caption-region selection that stays aligned at any window size
- Local Apple Vision OCR tuned for Latin-script subtitles, including Swiss German characters
- Change-aware sampling with frame-accurate cue boundaries and less unnecessary OCR
- Editable cue text and start/end times
- Seek on selection, delete, merge, and re-read individual cues
- Optional partial-video scan range
- Background extraction with progress and cancellation
- Standard multiline UTF-8 SRT export
- No accounts, cloud APIs, analytics, model downloads, or external runtimes

## Getting CaptionPeel

This repository contains the complete source. You can inspect it, modify it, and build it at no cost.

A paid Mac App Store edition will provide convenient installation and automatic updates while supporting continued Fly Media development. Both editions have the same core functionality.

## Building

CaptionPeel requires Xcode 26 or later.

```sh
open CaptionPeel.xcodeproj
```

Build and run the **CaptionPeel** scheme. The Xcode project is checked in. [`project.yml`](project.yml) is the XcodeGen source of truth when adding or removing files:

```sh
xcodegen generate
```

The app target is configured for Fly Media's Apple Developer team. Contributors without that team membership can select their own team or disable signing for local builds.

## Testing

```sh
swift test
```

Or run the **CaptionPeel** scheme's tests in Xcode with ⌘U.

## How extraction works

CaptionPeel makes one forward `AVAssetReader` pass through the video. A tiny luminance fingerprint is computed from every decoded frame in the selected caption area, while Vision OCR runs only for visual changes and periodic verification. Cue boundaries use the decoded frame’s real presentation timestamp, avoiding both quarter-second blind spots and repeated exact random seeks. Neighboring OCR observations are compared by edit-distance similarity so small recognition variations become one stable cue rather than duplicates.

Vision language correction is deliberately disabled to preserve visible spellings instead of rewriting Swiss German into Standard German. OCR lives behind the small `OCRRecognizing` protocol so another fully local engine can be added without replacing the extraction or interface layers.

## Privacy

Normal operation is fully offline. CaptionPeel reads only video files the user chooses and writes only the SRT destination the user chooses. See the [privacy policy](docs/privacy-policy.md).

## Automated builds and releases

Every push to `main` and every pull request runs tests, builds the complete app target, creates an unsigned DMG, and uploads it as a workflow artifact.

Pushing a `v*.*.*` tag builds a universal app, signs it with Developer ID, notarizes the app and DMG, and publishes a GitHub Release. The release workflow needs these repository secrets:

- `DEVELOPER_ID_P12_BASE64`
- `DEVELOPER_ID_P12_PASSWORD`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY`

To exercise packaging locally without signing or notarization:

```sh
SKIP_NOTARIZE=1 scripts/package-release.sh
```

## Scope

CaptionPeel extracts text already visible in video. It does not transcribe audio, translate subtitles, burn captions into video, or provide a full subtitle-authoring timeline.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Please open an issue before starting anything larger than a small fix.

## Support and security

Use GitHub Issues for ordinary bugs and feature requests. Report security-sensitive problems privately according to [`SECURITY.md`](SECURITY.md).

## License

Copyright © 2026 Fly Media LLC.

CaptionPeel is free software under the [GNU General Public License v3](LICENSE) or later.

Fly Media LLC is the sole copyright holder and may also distribute CaptionPeel through the Mac App Store under Apple's standard terms. Contributions must be licensed to Fly Media LLC under terms that permit App Store redistribution; see [`CONTRIBUTING.md`](CONTRIBUTING.md).
