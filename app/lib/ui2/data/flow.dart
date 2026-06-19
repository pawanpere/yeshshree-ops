/// Ephemeral cross-screen flow state — carries form values into the result
/// screens of a multi-step flow (e.g. the good/reject counts a confirmation was
/// posted with, and the server's returned doc id shown on the success screen).
/// Not persisted; a flow overwrites its own keys each run.
class Ui2Flow {
  Ui2Flow._();
  static final Map<String, dynamic> _bag = {};

  static void set(String key, dynamic value) => _bag[key] = value;
  static T? get<T>(String key) => _bag[key] as T?;
  static dynamic raw(String key) => _bag[key];
  static void clear(String prefix) =>
      _bag.removeWhere((k, _) => k.startsWith(prefix));
}
