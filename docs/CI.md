# GitHub Actions: unsigned IPA

Build a **unsigned** Release IPA on GitHub’s macOS runners—no Mac required. Install with **SideStore** (re-signs with your Apple ID) or **LiveContainer** (import IPA into the container).

## Repository secrets

In **Settings → Secrets and variables → Actions**, add:

| Secret | Source |
|--------|--------|
| `TELEGRAM_API_ID` | [my.telegram.org/apps](https://my.telegram.org/apps) |
| `TELEGRAM_API_HASH` | Same |

No Apple certificates or provisioning profiles are stored in GitHub.

## Run the workflow

1. Push this repo to GitHub (or use an existing remote).
2. Open **Actions → Build unsigned IPA**.
3. Click **Run workflow** (or push to `main` / `Stitch-stream`).
4. When the job finishes, open the run and download the **TelegramPlay-unsigned-ipa** artifact (`TelegramPlay-unsigned.ipa`).

First runs are slow while Swift Package Manager resolves **MPVKit** and **TDLibKit**. Later runs use caches for SPM, DerivedData, and Homebrew when possible.

## Install with SideStore

1. Copy `TelegramPlay-unsigned.ipa` to your iPhone (AirDrop, Files, etc.).
2. Open the IPA in **SideStore** and install.
3. SideStore **re-signs** the app with the Apple ID linked to SideStore.

With a **free** Apple Developer (Personal Team) account, sideloaded apps typically expire after **7 days** and need refresh via SideStore.

## Install with LiveContainer

1. Install [LiveContainer](https://github.com/LiveContainer/LiveContainer) on your device (per that project’s instructions).
2. Import `TelegramPlay-unsigned.ipa` (e.g. **+** or **Import** in LiveContainer).
3. Launch TelegramPlay from inside LiveContainer.

Behavior depends on LiveContainer and iOS versions; unsigned CI builds are the intended input.

## Local packaging (optional)

On macOS, after a local unsigned build:

```bash
ci/package-unsigned-ipa.sh path/to/Build/Products/Release-iphoneos/TelegramPlay.app
```

## If the workflow fails on code signing

The workflow builds with:

- `CODE_SIGNING_ALLOWED=NO`
- `CODE_SIGNING_REQUIRED=NO`

If `xcodebuild` still fails (sometimes due to embedded XCFrameworks), check the job log. You may need extra build settings in the workflow or in `project.yml` for CI-only unsigned builds.

## Limits

- Not for App Store distribution.
- Telegram API rules and Terms of Service still apply.
- MPVKit (LGPL) and TDLib licenses apply to redistribution.
