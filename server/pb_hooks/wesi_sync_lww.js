// Deterministic server-side last-write-wins guard for WesiOS sync rows.
//
// Client merge compares per-record timestamps, but a second device can change
// the same row after another client fetched it and before that client pushes.
// The server must therefore repeat the timestamp check at the write boundary;
// otherwise a late stale request can overwrite newer authoritative data.

function millis(raw) {
  const value = Date.parse(String(raw || ""));
  return Number.isFinite(value) ? value : null;
}

function decide(existingStamp, existingDeleted, incomingStamp, incomingDeleted) {
  const previous = millis(existingStamp);
  const incoming = millis(incomingStamp);

  // Incoming stamp is normalized by the route before this helper is called.
  // If an old/corrupt server row somehow has no parseable stamp, repairing it
  // with a valid incoming row is safer than making the corruption permanent.
  if (incoming == null) return {apply: false, reason: "invalid-incoming"};
  if (previous == null) return {apply: true, reason: "repair-invalid-existing"};

  if (incoming > previous) return {apply: true, reason: "newer"};
  if (incoming < previous) return {apply: false, reason: "stale"};

  // Exact timestamp tie. Keep the same conflict rule as the Dart merge:
  // deletion beats a live row. If both are live (or both tombstones), the
  // already-authoritative server row wins the tie. Clients explicitly apply
  // the remote payload on an equal-time live conflict, so this converges.
  if (incomingDeleted === true && existingDeleted !== true) {
    return {apply: true, reason: "tie-delete-wins"};
  }
  if (existingDeleted === true && incomingDeleted !== true) {
    return {apply: false, reason: "tie-existing-delete-wins"};
  }
  return {apply: false, reason: "tie-existing-authoritative"};
}

module.exports = {decide};
