# Scanner Utility

A native macOS SwiftUI scanner utility with SANE USB scanning and a mock scanner for development without hardware.

## Run

Requires macOS 14 or later and Xcode with Swift 6 tooling selected via `xcode-select`.

```sh
bash scripts/build-app.sh
open ".build/Scanner Utility.app"
```

You can also open `Package.swift` in Xcode and run the `ScannerUtility` executable scheme. No third-party packages are required.

## Document workflow

1. Select your scanner in **Product name**. Click **Refresh** after connecting a scanner. **Mock Scanner** remains available without hardware.
2. Put a document on the glass and close the lid. Choose **Document** to start scanning. **Warming up…** appears during preparation; when SANE reports acquisition, a percentage and determinate progress bar appear. If a device reports acquisition without a percentage, the app explicitly says progress is unavailable.
3. Choose **Scan** after each page to append another page to the same session. The app rediscovers the selected scanner's current USB address before every page. This starts another physical scan when a real scanner is selected, without generating a PDF.
4. Choose **Exit** to finish the session, select a new PDF filename, and save all pages in order as one PDF. The suggested name includes the local save date/time, for example `Scanned Document 2026-10-17_00-22-04.pdf`. Exit ends the batch; the app stays open.

Canceling a scan keeps earlier completed pages. Canceling the save dialog or encountering an export error keeps the session available for another attempt. Existing files are not overwritten. Unsaved pages are held in memory for this running session; recovery after a crash or forced quit is not implemented.

Other scan types are displayed but unavailable. Real scans default to A4, color, 300 dpi, 8 bits per RGB channel (24-bit color). These defaults follow the user's request; the [Canon specifications](https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/su-020.html) confirm A4 and 24-bit color support. The user reports the workflow now covers most daily use and supplied a two-page color PDF for export validation. Agent-run tests use mock commands or existing images; no physical scan is started without approval.

Warm-up covers device setup/calibration until the first acquisition report; `scanimage` does not provide a separate motor-start or temperature signal. Percentages measure image data received, not elapsed time. A 100% reading can be followed by a short finishing step before the completed-page actions appear.

## PDF file size

Choose **Settings → PDF quality**:

| Setting | Output |
| --- | --- |
| Standard (smaller files) | Default; JPEG-compressed page images with slight image quality loss. |
| High quality | Less JPEG compression, preserving more fine detail with larger files. |
| Lossless (large files) | Preserves the original image pixels; scanned color documents can be very large. |

All modes keep the scanned pixel dimensions, A4 page size, and color. Scanning remains at 300 dpi; PDF export does not downsample. Original PNG scans stay in the session until a new document starts, and the chosen compression is read when saving. Nothing is converted or written between page scans.

A two-page reference scan measured 34.8 MB with the old lossless output and 4.15 MB with Standard (88% smaller), with the same 2480 × 3507 pixels per page. Actual sizes depend on page content and scanner noise. JPEG is lossy, so compare fine print before choosing a setting for sensitive detail. Existing PDFs are never automatically rewritten.

Private exports and validation files under `output/` and `tmp/pdfs/` are ignored by Git.

## Real scanner requirements

Install SANE's `scanimage` utility and a SANE backend supporting your scanner on the computer connected to the USB device. The app searches standard Apple Silicon/Intel Homebrew locations and the launch environment's PATH. SANE 1.4.0 is already installed on the currently tested computer; no installation was performed by this project.

Device discovery does not scan a page. Selecting a real scanner also does not scan; **Document**, **Scan**, and **Try Again** do. The initial selection on launch is always Mock Scanner. Do not use automated hardware scan commands without explicit user approval.

If discovery fails, check the USB connection and close other scanner applications, then click Refresh. Command failures retain earlier pages for retry. Discovery times out after 20 seconds and acquisition after five minutes. Other scanner models may require different scan options and have not been validated.

SANE USB addresses can change between scans. The app matches the selected model and backend to its freshly discovered address. If the original address is gone and multiple matching scanners are connected, it asks you to disconnect the extras instead of guessing. An open failure can be retried once after an address change, only when no acquisition or image output has occurred; partial scans are never automatically repeated.

After rebuilding, save any open document with Exit, then quit and reopen the app to load the update. Rebuilding replaces the generated executable atomically so an already running app can keep its existing session until you finish it.

## Structure and tests

- `Sources/ScannerUtility`: SwiftUI views, native save dialog, and app lifecycle.
- `Sources/ScannerCore`: mock/SANE backends, subprocess lifecycle, document session, and PDF export.
- `Tests/ScannerCoreTests`: document workflow, cancellation, PDF validation, and hardware-independent SANE command tests.

```sh
bash scripts/test.sh
```

Read `AGENTS.md`, `docs/PROJECT_STATE.md`, and `docs/DECISIONS.md` before development or switching computers.

## Resume or switch computers

The current checkpoint is version 0.4.0; see [project state](docs/PROJECT_STATE.md) for completed work, validation, and remaining tasks.

Save any open document with **Exit** before quitting. Source changes must be committed and pushed with user approval before they can be pulled on the other Mac; the current implementation is still uncommitted. Rebuild using the Run commands above on each computer, since the generated app bundle is not stored in Git. Use Mock Scanner on the MacBook Air and select the real scanner on the Mac Studio when ready to scan.
