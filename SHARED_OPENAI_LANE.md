# Shared OpenAI API Lane

This repository may use a separate OpenAI API project with data sharing enabled **only** for low-risk Hermes Agent iOS eval/scout workloads.

The goal is to use OpenAI's complimentary shared-traffic quota without letting private Hermes Agent context leak into a training/data-sharing lane.

## Status

- Mode: opt-in, isolated, synthetic-first.
- Intended project name: `hermes-agent-ios-shared-evals`.
- API key env var: `OPENAI_SHARED_EVALS_API_KEY`.
- Required runtime guard: `HERMES_AGENT_SHARED_OPENAI_ALLOW=synthetic-only`.
- This lane must not be configured as the main Hermes provider.

## Hard rule

The shared OpenAI lane may only receive data that is safe to share with OpenAI for service/model improvement.

Default answer is **no** unless the payload fits one of the allowed categories below.

## Allowed data

Use this lane for:

- synthetic Hermes gateway event fixtures;
- synthetic approval/clarify/sudo/secret request objects with fake values;
- generated or hand-written fake session lists and resume payloads;
- non-sensitive issue-scout scoring based on GitHub issue titles/numbers and repo rail summaries;
- public-ish repo documentation excerpts that contain no secrets, personal notes, or private transcripts;
- test-output summaries with tokens, URLs, paths, and user data removed;
- UI-copy safety checks where all examples are synthetic.

## Forbidden data

Never send any of this to the shared lane:

- live Hermes Agent chat transcripts;
- Hermes memory or user profile contents;
- Obsidian vault notes, except a deliberately sanitized short excerpt copied for a specific non-sensitive purpose;
- emails, calendar entries, reminders, contacts, screenshots, or personal files;
- API keys, bearer tokens, dashboard session tokens, SSH keys, cookies, auth headers, or signed URLs;
- raw gateway WebSocket URLs containing tokens;
- full terminal logs that may contain environment variables or secrets;
- raw user messages unless the maintainer explicitly marks the exact text as share-safe;
- any payload copied from a third party, customer, private repo, or private service unless explicitly sanitized.

## Decision checklist

Before using `OPENAI_SHARED_EVALS_API_KEY`, answer all questions:

1. Is this payload synthetic or deliberately sanitized?
2. Would it be acceptable if OpenAI retained it for model/service improvement?
3. Does it avoid private Hermes memory, Obsidian notes, live chats, credentials, and screenshots?
4. Can the task be solved without sending private context?
5. Is the lane being used for eval/scoring/fixture generation, not main Hermes Agent reasoning?

If any answer is no or uncertain, do not use this lane.

## Setup

Create a separate OpenAI API project, for example:

```text
hermes-agent-ios-shared-evals
```

Enable data sharing only for that project, then create a dedicated API key.

Do **not** put the key in the main Hermes `.env` if that would make the main agent route private work through it. Prefer a shell-local export or a dedicated private env file that scripts source manually.

Example shell-local use:

```zsh
export OPENAI_SHARED_EVALS_API_KEY="sk-..."
export HERMES_AGENT_SHARED_OPENAI_ALLOW="synthetic-only"
python3 scripts/shared_openai_synthetic_eval.py --dry-run
```

To make a real API call:

```zsh
export OPENAI_SHARED_EVALS_API_KEY="sk-..."
export HERMES_AGENT_SHARED_OPENAI_ALLOW="synthetic-only"
python3 scripts/shared_openai_synthetic_eval.py --model gpt-5.4-mini
```

## Verification

The script must be able to run without a key in `--dry-run` mode:

```zsh
python3 scripts/shared_openai_synthetic_eval.py --dry-run
```

Expected behavior:

- prints the exact synthetic payload that would be sent;
- refuses to call the API without `HERMES_AGENT_SHARED_OPENAI_ALLOW=synthetic-only`;
- never reads Hermes memory, Obsidian, screenshots, or live transcripts;
- never prints API keys or bearer tokens.

## Current first use case

Synthetic Hermes gateway event eval:

- Given fake `session.list`, `session.resume`, `approval.request`, and `message.delta` events;
- ask the model to classify whether the event set is safe, complete enough for a UI fixture, and secret-free;
- return compact JSON/markdown suitable for a contract-test planning note.

## Upgrade path

Only after the synthetic eval lane proves useful:

1. Use it for issue-scout scoring with sanitized repo rails and GitHub issue titles.
2. Use it for synthetic fixture generation.
3. Consider CI-style eval batches.

Never upgrade it into a general Hermes provider lane without explicit maintainer approval.
