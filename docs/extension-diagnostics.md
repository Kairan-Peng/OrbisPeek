# Extension registration and conflict diagnostics

The diagnostic collector is read-only. It does not enable, disable, unregister,
delete or repair extensions, change file associations, reset caches, or restart
Finder or the system.

## What the application can prove

`ExtensionDiagnostics.snapshot(hostURL:)` reports:

- Whether the current host contains `Contents/PlugIns/QuicklookPreview.appex`.
- Whether the host is in `/Applications` or the current account's `Applications`
  directory, a development build directory, a mounted volume, or another path.
- The current user's PlugInKit registration/election records when the process is
  permitted to query them.
- Other non-Apple Quick Look providers whose readable `Info.plist` declares an
  exact `QLSupportedContentTypes` overlap with this project's manifest.
- Incomplete reads, another registered copy, multiple copies, and relevant
  user-facing guidance.

It does **not** claim that an election record proves Finder selected a provider.
Real sample previews and a receipt from the actual extension are separate,
stronger evidence.

## Explicit sample render check

The host exports a new URL for each built-in sample check, writes a short-lived
request to App Group `UserDefaults`, and registers a distributed notification
observer before presenting the system's `QLPreviewView`. The extension captures
the matching request before rendering. Only successful completion of its own
renderer can post a receipt token. Ordinary document previews do not create a
request or log document details.

The request is bounded to 16 KiB and expires after 120 seconds. It contains a
new UUID, the exact standardized sample path, and a creation time. A render must
still match the active request when it finishes. The permitted sample modes
are Markdown, JSON, JSONL and TOML's code preview; another mode cannot satisfy
the check.

The notification's `object` is only a SHA-256 digest of sorted-key JSON containing
the nonce, sample path, actual extension bundle path, identifier, marketing
version, build number and mode. It carries no `userInfo`, raw nonce or path. The
host computes the expected digest for its current installed extension, checks
that the request remains active and fresh, and accepts at most one match. The
returned `Receipt.completedAt` is the host's local receive time, rather than a
timestamp supplied by the extension. Closing the sample removes the observer
and request; a retry uses a new nonce and URL.

On the tested macOS 27.0.1, the Quick Look extension can read the shared request
but is denied both shared-container file creation and App Group preference
writes. Builds 7 and 8 reproduced those denials after successful rendering.
Consequently only the host writes shared preferences. The extension posts the
public distributed notification with `userInfo: nil` and immediate delivery;
no helper, permission change or private API is involved.

This is a functional self-check, not sender authentication or a security
boundary. Apple documents that distributed notifications are untrusted, may be
delayed and may be dropped. The digest limits stale-copy and stale-request
mistakes and avoids broadcasting request data; it is not a digital signature.
A missing notification remains unverified and can be retried. No successful
host-only renderer or PlugInKit election is substituted for this receipt.

### Finder acceptance uses ordinary document locations

The built-in sample URL lives in the host application's cache container. On the
tested machine, the embedded system `QLPreviewView` renders all four samples and
returns matching extension receipts, while revealing that same cache-container
Markdown file in Finder and pressing Space leaves Finder's preview loading.
Finder logs for that attempt show Apple's `QLPreviewGenerationExtension` followed
by a UI-service connection error and timeout, rather than this extension's
renderer being invoked. The same Markdown content copied to the workspace's
ordinary `.build/beta-validation/finder-sample.md` renders through the installed
then-named Quicklook extension with its Markdown toolbar.

The exact system reason for the cache-container path difference is unconfirmed.
Finder acceptance therefore uses a document in an ordinary user-accessible
folder. The app's sample check remains a real extension render through system
Quick Look, but does not independently prove Finder's behavior at every path.

Public API references:

