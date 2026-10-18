# Scanner Utility

A native macOS SwiftUI scanner utility using SANE, with a mock scanner for development without hardware. Requires macOS 14+ and Xcode with Swift 6 tooling selected via `xcode-select`.

## Build and run

```sh
bash scripts/build-app.sh
open ".build/Scanner Utility.app"
```

You can also open `Package.swift` in Xcode and run the `ScannerUtility` executable scheme. No third-party packages are required. After rebuilding, save any open session, quit, and reopen the app to load the update.

## Scan modes

The app selects a detected real scanner in **Product name**. Click **Refresh** after connecting a scanner. Without one, Product name and all scan buttons are disabled. For hardware-independent testing, enable **View → Debug Mode**, then select **Mock Scanner**. Debug Mode starts off each launch; real scanners remain preferred on discovery/Refresh.

| Mode | Workflow |
| --- | --- |
| Auto | Scan once, detect text locally, and suggest PDF for documents or JPEG for photos. Review or override the choice before saving. |
| Document | Scan the first page, use **Scan** for each additional page, then **Exit** to save one combined PDF. Defaults: A4, Color, 300 dpi. |
| Photo | Scan one photo and save JPEG, PNG, TIFF, or the configured PDF. Defaults: 4 × 6 inches, Color, 600 dpi, JPEG. |
| Custom | Use your own source, scan options, corrections, and output format. PDF supports multiple pages; image formats save one image. |
| Stitch | Scan two overlapping halves, select left-to-right or top-to-bottom, adjust overlap, inspect the join, then save one image or PDF. |
| Advanced | Adjust native SANE acquisition and local brightness/contrast/gamma before choosing Scan. This is the native alternative to the Windows ScanGear workflow. |

**Document**, other scan-mode buttons, **Scan**, **Scan second half**, and **Try Again** operate the selected real scanner. Advanced first opens a setup dialog. Discovery, Refresh, and scanner selection do not scan. Automated physical scans require explicit approval.

Warm-up includes device setup/calibration until SANE reports acquisition. Numeric progress measures received image data, not time remaining. A 100% reading may be followed by image processing. Canceling acquisition keeps earlier completed pages; save cancellation/failure retains scans for retry. Review can rotate/reorder pages or remove an unsaved page after confirmation. Discarding a session also requires confirmation; saved files are never deleted.

Stitching needs matching scan dimensions and carefully aligned overlapping content. It blends a manually chosen overlap; it does not automatically register features. Retake the second half or discard/restart if a join cannot be produced. Auto uses local text-density heuristics, so sparse text and handwriting may be classified as photos; choose PDF manually or use Document when needed.

## Settings

The settings layout follows [Canon's settings index](https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/Su-PAGE3.html), adapted to macOS. Each of the six modes has an independent profile.

- **Scan Options:** source, color/grayscale/black-and-white, common photo/paper sizes or custom dimensions, and resolution. Optional native crop, enhancement, sharpening, show-through/moiré/gutter-shadow reduction, deskew, orientation, and tone adjustments apply after acquisition. Magazine recommends moiré reduction. All pages keep the acquisition options captured when the session starts.
- **Save Settings:** PDF/JPEG/PNG/TIFF or automatic PDF/JPEG choice, timestamped filename prefix, destination, optional `yyyy_MM_dd` subfolder, PDF compression, JPEG quality, searchable PDF, and review controls. The native save dialog confirms the name and folder; date folders are created only after approval. Existing files are never overwritten.
- **Application Settings:** do nothing, Preview, Finder, a chosen app, an additional folder copy, an email draft, or a recognized-text sidecar. These run after successful saving. An email draft is never sent automatically, and failure of a follow-up action does not invalidate the saved file.
- **General Settings:** the same scanner selection as the main window, OCR language, outgoing image size (original or maximum 640/800/1024 pixels), and temporary outgoing-copy folder. Resizing affects only copies sent to apps/email; saved originals and PDFs are unchanged. Temporary copies are retained, not automatically deleted.

**OK** persists profile and General drafts locally. **Cancel** or closing Settings discards preference edits. **Defaults** resets only the selected draft. General Product selection changes the shared scanner immediately and is locked during a scan session. Existing Document/PDF preferences migrate.

OCR runs locally through Apple Vision and can add invisible searchable text to PDFs. Smaller analysis images are used for detection; saved image detail is not silently downsampled. Native corrections approximate the requested effects and can change appearance. Low-confidence crop/orientation detection preserves geometry; gutter correction reduces broad shading rather than dewarping book pages.

## PDF size and data safety

Choose **Settings → [scan mode] → Save Settings → PDF compression**:

| Setting | Output |
| --- | --- |
| Standard (smaller files) | Default JPEG-compressed PDF images, with slight quality loss. |
| High quality | Less JPEG compression, more detail, larger files. |
| Lossless (large files) | Original image pixels apart from selected processing; color scans can be large. |

An earlier two-page reference measured 34.8 MB losslessly versus 4.15 MB with Standard (88% smaller), preserving 2480 × 3507 pixels per page. Sizes depend on content/noise. Compression and searchable text are captured once per export. No PDF is written between Document page scans, and existing PDFs are never automatically rewritten.

Pages remain in memory until the session finishes; crash/forced-quit recovery and disk spooling are not implemented. Acquisition is limited to 128 MiB and 80 million pixels; stitch working bitmaps to 256 MiB. Large/high-resolution combinations can be rejected before scanning. This version does not implement Canon's large-image driver mode or physical scanner-button triggering.

## Real scanner setup

Install SANE's `scanimage` and a backend supporting your USB scanner. The app checks standard Apple Silicon/Intel Homebrew locations, then PATH. Prior hardware validation used SANE 1.4.0 and Canon LiDE 120. Scanner-specific capability negotiation is not implemented; unsupported options report an error while retaining earlier pages.

SANE USB addresses can change between pages. The app refreshes the selected model/backend address before acquisition. It refuses ambiguous replacements and automatically retries a changed address only after an open failure before any acquisition/output. Discovery times out after 20 seconds; acquisition after five minutes. Check USB connections and close other scanner apps if discovery fails.

## Development and tests

```sh
bash scripts/test.sh
```

OCR/CoreImage tests need ordinary macOS graphics/service access. Restricted execution environments may block those services; see [project state](docs/PROJECT_STATE.md) for actual results and remaining manual checks.

- `Sources/ScannerUtility`: SwiftUI, preferences, workflow/save coordination, native dialogs and app actions.
- `Sources/ScannerCore`: mock/SANE backends, image/OCR processing, stitching, session state, and native PDF/image export.
- `Tests`: hardware-independent process, session, image, OCR, persistence, and export tests.

Private artifacts under `output/` and `tmp/pdfs/`, and generated `.build/` files, are ignored by Git. Current version: **0.7.0**. Read `AGENTS.md`, [project state](docs/PROJECT_STATE.md), and [decisions](docs/DECISIONS.md) before development or switching computers. Commit/push requires approval; pull approved source and rebuild separately on each Mac.
