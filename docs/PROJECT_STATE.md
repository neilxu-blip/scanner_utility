# Project state

Last updated: 2026-10-17

## Current checkpoint

Version 0.7.0 implements all six on-screen scan modes and General Settings using native macOS frameworks and SANE. The latest layout update places General and all scan modes in one persistent left sidebar, with a fixed page header and action buttons on the right. General controls are grouped into Scanner, Text Recognition, and Outgoing Images. The app rebuild and 14 settings/profile tests passed; final visual checks remain pending because native UI inspection is unavailable. No agent-operated physical scans were initiated.

The Settings layout changes remain local and uncommitted on top of the existing committed workflows. No commit, push, fetch, or remote synchronization was performed for this update. Before switching computers, obtain approval to commit/push, then pull and rebuild on the other Mac. Save any open session before quitting; app bundles and scan artifacts are not stored in Git.

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

## Latest validation

- Settings sidebar update: `swift test` with the same cache/sandbox flags as `scripts/test.sh` and `--filter 'DocumentSettingsTests|ScanProfileSettingsTests'`: **14 passed, 0 failures**. Existing tests cover preference drafts, defaults, independent profiles, migration, and General persistence. These are model tests, not interactive navigation tests. `git diff --check` also passed.
- Previous full workflow validation: `bash scripts/test.sh` with normal macOS graphics/text-recognition access: **103 passed, 0 failures**. Covers all earlier behavior plus mode/profile migration, image formats and overwrite protection, custom/stitched PDF geometry, joining/order/seams/cancellation, outgoing copies, review/discard/export retry, local OCR/searchable PDF appearance, corrections, four text orientations, and selected Chinese recognition. The full graphics/OCR suite was not rerun for this layout-only update.
- A restricted-shell run could not use CoreImage/Vision services and failed graphics/OCR tests. The normal-access run above validates those same paths. The orientation test also exposed a real scoring issue, fixed and covered by regressions before the final successful suite.
- `bash scripts/build-app.sh`: version 0.7.0 app bundle rebuilt with the new Settings layout and passes `codesign --verify --deep --strict`.
- Native UI: the latest inspection attempt failed with “native pipe closed before response,” so the sidebar layout/navigation needs manual visual checking. Earlier inspection showed all six main-window scan modes disabled with no scanner connected; opening Settings crashed SkyComputerUseService (`Array.remove(at:)`), with no Scanner Utility crash observed. Modal scanning/review, save dialogs, and follow-up apps still need manual testing.
- Earlier hardware evidence: user-reported Canon LiDE 120 daily use and two-page output. Earlier compression benchmark: 34.8 MB to 4.15 MB (88% smaller), original untouched. New modes/options have not been physically validated.

## Known limits and next steps

1. Manually exercise all modes with Mock Scanner, including Settings/General navigation, save cancellation, page editing, Stitch retake/overlap, and post-save actions. Restore native UI automation before claiming visual verification.
2. With user approval for any agent-operated acquisition, validate new options/modes against Canon LiDE 120 on the Mac Studio. Other scanners and capability negotiation remain unverified.
3. Auto uses text-density heuristics; sparse text/handwriting can be misclassified. Review the PDF/JPEG choice or use an explicit mode. Corrections are native approximations, not Canon algorithms; gutter reduction is illumination correction, not book dewarping. Stitching uses manual alignment, not automatic feature registration.
4. Sessions remain in memory; crash recovery and disk spooling are absent. Acquisition is capped at 128 MiB and 80 million pixels; stitched bitmap working data is capped at 256 MiB. Some high-resolution combinations are rejected before scanning. No 4 GB/large-image ScanGear equivalent.
5. Physical scanner-button triggering was explicitly excluded from this update. Canon ScanGear and Windows-only integrations are not bundled. Native email actions open drafts only; configured temporary outgoing copies are retained and are not automatically purged.
6. Minimum macOS 14 and Intel execution, distribution/notarization, and release-build validation remain unverified. Refresh this file before switching computers; commit/push requires approval.

## Hardware requirements

| Computer | Requirements |
| --- | --- |
| MacBook Air | macOS 14+, Xcode with Swift 6; enable Debug Mode for Mock Scanner. No SANE/hardware needed for mock acquisition. |
| Mac Studio | Same build requirements; installed `scanimage`, compatible SANE backend, and USB access for real scanning. Prior integration used SANE 1.4.0 and Canon LiDE 120. |

Executable discovery checks standard Apple Silicon/Intel Homebrew locations, then PATH. Hardware discovery never acquires a page. CoreImage/Vision tests need ordinary macOS graphics/service access; the scripts configure writable SwiftPM caches and disable the nested package sandbox. Keep machine-specific paths, addresses, and private artifacts out of Git.
