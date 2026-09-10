typedef ApplicationListener = void Function();

/// Framework-neutral observable used by application services.
///
/// Presentation layers can adapt this to Flutter Listenable without making
/// application state depend on Flutter foundation classes.
class ApplicationChangeNotifier {
  final Set<ApplicationListener> _listeners = <ApplicationListener>{};
  bool _disposed = false;

  void addListener(ApplicationListener listener) {
    if (_disposed) return;
    _listeners.add(listener);
  }

  void removeListener(ApplicationListener listener) {
    _listeners.remove(listener);
  }

  void notifyListeners() {
    if (_disposed || _listeners.isEmpty) return;
    for (final listener in List<ApplicationListener>.of(_listeners)) {
      if (_listeners.contains(listener)) listener();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listeners.clear();
  }
}

/// Minimal framework-neutral equivalent of a value notifier.
class ApplicationValueNotifier<T> extends ApplicationChangeNotifier {
  ApplicationValueNotifier(this._value);

  T _value;

  T get value => _value;

  set value(T next) {
    if (_value == next) return;
    _value = next;
    notifyListeners();
  }
}
