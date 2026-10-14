# Project instructions

## Implementation

- Inspect the repository before making changes; follow existing structure and conventions.
- Prefer native SwiftUI for the macOS interface.
- Keep scanner backend code separate from UI code.
- Initially integrate SANE through the `scanimage` command-line utility.
- Support a mock scanner backend for hardware-independent UI development and testing.
- Do not introduce Docker or unnecessary dependencies.
- Run appropriate builds and tests after code changes. Report what ran, results, and any checks that could not run.

## Safety and Git

- Never delete user files or initiate physical scans without explicit user approval.
- Do not commit or push changes without user approval.

## Two-computer workflow

- MacBook Air: UI development and testing with the mock scanner.
- Mac Studio: SANE integration and testing with the real USB scanner.
- Use GitHub to synchronize work between computers; keep machine-specific paths and local artifacts out of committed documentation.
- Before implementation, read `docs/PROJECT_STATE.md` and `docs/DECISIONS.md` alongside these instructions.

## Documentation maintenance

- Update `docs/PROJECT_STATE.md` at meaningful milestones and before switching computers. Include current progress, tasks, issues, latest build/test results, next steps, and hardware requirements.
- Update `docs/DECISIONS.md` when significant technical decisions are made or changed. Record rationale, trade-offs, and rejected alternatives only when supported by actual decisions.
- Update this file only when permanent project instructions change.
- Keep documentation concise, practical, and suitable for GitHub. Do not invent completed features, test results, or decisions, or copy entire conversation histories.
