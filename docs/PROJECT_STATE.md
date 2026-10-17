# Project state

Last updated: 2026-10-17

## Break checkpoint

Development is stopped for a user-requested break at version 0.4.0. Document scanning, multipage sessions, and selectable PDF compression are implemented. The latest build and 35 tests passed; validation details and remaining limitations are below. No additional feature work is underway.

Implementation changes remain local and uncommitted. Before switching computers, obtain approval to commit and push, then pull and rebuild on the other Mac. Save any in-memory document before quitting; app bundles and scan artifacts are not synchronized through Git.

## Objectives and intended architecture

Build a native macOS scanner utility with a SwiftUI interface and separate scanner backends. The real backend invokes SANE's `scanimage` utility; the mock backend supports development without scanner hardware.

Use the MacBook Air for UI development and mock testing, the Mac Studio for real USB scanner integration, and GitHub to synchronize work.

## Current implementation

- Swift 6 package with separate `ScannerCore` library, SwiftUI executable, and core test target. No third-party dependencies.
- Main window discovers SANE devices and offers a scanner picker and Refresh button. Mock Scanner is always the initial selection. Document is implemented; other scan types are visibly unavailable.
- Document starts the selected scanner. Real scans default to A4, color, 300 dpi, 8 bits per RGB channel (24-bit color), with PNG output. Completed pages stay in memory; Scan appends another page without creating a PDF.
- The UI shows Warming up during preparation, then a determinate bar and numeric percentage from SANE's acquisition reports. Unknown percentages are explicitly identified, rather than presented as warm-up. Small stderr updates are delivered immediately instead of waiting for a buffer to fill or the command to finish.
- SANE runs as a direct subprocess without a shell. Both output streams are drained concurrently; cancellation interrupts the child, with termination fallbacks. Discovery/acquisition timeouts are 20/300 seconds. Invalid images and command failures are reported without appending an incomplete page.
- Every page rediscovers the selected scanner's current address, matching model name and SANE backend. A changed address can be retried once if open fails before acquisition/output; partial scans are not automatically repeated. Missing or ambiguous devices leave previous pages available for retry.
- Scanner selection is locked for a document with unsaved pages. The current scanner name is shown in both main and document windows.
- Exit ends the batch and opens a native save dialog with a local date/time filename (`Scanned Document yyyy-MM-dd_HH-mm-ss.pdf`). Successful export creates one A4 PDF containing all pages in scan order and returns to the main window.
- PDF export defaults to Standard JPEG compression (quality 0.75), keeping the original scanned pixel dimensions. Settings offers Standard, High quality (0.9), and Lossless. Preferences are read once at save time; source PNGs and the 300 dpi color acquisition settings are unchanged.
- Scan cancellation preserves earlier completed pages. Save cancellation and export failure preserve the batch for retry. Existing files are never overwritten.
- Window dismissal is disabled during the document session; the app guards termination while scanning, exporting, or holding unsaved pages.
- `scripts/build-app.sh` builds a locally signed app bundle; `scripts/test.sh` runs automated tests. See `README.md` for commands.
- The build script atomically replaces its generated executable so an already running app can keep its mapped binary and in-memory pages until the user saves and relaunches.
- The documentation baseline is committed in the repository; this implementation is uncommitted. `origin/main` is now available locally; remote synchronization was not tested in this milestone.

## Current tasks and known issues

- The user reports the scanner now handles most daily use and supplied a two-page color PDF. The old lossless export made that output 34.8 MB; compressed export is implemented and verified against that reference. Confirm preferred image quality on future physical scans. No agent-operated physical scan has been initiated.
- If an address disappears and more than one scanner with the same model/backend is connected, automatic rebinding is refused. Serial-number-based identity is not implemented.
- Warm-up is inferred until SANE reports acquisition, so it includes setup/calibration and is not an exact measurement of temperature or motor start. Percentages represent acquired image data, not time remaining.
- Real scan options match the connected Canon LiDE 120's previously queried capabilities, including Color mode. Other scanner models may require different options and are unverified. Other scan types and configurable scan settings are not implemented.
- Pages are held in memory only; crash/forced-quit recovery, OCR, page editing, and large-batch disk spooling are not implemented.
- PDF output is portrait A4 with aspect-fit images; additional sizes and orientation controls remain future work.
- Standard and High quality use lossy JPEG; Lossless remains available for exact pixel preservation. File size varies with document content/noise, and matching another scanner utility's size is not guaranteed.
- The native save dialog may offer Replace for an existing file; export deliberately rejects it and asks for another name.
- The macOS deployment target is 14, but execution on macOS 14 and Intel hardware has not been tested.

