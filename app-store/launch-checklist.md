# macOS App Store launch checklist

## Ready in the repository

- [x] Bundle ID is `com.FlyMedia.CaptionPeel`.
- [x] Initial marketing version and build are `1.0.0 (1)`.
- [x] macOS category is Utilities.
- [x] App Sandbox and user-selected read/write file access are enabled.
- [x] Privacy manifest declares no collected data and no tracking.
- [x] Export-compliance setting declares no nonexempt encryption.
- [x] Product-page copy, privacy response, and review notes are prepared in this directory.
- [x] Legacy raster app icons have been removed in favor of the origin-provided Icon Composer package.

## Complete in App Store Connect

- [ ] Create the macOS app record: CaptionPeel, primary language English (U.S.), bundle ID `com.FlyMedia.CaptionPeel`, and a permanent SKU.
- [ ] Confirm the app name is available.
- [ ] Set the paid price tier, availability countries or regions, and tax and banking agreements.
- [ ] Enter the privacy policy URL and publish the **No data collected** App Privacy response from [`privacy.md`](privacy.md).
- [ ] Complete the age-rating questionnaire truthfully; this utility should have no age-gated content, user-generated content, or parental controls.
- [ ] Add the manual screenshots (one to ten PNG or JPEG images) for the macOS `en-US` product page.
- [ ] Enter the App Review contact details and the notes from [`review-notes.md`](review-notes.md).
- [ ] Complete content-rights, advertising, and any region-specific declarations according to the final distribution plan.

## Build, upload, and submit

- [ ] Archive the Release target with App Store distribution signing (not the Developer ID signing path used for the direct-download DMG).
- [ ] Increment `CURRENT_PROJECT_VERSION` before each subsequent upload; App Store Connect uses the bundle ID, marketing version, and build string to identify a build.
- [ ] Upload the archive with Xcode, Transporter, or `xcrun altool`, then wait for processing to finish.
- [ ] Select the processed build for macOS version 1.0.0 and resolve all processing warnings.
- [ ] Add the version to a submission and submit it for review.

## Final release gate

- [ ] Build and test with the Xcode version that successfully compiles the Icon Composer `.icon` asset.
- [ ] Verify the app icon in Finder, Launchpad, and both light and dark appearances.
- [ ] Verify opening, scanning, editing, exporting, cancellation, and sandbox file access on a clean Mac user account.
- [ ] Review the final privacy policy, product-page metadata, screenshots, price, and territories against the shipped build.
