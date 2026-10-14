# Project state

Last updated: 2026-10-14

## Objectives and intended architecture

Build a native macOS scanner utility with a SwiftUI interface and a separate scanner backend. Initially, the real backend will invoke SANE's `scanimage` utility; a mock backend will support development without scanner hardware.

Use the MacBook Air for UI development and mock testing, the Mac Studio for real USB scanner integration, and GitHub to synchronize work.

## Current implementation

- Initial inspection found only Git metadata: no source files, Xcode project, Swift package, tests, or existing documentation.
- These project instructions, status notes, and decision records establish the initial documentation baseline.
- No application features or scanner backends are implemented.
- Git has no local commits. An `origin` remote is configured; GitHub synchronization has not been verified. The local `origin/main` tracking reference is unavailable.

## Current tasks and known issues

- Choose the initial project layout and build/test setup, then create the application scaffold.
- Define the boundary between the UI and scanner backends and implement mock behavior for initial UI work.
- Identify the USB scanner model and verify SANE compatibility on the Mac Studio.
- Build tooling, SANE installation, scanner access, and GitHub synchronization remain unverified.
- No implementation defects are known because application development has not started.

## Latest validation

- Repository inspection completed on 2026-10-14.
- Documentation formatting checks passed for all three files (trailing whitespace and final newlines).
- Application build: not run; no buildable project exists.
- Automated tests: not run; no test target or suite exists.
- Hardware tests: not run; no physical scan initiated.

## Next recommended steps

1. Review the documentation baseline before implementing features.
2. Create the macOS SwiftUI application scaffold and establish a reproducible build command.
3. Add a separate scanner interface and mock backend, then connect the initial UI to the mock.
4. On the Mac Studio, verify `scanimage` availability and scanner compatibility, then implement the real backend. Obtain approval before any physical scan.
5. Record build/test results at each meaningful milestone and refresh this file before switching computers. Commit and push only with approval.

## Hardware-specific requirements

| Computer | Development requirements |
| --- | --- |
| MacBook Air | macOS and appropriate Swift/Xcode tooling; mock backend must work without SANE or a connected scanner. |
| Mac Studio | macOS and appropriate Swift/Xcode tooling; SANE with `scanimage`, a compatible SANE backend, and access to the real USB scanner. |

Scanner model, minimum macOS version, Xcode version, SANE installation method, and executable discovery strategy are not yet established. Record shared requirements here when verified; keep local paths and device identifiers out of committed documentation.
