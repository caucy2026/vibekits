# Remote Harness Command Channel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a controller submit, observe, wait for, and stop remote Harness conversations by device ID, with submission acknowledged within 3 seconds and the official remote chat remaining authoritative and visible, without screenshots or coordinate input.

**Architecture:** Add a process-local command broker between the app-level MCP bridge and the active `OfficialHarnessWorkspace`. The simulator continues to transport authenticated MCP calls; the target exposes narrow Harness session tools that enqueue through the existing official Web UI queue bridge and publish structured state. This reuses the official Harness conversation and approval behavior.

**Tech Stack:** Flutter/Dart, existing VibeKits MCP tool bridge, official DSH Web UI queue adapter, RustDesk simulator transport.

**Spec:** `docs/64_HARNESS_REMOTE_INTERACTION_CONTRACT.md`

## Global Constraints

- The official Harness conversation, model behavior, approval flow, and history remain authoritative.
- Submission must return accepted state and identifiers within 3 seconds.
- Remote control must not depend on screenshots, OCR, coordinates, shell access, or reading private DSH credentials.
- Existing simulator authentication and authorization remain unchanged.
- Running-session follow-up messages use the existing queue semantics.

## Review Focus

- No active Harness workspace returns an explicit unavailable error within 3 seconds.
- Empty prompts are rejected before dispatch.
- Concurrent submissions retain distinct request IDs and queue order.
- A busy or approval-waiting session accepts the prompt as queued without interrupting the official task.
- Workspace restart unregisters stale callbacks so commands cannot target a disposed WebView.

---

### Task 1: Process-local Harness command broker

**Files:**
- Create: `lib/features/dev_tools/domain/harness_command_broker.dart`
- Test: `test/harness_command_broker_test.dart`

**Interfaces:**
- Produces: `HarnessCommandBroker.register`, `unregister`, `prompt`, `status`, `history`, `waitForChange`, and `cancel`.
- Consumes: an active workspace callback returning structured workspace/session/request state.

- [ ] Write failing tests for prompt validation, unavailable state, registration lifetime, concurrent IDs, queued acceptance, cursor-based history, state-change waiting, timeout-without-failure, approval state, and cancellation terminal state.
- [ ] Run `flutter test test/harness_command_broker_test.dart` and confirm failures are caused by the missing broker.
- [ ] Implement the minimal broker with bounded three-second callback timeout and generation-safe unregister.
- [ ] Run the broker tests and confirm they pass.

### Task 2: Expose target-side Harness MCP tools

**Files:**
- Modify: `lib/features/dev_tools/domain/harness_tool_bridge.dart`
- Test: `test/harness_tool_bridge_test.dart`

**Interfaces:**
- Consumes: `HarnessCommandBroker.prompt` and `HarnessCommandBroker.status`.
- Produces: `vibekits.harness.session_prompt`, `vibekits.harness.session_status`, `vibekits.harness.session_history`, `vibekits.harness.session_wait`, and `vibekits.harness.session_cancel` in the executable catalog.

- [ ] Write failing catalog and invocation tests, including exact schemas, cursor handling, bounded wait timeout, terminal states, and unavailable errors.
- [ ] Run the focused tests and confirm the tools are absent.
- [ ] Add the two narrow tool definitions and handlers without changing existing Harness behavior.
- [ ] Run focused bridge tests and confirm they pass.

### Task 3: Bind the official Harness workspace

**Files:**
- Modify: `lib/features/local_models/presentation/official_harness_workspace.dart`
- Test: `test/deepseek_harness_test.dart`

**Interfaces:**
- Consumes: broker registration and existing `_messageQueue` / `_messageQueueScheduler`.
- Produces: visible official-chat enqueue acknowledgements plus authoritative state/history projections containing workspaceId, sessionId, requestId, state, approval, cursor, terminal result, and queue position.

- [ ] Write a failing widget test proving an MCP-origin prompt appears in the official queue and remains visible in the selected session.
- [ ] Run the focused widget test and confirm the missing registration causes failure.
- [ ] Register on workspace readiness, enqueue with `HarnessMessageSource.appMcp`, return within three seconds, publish busy/approval state, and unregister on dispose/restart.
- [ ] Run the focused widget and queue tests.

### Task 4: Build and real-device acceptance

**Files:**
- Modify: `docs/64_HARNESS_REMOTE_INTERACTION_CONTRACT.md`
- Modify: the existing release/change log used by the current development version.

**Interfaces:**
- Consumes: simulator connect/catalog/call/disconnect and the new target tools.
- Produces: repeatable evidence for device `4456560334`.

- [ ] Run formatting, static analysis, focused tests, and the project release gate using the ORICO build cache.
- [ ] Build and launch the local candidate without replacing a running signed release.
- [ ] Connect to `4456560334`, confirm the new tools appear, and submit the KOffice App Center task with `vibekits.simulator.call`.
- [ ] Verify acceptance in under three seconds, issue a follow-up while running, read structured status, and verify KOffice installation and launch.
- [ ] Record exact results and disconnect the simulator tunnel.
