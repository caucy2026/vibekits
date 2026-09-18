# Harness Context Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add clean context-continuation sessions and F1–F12 visible-session focus switching around the unmodified official Harness runtime.

**Architecture:** VibeKits owns a small versioned continuation relation store and exposes host bridge actions while the official Harness remains unchanged. The injected workspace UX script handles visible-row keyboard selection and forwards continuation requests to Flutter; the host adapter performs summary, blank-session creation, relationship persistence, and bounded source lookup.

**Tech Stack:** Flutter/Dart, JavaScript WebView bridge, package:test/flutter_test, official Harness HTTP/WebSocket adapter

**Spec:** `docs/superpowers/specs/2026-09-19-harness-context-continuation-design.md`

## Global Constraints

- Do not patch, replace, or change official Harness runtime or inference behavior.
- A continuation starts with an empty visible chat timeline.
- Persist source relationships separately with schema version 1 and bounded summaries.
- F1–F12 map to the first twelve currently visible sidebar sessions and do nothing during IME composition.
- Source lookup is read-only, direct-source-only, workspace-scoped, bounded, and redacted.

---

### Task 1: Continuation Relation Store

**Files:**
- Create: `lib/features/dev_tools/domain/harness_continuation_store.dart`
- Test: `test/harness_continuation_store_test.dart`

**Interfaces:**
- Produces: `HarnessContinuationRecord`, `HarnessContinuationStore.load/save/upsert/removeWorkspace`, and direct source/children lookup.

- [ ] **Step 1: Write failing tests** for JSON round trips, missing/corrupt files, summary length rejection, direct relationship lookup, and retained broken links.
- [ ] **Step 2: Run** `flutter test test/harness_continuation_store_test.dart` and confirm failure because the store does not exist.
- [ ] **Step 3: Implement** schema-version validation, normalized workspace keys, atomic JSON persistence, bounded fields, and deterministic relationship queries.
- [ ] **Step 4: Run the test again** and confirm all cases pass.

### Task 2: Visible Session Function-Key Switching

**Files:**
- Modify: `assets/harness/codex_conversation_ux.js`
- Modify: `lib/features/local_models/presentation/official_harness_workspace.dart`
- Modify: `lib/features/local_models/presentation/deepseek_agent_workspace.dart`
- Test: `test/harness_conversation_ux_contract_test.dart`
- Test: `test/deepseek_harness_test.dart`

**Interfaces:**
- Produces: F1–F12 mapping to visible session rows, composer focus after selection, and `vibekits.sessionShortcutMissing` feedback.

- [ ] **Step 1: Add failing contract/widget tests** covering all twelve keys, filtered/collapsed visibility, missing positions, modifier keys, and `event.isComposing`.
- [ ] **Step 2: Run both focused tests** and confirm the new assertions fail.
- [ ] **Step 3: Implement the WebView key handler** using rendered, non-workspace tree items in DOM order; click the target and focus the visible composer.
- [ ] **Step 4: Implement equivalent fallback Flutter shortcuts** over the displayed session order and preserve each session's state.
- [ ] **Step 5: Run both focused tests** and confirm they pass.

### Task 3: Context Summary and Blank Continuation Creation

**Files:**
- Modify: `lib/features/dev_tools/domain/harness_official_remote_adapter.dart`
- Modify: `lib/features/local_models/presentation/harness_webview_bridge.dart`
- Modify: `lib/features/local_models/presentation/official_harness_workspace.dart`
- Modify: `assets/harness/codex_conversation_ux.js`
- Test: `test/harness_remote_adapter_test.dart`
- Test: `test/harness_conversation_ux_contract_test.dart`

**Interfaces:**
- Consumes: `HarnessContinuationStore.upsert`.
- Produces: structured-summary validation, official blank session creation, first-request handoff attachment, cancellation, and rollback for persistence failure.

- [ ] **Step 1: Add failing adapter tests** with a fake Harness service for summary completion, invalid/cancelled summary, blank session creation, first-request context, and rollback.
- [ ] **Step 2: Run the focused tests** and confirm missing adapter methods fail.
- [ ] **Step 3: Add the right-click bridge action** labelled `整理上下文并继续`, disabled for active sessions, with progress and cancellation messages.
- [ ] **Step 4: Implement adapter orchestration** in the required order: summarize, validate, create empty session, atomically save relation, select the child; delete an empty child if persistence fails.
- [ ] **Step 5: Run the focused tests** and confirm visible user history stays empty while the first execution receives the bounded handoff.

### Task 4: Source Navigation and Bounded Lookup

**Files:**
- Create: `lib/features/dev_tools/domain/harness_source_context_service.dart`
- Modify: `lib/features/local_models/presentation/official_harness_workspace.dart`
- Modify: `assets/harness/codex_conversation_ux.js`
- Test: `test/harness_source_context_service_test.dart`
- Test: `test/harness_conversation_ux_contract_test.dart`

**Interfaces:**
- Consumes: direct relationship records and official session snapshots.
- Produces: `querySourceContext(currentSessionId, query, beforeCursor, afterCursor, limit)`, source card navigation, and source-to-child menu entries.

- [ ] **Step 1: Add failing tests** for direct-source resolution, cursor windows, redaction, length limits, missing source, and cross-workspace denial.
- [ ] **Step 2: Run the tests** and confirm the service is absent.
- [ ] **Step 3: Implement the read-only service** and emit a visible tool-activity event for each successful source read.
- [ ] **Step 4: Add source/child navigation UI** including deleted-link text and multiple-child selection.
- [ ] **Step 5: Run the focused tests** and confirm all source boundaries hold.

### Task 5: Release Verification and Commit

**Files:**
- Verify: all files above

**Interfaces:**
- Produces: a reviewed commit on the current branch.

- [ ] **Step 1: Run focused tests** for continuation storage, remote adapter, source lookup, JavaScript contracts, and fallback workspace behavior.
- [ ] **Step 2: Run existing official-runtime integrity tests** and confirm bundled official files remain byte-for-byte unmodified.
- [ ] **Step 3: Run `flutter analyze`** and resolve only diagnostics introduced by this change.
- [ ] **Step 4: Inspect `git diff --check` and `git status --short`**, excluding existing untracked build artifacts.
- [ ] **Step 5: Commit the related source, tests, spec, and plan** with a single feature commit after all checks pass.
