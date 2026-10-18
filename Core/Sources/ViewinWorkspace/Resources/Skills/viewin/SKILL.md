---
name: viewin
description: Inspect the live UIKit, SwiftUI, Android View/XML, or Compose hierarchy of an app using the Viewin SDK. Use for layout, dimensions, styling, accessibility, and gesture diagnostics from runtime snapshots.
---

# Viewin

Use the bundled CLI without opening the Viewin desktop app. The target app must already integrate Viewin SDK and be running in the foreground on a simulator, emulator, or supported connection. This skill inspects; it does not modify live properties or perform taps.

The CLI launcher is `scripts/viewin` beside this file. Resolve its absolute path from this skill's location and quote it in shell commands; it does not require PATH configuration, Swift, or Xcode.

1. Run `"<skill-directory>/scripts/viewin" --list` to discover targets. Each line contains a port, app name, and device name, separated by tabs. If there are multiple matches, use the requested app/device or ask the user which one. No results means no reachable SDK app; do not claim the app was inspected.
2. Capture the chosen port with `"<skill-directory>/scripts/viewin" --port <port> --output "<working-directory>/capture.viewin"`. Always specify the port so the first discovered app is not silently chosen. Use a new output path to preserve existing captures.
3. For direct data analysis, instead capture with `--format json --output "<new-directory>"`. Read `snapshot.json` and the `images/` directory. Use tools already available in the environment to read JSON and images.

The snapshot contains nodes, roots, images, coordinate spaces, and structured property groups. Read [references/snapshot.md](references/snapshot.md) for field meaning and limitations. Follow parent/child IDs, inspect relevant properties, and view images where necessary. Report the app/device and observed evidence (node type, member name/resource ID/test tag, frame, property values), plus capture limitations when they affect the finding.

A `.viewin` file is a ZIP archive with `snapshot.json`, `manifest.json`, and deduplicated images. The manifest maps logical image paths to archive paths. It can be opened in Viewin for human inspection. This CLI currently captures and lists apps; do not invent node-query, interaction, wireless pairing, or property-editing commands.

If the launcher reports that the app has moved, reinstall/update this skill from Viewin → Settings → Agent. After an agent's first installation, start a new agent session if its skill list does not refresh.
