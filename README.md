# TelegramPlay (iOS)

Sign in with Telegram (TDLib), open a chat, and play videos with **MPVKit** (libmpv + Metal).

## Requirements

- Mac with **Xcode 15+**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Telegram **API ID** and **API hash** from [my.telegram.org](https://my.telegram.org/apps)

## Setup

1. Copy API credentials:
   ```bash
   cp Config/Secrets.xcconfig.example Config/Secrets.xcconfig
   ```
   Edit `Config/Secrets.xcconfig` with your `TELEGRAM_API_ID` and `TELEGRAM_API_HASH`.

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   open TelegramPlay.xcodeproj
   ```

3. In Xcode, set your **Development Team** for signing.

4. Build and run on a device or simulator (first SPM resolve downloads TDLib + MPV binaries; can take several minutes).

## Usage

1. Enter your phone number and Telegram login code (and 2FA password if enabled).
2. Pick a chat from the list.
3. Tap a video, animation, or video document — the file is downloaded via TDLib and played in MPV.

## Architecture

| Layer | Library |
|--------|---------|
| Telegram account, chats, file download | [TDLibKit](https://github.com/Swiftgram/TDLibKit) |
| Playback (H.264/H.265, subtitles, HDR) | [MPVKit](https://github.com/mpvkit/MPVKit) |

Telegram does not expose plain HTTP URLs for chat files; TDLib writes a local path as the file downloads, which MPV opens with `loadfile`.

## Cache (2 GB limit)

Downloaded media is stored by TDLib under Application Support (`TelegramPlay/files/`). The app enforces a **2 GB cap** on that file cache:

- **Automatic:** When usage exceeds 2 GB, TDLib `optimizeStorage` trims eligible files back under the limit (after login, when returning to the app, and after starting playback). TDLib’s `use_storage_optimizer` option is enabled for a daily background pass.
- **Manual:** Open **Cache** from the gear icon on the chat list to see usage and tap **Clean up now** to clear eligible downloaded media immediately.
- **While playing:** Cleanup is deferred and the current chat is excluded from automatic trimming when possible.

The **message database** (chat history metadata) is separate and is **not** limited to 2 GB by TDLib.

## Notes

- This is a minimal client for learning and personal use, not a full Telegram replacement.
- Respect Telegram’s [Terms of Service](https://telegram.org/tos) and API rules for third-party apps.
- For HDR test streams, disable **Metal API Validation** in the Xcode scheme if the player crashes (see MPVKit demo notes).

## License

App source: MIT-style use for your project. **MPVKit** is LGPL; **TDLib** has its own license — review before App Store distribution.
