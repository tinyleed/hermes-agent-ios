# Next

Use [`ROADMAP.md`](ROADMAP.md) for public project direction.

Gateway-backend status: the approval/sudo/secret request-response loop is now proven end-to-end in the simulator and on a physically signed iPhone against the safe mock WebSocket gateway, with redacted final output. The APNs device-registration gateway contract is now defined and covered by Swift/Python mock-gateway tests.

Next implementation slice: wire the iOS remote-notification registration path to the new APNs device-registration contract, then use the physical APNs sandbox push proof as the device-only follow-up.
