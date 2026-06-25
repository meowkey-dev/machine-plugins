# Changelog

All notable changes to the mesh-channel plugin are documented in this file.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [0.1.2] - 2026-05-26
### Documentation
- OSS-readiness redaction: replaced an internal agent codename with a neutral `worker` example in the README and SKILL (no behavior change).

## [0.1.1] - 2026-05-24
### Added
- CHANGELOG.md (this file); version-bump convention note in README.

## [0.1.0] - 2026-05-15
### Added
- Initial plugin: shared JSONL file, append-only protocol, per-agent cursor, self-filter; Monitor-driven wake (no polling).
- `mesh-channel-send` and `mesh-channel-watch` commands.
### Changed
- Clarified controller-asymmetric comms overlap in docs (2026-05-22).
