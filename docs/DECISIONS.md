# Technical decisions

Record only decisions that have actually been made. Add dated entries for significant changes, including rationale, trade-offs, and any alternatives explicitly rejected. If a decision changes, mark the earlier entry as superseded and link its replacement.

## 2026-10-14 — Native SwiftUI interface and separate scanner backend

**Decision:** Prefer native SwiftUI for the macOS interface and keep scanner backend code separate from UI code.

**Rationale:** This follows the project's native macOS objective and lets UI development proceed independently of hardware integration.

**Trade-off:** A shared backend boundary must be defined and maintained. Its concrete API and project layout have not been decided.

## 2026-10-14 — Initial SANE integration through `scanimage`

**Decision:** Initially use the SANE `scanimage` command-line utility for the real scanner backend.

**Rationale:** This establishes a concrete first integration path for SANE.

**Trade-off:** The app will need executable discovery, process execution, output/error handling, and a local SANE installation. Direct SANE library integration is deferred; no permanent rejection has been made.

## 2026-10-14 — Mock backend and two-computer development

**Decision:** Support a mock scanner backend on the MacBook Air and use the Mac Studio for real USB scanner development and testing. Synchronize work through GitHub.

**Rationale:** UI development and testing must remain possible without scanner hardware.

**Trade-off:** Mock behavior must stay aligned with the shared backend interface, and real hardware behavior must be validated separately on the Mac Studio.

## 2026-10-14 — Dependency constraints

**Decision:** Do not introduce Docker or unnecessary dependencies.

**Rationale:** Keep setup focused on the native macOS application and its required SANE integration across both computers.

**Rejected alternative:** Docker-based development is excluded by the project requirements. Specific additional libraries have not been evaluated or rejected.

## 2026-10-15 — Swift package with a native macOS app

**Decision:** Use a Swift 6 package targeting macOS 14+, with separate `ScannerCore` and SwiftUI executable targets. Provide a shell script that builds and locally signs an app bundle using Xcode tools.

**Rationale:** Both computers can build and test the same source without project generators or third-party dependencies. The core can be tested independently of the views.

**Trade-off:** There is no checked-in Xcode project or distribution/signing setup yet. Xcode can open the package; the bundle script provides a Finder-launchable app for local development. Earlier macOS versions are outside the current deployment target.

## 2026-10-15 — Explicit document sessions and export on Exit

**Decision:** Document starts the first page, Scan adds pages to the current in-memory session, and Exit finishes the batch through a native PDF save dialog. Exit does not quit the app. No PDF is generated between scans.

**Rationale:** This follows the requested multipage workflow and lets users choose the destination only after acquiring all pages.

**Trade-off:** Canceling scanning discards only the incomplete page. Canceling saving or failing export preserves completed pages for retry. The app prevents normal dismissal/termination with unsaved work, but memory-only sessions cannot survive crashes or forced termination. Per-page PDF output is excluded from this workflow.

## 2026-10-15 — Mock-first acquisition and native PDF export

**Decision:** Implement the initial UI with a cancellable mock `ScannerBackend` that returns PNG page data and fractional progress. Use CoreGraphics/ImageIO to combine images in scan order into portrait A4 PDF pages. Refuse existing destination files.

**Rationale:** This makes the entire Document flow testable without hardware, keeps acquisition independent of SwiftUI, uses system frameworks, and protects user files.

**Trade-off:** Progress is simulated and only Document is functional in this milestone. Fixed A4 output, in-memory images, and no overwrite keep the first implementation small. Real `scanimage` integration remains the agreed next backend, and additional page sizes or large-batch storage can be added later.

## 2026-10-17 — Selectable SANE backend for physical documents

