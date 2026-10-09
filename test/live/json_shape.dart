/// The shape of JSON payloads — which keys, which value types — merged over
/// every payload seen at a route, so the fake API's canned answers can be
/// held up against what the real server sent.
library;

/// One spot of a payload (the root, a key, a list's elements), merged over
/// every value seen there.
class JsonShape {
  /// The kinds of value seen: `null`, `string`, `num`, `bool`, `map`, `list`.
  final types = <String>{};

  /// A map's keys, each with the shape of its values.
  final keys = <String, JsonShape>{};

  /// How often each key was present.
  final _present = <String, int>{};

  /// How many maps were seen here.
  var _maps = 0;

  /// A list's elements, all merged.
  JsonShape? element;

  void add(Object? value) {
    switch (value) {
      case null:
        types.add('null');
      case String():
        types.add('string');
      case num():
        types.add('num');
      case bool():
        types.add('bool');
      case Map():
        types.add('map');
        _maps++;
        value.forEach((key, v) {
          keys.putIfAbsent('$key', JsonShape.new).add(v);
          _present.update('$key', (n) => n + 1, ifAbsent: () => 1);
        });
      case List():
        types.add('list');
        final e = element ??= JsonShape();
        for (final item in value) {
          e.add(item);
        }
      default:
        types.add('${value.runtimeType}');
    }
  }

  /// Whether [key] was in every map seen here.
  bool always(String key) => _present[key] == _maps;

  /// How [fake] (a canned answer) departs from this shape (the server's), as
  /// one line per difference under [path]:
  ///
  /// * a key the server sent in every payload that the fake leaves out;
  /// * a key the fake sends that the server never did;
  /// * a value of another kind than the server ever sent (nulls aside).
  ///
  /// A spot the server only ever left null or empty says nothing about the
  /// fake's value there.
  ///
  /// Keys whose path ends with one of [conditional] are left out both ways:
  /// the contract sends them only for some records (a chain day's counts on
  /// a partial day, a habit's `period` for a weekly or monthly one), so one
  /// run's payloads say nothing about whether they are always there.
  List<String> departures(
    JsonShape fake,
    String path, {
    Set<String> conditional = const {},
  }) {
    final out = <String>[];
    bool skipped(String key) =>
        conditional.any((suffix) => '$path.$key'.endsWith(suffix));
    final real = types.difference({'null'});
    final canned = fake.types.difference({'null'});
    if (real.isNotEmpty && canned.isNotEmpty && !real.containsAll(canned)) {
      out.add('$path: fake sends ${canned.join('|')}, '
          'server sends ${real.join('|')}');
    }
    if (types.contains('map') && fake.types.contains('map')) {
      for (final key in keys.keys) {
        if (skipped(key)) continue;
        if (always(key) && !fake.keys.containsKey(key)) {
          out.add('$path.$key: server always sends it, fake leaves it out');
        }
      }
      for (final MapEntry(:key, :value) in fake.keys.entries) {
        final served = keys[key];
        if (served == null) {
          if (!skipped(key)) {
            out.add('$path.$key: fake sends it, server never did');
          }
        } else {
          out.addAll(served.departures(value, '$path.$key',
              conditional: conditional));
        }
      }
    }
    final e = element;
    final fe = fake.element;
    if (e != null && fe != null) {
      out.addAll(e.departures(fe, '$path[]', conditional: conditional));
    }
    return out;
  }
}

/// `METHOD /path` with ids as `:id` and dates as `:date`, so the fake's
/// `/habits/7` and the server's `/habits/1234` are the same route.
String routeTemplate(String method, String path) {
  final segments = [
    for (final s in path.split('/'))
      if (RegExp(r'^\d+$').hasMatch(s))
        ':id'
      else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s))
        ':date'
      else
        s,
  ];
  return '${method.toUpperCase()} ${segments.join('/')}';
}
