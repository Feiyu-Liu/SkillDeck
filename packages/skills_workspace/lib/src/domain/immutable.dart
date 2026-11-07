bool listsEqual<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool mapsEqual<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

int unorderedMapHash<K, V>(Map<K, V> values) => Object.hashAllUnordered(
  values.entries.map((entry) => Object.hash(entry.key, entry.value)),
);

bool setsEqual<T>(Set<T> left, Set<T> right) {
  if (identical(left, right)) {
    return true;
  }
  return left.length == right.length && left.containsAll(right);
}

int unorderedSetHash<T>(Set<T> values) => Object.hashAllUnordered(values);
