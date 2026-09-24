# Release screenshots

Keep each release's screenshots in its own dated directory, such as `2026-09-24/capture.png`.

- Capture the app with sample content suitable for public viewing.
- Keep the toolbar and window visible so interface changes can be compared.
- Link each screenshot from its matching entry in `../release-notes.html`, with the date and a full-size link.
- Preserve older screenshots. Add a new directory for each release instead of replacing an earlier image.
- Describe released behavior factually; use a date unless a version number is established.
- Record the app bundle's measured disk usage in the screenshot caption for each release, rather than the compressed DMG size. The September 24 caption currently uses the existing July 6 download: `du -sk Capture.app` reported 1,088 KiB (about 1.1 MB). Update that figure when the matching release build is packaged.
