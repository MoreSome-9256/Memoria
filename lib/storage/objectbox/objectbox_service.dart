/// ObjectBox 数据库入口服务，负责初始化存储并提供全局 store 访问。

import 'dart:io';
import 'dart:typed_data';

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

    final directory = await getApplicationSupportDirectory();
    final objectBoxDirectory = Directory(p.join(directory.path, 'objectbox'));
    await objectBoxDirectory.create(recursive: true);
    _store = Store.isOpen(objectBoxDirectory.path)
        ? Store.attach(getObjectBoxModel(), objectBoxDirectory.path)
        : await openStore(directory: objectBoxDirectory.path);
  }

  Uint8List get storeReferenceBytes {
    final reference = store.reference;
    return Uint8List.fromList(
      reference.buffer.asUint8List(
        reference.offsetInBytes,
        reference.lengthInBytes,
      ),
    );
  }

  void attachReferenceBytes(Uint8List referenceBytes) {
    if (_store != null) {
      return;
    }
    final reference = ByteData.sublistView(referenceBytes);
    _store = Store.fromReference(getObjectBoxModel(), reference);
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
