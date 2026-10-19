# Project state

Last updated: 2026-10-19

## Current checkpoint

Version 0.7.0 implements all six on-screen scan modes and General Settings using native macOS frameworks and SANE. The latest layout places General and all scan modes in one persistent left sidebar, with a fixed page header and action buttons on the right. General controls are grouped into Scanner, Text Recognition, and Outgoing Images. The optimized release build passed all 103 tests on Apple silicon/macOS 15.8. Final interactive UI and additional hardware checks remain pending. No agent-operated physical scans were initiated.

The current distribution path is the public [GitHub repository](https://github.com/neilxu-blip/scanner_utility) and [v0.7.0 preview release](https://github.com/neilxu-blip/scanner_utility/releases/tag/v0.7.0). The user authorized source, documentation, and a downloadable app. The download is an arm64 ZIP plus SHA-256 checksum, targeting macOS 14+. It is ad-hoc signed, not Developer ID signed or Apple-notarized, and requires separately installed SANE for real scans. README is the user manual; this file owns build/test and handoff instructions. Save any open session before quitting; binaries are release attachments rather than files stored in Git.

All implemented features remain available without purchases. StoreKit, a Pro feature split, pricing, App Store signing/sandbox configuration, and self-contained SANE packaging have not been implemented or finalized. App Store work is deferred while the current GitHub version is shared and tested. No Intel binary or notarized installer is provided. A project license has not been selected; do not describe the repository as permissively licensed or add license terms without a decision.

## Objectives and architecture

Native SwiftUI macOS scanner utility, targeting macOS 14+ with Swift 6. `ScannerCore` separates acquisition, session state, image processing, OCR, stitching, and export from the app UI. Real acquisition uses installed SANE `scanimage`; Mock Scanner supports hardware-independent development. No third-party packages or Docker.

MacBook Air: UI/mock development. Mac Studio: real USB/SANE integration. GitHub synchronizes approved source changes.

## Implemented workflows

| Mode | Behavior |
| --- | --- |
| Auto | One acquisition using the profile's scan area/resolution, then local text detection chooses PDF or JPEG. Users can override the output choice. |
| Document | Default A4/Color/300 dpi. Scan adds pages; Exit saves one combined PDF by default. |
| Photo | Default 4 × 6 inches/Color/600 dpi/JPEG; also supports PNG/TIFF or configured PDF output. |
| Custom | Independent source, color, paper/custom dimensions, resolution, corrections, and output settings. |
| Stitch | Two user-triggered acquisitions; adjustable direction and overlap; blended join and expanded PDF/image canvas. Retake/discard remain available if joining fails. |
| Advanced | Native SANE setup before acquisition, including custom dimensions and local brightness/contrast/gamma adjustments. Replaces the on-screen workflow, not Canon's proprietary ScanGear driver. |

- Real scanners are preferred on launch/Refresh. Without one, Product name and scan buttons are disabled. View → Debug Mode exposes Mock Scanner, starts off each launch, and never displaces a valid real selection unless chosen explicitly.
- Separate persisted profiles for all six modes. Existing Document/PDF preferences migrate. Settings edits remain drafts until OK; Defaults resets only the selected profile/General draft; Cancel/close discards edits. General Product selection is shared immediately with the main window and locked during sessions.
- General Settings: selected scanner, OCR language, outgoing image size (original/640/800/1024 pixel limit), and temporary outgoing-copy folder.
- Native corrections: crop, enhancement, sharpening, show-through/moiré/broad gutter-shadow reduction, deskew, orientation, black-and-white threshold, brightness/contrast/gamma. Geometry changes require confident detection; scan originals are not silently downsampled.
- PDF/JPEG/PNG/TIFF export; PDF supports Standard/High quality/Lossless and optional searchable text from local Vision OCR. Analysis may use smaller images; output retains acquisition pixel detail apart from chosen corrections/compression.
- Optional review rotates, reorders, or removes in-memory pages after confirmation. Discard requires confirmation and does not delete saved files. Acquisition options stay fixed for a session; save preferences are captured per save attempt.
- Timestamped names, destination/date subfolders, native save confirmation, exclusive writes, and retention of pages after canceled/failed saves. Post-save actions: Preview, Finder, another chosen app, additional folder copy, email draft, or OCR text sidecar. Email is never sent automatically; outgoing resizing never alters the saved original.
- SANE discovery per page resolves changing USB addresses. Retry only after a failed open with no acquisition/output and a changed address. Ambiguous/missing devices retain earlier pages. Concurrent pipe draining, live SANE percentages, warm-up status, timeouts, cancellation, and incomplete-image checks remain.
- Build script atomically replaces the generated executable; finish and save a running session before quitting/relaunching the update.
- Each page uses a new `scanimage` process after discovery. No resident helper, persistent SANE connection, launch-at-login component, or physical-button monitor is implemented. Startup/preparation timings have not been benchmarked.

## Latest validation

- Downloadable preview (2026-10-19): `bash scripts/build-app.sh release` passed. `swift test --configuration release` with the test script's cache/sandbox flags and normal macOS graphics access: **103 passed, 0 failures** on arm64/macOS 15.8. No application feature code changed during release preparation.
- `bash scripts/package-release.sh` passed: optimized build, debug-map stripping, renewed ad-hoc signature, ZIP integrity, extracted-app signature verification, executable byte comparison, and SHA-256 verification. Archive inventory contains only the app bundle; no `/Users/` or temporary home-directory paths remain in its executable. Mach-O metadata confirms arm64 and minimum macOS 14; linked libraries are system libraries, with SANE invoked separately. This does not verify clean-Mac/Gatekeeper launch, macOS 14 runtime behavior, or new physical scanner combinations.
- GitHub publication check (2026-10-19): the existing repository is public and its `main` matched local `e8933a9` before this documentation update. All 50 tracked files were reviewed by filename; no scan/build archives or common private-key/token patterns were found. `.build/`, `output/`, and `tmp/pdfs/` remain ignored. These are limited publication checks, not a comprehensive security audit. No physical scans or application code changes were made.
- Latest documentation pass: checked the manual against the current views, preference defaults, save flow, and exporters. All four Markdown files passed local link/heading and code-fence checks (15 local links), and `git diff --check` passed. No application code changed during this pass, so builds/tests were not rerun; the results below are from the preceding implementation work.
- Settings sidebar update: `swift test` with the same cache/sandbox flags as `scripts/test.sh` and `--filter 'DocumentSettingsTests|ScanProfileSettingsTests'`: **14 passed, 0 failures**. Existing tests cover preference drafts, defaults, independent profiles, migration, and General persistence. These are model tests, not interactive navigation tests. `git diff --check` also passed.
- Previous full workflow validation: `bash scripts/test.sh` with normal macOS graphics/text-recognition access: **103 passed, 0 failures**. Covers all earlier behavior plus mode/profile migration, image formats and overwrite protection, custom/stitched PDF geometry, joining/order/seams/cancellation, outgoing copies, review/discard/export retry, local OCR/searchable PDF appearance, corrections, four text orientations, and selected Chinese recognition. The full graphics/OCR suite was not rerun for this layout-only update.
- A restricted-shell run could not use CoreImage/Vision services and failed graphics/OCR tests. The normal-access run above validates those same paths. The orientation test also exposed a real scoring issue, fixed and covered by regressions before the final successful suite.
- `bash scripts/build-app.sh`: version 0.7.0 app bundle rebuilt with the new Settings layout and passes `codesign --verify --deep --strict`.
- Native UI: the latest inspection attempt failed with “native pipe closed before response,” so the sidebar layout/navigation needs manual visual checking. Earlier inspection showed all six main-window scan modes disabled with no scanner connected; opening Settings crashed SkyComputerUseService (`Array.remove(at:)`), with no Scanner Utility crash observed. Modal scanning/review, save dialogs, and follow-up apps still need manual testing.
- Earlier hardware evidence: user-reported Canon LiDE 120 daily use and two-page output. Earlier compression benchmark: 34.8 MB to 4.15 MB (88% smaller), original untouched. New modes/options have not been physically validated.

## Known limits and next steps

1. Manually exercise all modes with Mock Scanner, including the new sidebar, switching between edited profiles and General, OK/Cancel/close/Defaults, save cancellation, page editing, Stitch retake/overlap, and post-save actions. Restore native UI automation before claiming visual verification.
2. With user approval for any agent-operated acquisition, validate new options/modes against Canon LiDE 120 on the Mac Studio. Other scanners and capability negotiation remain unverified.
3. Auto uses text-density heuristics; sparse text/handwriting can be misclassified. Review the PDF/JPEG choice or use an explicit mode. Corrections are native approximations, not Canon algorithms; gutter reduction is illumination correction, not book dewarping. Stitching uses manual alignment, not automatic feature registration.
4. Sessions remain in memory; crash recovery and disk spooling are absent. Acquisition is capped at 128 MiB and 80 million pixels; stitched bitmap working data is capped at 256 MiB. Some high-resolution combinations are rejected before scanning. No 4 GB/large-image ScanGear equivalent.
5. Physical scanner-button triggering was explicitly excluded from this update. Canon ScanGear and Windows-only integrations are not bundled. Native email actions open drafts only; configured temporary outgoing copies are retained and are not automatically purged.
6. The release build and ZIP are validated; clean-Mac/Gatekeeper launch, minimum macOS 14 execution, Intel execution, and Developer ID signing/notarization remain unverified. For a future App Store build, first evaluate SANE redistribution licenses, sandboxed USB access, persistent folder permissions, and self-contained packaging; purchases come after that feasibility work. Refresh this file before switching computers; commit/push requires approval.
7. Settings wording currently overstates saving behavior: “Check scan results” only toggles page-editing controls, and `DocumentView.chooseDestination()` always opens a save dialog. The explanatory text also implies image batches, while JPEG/PNG/TIFF workflows currently save one image per session. The manual documents actual behavior; aligning the UI wording is pending.

## Performance and button proposals

The user asked whether physical buttons can be supported and whether a resident helper would improve speed. Neither proposal has been approved for implementation. Before choosing a new backend design, measure device discovery, preparation, acquisition, and processing separately during an approved hardware test. A helper that only launches the existing commands would retain repeated setup; a connection kept open during a session might reduce it, but no speed improvement is established. Background button support would need separate hardware validation and lifecycle design. Direct SANE integration and an always-running helper remain undecided, not rejected.

## Build and test

Use macOS 14+ and Xcode with Swift 6 tooling selected through `xcode-select`. From the repository root:

```sh
bash scripts/build-app.sh
open ".build/Scanner Utility.app"
```

Alternatively, open `Package.swift` in Xcode and run the `ScannerUtility` executable scheme. `bash scripts/build-app.sh release` produces the validated optimized build. The script signs the local app ad hoc; Developer ID signing and notarization are not configured.

To build and package a download without uploading it:

```sh
bash scripts/package-release.sh
```

This writes a version/architecture-named ZIP and `.sha256` file under `.build/releases/<version>-<architecture>/`, retaining ignored staging/verification copies. It strips debug-map records from the distribution copy, renews its ad-hoc signature, and verifies an extracted copy. Existing release archives are never replaced. SANE and user data are excluded. Upload only the ZIP/checksum as GitHub Release assets after checks pass, targeting the corresponding source commit; the initial `v0.7.0` is a prerelease.

```sh
bash scripts/test.sh
codesign --verify --deep --strict ".build/Scanner Utility.app"
git diff --check
```

Tests use mock/synthetic inputs and do not initiate physical scans. CoreImage/Vision tests need ordinary macOS graphics/service access. The scripts use project-local caches and disable SwiftPM's nested sandbox.

The generated app bundle is updated in place, so Finder may show an older modification date for its outer folder while the executable inside is current. A running copy keeps its old executable until relaunched. Save the current session, quit, and reopen after building.

## Development handoff

- `Sources/ScannerCore`: acquisition, session state, image processing, OCR, stitching, and export.
- `Sources/ScannerUtility`: SwiftUI, preferences, workflow coordination, native dialogs, and post-save actions.
- `Tests`: hardware-independent process, session, preferences, image, and export checks.
- Generated `.build/` and private artifacts under `output/` and `tmp/pdfs/` are ignored. Keep personal scans and local machine paths out of commits.

Before switching computers, save/finish sessions, update this file with actual validation and open issues, and obtain approval before committing or pushing. On the other computer, pull approved changes and rebuild locally. App bundles and local preferences are not synchronized through GitHub; check profiles and folder choices on each Mac.

## Hardware requirements

| Computer | Requirements |
| --- | --- |
| MacBook Air | macOS 14+, Xcode with Swift 6; enable Debug Mode for Mock Scanner. No SANE/hardware needed for mock acquisition. |
| Mac Studio | Same build requirements; installed `scanimage`, compatible SANE backend, and USB access for real scanning. Prior integration used SANE 1.4.0 and Canon LiDE 120. |

Executable discovery checks standard Apple Silicon/Intel Homebrew locations, then PATH. Hardware discovery never acquires a page. CoreImage/Vision tests need ordinary macOS graphics/service access; the scripts configure writable SwiftPM caches and disable the nested package sandbox. Keep machine-specific paths, addresses, and private artifacts out of Git.
