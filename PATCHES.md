# netglade patches to package:ably

Fork base: `50358867d41d6f72b000872d742eaacc8f1530d7` (tag `upstream-0.2.0`),
`ably/ably-pubsub-dart` main, byte-identical to published `ably` 0.2.0.

Integration branch: `netglade/chat-v0.2.0`. Every patch also lives on its own
branch off `upstream-0.2.0` so it can be raised as a standalone upstream PR.
Commit shas and upstream PR URLs are added to this table once each patch is
pushed; until then the branch column is the address of the work.

| | Defect | Evidence (upstream line numbers) | Fix | Branch |
|---|---|---|---|---|
| A | Realtime-delivered `Message` drops `version` and `annotations` | `lib/src/impl/realtime_channel_impl.dart:1100-1112` hand-builds `Message` with nine named args, omitting both, bypassing the TM2s1/TM2s2/TM2u defaults at `lib/src/message/message.dart:51-72` | Additive patch at the call site | `patch/a-realtime-message-version-annotations` |
| B | `attach()` never settles when the connection settles in a terminal state | `lib/src/impl/realtime_channel_impl.dart:650` awaits `_connection.on(connected).first` only, with no FAILED/CLOSING/CLOSED/SUSPENDED branch, so an RTL4b outcome leaves the caller parked forever even though `_failPendingOperations` has already errored the attach completer | `Future.any` over connected plus the four terminal connection events plus the attach completer, with an RTL4b state re-check afterwards | `patch/b-attach-connection-wait` |
| C | `release()` throws 90001 on a FAILED channel and leaks the state-change controller | `lib/src/impl/realtime_channels_impl.dart:201-209` awaits `channel.detach()` unguarded; `detach()` raises 90001 from FAILED at `realtime_channel_impl.dart:683-691`, so `_channels.remove()` at line 207 never runs and `dispose()` is never called | try/catch, unconditional removal, call `dispose()` | `patch/c-release-idempotent` |
| D | `ErrorInfo` has no `detail` | `lib/src/error/error_info.dart:9-16` declares exactly `code`, `statusCode`, `message`, `href`, `requestId`, `cause`, so the TI6 `detail` map is discarded | Add `Map<String, String>? detail` (TI6); carried through the REST mapping at `lib/src/impl/http/http_client.dart:442` | `patch/d-error-info-detail` |
| E | Wire enums throw `ArgumentError` on unknown values, from inside the transport handler | `message_action.dart:63`, `annotation_action.dart:34`, `presence_action.dart:53` and `:87`, `protocol_message.dart:63` | Return `null` for unknown values; ignore with an INFO log at each realtime call site (RTF1, CHA-M4m5) | `patch/e-wire-enum-unknown-values` |
