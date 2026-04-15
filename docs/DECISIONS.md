# Photos Caption Assistant Decision Log

## 2026-04-14 — Keep captioning local-first through Ollama
Status: approved
Rationale: Caption and keyword generation stays on the local Mac through Ollama running on `127.0.0.1`. This preserves the project's privacy-first, personal-use operating model and avoids silent cloud inference.

## 2026-04-14 — Keep Apple Photos automation as the production write path
Status: approved
Rationale: The app may expand guarded PhotoKit reads over time, but production metadata reads, writes, overwrite gating, and Photos lifecycle control remain AppleScript/automation-backed until a safer replacement is proven.

## 2026-04-14 — Keep app identity on `com.jkfisher.PhotosCaptionAssistant`
Status: approved
Rationale: The bundle identifier is a durable app identity and should not be casually renamed again after the existing permission prompts, saved state, and distribution expectations have already moved to this name.

## 2026-04-14 — Use checked-in Info.plist versioning as release source of truth
Status: approved
Rationale: `Sources/PhotosCaptionAssistant/Resources/Info.plist` is the canonical source for marketing version and build number. Local or CI packaging must not auto-bump or derive version/build from generated artifacts.

## 2026-04-14 — Keep distribution ad-hoc signed and non-notarized for now
Status: approved
Rationale: This repo distributes personal-use, ad-hoc-signed macOS builds and does not currently use Developer ID signing or notarization. README and release notes must describe the Gatekeeper implications honestly.

## 2026-04-14 — Publish GitHub releases from version changes on main
Status: approved
Rationale: A checked-in version/build change on `main` is the publish signal. CI should create or update the corresponding GitHub Release using the existing `vX.Y.Z` tag shape and attach a DMG built from committed source.

## 2026-04-15 — Keep the main app as a hybrid workbench, not a sidebar-first redesign
Status: approved
Rationale: The app’s core job is still a run-centric setup and monitoring workflow, so the modernization pass keeps that workbench model while making it feel more Mac-native through better scenes, menus, toolbars, and window behavior instead of forcing a document/sidebar architecture.

## 2026-04-15 — Use a dedicated Preview window and Settings scene for macOS defaults
Status: approved
Rationale: Completed-item preview now lives in its own macOS window, with optional full-screen behavior, and durable app-wide defaults now live in a proper Settings scene. This keeps the main workbench focused on the current run while matching standard Mac window and menu expectations.
