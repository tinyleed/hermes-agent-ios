# Status

Hermes Agent iOS is an early open-source iPhone operator cockpit for Hermes Agent.

Current state:

- SwiftUI app shell and command/chat cockpit exist.
- `HermesAgentCore` contains gateway contracts, request builders, runtime reducers, and client seams.
- Python mock gateways and Swift/Python contract tests cover local development flows.
- Approval, sudo, and secret blocking-card fixtures are represented with redacted response state.
- The full local gate is `./scripts/test_all.sh`.

Known limitations:

- The project is not yet production-ready or App Store-ready.
- Physical-device flows require local signing and a reachable private Hermes host.
- Hosted/public gateway auth is intentionally deferred.
- The Share Extension activation rule is narrowed for text and one web URL; broader media/file support still needs deliberate design before App Store/TestFlight submission.

See [`ROADMAP.md`](ROADMAP.md) for current priorities.
