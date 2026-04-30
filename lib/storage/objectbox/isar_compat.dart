import 'dart:async';

import '../../objectbox.g.dart';
import 'objectbox_service.dart';

class PhotoStoreCompat {
  PhotoStoreCompat(this._service);

  final ObjectBoxService _service;

  EntityBoxCompat<T> collection<T>() {
    return EntityBoxCompat<T>(_service.store.box<T>());
  }

  EntityBoxCompat<dynamic> get photoEntitys => collection<dynamic>();
  EntityBoxCompat<dynamic> get eventEntitys => collection<dynamic>();
  EntityBoxCompat<dynamic> get storyEntitys => collection<dynamic>();
  EntityBoxCompat<dynamic> get faceEntitys => collection<dynamic>();
  EntityBoxCompat<dynamic> get createRecommendationEntitys =>
      collection<dynamic>();
  EntityBoxCompat<dynamic> get digitalAlbumBookEntitys =>
      collection<dynamic>();

  Future<void> writeTxn(Future<void> Function() fn) async {
    await fn();
  }
}

class EntityBoxCompat<T> {
  EntityBoxCompat(this._box);

  final Box<T> _box;

  QueryCompat<T> where() => QueryCompat<T>(_box);
  QueryCompat<T> filter() => QueryCompat<T>(_box);
  QueryCompat<T> query([Object? _]) => QueryCompat<T>(_box);

  Future<T?> get(int id) async => _box.get(id);

  Future<List<T>> getAll(List<int> ids) async {
    final rows = _box.getMany(ids);
    return rows.whereType<T>().toList(growable: false);
  }

  Future<int> put(T entity) async => _box.put(entity);

  Future<List<int>> putAll(List<T> entities) async => _box.putMany(entities);

  Future<int> count() async => _box.count();

  Future<void> clear() async {
    _box.removeAll();
  }

  Future<bool> delete(int id) async => _box.remove(id);

  Future<int> deleteAll(List<int> ids) async {
    _box.removeMany(ids);
    return ids.length;
  }

  Stream<void> watchLazy({bool fireImmediately = false}) {
    if (!fireImmediately) {
      return const Stream<void>.empty();
    }
    return Stream<void>.value(null);
  }
}

class QueryCompat<T> {
  QueryCompat(this._box);

  final Box<T> _box;
  int? _limit;
  Comparator<T>? _comparator;

  QueryCompat<T> sortByTimestampDesc() {
    _comparator = (a, b) => _readInt(b, 'timestamp').compareTo(
      _readInt(a, 'timestamp'),
    );
    return this;
  }

  QueryCompat<T> sortByTimestamp() {
    _comparator = (a, b) => _readInt(a, 'timestamp').compareTo(
      _readInt(b, 'timestamp'),
    );
    return this;
  }

  QueryCompat<T> limit(int value) {
    _limit = value;
    return this;
  }

  QueryCompat<T> anyOf(Iterable<dynamic> values, dynamic Function(dynamic, dynamic) cb) {
    for (final value in values) {
      cb(this, value);
    }
    return this;
  }

  QueryCompat<T> build() => this;

  void close() {}

  Future<List<T>> findAll() async {
    final rows = _box.getAll();
    if (_comparator != null) {
      rows.sort(_comparator);
    }
    if (_limit != null && _limit! >= 0 && rows.length > _limit!) {
      return rows.take(_limit!).toList(growable: false);
    }
    return rows;
  }

  Future<T?> findFirst() async {
    final rows = await findAll();
    if (rows.isEmpty) {
      return null;
    }
    return rows.first;
  }

  Future<int> count() async {
    final rows = await findAll();
    return rows.length;
  }

  List<int> findIds() {
    final rows = _box.getAll();
    return rows
        .map((row) => _readInt(row, 'id'))
        .where((id) => id > 0)
        .toList(growable: false);
  }

  List<ObjectWithScore<T>> findWithScores() {
    final rows = _box.getAll();
    return rows
        .map((row) => ObjectWithScore<T>(row, 0.0))
        .toList(growable: false);
  }

  int _readInt(dynamic obj, String field) {
    try {
      final dynamic source = obj as dynamic;
      switch (field) {
        case 'id':
          final dynamic raw = source.id;
          if (raw is int) return raw;
        case 'timestamp':
          final dynamic raw = source.timestamp;
          if (raw is int) return raw;
        case 'createdAt':
          final dynamic raw = source.createdAt;
          if (raw is int) return raw;
        case 'startTime':
          final dynamic raw = source.startTime;
          if (raw is int) return raw;
      }
    } catch (_) {}

    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return this;
  }
}
