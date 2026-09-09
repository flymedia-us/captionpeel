# Contributing to CaptionPeel

Thanks for your interest in CaptionPeel. Bug reports, representative footage descriptions, reproducible OCR failures, and pull requests are welcome.

## Before you start

- Open an issue first for anything larger than a small fix so the approach and product scope can be agreed on.
- Keep CaptionPeel focused on extracting visible subtitles. Speech transcription, translation, cloud processing, and full subtitle authoring are intentionally out of scope.
- Keep OCR behind `OCRRecognizing`; extraction timing should not depend directly on a particular OCR engine.
- New behavior needs test coverage. Run `swift test` and an unsigned Release app build before submitting.
- The project builds with Swift 6 strict concurrency. Please keep the app warning-free.
- Do not add accounts, analytics, remote APIs, downloaded models, or external runtime requirements.

## Developer Certificate of Origin and license grant

CaptionPeel is distributed as GPLv3 source and may also be distributed as a paid binary on the Mac App Store. To keep both channels legally available, Fly Media LLC must be able to relicense every contribution.

By submitting a pull request, you agree that:

1. You certify the contribution is your original work, or that you have the right to submit it under these terms, under the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
2. You grant Fly Media LLC a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, reproduce, modify, publicly display, sublicense, and distribute your contribution under any license terms, including GPLv3 and proprietary App Store terms.
3. You retain copyright in your contribution.

Record that agreement with a sign-off:

```sh
git commit -s -m "Describe the change"
```

If you prefer not to grant that license, open an issue describing the requested change instead.

## Third-party material

Do not commit copyrighted video samples, subtitle tracks, screenshots, fonts, models, or other third-party assets unless their redistribution terms are documented and compatible with this repository.
