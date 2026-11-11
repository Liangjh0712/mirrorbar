# AGENTS.md

Mirrorbar is a macOS menu bar app (SwiftPM, Swift 6, macOS 14+) that drives scrcpy.

- Build and install: `./scripts/build-app.sh --install`
- Logs: `~/Library/Logs/Mirrorbar/mirrorbar.log`
- Test without clicking: `open mirrorbar://start`, `open mirrorbar://back` and the other URLs in README

Skills in `.agents/skills/` (also linked from `.claude/skills/`):

- `pair-phone`: pair a new Android phone with this Mac, step by step, until mirroring works
