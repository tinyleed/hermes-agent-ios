# Next

Use [`ROADMAP.md`](ROADMAP.md) for public project direction.

Gateway-backend status: the approval/sudo/secret request-response loop is now proven end-to-end in the simulator and on a physically signed iPhone against the safe mock WebSocket gateway, with redacted final output. The APNs device-registration gateway contract is defined and covered by Swift/Python mock-gateway tests, and the iOS app now syncs a redacted device registration to that contract after APNs captures a device token. Device-token rotation now clears stale gateway registration state and re-registers with redacted replacement metadata. Notification permission is requested only after explicit operator action or the first live blocking request, not on cold launch.

Next implementation slice: run the physical-device APNs sandbox push proof for issue #20 using a wake/attention-only `blocking_request_available` payload; keep credentials, Team ID, provisioning state, and raw device tokens local/private.
