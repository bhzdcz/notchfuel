# TopNotch AI

A small native macOS notch app that shows how much AI usage is used or remaining beside the MacBook camera cutout for:

- Anthropic / Claude Code
- OpenAI / Codex
- Grok CLI

The idle island hugs the top-center camera notch. Move the pointer onto it and it smoothly expands downward to reveal the detailed usage panel; move away and it collapses after a short delay. It reuses the sessions maintained by the official command-line tools. Credentials are read-only, stay on the Mac, and are never logged or copied into TopNotch AI storage.

## Requirements

- Apple-silicon Mac
- macOS 14 or newer
- At least one supported CLI installed and signed in

## Build and test

```sh
swift test
./scripts/build-release.sh
```

The release script produces:

- `build/TopNotch AI.app`
- `release/TopNotchAI-1.2.0-arm64.dmg`

The local build is ad-hoc signed. A public internet release should be signed with an Apple Developer ID and notarized.

## Privacy

TopNotch AI makes read-only HTTPS usage requests to the same provider services used by the installed CLIs. It has no analytics, account system, or background server. Anthropic credentials are read from macOS Keychain; Codex and Grok credentials are read from their local auth files. TopNotch AI does not refresh or modify any provider credential.

## Acknowledgement

The provider endpoint and response-shape research was informed by Jaco Veldsman's MIT-licensed [usage-monitor](https://github.com/jackfieldman/usage-monitor). See `THIRD_PARTY_NOTICES.md`.
