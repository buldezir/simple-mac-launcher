# Simple Launcher

A minimal Alfred/Sol-style macOS launcher built with native SwiftUI.

## Features

- **App launcher** — fuzzy search installed apps, open with Return or ⌘1–⌘9
- **Calculator** — math in the search field, including percentages (`100-20%` → `80`)
- **Ask AI** — OpenAI-compatible chat, or a local Codex, Claude, Cursor Agent, or OpenCode CLI. Trigger with `?` / `ask `, or as a fallback when nothing matches. Optional [Tavily](https://tavily.com) web search when the API provider is selected and a key is set
- **Launch at login** — optional startup via Settings

## Screenshots

<p align="center">
  <img src="docs/screenshots/01-empty.png" alt="Empty launcher" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/02-apps-app.png" alt="App search for app" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/02-apps-dis.png" alt="App search for dis" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/02-apps-tab.png" alt="App search for tab" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/03-calc.png" alt="Calculator result" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/04-ask.png" alt="Ask AI fallback result" width="640" />
</p>

<p align="center">
  <img src="docs/screenshots/05-ask-answer.png" alt="Ask AI answer" width="640" />
</p>

## Requirements

- macOS 14+ (Apple Silicon)
- Xcode 15+

## Download & install

Download `SimpleLauncher-macOS-arm64.zip` from [GitHub Releases](https://github.com/buldezir/simple-mac-launcher/releases), extract it, and drag `SimpleLauncher.app` into `/Applications` before you open it.

Release downloads require macOS 14+ on Apple Silicon; Xcode is only needed to build from source. The app is signed with Developer ID and notarized by Apple, and updates itself: **Check for Updates…** is in the menu bar menu and in Settings, which also turns the daily checks and automatic installs on and off. If it says it can't be updated, it is running from the temporary copy macOS makes of an app opened where it was downloaded: quit it and run `xattr -dr com.apple.quarantine /Applications/SimpleLauncher.app`.

## Build & run

```sh
./build.sh
```

Builds a Debug app under `build/DerivedData/`.

Pass `Release` to build and install to `/Applications`:

```sh
./build.sh Release
```

Or open in Xcode:

```sh
open SimpleLauncher.xcodeproj
```

Select the **SimpleLauncher** scheme and press Run.

The app runs as a menu bar accessory (no Dock icon).

## Usage

| Action | How |
| --- | --- |
| Toggle launcher | **⌥ Space** (Alt+Space), or menu bar → Show Launcher |
| Launch app | Type name → Return / click / ⌘1–⌘9 |
| Calculate | Type `100-20%` → Return copies result |
| Ask AI (prefix) | `? your question` or `ask your question` → Return to send |
| Ask AI (fallback) | Type something with no app matches → select Ask AI |
| Browse AI history | `/h`, optionally `/h filter` |
| Delete a history entry | **⌘⌫** on the highlighted entry, or hover → trash |
| Settings | Menu bar → Settings…, or **⌘,** |
| Launch at login | Settings → Launch at login |
| Dismiss | Esc or click outside (focus returns to the previous app) |

### Ask AI settings

In Settings, choose a **Provider**.

**API** — OpenAI-compatible Chat Completions:

1. **Endpoint** — e.g. `https://api.openai.com/v1` or `https://opencode.ai/zen/go/v1/chat/completions`
2. **API key** — stored in UserDefaults (personal use; no Keychain prompts)
3. **Model name** — e.g. `deepseek-v4-flash` (tool calling required for web search)
4. **Tavily API key** (optional) — enables `web_search` and `web_fetch`; free tier at [tavily.com](https://tavily.com)

Requests go to `{endpoint}/chat/completions` (OpenAI-compatible streaming). When Tavily is configured, Ask AI may call `web_search` / `web_fetch` (up to a few rounds) before answering.

**Codex, Claude, Cursor Agent, or OpenCode** — runs the CLI already installed on this Mac (`codex`, `claude`, `cursor-agent`, or `opencode`) and uses that CLI’s login (`codex login`, `claude auth login`, `cursor-agent login`, or `opencode auth login`). No API key in the launcher. Off by default, the CLI stays read-only. **Auto mode** lets it edit files and run commands in your home folder. Optional **Model** and **Executable** override the CLI default and the auto-detected binary (Homebrew, `~/.local/bin`, `~/.opencode/bin`, then your login PATH). Settings shows an error when the selected CLI is not installed.

AI answers appear in an inline markdown pane under the search field. **Return** copies the plain-text answer; **Esc** exits answer mode.

## Notes

- App Sandbox is off so the launcher can open apps and call custom AI endpoints.
- If Alt+Space does not work, another app may already own that hotkey (e.g. Spotlight alternatives).

## Releases

`.github/workflows/release.yml` runs on `v*` tags, such as the one a release published on GitHub creates, on the `xcode-27` runner:

- It builds SimpleLauncher in Release, arm64 only. The tag sets `MARKETING_VERSION`, and `CURRENT_PROJECT_VERSION`, a build number that only grows (`1.2.0-beta.2` → 1020002, `1.2.0` → 1020099), which Sparkle compares. A local build is version `0.1`, and doesn't update.
- It signs the app with the Developer ID certificate in the repository's secrets, then notarizes it with an App Store Connect API key and staples it. `scripts/sign-sparkle.sh`, the target's last build phase, signs Sparkle's helpers with Developer ID, as notarization requires.
- `scripts/appcast.sh` writes the app's [Sparkle](https://sparkle-project.org) feed, `SimpleLauncher-macOS-appcast.xml`: the zip's EdDSA signature (`SPARKLE_PRIVATE_KEY`, checked against the app's `SUPublicEDKey`) and the release's notes up to its `## Downloads`, if the release is written by then. The release job uploads `SimpleLauncher-macOS-arm64.zip` and `SHA256SUMS`, then the feed, which the app's `SUFeedURL` reads from the latest release.
- A tag without the secrets fails. A run by hand without them signs ad hoc and keeps the zip as a run artifact. An ad hoc build has no hardened runtime, under which it couldn't load Sparkle.framework (`HARDENED_RUNTIME_WITHOUT_TEAM` in the project). A run by hand takes a `version`, such as `1.1.0-test.1`, to build an app that offers and takes updates, and a `bundle_id`, such as `com.sasha.simplelauncher.updatetest`, to keep it apart from the installed one.

Signing takes a Developer ID Application certificate, exported from Keychain Access as a `.p12`, and notarization an App Store Connect API key (Users and Access › Integrations › Team Keys, with Developer access). Sparkle installs only updates signed with the key whose public half is `SPARKLE_PUBLIC_KEY` in the project's build settings. Its private half is in the login keychain of the Mac that made it, and in the repository's secrets; keep a backup, since without it the app can never update again:

```sh
base64 -i DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set APPLE_TEAM_ID              # from developer.apple.com › Membership details
base64 -i AuthKey_<KEYID>.p8 | gh secret set NOTARY_API_KEY_BASE64
gh secret set NOTARY_API_KEY_ID
gh secret set NOTARY_API_ISSUER_ID

mkdir -p ~/sparkle && curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz | tar -xf - -C ~/sparkle
~/sparkle/bin/generate_keys --account simple-mac-launcher         # prints the public key
~/sparkle/bin/generate_keys --account simple-mac-launcher -x ~/sparkle/private-key
gh secret set SPARKLE_PRIVATE_KEY < ~/sparkle/private-key
```
