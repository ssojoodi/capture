# Release preparation

## Summary
Prepare Capture 2026.10.3 build 2 with text layout, transparent PNG output, image-matched JPEG backgrounds, and selected-annotation copying.

## Product behavior target
Bundle metadata, website copy, and release notes accurately describe the pending release. Existing historical release entries remain intact. Produce a local signed/notarized package if the existing credentials are accessible; do not publish the website or push the branch.

## Architecture changes
Update version metadata and About checks. Correct the blur-brightness regression test to compare source and output pixel values in the same color space, preserving a strict tolerance. Reuse the existing release Makefile and signing setup.

## UX acceptance criteria
Release notes cover all changes since September 27. Export documentation defaults to PNG and explains object copy as a transparent image. Release app reports 2026.10.3 build 2. No public deployment occurs.

## Automated test plan
Run the full Xcode suite without exclusions, AppKit checks, a Release build, and signing/package validation if available. Inspect staged diff and run git diff --check. Verify app version and architecture from built artifacts.

## Manual verification plan
Inspect existing generated image artifacts and prepare a public-safe app snapshot from an AppKit sample fixture if direct desktop capture remains unavailable. Do not claim direct Keynote paste was tested. Check release artifact and document any packaging blocker.

## Assumptions and non-goals
Date-based version 2026.10.3 with incremented build 2. Prepare a local release only. Existing uncommitted PNG and object-copy features belong in the requested commit. Final commit message approval is required by the installed git-staged-user-message skill; prepare reviewable changes first.

## Outcome
Release preparation continued under docs/2026-10-03-22-03-configured-release-workflow.md after the user requested Retriever-style configuration-driven releases. All 39 tests now pass without exclusions: the blur test compares original and rendered sRGB bitmap samples directly. Release 2026.10.3 build 2 was successfully signed, notarized, and prepared locally with updated release notes and social previews. Publication and commit-message approval remain separate final steps.
