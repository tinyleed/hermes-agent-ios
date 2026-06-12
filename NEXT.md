# Next

Use [`ROADMAP.md`](ROADMAP.md) for public project direction.

Gateway-backend status: the approval/sudo/secret request-response loop is now proven end-to-end in the simulator against the safe mock WebSocket gateway, with redacted final output.

Next implementation slice: verify the same gateway-backed blocking requests on a physically signed iPhone against the private Hermes host, then layer APNs/local notification delivery on top of the green blocking loop.
