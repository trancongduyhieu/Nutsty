# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

Note: Nutsty is a native desktop app (Qt 6 / QML through Quickshell on Linux Wayland, PySide6 on Windows), not a website. It is recorded as `web` because it has one design language of its own, identical on Linux and Windows, and does not follow either OS's native look. Web-only advice (CSS, browsers, breakpoints, SEO) does not apply. The QML equivalents do.

## Users

The primary users are the maintainer and a small group of Vietnamese friends. Some run Linux Wayland (Niri on CachyOS), others run Windows 10/11. They use Nutsty as their everyday music player on their own computers and listen together across the two platforms. Feature requests and bug reports from this group are tracked under the `from-friends` GitHub label.

## Product Purpose

Nutsty is a desktop music player. It plays local files from `~/Music` and streams YouTube Music, and it can import Spotify playlists. Friends can listen to the same track at the same moment wherever they are. Success means the group picks Nutsty over Spotify or the YT Music website for daily listening, and listening together feels instant on both Linux and Windows.

## Positioning

Three things together, which neighbouring players do not offer as one package:

- **Listening with friends**: Listen Along keeps a friend's machine in step with yours between Linux and Windows. It also has 24-hour notes with a song attached, floating chat bubbles while listening, and invites.
- **Colour taken from the wallpaper**: the interface takes its accent colour from the desktop wallpaper and the album cover (OKLAB/OKLCH chromatic salience), so it looks like part of the user's desktop.
- **Free, with no ads**: YouTube Music streaming, Spotify playlist import and the local library, with no subscription and no ads.

## Operating Context

- It runs as a resident desktop app next to whatever else the user is doing. On Windows it has a system tray icon with "Open Full" and "Quit". On Linux it can show a Wayland layer-shell overlay.
- A Desktop Lyrics overlay and a 216x216 mini widget sit on the desktop outside the main window.
- The social layer (identity, friends, notes, Listen Along) runs on Cloudflare Workers + D1 over HTTPS.
- Settings and user data live in `~/.config/noctalia` with a per-profile suffix, outside the install folder, so reinstalling keeps them.
- Release notes come from `CHANGELOG.md` and are shown in the app's What's New modal in plain user language.

## Capabilities and Constraints

- **Dual-platform parity is mandatory.** Every feature must work on Linux Wayland and on Windows (`launcher_win.py` + `compat/Quickshell`). Any Quickshell API used in QML must also exist in the compat layer.
- **Strict bilingual UI.** Every visible string goes through `I18n.tr("Tiếng Việt", "English")`. Vietnamese mode is 100% Vietnamese and English mode is 100% English, with no mixing.
- **No hardcoded user paths.** Use `Quickshell.env("HOME")` or `pathlib.Path.home()`.
- **Lite mode** turns off whole-window redraw effects on machines without a GPU. New visual effects must respect it.
- **Status bar is out of scope.** Waybar and Noctalia status bar work belongs to the `noctalia-shell` repo, not Nutsty.
- **Roadmap, ideas and bugs live only in GitHub Issues**, never in a TODO file.
- **Decided:** a listener card and listening recap like Mochy (issue #5), counting a play at 30 seconds or more.
- **Open:** whether Nutsty is ever distributed beyond the friend group.

## Brand Commitments

- The name is **Nutsty**. The repository folder is still called FrostifyLocal.
- Vietnamese is the primary voice and English is a full equal. The in-app tone is friendly and playful where it fits, for example funny welcome greetings.
- User-facing copy avoids programming jargon (see the WhatsNew rules in `.agents/rules/04-code-recipes-and-patterns.md`).
- License: MIT.

## Evidence on Hand

- Feature history: `CHANGELOG.md` (current release 2.2.0, 2026-11-18).
- Domain language: `CONTEXT.md`, `GLOSSARY.md`.
- Architecture and footguns: `AGENTS.md`, `.agents/rules/`.
- Design reference app: `references/Mochy-Music/` (Kotlin/Compose). It is studied for patterns and never copied.
- None exist: no public user base, testimonials, download counts or press. Do not invent them.

## Product Principles

1. **Together first.** Features that make listening with friends feel live and personal beat solo power-user features.
2. **Same experience on both platforms.** A feature that only works on one OS is unfinished.
3. **It belongs to the user's desktop.** Colour, overlays and widgets adapt to the user's wallpaper and setup instead of imposing a fixed brand look.
4. **Free and honest.** No ads, no paywalls, and notifications only claim what really happened (a change is reported as saved only once it is saved).
5. **Light machines matter.** Effects degrade gracefully through Lite mode so friends on weak laptops can still use it.
