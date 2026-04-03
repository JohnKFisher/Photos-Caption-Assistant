# Contributing

Thanks for taking an interest in Photos Caption Assistant.

This project is still primarily a personal hobby app, so contributions work best when they are small, clear, and discussed before large behavior changes.

## Before You Start

- Read [README.md](README.md) first so the current operating model and distribution caveats are clear.
- Prefer opening an issue or starting a discussion before large UI, architecture, permission, or workflow changes.
- Keep the app local-first, explicit, and safe by default.

## Good Contribution Areas

- UI clarity and usability improvements.
- Fixes for incorrect behavior, crashes, or poor error handling.
- Tests that improve confidence without weakening existing coverage.
- Documentation improvements that make setup, limits, or risks more truthful.

## Please Avoid Surprise Changes

- Do not add telemetry, analytics, ads, or hidden network behavior.
- Do not add new third-party dependencies unless they are clearly necessary and called out.
- Do not silently broaden write scope, permissions, or destructive behavior.
- Do not remove safety prompts, overwrite protections, or other guardrails without discussion.

## Development

Typical local verification:

```bash
swift test
swift build -c release --triple arm64-apple-macosx15.0 --product PhotosCaptionAssistant
swift build -c release --triple x86_64-apple-macosx15.0 --product PhotosCaptionAssistant
./scripts/build_app.sh
```

## Pull Requests

- Keep pull requests focused and easy to review.
- Explain what changed, why it changed, and any manual verification still needed.
- Update docs when behavior, setup, or safety expectations change.
- Be honest about partial work, tradeoffs, and known limitations.