## Latest validation

- 2026-10-17: `bash scripts/build-app.sh` passed; version 0.4.0 bundle passes `codesign --verify --deep --strict`. Settings UI shows Standard (smaller files) as the default. No physical scan was initiated.
- `bash scripts/test.sh`: 35 tests passed, 0 failures. New tests verify substantial size reduction on a noisy document fixture, actual JPEG streams inside the PDF, unchanged image dimensions, a distinct lossless path, and white backgrounds for transparent images. Existing document/PDF/progress/process/timestamp/reconnection tests also pass.
- Reference measurement with the app's exporter: a supplied two-page PDF went from 34,814,590 bytes to 4,151,044 bytes (88.08% smaller) with Standard. High quality measured 6,095,927 bytes. Reopening confirms two A4 pages with 2480 × 3507 pixels each. Original and compressed pages were rendered with Poppler and visually compared; the source hash is unchanged. A separate compressed copy was created, never replacing the source.
- A new regression test reproduced the delayed progress: a child that waits for acknowledgement of a small stderr update timed out with the old reader. It now completes successfully with immediate pipe reads.
- Hardware discovery: macOS sees a Canon USB scanner; installed SANE 1.4.0 identifies Canon LiDE 120. Read-only `scanimage --help` confirms grayscale, 300 dpi, and A4-compatible geometry. The restricted shell could not discover it; enumeration/capability queries succeeded outside that shell restriction.
- Address diagnosis: two non-scanning discovery calls identify the same Canon at a current address different from the address in the user's second-page error. The old backend reused its original address; the new backend resolves it per page.
- App UI verification: the mock scanner displays an actual numeric percentage with a determinate bar; two pages were accumulated and the native save dialog supplied a timestamped filename. The mock PDF saved successfully. Warm-up and unknown-percentage transitions are covered by automated status tests.
- Previous mock milestone (2026-10-15): two-page acquisition, save cancellation, combined PDF save, and session dismissal guards were manually exercised. PDFKit reopened the exported PDF and verified two A4 pages.
- SwiftPM needs writable module caches and `--disable-sandbox` in this restricted execution environment; the scripts configure these without adding dependencies.
- Hardware: user-reported daily use and two-page scanner output. Compression validation used existing scan images without operating the scanner. Release builds and minimum-OS testing remain unverified.

## Next recommended steps

1. Test the rebuilt app with Canon LiDE 120 selected. Obtain explicit approval before any agent-operated test scan.
2. Compare Standard and High quality output on normal documents, including fine print, and select the preferred size/quality balance in Settings. Continue checking physical multipage scanning, cancellation, and progress; record actual results here.
3. On the other computer, rebuild from the approved synchronized source and use Mock Scanner unless SANE and compatible hardware are available.
4. Consider crash recovery and configurable scan options after the basic real-scanner document flow is validated.
5. Refresh this file before switching computers. Commit and push only with approval.

## Hardware-specific requirements

| Computer | Development requirements |
| --- | --- |
| MacBook Air | macOS 14+ and Xcode with Swift 6 tooling; the mock backend works without SANE or a connected scanner. |
| Mac Studio | Same build requirements; real backend requires SANE with `scanimage`, a compatible SANE backend, and access to the real USB scanner. Canon LiDE 120 is detected with installed SANE 1.4.0 on the current computer. |

Executable discovery checks standard Apple Silicon/Intel Homebrew locations, then PATH. The current SANE installation is managed by Homebrew. Hardware discovery does not establish that physical acquisition works; record that only after an approved test. Keep local device addresses and user paths out of committed documentation.
