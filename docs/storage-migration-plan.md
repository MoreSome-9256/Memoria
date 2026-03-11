# Storage Migration Plan (Isar -> SQLite)

## Why Migrate

Current blockers in this project:

- `isar 3.1.0+1` pulls `js 0.6.7` (discontinued).
- `isar_generator 3.1.0+1` is pinned to old `build` ecosystem and blocks modern generator stack.
- Domain model methods currently know too much about Isar query details.

Goal: remove dependency on discontinued packages and reduce vendor lock-in with a controlled migration.

## Target Stack

Recommended target: SQLite with `sqlite3` + `sqlite3_flutter_libs` (no codegen required).

Why this stack:

- Mature, actively maintained, and widely audited ecosystem.
- Works on Android/iOS/macOS/Linux/Windows.
- Avoids build-runner coupling for database schema.
- SQL is explicit and easy to inspect and migrate.

## Current Refactor Status

Completed in this commit:

- Added query port abstraction: `lib/storage/event_photo_query_port.dart`.
- Added Isar adapter: `lib/storage/isar_event_photo_query_port.dart`.
- `EventEntity.toUIModel(...)` now depends on query port instead of Isar runtime type.
- `AlbumPage` call site switched to adapter.

This is the first anti-corruption layer to enable backend replacement without touching UI/domain logic repeatedly.

## Phased Migration

### Phase 1: Expand Ports (1-2 days)

- Add ports for event/story/photo read/write operations used by services.
- Keep Isar adapters as default implementation.
- Replace direct Isar calls in service layer with ports incrementally.

Exit criteria:

- New code paths do not import `package:isar/isar.dart` outside adapter module.

### Phase 2: Introduce SQLite Store (2-4 days)

- Add `lib/storage/sqlite/` with:
  - schema bootstrap SQL
  - repository implementations for ports
  - transaction helper
- Keep entity classes unchanged first; map rows <-> entities in adapter.

Exit criteria:

- End-to-end read path (home/album/event list) works from SQLite backend behind feature flag.

### Phase 3: Dual-Write + Read Validation (2-3 days)

- During mutation operations, write to Isar and SQLite.
- Read from Isar as source-of-truth, compare sampled reads from SQLite in debug logs.
- Add consistency counters (record count, checksum by updatedAt/time bucket).

Exit criteria:

- Consistency mismatch rate near 0 in real user scenarios.

### Phase 4: Cutover (1 day)

- Switch read source to SQLite.
- Keep one release with fallback toggle to Isar.
- Remove Isar dependencies only after rollback window.

Exit criteria:

- No blocking bug after one stable release cycle.

### Phase 5: Cleanup (0.5-1 day)

- Remove Isar package and generated files.
- Delete legacy adapters.
- Run `flutter pub outdated` and confirm no discontinued DB transitive deps remain.

## Risk Controls

- Keep migration idempotent with schema versioning.
- Never do destructive migration without backup/export.
- Add startup integrity checks:
  - critical table exists
  - expected columns exist
  - key indexes created
- Add kill-switch via env flag for rapid rollback.

## Immediate Next Step

Implement `PhotoReadPort` and refactor one heavy service (`EventService`) to use the port end-to-end, while still backed by Isar adapter.
