# Build And Verification Policy

Do not run production, release, archive, App Store, TestFlight, EAS, or full app builds unless the user explicitly asks for that exact build in the current chat.

Allowed: lightweight compile, type-check, lint, and test commands needed to verify changes. iOS debug target compile checks must not create release/archive artifacts.

`scripts/check.sh` only type-checks application sources and compiles/runs an isolated test executable. `scripts/build-app.sh` creates a complete development app and requires an explicit user request before execution.
