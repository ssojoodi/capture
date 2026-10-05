# Summary
Improve the two static public Capture pages for search, sharing, accessibility, and loading performance.

## Product behavior target
Accurate, distinct page metadata; a 1200 × 630 social card; readable controls and usable navigation on mobile and keyboard; fast, stable screenshots.

## Architecture changes
Keep static HTML. Add verified SoftwareApplication/WebPage structured data, raster icons, responsive screenshot derivatives, and a code-authored social card. Remove external font stylesheets in favor of native system fonts. Preserve original dated screenshots.

## UX acceptance criteria
One H1 per page, visible keyboard focus and working skip links, no horizontal overflow at 320px, sufficient text contrast, reduced-motion support, and links to the main site and apps catalog.

## Automated test plan
Parse HTML metadata, JSON-LD, local URLs and image dimensions. Check public HTTP status and indexing directives. Browser-check desktop/mobile layout, keyboard navigation, image loading, and accessibility where tooling permits.

## Manual verification plan
Inspect rendered pages and social card; save verification screenshots. Record canonical URLs and deployment limitations.

## Assumptions and non-goals
Canonical base remains https://sojoodi.com/apps/Capture/. No invented ratings, prices, or compatibility claims. No app changes, release packaging, deployment, or changes to centrally managed sitemap/robots.txt. Release anchors are sections, not separate indexable pages.
