# Technical decisions

Record only decisions that have actually been made. Add dated entries for significant changes, including rationale, trade-offs, and any alternatives explicitly rejected. If a decision changes, mark the earlier entry as superseded and link its replacement.

## 2026-10-14 — Native SwiftUI interface and separate scanner backend

**Decision:** Prefer native SwiftUI for the macOS interface and keep scanner backend code separate from UI code.

**Rationale:** This follows the project's native macOS objective and lets UI development proceed independently of hardware integration.

**Trade-off:** A shared backend boundary must be defined and maintained. Its concrete API and project layout have not been decided.

## 2026-10-14 — Initial SANE integration through `scanimage`

**Decision:** Initially use the SANE `scanimage` command-line utility for the real scanner backend.

**Rationale:** This establishes a concrete first integration path for SANE.

**Trade-off:** The app will need executable discovery, process execution, output/error handling, and a local SANE installation. Direct SANE library integration is deferred; no permanent rejection has been made.

## 2026-10-14 — Mock backend and two-computer development

**Decision:** Support a mock scanner backend on the MacBook Air and use the Mac Studio for real USB scanner development and testing. Synchronize work through GitHub.

**Rationale:** UI development and testing must remain possible without scanner hardware.

**Trade-off:** Mock behavior must stay aligned with the shared backend interface, and real hardware behavior must be validated separately on the Mac Studio.

## 2026-10-14 — Dependency constraints

**Decision:** Do not introduce Docker or unnecessary dependencies.

**Rationale:** Keep setup focused on the native macOS application and its required SANE integration across both computers.

**Rejected alternative:** Docker-based development is excluded by the project requirements. Specific additional libraries have not been evaluated or rejected.
