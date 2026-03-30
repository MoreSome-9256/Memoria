import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../objectbox.g.dart';

class ObjectBoxService {
  ObjectBoxService._internal();

  static final ObjectBoxService _instance = ObjectBoxService._internal();

  factory ObjectBoxService() => _instance;

  Store? _store;

  bool get isInitialized => _store != null;

  Store get store {
    final store = _store;
    if (store == null) {
      throw StateError('ObjectBox has not been initialized yet.');
    }
    return store;
  }

  Future<void> init() async {
    if (_store != null) {
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    _store = await openStore(directory: p.join(directory.path, 'objectbox'));
  }

  Box<T>? tryBox<T>() {
    final store = _store;
    if (store == null) {
      return null;
    }
    return store.box<T>();
  }

  void close() {
    _store?.close();
    _store = null;
  }
}