- [Apple: Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
  lists distributed-notification `userInfo` dictionaries among sandbox restrictions.
- [Apple: DistributedNotificationCenter](https://developer.apple.com/documentation/foundation/distributednotificationcenter)
  describes cross-task delivery, latency, dropped messages and the untrusted channel.
- [Apple: Sharing data with your containing app](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)
  describes App Group shared preferences; it does not guarantee that every
  extension point permits shared writes.

## Election interpretation

The system's `pluginkit(8)` manual defines the markers returned by its read-only
match operation. The collector uses `pluginkit -m -AvD -p com.apple.quicklook.preview`
so that multiple versions and physical copies are visible when querying is
permitted.

| Marker | Diagnostic state | Meaning |
|---|---|---|
| `+` | `preferred` | User elected to use the extension |
| blank | `defaultElection` | System default election; not proof of enabled/selected |
| `-` | `ignored` | User elected to ignore the extension |
| `!` | `debugger` | Elected for debugger use |
| `=` | `superseded` | Superseded by another version/copy |
| `?` | `unknown` | Election state is unknown |

The manual explicitly says this output reproduces discovery **without
host-specific restrictions**. Consequently even `+` cannot guarantee a Finder
result. A successful recognized empty registry is distinct from a failed or
unrecognized query. Exit failure, timeout, rejected sandbox access, oversized
output, or incompatible output format becomes `unavailable`, never "disabled".

## Sandbox observation

On macOS 27.0.1, a minimal sandboxed Developer ID application was tested with the
same `Process` invocation used by the collector. Both `-m -AvD -p ...` and the
reduced `-m -v -p ...` exited with status 1 and reported:

```text
match: unauthorized discovery flag (PKDiscoverAll)
```

Evidence is saved in `.build/diagnostics-experiment/sandbox-result.json` and
`sandbox-basic-result.json`. The experiment did not add exceptions or private
discovery entitlements. The ordinary terminal invocation succeeds on this
machine. The product therefore preserves its sandbox and exposes the limitation
honestly instead of treating a failed query as an empty registry. Actual host
results remain subject to its environment and are reported by the same collector.

Foundation's home-directory APIs were also observed to return the application's
container in this sandbox. Install-location classification uses thread-safe
`getpwuid_r` account metadata to identify `~/Applications`; this does not read
files from the user's home directory.

## Conflict boundaries

- Apple identifiers are omitted from conflict checks. Xcode and built-in system
  preview providers are not presented as removable third-party conflicts.
- Ignored and superseded registrations are omitted from active-candidate
  conflicts.
- Other providers are reported only after reading their actual preview UTI
  declarations and finding an exact intersection with the current manifest.
- An unreadable provider's plist increments an incomplete-scan count; it is not
  silently treated as non-conflicting.
- Another copy of OrbisPeek is reported separately from a competing app. The
  current host path must match the registered extension path before its election
  is used as the current copy's status.
- No file is executed or loaded as a code bundle during these checks. Plists are
  read as data with a 1 MiB size bound. The registry subprocess has a five-second
  timeout and 1 MiB output bound.

## Public API choice

The installed macOS 27.2 SDK exposes ExtensionFoundation's
`AppExtensionIdentity.matching` (macOS 13+, deprecated in 26 in favor of
`AppExtensionPoint.Monitor`). Its public identity fields do not expose a bundle
URL or an enabled flag. ExtensionKit's browser is documented for extension points
that the host app supports; it is not adopted here as a manager for Apple's
system Quick Look point. The implementation does not use private `NSExtension`,
private PlugInKit APIs or method invocation via runtime strings.

Primary references:

- Local `man pluginkit`, including `-m`, `-A`, `-D`, `-v` and election semantics.
- SDK `ExtensionFoundation.framework/.../ExtensionFoundation.swiftinterface`.
- SDK `ExtensionKit.framework/.../EXAppExtensionBrowserViewController.h`.
- [Apple ExtensionKit browser documentation](https://developer.apple.com/documentation/extensionkit/exappextensionbrowserviewcontroller).
- [Apple Developer Forums: Active Quicklook extension is ignored](https://developer.apple.com/forums/thread/817354)
  is a developer's report of provider-selection behavior, not an Apple promise
  about the selection algorithm.

## Validation

`swift test --filter ExtensionDiagnosticsTests` covers all election markers,
paths containing spaces, query failures, future-format mismatch, empty registry,
multiple versions/copies, current-copy matching, exact-type conflicts,
system/ignored/superseded exclusions, and incomplete plist reads.

`swift test --filter PreviewVerificationTests` covers token matching, wrong
copies/versions/builds, old nonces, different paths, expiry, cancellation,
sample-mode restrictions, bounded malformed requests, actual distributed
notification delivery, one-shot consumption and observer removal. Unit tests
use an isolated preferences suite; installed extension-to-host delivery also
requires a real system Quick Look acceptance check.

This is a diagnostic collector, not a proof of compatibility across macOS
versions. No system restart was performed during its implementation or tests.
