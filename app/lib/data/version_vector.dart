/// Tracks which edits an item has seen, one counter per member.
///
/// Comparing two vectors tells whether one copy of an item already includes
/// the other's edits, or whether two people edited it independently.
enum Order { same, before, after, concurrent }

class VersionVector {
  const VersionVector([this.counters = const {}]);

  factory VersionVector.fromJson(Map<String, Object?> json) =>
      VersionVector({for (final e in json.entries) e.key: e.value! as int});

  final Map<String, int> counters;

  Map<String, int> toJson() => Map.of(counters);

  /// Total number of edits, used as the item's version number.
  int get total => counters.values.fold(0, (a, b) => a + b);

  VersionVector bump(String memberId) =>
      VersionVector({...counters, memberId: (counters[memberId] ?? 0) + 1});

  VersionVector merge(VersionVector other) {
    final out = Map.of(counters);
    other.counters.forEach((k, v) {
      if ((out[k] ?? 0) < v) out[k] = v;
    });
    return VersionVector(out);
  }

  Order compare(VersionVector other) {
    var less = false;
    var greater = false;
    for (final key in {...counters.keys, ...other.counters.keys}) {
      final a = counters[key] ?? 0;
      final b = other.counters[key] ?? 0;
      if (a < b) less = true;
      if (a > b) greater = true;
    }
    if (less && greater) return Order.concurrent;
    if (less) return Order.before;
    if (greater) return Order.after;
    return Order.same;
  }
}
