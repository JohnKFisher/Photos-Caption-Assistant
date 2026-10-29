# Photos Caption Assistant

Photos Caption Assistant is a macOS app for adding AI-generated captions and keywords to items in Apple Photos.

It runs the image/video analysis locally through Ollama, then writes the generated caption and keywords back into Photos. It is built for personal Mac photo-library cleanup, not for cloud sync, collaboration, or production media management.

Learn more about Sidelark Labs projects at [sidelarklabs.com](https://sidelarklabs.com).

Source code is available on [GitHub](https://github.com/JohnKFisher/Photos-Caption-Assistant).

## Before You Use It

You need:

- macOS 15 or later.
- Apple Photos installed.
- Full Photos library access.
- On macOS 15–26, Photos.app must be open and Apple Events automation must be allowed. On macOS 27+, the app uses PhotoKit and Photos.app can stay closed.
- Homebrew installed.
- Ollama installed through Homebrew.
- The `qwen2.5vl:7b` Ollama model.
- Permission to let the app access Photos and automate Photos when macOS asks.

The app can help you download `qwen2.5vl:7b` after Homebrew and Ollama are installed. It does not install Homebrew or Ollama for you.

## Install Homebrew And Ollama

Install Homebrew from [brew.sh](https://brew.sh).

Then install Ollama:

```bash
brew install ollama
```

After that, open Photos Caption Assistant and use its setup checks. If Ollama is installed but the required model is missing, the app will ask before downloading `qwen2.5vl:7b` through Ollama. That first model download can take several minutes.

You can also install the model yourself:

```bash
ollama pull qwen2.5vl:7b
```

## How A Run Works

1. On macOS 15–26, open the Photos library you want the app to use. On macOS 27+, PhotoKit always uses the System Photo Library, regardless of which library Photos.app currently displays.
2. Open Photos Caption Assistant.
3. Grant Photos permission when macOS asks. Apple Events automation is additionally required on macOS 15–26.
4. Choose what to process:
   - an album,
   - the whole library,
   - selected items from the Photos picker,
   - or a saved queue of albums.
5. Review the run summary.
6. Choose overwrite behavior carefully.
7. Start the run.

The app reads each selected photo or video, sends local analysis input to Ollama, receives a caption and keywords, and writes the result back into Photos.

On macOS 27 and later, caption and keyword metadata are read and written through PhotoKit, then read back for verification. On macOS 15–26, the app uses its AppleScript compatibility backend. Both paths retain overwrite prompts, app ownership tags, and resumable runs.

## Safety Notes

The safest starting point is a small album.

On macOS 27+, check the run summary to confirm the target is the System Photo Library. Opening another library in Photos.app does not isolate or redirect PhotoKit.

Whole-library runs are available, but they can touch a lot of Photos metadata. The app asks for confirmation before starting a whole-library run.

The app can also overwrite captions or keywords that were not created by Photos Caption Assistant. Review the run summary and overwrite settings before starting.

If a run is interrupted, the app keeps resumable state where possible. On macOS 27+, normal PhotoKit runs queue the complete selected-scope snapshot before writing; durable recovery depends on the existing best-effort save succeeding. On the older compatibility backend, library and album scans save discovered pending items, so a fresh run with the original scope may be needed if cancellation interrupts discovery. Queued-album workflows also save discovered pending items.

## Privacy

Photos Caption Assistant is local-first:

- It uses Ollama on your Mac.
- It talks to Ollama through the local service on your machine.
- It does not upload your Photos library to a cloud captioning service.
- It does not add telemetry, analytics, ads, or background sync.

If the model returns malformed output, the app may save the raw model response to a temporary local diagnostics file so failures can be understood. Those diagnostics stay on your Mac unless you choose to share them.

## Where Data Is Stored

The app stores its own resumable run state and settings under:

```text
~/Library/Application Support/PhotosCaptionAssistant/
```

Temporary previews, exports, and diagnostics are written to temporary folders on your Mac.

The app includes Data & Storage and Diagnostics windows so you can inspect important local paths from inside the app.

## Opening The App

If you download a GitHub Release DMG, it is intended to be signed and notarized so macOS can open it like a normal downloaded Mac app.

If you build the app locally from source, that local build is not notarized by default. macOS may require you to Control-click the app, choose Open, and confirm that you want to open it.

## Current Limits

- Photos.app and Apple Events automation are required for write runs only on macOS 15–26. Native PhotoKit runs on macOS 27+ can operate while Photos.app is closed.
- Native PhotoKit writes have not yet been validated against a designated disposable asset; do not use an unrelated production photo for a write test.
- PhotoKit authorization must grant full library access; limited access does not support the app's complete library and album workflows.
- First-time Ollama setup is still manual.
- First-time model download can take several minutes.
- The app expects the local `ollama` command to be available in common Homebrew-style locations.
- This is a personal hobby app with no support commitment, compatibility guarantee, or warranty beyond the project license.

## License

Photos Caption Assistant is released under the MIT License. See [LICENSE](LICENSE).

Copyright © 2026 Sidelark Labs ; John Kenneth Fisher
