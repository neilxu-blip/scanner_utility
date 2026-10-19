# Scanner Utility — User Manual

Scan documents and photos on macOS, combine pages into one PDF, and save scans as images. Current version: **0.7.0**. Requires **macOS 14 or later** and a compatible scanner configured with SANE. Canon LiDE 120 has been used successfully for document scanning; other scanners and the newer scan modes still need hardware testing.

The project is currently shared through [GitHub](https://github.com/neilxu-blip/scanner_utility). All implemented features are available in the current build; there are no in-app purchases. Mac App Store distribution is a future possibility.

## Download and open the app

1. Open the [version 0.7.0 preview release](https://github.com/neilxu-blip/scanner_utility/releases/tag/v0.7.0) and download **ScannerUtility-0.7.0-macos-arm64.zip** under Assets. The source-code archives are for building the app yourself.
2. Double-click the ZIP to extract **Scanner Utility.app**, then drag it to your **Applications** folder.
3. Open the app. This download is for **Apple silicon Macs (M-series), macOS 14 or later**. An Intel download is not provided in this release.

**Signing:** this preview is ad-hoc signed, not Developer ID signed or notarized by Apple. macOS may block its first launch. If you trust this project's download, try opening it, then use **System Settings → Privacy & Security → Open Anyway** if offered. Follow [Apple's instructions for opening an unnotarized app](https://support.apple.com/en-us/102445); managed Macs may disallow this. A checksum file is included on the release page to verify the downloaded ZIP.

You do not need Xcode to use the download. To build from source instead, follow [Build and test](docs/PROJECT_STATE.md#build-and-test); the generated app is in the hidden `.build` folder inside your checkout.

After an update, save your current scans, quit Scanner Utility, and reopen it to load the new version.

### Set up a real scanner

The download does **not** include SANE or scanner drivers. If SANE is already working on your Mac, no reinstall is needed. Otherwise, with [Homebrew](https://brew.sh) installed, open Terminal and run:

```sh
brew install sane-backends
```

This is Homebrew's [SANE package](https://formulae.brew.sh/formula/sane-backends). Connect a compatible scanner and click **Refresh** in the app. Compatibility depends on the scanner and SANE backend; installing the package does not guarantee every scanner will work. You can try [Mock Scanner](#try-the-app-without-a-scanner) immediately without installing SANE.

## Scan several pages into one PDF

1. Connect the scanner and open Scanner Utility.
2. Check **Product name**. Your connected scanner should be selected. Click **Refresh** if you connected it after opening the app.
3. Place the first page on the glass and close the cover.
4. Click **Document**. With the default settings, this scans in **A4, Color, 300 dpi** and collects pages for a PDF.
5. After the page finishes, replace it with the next page and click **Scan**. Repeat for every page. No PDF is created between scans.
6. When all pages are ready, click **Exit**, choose the filename and destination, and click **Save**.

**Exit finishes and saves the document; it does not quit the application.** To keep this multipage workflow, leave **Settings → Document Scan → Data format** set to **PDF (Multiple Pages)**.

The default save location is your **Documents** folder. Suggested names include the date and time, such as `Scanned Document 2026-10-17_14-30-05.pdf`. You can change the name and destination in the save dialog.

### Progress, review, and cancellation

- **Warming up:** the app is finding/preparing the scanner. This label covers setup and calibration until scanning progress becomes available.
- **Scanning:** the percentage reflects image data received, rather than time remaining. If the scanner cannot supply a percentage, the app says so.
- **100%:** finishing acquisition or image processing may still take time.
- **Cancel:** stops the current acquisition; earlier completed pages remain available.
- **Check scan results:** enables page review controls. Use **Review page**, **Earlier**, **Later**, **Rotate**, and **Remove…** as needed. Removal requires confirmation.
- **Discard…:** clears unsaved scans after confirmation. It does not delete files already saved.

Canceling the save dialog or encountering a save error keeps the completed pages available for another attempt. Save before quitting: unsaved scans are held in memory and cannot be recovered after a crash or forced quit.

## Choose a scan mode

Clicking a mode starts scanning, except **Advanced**, which first shows its setup window.

| Mode | Use it for | How to finish |
| --- | --- | --- |
| **Auto** | One item; text detection suggests PDF or JPEG when Data format is Automatic. Check the choice, especially for sparse text or handwriting. | Choose PDF or JPEG if needed, then **Save…**. |
| **Document** | Several pages in one PDF. Defaults to A4, Color, 300 dpi. | **Scan** adds pages; **Exit** saves the batch. |
| **Photo** | A photo. Defaults to 4 × 6 inches, Color, 600 dpi, JPEG. | **Save…**, then start another scan from the main window. |
| **Custom** | A separate set of your preferred scan and save settings. | With PDF selected, **Scan** adds pages; **Save…** finishes. |
| **Stitch** | An item larger than the glass, scanned in two overlapping parts. | Scan the first part, reposition it, click **Scan second half**, adjust the join, then **Save…**. |
| **Advanced** | Adjust scan size, resolution, and image corrections before starting. | Choose **Scan** in the setup window, then **Save…** after acquisition. |

JPEG, PNG, and TIFF workflows save one image per session. PDF can collect multiple pages in Document, Photo, Custom, or Advanced when explicitly selected. Auto always acquires one item. Stitch combines its two scans into one image or one PDF page.

For Stitch, keep some of the same detail visible in both scans. Set **Join direction** and **Overlap** to match how you moved the original. Check the preview; use **Retake second half…** if needed. Alignment is manual.

## Change settings

Click **Settings…** in the main window. The left sidebar contains **General** and six scan profiles under **Scanning**. Select a page to edit its controls on the right.

Each scan mode remembers its own settings. **OK** saves your edits across the pages you changed. **Cancel** or closing the window discards preference edits. **Defaults** resets only the selected page's draft; click OK to keep the reset. These buttons remain visible while scrolling.

### Settings for each scan mode

| Group | What you can change |
| --- | --- |
| **Scan Options** | Source, color mode, paper size or custom dimensions, and resolution. Expand **Image Processing Settings** for crop, enhancement, sharpening, show-through/moiré/gutter-shadow reduction, straightening, and text rotation. |
| **Save Settings** | Filename prefix, default folder, PDF/JPEG/PNG/TIFF or Automatic format, PDF compression, JPEG quality, searchable text, dated subfolders, and review controls. |
| **Application Settings** | What happens after saving: nothing, open Preview or another app, show in Finder, copy to another folder, create an email draft, or save recognized text in a separate text file. |

Scan options take effect when you start a new session. Selecting **Magazine** enables moiré reduction; you can turn it off under Image Processing Settings. Optional corrections can change the appearance of a scan, so check results before relying on them.

**Check scan results** currently controls page-editing tools. Turning it off still leaves the save dialog in place, despite the Settings wording suggesting direct saving.

If **Save to a subfolder with the current date** is enabled, the app saves inside a folder such as `2026_10_17` under the folder chosen in the save dialog. It creates that dated folder only after you approve Save. Existing files are never replaced; use a different name if one already exists.

Post-save actions run only after the file has been saved. Email opens a draft for you to review and send yourself. An error opening another app does not mean the scan failed to save.

### General settings

| Section | Purpose |
| --- | --- |
| **Scanner** | Select **Product name** or refresh the scanner list. This selection changes the main window immediately, even before OK. Finish the current scan session before changing scanners. |
| **Text Recognition** | Choose the document language for searchable PDFs, text export, and text orientation. Recognition runs locally on the Mac. |
| **Outgoing Images** | Limit image copies sent to apps/email to 640, 800, or 1024 pixels on the longest side, or choose **No change**. Select the temporary folder for those copies. Saved originals and PDFs keep their dimensions. |

The temporary folder is not a recovery folder for unsaved scans. The app does not automatically remove the outgoing copies it creates.

### Keep PDF files smaller

Open **Settings → Document Scan → Save Settings → PDF compression** (or choose another scan profile).

| Choice | Result |
| --- | --- |
| **Standard (smaller files)** | Default compression with some image quality loss. Keeps the scanned pixel dimensions. |
| **High quality** | Preserves more fine detail, with larger files. |
| **Lossless (large files)** | Preserves processed image pixels; full-color scans can be much larger. |

For comparison, one two-page scan measured **34.8 MB** with lossless storage and **4.15 MB** with Standard compression. Results vary with page content; no particular file size is guaranteed.

To make a searchable PDF, enable **Create a PDF that supports keyword search** and choose the appropriate language in General. Check recognized text before relying on it.

## Try the app without a scanner

Choose **View → Debug Mode** in the menu bar, then select **Mock Scanner** under Product name. It creates sample pages for trying the workflow without moving scanner hardware.

Debug Mode starts off each time the app launches. If a real scanner is connected, it remains the default. Refresh prefers a real scanner again, so explicitly select Mock Scanner when you want sample pages.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| Product name and scan buttons are gray | Connect the scanner and click **Refresh**. Real scanning requires SANE's `scanimage` and a compatible backend installed on the Mac. |
| Scanner remains missing or busy | Check the USB connection, close other scanner applications, then Refresh. SANE setup details are in [Hardware requirements](docs/PROJECT_STATE.md#hardware-requirements). |
| A later page fails | Earlier completed pages remain available. Check the connection before retrying **Scan**, or save the completed pages. The app refreshes the scanner address before each page. |
| Progress pauses before scanning | Preparation can take time. A resident helper has not been implemented, and its potential speed benefit has not been measured. |
| A high-resolution scan is rejected | Reduce resolution or scan area. Large scans and stitched images can exceed the app's memory limits. |
| Saving fails | Choose a writable folder and a new filename, then try saving again. Existing files are protected. |
| New features do not appear after rebuilding | Save any current session, quit the running app, and reopen the newly built copy. |
| Finder shows an old modification date on the app | A macOS app is a folder. Its contents can be updated without changing the outer folder's displayed date. |

This version does not respond to the scanner's physical buttons or run an always-on background helper. Advanced uses native controls; Canon's Windows ScanGear driver is not included.

For development, current test results, and remaining validation work, see [Project state](docs/PROJECT_STATE.md). Architecture history is in [Technical decisions](docs/DECISIONS.md); contributor instructions are in [AGENTS.md](AGENTS.md).
