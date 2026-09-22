# netglade patches to package:ably

Fork base: `50358867d41d6f72b000872d742eaacc8f1530d7` (tag `upstream-0.2.0`),
`ably/ably-pubsub-dart` main. `lib/` at that commit is source-identical to
published `ably` 0.2.0; the two commits between the `v0.2.0` tag and this
one touch only README.md, CONTRIBUTING.md and pubspec.yaml's repository
URLs for the repo rename, never `lib/`.

Integration branch: `netglade/chat-v0.2.0`, which now carries all six
patches (`git merge --no-ff`, in A-B-C-D-E-F order — see its log). Every
patch also lives on its own branch off `upstream-0.2.0` so it can be
raised as a standalone upstream PR.

The table is complete: every patch names its commit and its upstream PR
URL. The GitHub hand-off in `docs/fork.md` ran on 2026-09-22 and the five
PRs it raised are open against `ably/ably-pubsub-dart`; patch F postdates
that hand-off and was raised separately as #23. None is merged, so the
`Merged?` column still reads `no` throughout and this fork stays the
dependency the chat SDK consumes.

`Commit` is each branch's current **tip**, not necessarily its whole
patch: branches b, d and e each carry two commits (the original patch
plus one review fix round) and branch c carries three (the original
patch, one review fix round, and a further fix from final review that
settles in-flight attach()/detach() operations in dispose()); only
branches a and f are single commits — see `docs/fork.md`'s "Fork maintenance
notes". Read a branch's own log for its full history, not just the sha
cited here.

| | Defect | Evidence (upstream line numbers) | Fix | Branch | Commit (tip) | Upstream PR | Merged? |
|---|---|---|---|---|---|---|---|
| A | Realtime-delivered `Message` drops `version` and `annotations` | `lib/src/impl/realtime_channel_impl.dart:1100-1112` hand-builds `Message` with nine named args, omitting both, bypassing the TM2s1/TM2s2/TM2u defaults at `lib/src/message/message.dart:51-72` | Additive patch at the call site | `patch/a-realtime-message-version-annotations` | `4c9013207838` | https://github.com/ably/ably-pubsub-dart/pull/18 | no |
| B | `attach()` never settles when the connection settles in a terminal state | `lib/src/impl/realtime_channel_impl.dart:650` awaits `_connection.on(connected).first` only, with no FAILED/CLOSING/CLOSED/SUSPENDED branch, so an RTL4b outcome leaves the caller parked forever even though `_failPendingOperations` has already errored the attach completer | A single subscription on the connection's shared state-change stream races CONNECTED, the four RTL4b terminal states and the attach completer, cancelled in `finally` on every exit (not `Future.any`, which would leak a listener per losing state on every ordinary attach); an RTL4b state re-check follows | `patch/b-attach-connection-wait` | `976d1b126358` | https://github.com/ably/ably-pubsub-dart/pull/19 | no |
| C | `release()` throws 90001 on a FAILED channel, leaks the state-change controller, and can strand a concurrent `attach()` | `lib/src/impl/realtime_channels_impl.dart:201-209` awaits `channel.detach()` unguarded; `detach()` raises 90001 from FAILED at `realtime_channel_impl.dart:683-691`, so `_channels.remove()` at line 207 never runs and `dispose()` is never called; separately, releasing a channel that is still ATTACHING with the connection not yet CONNECTED leaves a concurrent `attach()` call parked forever, because `detach()`'s RTL5l path transitions straight to DETACHED without failing the pending attach completer | Unconditional removal from `_channels` up front; `detach()` wrapped in try/`on AblyException` (logged, swallowed); `dispose()` moved into `finally` so it runs even if `detach()` throws something else; `dispose()` also now fails any pending attach()/detach() with 90001 before closing the state-change controller, so release() always leaves the channel dead — removed, detached best-effort, disposed, and with its in-flight operations settled rather than orphaned | `patch/c-release-idempotent` | `5ed841639dc1` | https://github.com/ably/ably-pubsub-dart/pull/20 | no |
| D | `ErrorInfo` has no `detail` | `lib/src/error/error_info.dart:9-16` declares exactly `code`, `statusCode`, `message`, `href`, `requestId`, `cause`, so the TI6 `detail` map is discarded | Add `Map<String, String>? detail` (TI6); carried through the REST mapping at `lib/src/impl/http/http_client.dart:442` (unchanged — it already just calls `ErrorInfo.fromMap`) | `patch/d-error-info-detail` | `960eb5245459` | https://github.com/ably/ably-pubsub-dart/pull/21 | no |
| E | Wire enums throw `ArgumentError` on unknown values, from inside the transport handler | `message_action.dart:63`, `annotation_action.dart:34`, `presence_action.dart:53` and `:87`, `protocol_message.dart:63` | Return `null` for unknown values (each decoder); ignore-with-log at every realtime call site, keyed off the raw wire value (not just the decoded result being `null`) so an absent field is never mistaken for an unrecognised one — the protocol-message level uses a new `unrecognisedAction` field for this distinction (RTF1, CHA-M4m5) | `patch/e-wire-enum-unknown-values` | `c0abe370f0d7` | https://github.com/ably/ably-pubsub-dart/pull/22 | no |
| F | The transport interface is public API, but only a `@visibleForTesting` constructor accepts one | `lib/ably.dart:108` exports `websocket_client.dart`, so `WebSocketClient` and `WebSocketConnection` are public API; but the RTC1a factory at `lib/src/realtime/realtime_client.dart:27-30` takes only `options` and `key`, and the only constructor that accepts a transport is `RealtimeClient.forTesting` at `:52-58`. An application that must supply its own — a browser, where `dart:io` compiles to a stub that throws the moment a socket is opened — can therefore only reach the seam through `forTesting`, which raises `invalid_use_of_visible_for_testing_member` outside a test | Add `WebSocketClient? webSocketClient` to the RTC1a factory and pass it through to `RealtimeClientImpl`, which already accepted one. Nothing changes when it is omitted | `patch/f-public-transport-seam` | `2145a63899fc` | https://github.com/ably/ably-pubsub-dart/pull/23 | no |

Note on the merge: patches A and E both touch `_handleMessage`'s per-message
decode loop, at distinct anchors, so the merge was textually clean with no
conflict. A dedicated integration-only test —
`test/realtime/unit/channels/channel_unknown_action_and_version_annotations_test.dart`
— exercises both together in one batch and cannot pass on either patch
branch alone; see `docs/fork.md`'s no-regression evidence.

Note on B×C: patch B's `attach()` and patch C's `dispose()` now both touch
`lib/src/impl/realtime_channel_impl.dart`, at distinct anchors (`attach()`'s
connection wait versus `dispose()`'s pending-operations fix), so the merge
was textually clean with no conflict — but before row C's `dispose()` fix
above, releasing a channel that was still ATTACHING while the connection
had not yet reached CONNECTED left a concurrent `attach()` call parked
forever, a defect the two patches share by lifecycle rather than by file.
A second integration-only test —
`test/realtime/unit/channels/channel_release_pending_attach_test.dart` —
covers this and, like the A×E test, only makes sense with both patches
present.
