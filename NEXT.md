# Next

Use [`ROADMAP.md`](ROADMAP.md) for public project direction.

Gateway-backend status: the approval/sudo/secret request-response loop is now proven end-to-end in the simulator and on a physically signed iPhone against the safe mock WebSocket gateway, with redacted final output.

Next implementation slice: layer APNs/local notification delivery on top of the green blocking loop, while keeping a contributor-safe repeatable physical-device harness as a follow-up.
