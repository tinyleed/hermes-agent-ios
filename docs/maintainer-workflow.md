# Maintainer workflow

Hermes Agent iOS uses a small-slice workflow inspired by `NousResearch/hermes-agent`: issues define intent, PRs carry proof, CI is the merge gate, and security-sensitive work gets called out explicitly.

## Labels

Use labels as routing metadata, not decoration.

### Type

- `type/bug` — something is broken.
- `type/feature` — new capability or user-facing improvement.
- `type/docs` — documentation only.
- `type/test` — tests, fixtures, or verification infrastructure.
- `type/refactor` — restructuring without behavior change.
- `type/security` — vulnerability fix or hardening.
- `type/task` — maintainer/autonomous-agent work item.
- `type/dependencies` — dependency or GitHub Actions update.

### Component

- `comp/app` — SwiftUI app shell.
- `comp/core` — `HermesAgentCore` contracts/runtime.
- `comp/gateway` — gateway/WebSocket integration.
- `comp/fixtures` — mock gateway, schemas, deterministic fixtures.
- `comp/ios-native` — App Intents, Share Extension, Live Activity, notifications.
- `comp/device` — physical-device bootstrap, signing, install scripts.
- `comp/docs` — README/docs/project metadata.
- `comp/ci` — CI, repo automation, workflows.
- `comp/github-actions` — GitHub Actions dependencies/workflows.

### Priority / state

- `P0` — critical: secret exposure, data loss, unsafe approval behavior.
- `P1` — high: core workflow broken with no good workaround.
- `P2` — medium: degraded but workaround exists.
- `P3` — low: polish or nice-to-have.
- `needs-triage` — needs routing/priority.
- `needs-repro` — bug needs a minimal reproduction.
- `good first issue` — small, safe, contributor-friendly.

## Issue-first rule

Create an issue first for any non-trivial change. A good issue includes:

1. desired outcome;
2. scope and non-scope;
3. likely files;
4. required verification;
5. risk/escalation boundary.

Tiny documentation fixes can go straight to PR.

## PR rule

Every PR should include:

- what changed and why;
- related issue;
- type of change;
- exact verification commands/output;
- security/privacy checklist;
- screenshots/logs for UI, landing page, simulator, or device behavior when useful.

## Autonomous-agent slice pattern

When handing work to an agent, use this brief:

```md
Goal:
Scope:
Files likely relevant:
Do not touch:
Verification required:
Escalate if:
Return only:
- changed files
- commands run
- verification result
- blocker/risk
```

Default verification:

```zsh
git diff --check
./scripts/test_all.sh
```

Use narrower checks while developing, but run the full gate before merge unless the change is docs-only and clearly cannot affect code.

## Safety boundaries

Stop and ask before:

- changing repository visibility;
- changing signing/team/device settings;
- adding secrets or live gateway credentials;
- weakening approval/sudo/secret redaction;
- broad rewrites of bootstrap/deep-link/APNs behavior;
- merging changes when CI is red.

## Dependabot posture

Dependabot is enabled for GitHub Actions only. Source dependency bumps remain manual because the project is early-stage and should keep lockfile/source changes deliberate.