**Decision:** Extend the existing backend boundary with a `scanimage` subprocess backend and non-scanning device discovery. Initially keep Mock Scanner as the launch default and require users to select a real scanner explicitly; this selection policy is superseded by [Debug Mode and real-scanner defaults](#2026-10-17--debug-mode-and-real-scanner-defaults). Document and Scan invoke one acquisition; PDF generation remains deferred until Exit.

**Rationale:** The connected Canon LiDE 120 is detected by the installed SANE 1.4.0, and its queried capabilities support the initial A4, grayscale, 300 dpi, 8-bit settings. This implements the previously selected CLI integration without adding a library dependency.

**Trade-off:** Those options are fixed in this version and may not apply to other scanners. PNG data stays in memory. Preparation uses an indeterminate bar until SANE reports acquisition percentages; no simulated percentages are used for physical scanning. Hardware acquisition is not considered verified until an approved physical test succeeds. This supersedes the mock-only implementation scope of the 2026-10-15 milestone, retaining its mock backend and PDF choices.

**Process handling:** Launch `scanimage` directly with argument arrays, read stdout/stderr concurrently, apply timeouts, and interrupt cancellation with termination fallbacks. Only validated complete image output becomes a session page. Commands and parsing are tested without scanner hardware.

**Reference:** [SANE scanimage manual](https://sane-project.gitlab.io/website/man/scanimage.1.html) documents device listing, PNG output, progress reporting, and device-specific options.

## 2026-10-17 — Color defaults, live acquisition progress, and dated filenames

**Decision:** Use A4, color, 300 dpi, and 8 bits per RGB channel by default, superseding the grayscale choice in the earlier SANE milestone. Suggest a save-time filename containing the local date and time through seconds, using filename-safe separators; users can edit it in the save dialog.

**Rationale:** These are the user's requested document defaults. The [Canon specifications](https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/su-020.html) support A4 and 24-bit color output; the linked page does not prescribe these application defaults.

**Progress handling:** Read small stderr messages immediately with a single POSIX pipe read. The old length-filling reader delayed progress until its buffer filled or the process ended; a child/callback acknowledgement regression test reproduces this. Expose preparation and acquisition status separately to the UI. Show Warming up with a spinner before acquisition reports, then a numeric percentage and determinate bar. If SANE reports an unknown percentage, label acquisition progress unavailable. Retain monotonic progress and stale-event guards.

**Trade-off:** The warm-up label covers initialization/calibration until SANE reports acquisition; it does not detect exact motor start or temperature. Percentages are based on received image data, not predicted duration. The default filename is generated when the save dialog opens; existing-file protection still applies if a name collides.

## 2026-10-17 — Resolve the scanner address for every page

**Decision:** Rediscover the selected scanner before each acquisition. Prefer its exact address when model/backend still match; otherwise use a unique matching model/backend at its current address. Refuse absent or ambiguous matches, preserving completed pages. This supersedes retaining the original USB address throughout a document session.

**Rationale:** The user's second-page error referenced an address no longer reported by discovery. The [SANE Genesys implementation](https://gitlab.com/sane-project/backends/-/raw/1.4.0/backend/genesys/genesys.cpp) resets USB during device close, so an address stored across separate CLI processes cannot be treated as permanent.

**Recovery:** Retry once only when opening the old address failed, the refreshed address differs, and neither acquisition progress nor image output has occurred. Never automatically repeat a partial or completed acquisition. Session accumulation and export-on-Exit remain unchanged.

**Trade-off:** Discovery adds preparation time before each page. Matching by model/backend cannot distinguish identical devices after their old address disappears; require the user to leave only one matching scanner connected in that case. Initial validation used changing-address simulations and PDF export. Subsequent user-reported use and the supplied two-page scanner output are recorded in [PROJECT_STATE.md](PROJECT_STATE.md); no agent-operated physical test was performed.

## 2026-10-17 — Compressed page images in PDFs

**Decision:** Default PDF export to JPEG-compressed images at quality 0.75, with High quality (0.9) and Lossless choices in Settings. Keep A4, color, and original image dimensions; do not reduce the 300 dpi acquisition resolution. Read the preference when exporting, retaining source PNG scans in the session.

**Rationale:** Lossless compression of noisy full-color scans produced a 34.8 MB two-page reference PDF. The new Standard exporter produces 4.15 MB from those page images (88% smaller); High quality produces 6.10 MB. Use native ImageIO for JPEG encoding and a JPEG-backed CGImage so CoreGraphics embeds the compressed stream directly. No external compression dependency is required.

**Trade-off:** JPEG can introduce slight edge/color artifacts, so exact pixel preservation remains available through Lossless. Compression ratios depend on page content; no target file size is guaranteed. Preserve scan order, A4 bounds, and original pixel dimensions, composite transparency on white, and keep existing-file protection. Existing PDFs are only converted to a separate copy when requested.

**Validation:** Native tests inspect JPEG filters and dimensions inside exported PDFs and compare file sizes. Reference PDF pages were reopened and rendered for visual comparison, and the original file hash remained unchanged. Private reference/output artifacts are ignored by Git; documentation contains only aggregate measurements.

## 2026-10-17 — Debug Mode and real-scanner defaults

**Decision:** Hide Mock Scanner in normal use. Expose it through a View → Debug Mode toggle that starts off each launch. Automatically select a real scanner on discovery/Refresh and mode changes, preserving a valid real selection; otherwise choose mock only in Debug Mode. With no available scanner, disable Product name and Document. Resolve the selected backend again when Document is clicked, with no hidden mock fallback.

**Rationale:** Daily use should show the connected scanner and make a disconnected device obvious, while retaining hardware-independent development on the MacBook Air. This supersedes the earlier mock-first launch policy.

**Trade-off:** Debug Mode must be enabled again after relaunch. Refresh prefers an available real scanner even after an explicit mock selection; select mock again to continue testing. Disable the toggle during discovery and open document sessions to keep the current document's scanner fixed. Automatic selection only enumerates devices; it never starts acquisition.

## 2026-10-17 — Document settings and batch configuration

**Decision:** Use a native SwiftUI sidebar with Document Scan active and placeholder pages for other scan modes. Group its controls into Scan Options, Save Settings, and Application Settings, following the [Canon reference](https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/su-110.html). Implement color/grayscale, common paper sizes, 150/300/600 dpi, filename prefix, destination/date folder, PDF compression, and None/Preview/Finder post-save actions. Show unsupported image corrections, OCR, and integrations as disabled placeholders.

**Rationale:** Provide familiar document controls while keeping the native interface and exposing only options connected to actual behavior. Preserve A4/Color/300 defaults, timestamped names, and the existing multipage-PDF-on-Exit workflow. Single-image formats and other scan modes remain outside this version.

**Configuration lifetime:** Capture acquisition options and the PDF paper size when Document starts; refuse changing that batch's backend/exporter until saved. This supersedes hard-coded A4-only geometry and fixed scan options. Save preferences are captured when opening the save dialog; compression remains read once per export. Settings edits are a draft until OK; Cancel/window close discards them and Defaults resets only the draft. Persist locally through UserDefaults, preserving the existing compression key.

**Save handling:** The native save dialog remains the final approval. When enabled, its message explains the dated subfolder added under the chosen folder; create it only after Save, preserve an explicitly edited filename, and never overwrite existing files. Run Preview/Finder only after successful export; inability to launch Preview does not invalidate the saved PDF.

**Trade-off:** Common options are offered without scanner-specific capability negotiation. Unsupported device settings report errors while preserving earlier pages. Mock pages approximate selected paper proportions and grayscale at a fixed lightweight resolution. OCR, corrections, custom geometry, and other formats remain future work; this is not full Canon feature parity.

## 2026-10-17 — All on-screen workflows and native processing

**Decision:** Implement Auto, Document, Photo, Custom, Stitch, Advanced, and General Settings with independent persisted profiles, following the [Canon settings index](https://ij.manual.canon/ij/webmanual/ScanUtility/W/LiDE%20120/1.1/EN/SU/Su-PAGE3.html). The user explicitly limited scope to on-screen modes and General Settings; physical scanner-button triggering is excluded. Advanced provides native SANE controls rather than launching Canon's proprietary Windows ScanGear driver.

**Rationale:** Extend the working document flow without introducing driver/library dependencies. Shared CoreImage/Vision/ImageIO/CoreGraphics code supports local corrections, OCR/searchable PDFs, image exports, and both mock and real backends. This supersedes the prior Document-only settings scope and disabled on-screen mode placeholders. Document retains A4/Color/300 dpi and multipage export on Exit.

**Workflow choices:** Auto performs one configured acquisition and uses local text-density detection to suggest PDF/JPEG, with an explicit output override and failure fallback. Photo defaults to 4 × 6 inches/600 dpi/JPEG. Image formats save one image; PDF supports a batch. Stitch uses two user-triggered scans with manual direction/overlap and a feathered seam. Native review rotates/reorders/removes in-memory pages; confirmed discard and retake paths prevent failed classification/joining from trapping unsaved sessions.

**Processing and OCR:** Apply optional corrections after acquisition; black-and-white uses supported Gray acquisition plus native thresholding. Detection can reduce its analysis resolution, while output retains full image detail. Confident text/geometry controls orientation/crop changes. OCR adds an invisible CoreText layer without changing PDF raster appearance. Orientation scoring uses Vision reading direction because accurate OCR can recognize text in several orientations equally well. These are native approximations, not Canon's proprietary algorithms.

**General and actions:** Share the live scanner picker and persist local OCR language, outgoing image limits, and temporary-copy folder. Save configuration is captured once per save dialog/export, while acquisition stays fixed per session. Follow-up apps, additional copies, email drafts, and text sidecars run only after saving; no automatic email sending or overwriting. Outgoing resizing creates a separate copy and never rewrites saved originals. Temporary outgoing copies are retained to honor the no-user-file-deletion rule.

**Trade-offs:** Automatic classification can misread sparse/handwritten pages, corrections can affect appearance, and manual stitching requires alignment. Keep explicit overrides and conservative fallbacks. Retain memory-only sessions and enforce 128 MiB/80-million-pixel acquisition and 256 MiB stitched bitmap budgets; Canon's multi-gigabyte driver mode is not implemented. Capability negotiation, physical validation of new combinations, crash recovery, and full distribution remain separate work.

## 2026-10-17 — Unified Settings navigation

**Decision:** Replace the top Scanning/General switch with one persistent native sidebar: General followed by the six profiles under Scanning. Keep the selected page's heading and Defaults/Cancel/OK visible while its controls scroll. Group General controls by Scanner, Text Recognition, and Outgoing Images.

**Rationale and trade-off:** All destinations remain visible and one click away, following the user's preference for navigation on the left. This removes the extra section-switching step while using some horizontal space for the sidebar on General. Drafts, per-profile defaults, and OK/Cancel behavior remain unchanged.
