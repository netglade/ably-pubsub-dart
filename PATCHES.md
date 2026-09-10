# netglade patches to package:ably

Fork base: `50358867d41d6f72b000872d742eaacc8f1530d7` (tag `upstream-0.2.0`),
`ably/ably-pubsub-dart` main. `lib/` at that commit is source-identical to
published `ably` 0.2.0; the two commits between the `v0.2.0` tag and this
one touch only README.md, CONTRIBUTING.md and pubspec.yaml's repository
URLs for the repo rename, never `lib/`.

Integration branch: `netglade/chat-v0.2.0`, which now carries all five
patches (`git merge --no-ff`, in A-B-C-D-E order — see its log). Every
patch also lives on its own branch off `upstream-0.2.0` so it can be
raised as a standalone upstream PR.

The table is complete: every patch names its commit, and either its
upstream PR URL or, until the deferred GitHub hand-off in `docs/fork.md`
opens it, the exact sentinel "not yet opened".

`Commit` is each branch's current **tip**, not necessarily its whole
patch: branches b, c, d and e each carry two commits (the original patch
plus one review fix round; only branch a is a single commit — see
`docs/fork.md`'s "Fork maintenance notes"), so read a branch's own log
for its full history, not just the sha cited here.

| | Defect | Evidence (upstream line numbers) | Fix | Branch | Commit (tip) | Upstream PR | Merged? |
|---|---|---|---|---|---|---|---|
| A | Realtime-delivered `Message` drops `version` and `annotations` | `lib/src/impl/realtime_channel_impl.dart:1100-1112` hand-builds `Message` with nine named args, omitting both, bypassing the TM2s1/TM2s2/TM2u defaults at `lib/src/message/message.dart:51-72` | Additive patch at the call site | `patch/a-realtime-message-version-annotations` | `4c9013207838` | not yet opened | no |
| B | `attach()` never settles when the connection settles in a terminal state | `lib/src/impl/realtime_channel_impl.dart:650` awaits `_connection.on(connected).first` only, with no FAILED/CLOSING/CLOSED/SUSPENDED branch, so an RTL4b outcome leaves the caller parked forever even though `_failPendingOperations` has already errored the attach completer | `Future.any` over connected plus the four terminal connection events plus the attach completer, with an RTL4b state re-check afterwards | `patch/b-attach-connection-wait` | `976d1b126358` | not yet opened | no |
| C | `release()` throws 90001 on a FAILED channel and leaks the state-change controller | `lib/src/impl/realtime_channels_impl.dart:201-209` awaits `channel.detach()` unguarded; `detach()` raises 90001 from FAILED at `realtime_channel_impl.dart:683-691`, so `_channels.remove()` at line 207 never runs and `dispose()` is never called | try/catch, unconditional removal, call `dispose()` | `patch/c-release-idempotent` | `681211f2eca7` | not yet opened | no |
| D | `ErrorInfo` has no `detail` | `lib/src/error/error_info.dart:9-16` declares exactly `code`, `statusCode`, `message`, `href`, `requestId`, `cause`, so the TI6 `detail` map is discarded | Add `Map<String, String>? detail` (TI6); carried through the REST mapping at `lib/src/impl/http/http_client.dart:442` | `patch/d-error-info-detail` | `960eb5245459` | not yet opened | no |
| E | Wire enums throw `ArgumentError` on unknown values, from inside the transport handler | `message_action.dart:63`, `annotation_action.dart:34`, `presence_action.dart:53` and `:87`, `protocol_message.dart:63` | Return `null` for unknown values; ignore with an INFO log at each realtime call site (RTF1, CHA-M4m5) | `patch/e-wire-enum-unknown-values` | `c0abe370f0d7` | not yet opened | no |

Note on the merge: patches A and E both touch `_handleMessage`'s per-message
decode loop, at distinct anchors, so the merge was textually clean with no
conflict. A dedicated integration-only test —
`test/realtime/unit/channels/channel_unknown_action_and_version_annotations_test.dart`
— exercises both together in one batch and cannot pass on either patch
branch alone; see `docs/fork.md`'s no-regression evidence.
