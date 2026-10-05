# Release screenshots

Keep each release's screenshots in its own dated directory, such as `2026-09-24/capture.png`.

- Capture the app with sample content suitable for public viewing.
- Keep the toolbar and window visible so interface changes can be compared.
- Link each screenshot from its matching entry in `../release-notes.html`, with the date and a full-size link.
- Preserve older screenshots. Add a new directory for each release instead of replacing an earlier image.
- Describe released behavior factually; use a date unless a version number is established.
- Record the app bundle's measured disk usage in the screenshot caption for each release, rather than the compressed DMG size. The September 24 caption currently uses the existing July 6 download: `du -sk Capture.app` reported 1,088 KiB (about 1.1 MB). Update that figure when the matching release build is packaged.

The September 27 caption uses the optimized Release build of Capture 2026.9.27 (build 1): `du -sk` reported 1,200 KiB (about 1.2 MB on disk) before signing. Recheck the caption after packaging if signing changes the rounded size.

The October 3 screenshot shows Capture 2026.10.3 (build 2) with a selected arrow and centered text. It was generated from the AppKit release-preview fixture using `CAPTURE_RELEASE_SCREENSHOT=1 bash scripts/check_windows.sh`; the image contains only public sample content. The signed universal app measured 2,256 KiB with `du -sk` (about 2.3 MB on disk). Both website pages display optimized derivatives of this dated image. Social previews use `../assets/social-preview.png`, a separate 1200 × 630 product card. Preserve the original screenshots and full-size links.
