# Summary
Use Google Analytics measurement ID `G-KLFFZDT458` on both public website pages.

## Product behavior target
Home and release-notes visits use the same analytics property, with one tag initialization per page.

## Architecture changes
Reuse the existing asynchronous home-page Google tag on the release-notes page.

## UX acceptance criteria
Analytics does not block page rendering or change navigation and content.

## Automated test plan
Verify each HTML page has exactly one asynchronous loader and one configuration call for the requested ID. Run the existing website validator and diff checks.

## Manual verification plan
After deployment, verify page visits in the property's realtime view when analytics is permitted by the browser.

## Assumptions and non-goals
The home page already uses the requested ID. No deployment or analytics account configuration changes.
