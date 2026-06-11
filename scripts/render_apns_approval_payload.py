#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json


def build_payload(run_id: str, approval_id: str, command: str) -> dict[str, object]:
    return {
        "aps": {
            "alert": {
                "title": "Hermes Agent approval required",
                "body": command,
            },
            "sound": "default",
            "category": "HERMES_AGENT_APPROVAL",
            "thread-id": run_id,
        },
        "run_id": run_id,
        "approval_id": approval_id,
        "route": f"hermes-agent-ios://approval/{approval_id}",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Render a credential-free APNs approval payload skeleton for Hermes Agent iOS.")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--approval-id", required=True)
    parser.add_argument("--command", required=True)
    args = parser.parse_args()

    print(json.dumps(build_payload(args.run_id, args.approval_id, args.command), sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
