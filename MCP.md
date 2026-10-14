# Capture agent control

Capture exposes local MCP tools for editing images in its visible macOS windows. Changes use the same rendering and undo history as manual edits. The server does not interpret natural-language instructions; the connected agent chooses tools and coordinates.

## Connect

1. Install or build Capture and open it.
2. Choose **Capture → Allow Agent Control**. This is off by default and grants access to all open documents.
3. Choose **Capture → Copy MCP Configuration** and add that configuration to a local MCP client.

The configuration points to `Capture.app/Contents/Helpers/capture-mcp`. It must use the actual app location; copy it again if you move the app. The helper launches its containing app when necessary. It does not enable access automatically.

The helper uses MCP over stdio and connects to Capture over a private Unix-domain socket. It listens on no network port. Socket access is restricted to the current macOS user. Turning agent control off disconnects existing sessions. Disconnecting a client leaves documents open. Quitting Capture ends connections without automatically reopening the app; restart the client connection when ready.

The Capture menu shows the number of agent connections. The affected document's status bar shows the latest editing action. Enabling control trusts local clients running as your user to read open documents, open local images, and export images to local paths.

## Workflow

1. Call `list_documents` or `open_image` to obtain a document ID.
2. Call `inspect_document` for annotation IDs/properties, or `preview_document` for a flattened PNG.
3. Pass the returned `documentID` and `revision` to each editing or output command.
4. Use the new revision returned after each edit. Inspect again if Capture reports `stale_revision`.
5. Export the result, or leave the document open for manual editing.

A document ID lasts until its window closes. Commands never implicitly follow the frontmost window. Revisions change for both user and agent edits, including undo and redo. A live text edit, drag, or dialog produces `document_busy`; finish the interaction and inspect again. Agent commands do not commit or cancel that interaction.

Each editing command is one undo step. Undo and redo apply to the shared document history, including manual edits. They are not limited to an individual agent's actions. The server serializes requests, including requests from multiple clients. After a connection error, inspect before retrying: the previous edit may have completed even if its response was lost. The helper never automatically repeats an edit.

## Tools

| Tool | Required arguments | Result or effect |
| --- | --- | --- |
| `list_documents` | None | IDs, titles, revisions, dimensions, busy state and undo/redo availability |
| `open_image` | `path` | Decode a local image into a new visible document |
| `inspect_document` | `documentID` | Document state and annotation IDs/properties |
| `preview_document` | `documentID` | PNG plus revision and coordinate mapping |
| `add_annotation` | `documentID`, `revision`, `kind`, `properties` | Add an arrow, rectangle, ellipse or text box; return its ID |
| `update_annotation` | `documentID`, `revision`, `annotationID`, `properties` | Update supplied properties while retaining the annotation ID |
| `delete_annotation` | `documentID`, `revision`, `annotationID` | Remove an annotation |
| `blur_region` | `documentID`, `revision`, `bounds` | Blur base-image pixels; optional `radius` defaults to 16 |
| `crop_document` | `documentID`, `revision`, `bounds` | Flatten and crop the image, clearing editable annotations |
| `undo`, `redo` | `documentID`, `revision` | Change history position and return a fresh revision |
| `export_image` | `documentID`, `revision`, `path` | Export PNG/JPEG; optional `overwrite` defaults to false |
| `copy_image` | `documentID`, `revision` | Copy the flattened PNG to the system clipboard |

Tool schemas returned by `tools/list` are the authoritative argument definitions. Unknown fields, missing required fields, invalid colors and nonfinite numbers are rejected.

### Geometry and appearance

Coordinates are image pixels from the **original image's top-left**, with positive X rightward and positive Y downward. They do not depend on window size, Retina scaling, zoom, or pan.

- Points: `{ "x": 30, "y": 40 }`.
- Bounds: `{ "x": 30, "y": 40, "width": 200, "height": 80 }`.
- Arrows require `start` and `end`; use these endpoints for moving/resizing, not bounds.
- Rectangles and ellipses require `bounds`.
- Text requires `bounds` and `text`. Text wraps at the box width and expands downward to fit.
- Arrows and shapes accept `color` and `strokeWidth`; text accepts `color`, `fontSize`, and `backgroundColor`.
- Colors use sRGB `#RRGGBB` or `#RRGGBBAA`. An alpha of `00` makes a text background transparent.
- Defaults match the current medium tool style: Capture's soft red, stroke width 16, font size 52, and half-opaque black text background.

Annotations can extend outside the original image, including negative coordinates. `canvasBounds` includes the resulting painted area. Previews are at most 1600 pixels on the longest side, without upscaling. Convert preview coordinates to document coordinates using:

```text
imageX = originX + previewX * imagePixelsPerPreviewPixelX
imageY = originY + previewY * imagePixelsPerPreviewPixelY
```

The mapping fields are returned in `preview`. The PNG has no selection handles or other window decorations.

Blur and crop are clipped to the original image, matching Capture's existing tools. Blur edits underlying pixels rather than creating a movable object. Crop flattens visible annotations, clears their IDs, and resets the image origin. Undo restores the previous pixels and editable annotations.

### Files and limits

Use absolute local paths. `open_image` decodes the first image frame and honors orientation. It never replaces an existing document. Export format comes from `.png`, `.jpg`, or `.jpeg`; exports do not change the document's source path or saved state. PNG retains transparency; JPEG uses Capture's image-matched background. Parent output directories must already exist. Replacing a file requires `overwrite: true`.

Agent-created images/expanded canvases are limited to 16384 pixels per side and 32 megapixels. Other limits are 2000 annotations per document, 10000 characters per text box, strokes of 1–256 pixels, font sizes of 6–256, and blur radii of 1–100. Private protocol requests are bounded to 1 MiB and responses to 20 MiB. These limits do not change the normal UI's controls.

Errors include a stable `code` and readable `message`, returned as an MCP tool error. Common codes are `connection_unavailable`, `access_disabled`, `document_not_found`, `annotation_not_found`, `document_busy`, `stale_revision`, `invalid_arguments`, `limit_exceeded`, and `file_exists`. No remote URLs, shell commands, clipboard reads, window closing, native sharing, or screenshot capture are exposed.

## Build and validate

Normal Xcode builds include the helper. It uses the official Swift MCP SDK pinned in `Package.swift`; `Package.resolved` locks its dependencies. The first build requires dependency downloads. Release builds include both CPU architectures, and the release script signs the helper before the containing app.

After building Debug, run:

```sh
bash scripts/check_windows.sh
bash scripts/check_mcp.sh
make check-release
```

The MCP test uses a client-neutral JSON-RPC harness with isolated app preferences and a private fixture endpoint. It does not enable access in your installed Capture app. The helper's `CAPTURE_MCP_TEST_SOCKET_DIRECTORY` environment override is for that harness; omit it in client configurations.

### Codex connection regression

For a local check with Codex installed:

```sh
python3 scripts/check_codex_mcp.py .build/DerivedData/Build/Products/Debug/Capture.app/Contents/Helpers/capture-mcp
```

This starts an isolated, ephemeral Codex thread and checks its MCP runtime status without making a model call or changing your Codex configuration. It tests runtime initialization, not just standalone tool discovery: Codex sends additional capabilities when a thread starts.

The helper ignores unused experimental client capabilities during initialization because Swift MCP SDK 0.12.1 restricts that field to string values. Object-valued capabilities are valid MCP data and otherwise cause a decoding error. Standard capabilities and tool messages pass through unchanged. Remove the compatibility adapter when the SDK supports arbitrary JSON values in this field.
