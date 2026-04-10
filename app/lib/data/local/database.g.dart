// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CacheMetaTable extends CacheMeta
    with TableInfo<$CacheMetaTable, CacheMetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta =
      const VerificationMeta('cacheKey');
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
      'cache_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastFetchedAtMeta =
      const VerificationMeta('lastFetchedAt');
  @override
  late final GeneratedColumn<DateTime> lastFetchedAt =
      GeneratedColumn<DateTime>('last_fetched_at', aliasedName, false,
          type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
      'etag', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<String> cursor = GeneratedColumn<String>(
      'cursor', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [cacheKey, lastFetchedAt, etag, cursor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_meta';
  @override
  VerificationContext validateIntegrity(Insertable<CacheMetaData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(_cacheKeyMeta,
          cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta));
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('last_fetched_at')) {
      context.handle(
          _lastFetchedAtMeta,
          lastFetchedAt.isAcceptableOrUnknown(
              data['last_fetched_at']!, _lastFetchedAtMeta));
    } else if (isInserting) {
      context.missing(_lastFetchedAtMeta);
    }
    if (data.containsKey('etag')) {
      context.handle(
          _etagMeta, etag.isAcceptableOrUnknown(data['etag']!, _etagMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(_cursorMeta,
          cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  CacheMetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheMetaData(
      cacheKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cache_key'])!,
      lastFetchedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_fetched_at'])!,
      etag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}etag']),
      cursor: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cursor']),
    );
  }

  @override
  $CacheMetaTable createAlias(String alias) {
    return $CacheMetaTable(attachedDatabase, alias);
  }
}

class CacheMetaData extends DataClass implements Insertable<CacheMetaData> {
  final String cacheKey;
  final DateTime lastFetchedAt;
  final String? etag;
  final String? cursor;
  const CacheMetaData(
      {required this.cacheKey,
      required this.lastFetchedAt,
      this.etag,
      this.cursor});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['last_fetched_at'] = Variable<DateTime>(lastFetchedAt);
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || cursor != null) {
      map['cursor'] = Variable<String>(cursor);
    }
    return map;
  }

  CacheMetaCompanion toCompanion(bool nullToAbsent) {
    return CacheMetaCompanion(
      cacheKey: Value(cacheKey),
      lastFetchedAt: Value(lastFetchedAt),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      cursor:
          cursor == null && nullToAbsent ? const Value.absent() : Value(cursor),
    );
  }

  factory CacheMetaData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheMetaData(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      lastFetchedAt: serializer.fromJson<DateTime>(json['lastFetchedAt']),
      etag: serializer.fromJson<String?>(json['etag']),
      cursor: serializer.fromJson<String?>(json['cursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'lastFetchedAt': serializer.toJson<DateTime>(lastFetchedAt),
      'etag': serializer.toJson<String?>(etag),
      'cursor': serializer.toJson<String?>(cursor),
    };
  }

  CacheMetaData copyWith(
          {String? cacheKey,
          DateTime? lastFetchedAt,
          Value<String?> etag = const Value.absent(),
          Value<String?> cursor = const Value.absent()}) =>
      CacheMetaData(
        cacheKey: cacheKey ?? this.cacheKey,
        lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
        etag: etag.present ? etag.value : this.etag,
        cursor: cursor.present ? cursor.value : this.cursor,
      );
  CacheMetaData copyWithCompanion(CacheMetaCompanion data) {
    return CacheMetaData(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      lastFetchedAt: data.lastFetchedAt.present
          ? data.lastFetchedAt.value
          : this.lastFetchedAt,
      etag: data.etag.present ? data.etag.value : this.etag,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaData(')
          ..write('cacheKey: $cacheKey, ')
          ..write('lastFetchedAt: $lastFetchedAt, ')
          ..write('etag: $etag, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, lastFetchedAt, etag, cursor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheMetaData &&
          other.cacheKey == this.cacheKey &&
          other.lastFetchedAt == this.lastFetchedAt &&
          other.etag == this.etag &&
          other.cursor == this.cursor);
}

class CacheMetaCompanion extends UpdateCompanion<CacheMetaData> {
  final Value<String> cacheKey;
  final Value<DateTime> lastFetchedAt;
  final Value<String?> etag;
  final Value<String?> cursor;
  final Value<int> rowid;
  const CacheMetaCompanion({
    this.cacheKey = const Value.absent(),
    this.lastFetchedAt = const Value.absent(),
    this.etag = const Value.absent(),
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheMetaCompanion.insert({
    required String cacheKey,
    required DateTime lastFetchedAt,
    this.etag = const Value.absent(),
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : cacheKey = Value(cacheKey),
        lastFetchedAt = Value(lastFetchedAt);
  static Insertable<CacheMetaData> custom({
    Expression<String>? cacheKey,
    Expression<DateTime>? lastFetchedAt,
    Expression<String>? etag,
    Expression<String>? cursor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (lastFetchedAt != null) 'last_fetched_at': lastFetchedAt,
      if (etag != null) 'etag': etag,
      if (cursor != null) 'cursor': cursor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheMetaCompanion copyWith(
      {Value<String>? cacheKey,
      Value<DateTime>? lastFetchedAt,
      Value<String?>? etag,
      Value<String?>? cursor,
      Value<int>? rowid}) {
    return CacheMetaCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      etag: etag ?? this.etag,
      cursor: cursor ?? this.cursor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (lastFetchedAt.present) {
      map['last_fetched_at'] = Variable<DateTime>(lastFetchedAt.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<String>(cursor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheMetaCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('lastFetchedAt: $lastFetchedAt, ')
          ..write('etag: $etag, ')
          ..write('cursor: $cursor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PinsTable extends Pins with TableInfo<$PinsTable, Pin> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
      'slug', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _centerLatitudeMeta =
      const VerificationMeta('centerLatitude');
  @override
  late final GeneratedColumn<double> centerLatitude = GeneratedColumn<double>(
      'center_latitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _centerLongitudeMeta =
      const VerificationMeta('centerLongitude');
  @override
  late final GeneratedColumn<double> centerLongitude = GeneratedColumn<double>(
      'center_longitude', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
      'level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentPinIdMeta =
      const VerificationMeta('parentPinId');
  @override
  late final GeneratedColumn<String> parentPinId = GeneratedColumn<String>(
      'parent_pin_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _userCountMeta =
      const VerificationMeta('userCount');
  @override
  late final GeneratedColumn<int> userCount = GeneratedColumn<int>(
      'user_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _activeMatchRequestsMeta =
      const VerificationMeta('activeMatchRequests');
  @override
  late final GeneratedColumn<int> activeMatchRequests = GeneratedColumn<int>(
      'active_match_requests', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        slug,
        centerLatitude,
        centerLongitude,
        level,
        parentPinId,
        isActive,
        userCount,
        activeMatchRequests,
        createdAt,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pins';
  @override
  VerificationContext validateIntegrity(Insertable<Pin> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
          _slugMeta, slug.isAcceptableOrUnknown(data['slug']!, _slugMeta));
    }
    if (data.containsKey('center_latitude')) {
      context.handle(
          _centerLatitudeMeta,
          centerLatitude.isAcceptableOrUnknown(
              data['center_latitude']!, _centerLatitudeMeta));
    } else if (isInserting) {
      context.missing(_centerLatitudeMeta);
    }
    if (data.containsKey('center_longitude')) {
      context.handle(
          _centerLongitudeMeta,
          centerLongitude.isAcceptableOrUnknown(
              data['center_longitude']!, _centerLongitudeMeta));
    } else if (isInserting) {
      context.missing(_centerLongitudeMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('parent_pin_id')) {
      context.handle(
          _parentPinIdMeta,
          parentPinId.isAcceptableOrUnknown(
              data['parent_pin_id']!, _parentPinIdMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('user_count')) {
      context.handle(_userCountMeta,
          userCount.isAcceptableOrUnknown(data['user_count']!, _userCountMeta));
    }
    if (data.containsKey('active_match_requests')) {
      context.handle(
          _activeMatchRequestsMeta,
          activeMatchRequests.isAcceptableOrUnknown(
              data['active_match_requests']!, _activeMatchRequestsMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Pin map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Pin(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      slug: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}slug']),
      centerLatitude: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}center_latitude'])!,
      centerLongitude: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}center_longitude'])!,
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}level'])!,
      parentPinId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_pin_id']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      userCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}user_count'])!,
      activeMatchRequests: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}active_match_requests']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $PinsTable createAlias(String alias) {
    return $PinsTable(attachedDatabase, alias);
  }
}

class Pin extends DataClass implements Insertable<Pin> {
  final String id;
  final String name;
  final String? slug;
  final double centerLatitude;
  final double centerLongitude;
  final String level;
  final String? parentPinId;
  final bool isActive;
  final int userCount;
  final int? activeMatchRequests;
  final DateTime createdAt;
  final DateTime cachedAt;
  const Pin(
      {required this.id,
      required this.name,
      this.slug,
      required this.centerLatitude,
      required this.centerLongitude,
      required this.level,
      this.parentPinId,
      required this.isActive,
      required this.userCount,
      this.activeMatchRequests,
      required this.createdAt,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || slug != null) {
      map['slug'] = Variable<String>(slug);
    }
    map['center_latitude'] = Variable<double>(centerLatitude);
    map['center_longitude'] = Variable<double>(centerLongitude);
    map['level'] = Variable<String>(level);
    if (!nullToAbsent || parentPinId != null) {
      map['parent_pin_id'] = Variable<String>(parentPinId);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['user_count'] = Variable<int>(userCount);
    if (!nullToAbsent || activeMatchRequests != null) {
      map['active_match_requests'] = Variable<int>(activeMatchRequests);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  PinsCompanion toCompanion(bool nullToAbsent) {
    return PinsCompanion(
      id: Value(id),
      name: Value(name),
      slug: slug == null && nullToAbsent ? const Value.absent() : Value(slug),
      centerLatitude: Value(centerLatitude),
      centerLongitude: Value(centerLongitude),
      level: Value(level),
      parentPinId: parentPinId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentPinId),
      isActive: Value(isActive),
      userCount: Value(userCount),
      activeMatchRequests: activeMatchRequests == null && nullToAbsent
          ? const Value.absent()
          : Value(activeMatchRequests),
      createdAt: Value(createdAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory Pin.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Pin(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      slug: serializer.fromJson<String?>(json['slug']),
      centerLatitude: serializer.fromJson<double>(json['centerLatitude']),
      centerLongitude: serializer.fromJson<double>(json['centerLongitude']),
      level: serializer.fromJson<String>(json['level']),
      parentPinId: serializer.fromJson<String?>(json['parentPinId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      userCount: serializer.fromJson<int>(json['userCount']),
      activeMatchRequests:
          serializer.fromJson<int?>(json['activeMatchRequests']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'slug': serializer.toJson<String?>(slug),
      'centerLatitude': serializer.toJson<double>(centerLatitude),
      'centerLongitude': serializer.toJson<double>(centerLongitude),
      'level': serializer.toJson<String>(level),
      'parentPinId': serializer.toJson<String?>(parentPinId),
      'isActive': serializer.toJson<bool>(isActive),
      'userCount': serializer.toJson<int>(userCount),
      'activeMatchRequests': serializer.toJson<int?>(activeMatchRequests),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  Pin copyWith(
          {String? id,
          String? name,
          Value<String?> slug = const Value.absent(),
          double? centerLatitude,
          double? centerLongitude,
          String? level,
          Value<String?> parentPinId = const Value.absent(),
          bool? isActive,
          int? userCount,
          Value<int?> activeMatchRequests = const Value.absent(),
          DateTime? createdAt,
          DateTime? cachedAt}) =>
      Pin(
        id: id ?? this.id,
        name: name ?? this.name,
        slug: slug.present ? slug.value : this.slug,
        centerLatitude: centerLatitude ?? this.centerLatitude,
        centerLongitude: centerLongitude ?? this.centerLongitude,
        level: level ?? this.level,
        parentPinId: parentPinId.present ? parentPinId.value : this.parentPinId,
        isActive: isActive ?? this.isActive,
        userCount: userCount ?? this.userCount,
        activeMatchRequests: activeMatchRequests.present
            ? activeMatchRequests.value
            : this.activeMatchRequests,
        createdAt: createdAt ?? this.createdAt,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  Pin copyWithCompanion(PinsCompanion data) {
    return Pin(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      slug: data.slug.present ? data.slug.value : this.slug,
      centerLatitude: data.centerLatitude.present
          ? data.centerLatitude.value
          : this.centerLatitude,
      centerLongitude: data.centerLongitude.present
          ? data.centerLongitude.value
          : this.centerLongitude,
      level: data.level.present ? data.level.value : this.level,
      parentPinId:
          data.parentPinId.present ? data.parentPinId.value : this.parentPinId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      userCount: data.userCount.present ? data.userCount.value : this.userCount,
      activeMatchRequests: data.activeMatchRequests.present
          ? data.activeMatchRequests.value
          : this.activeMatchRequests,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Pin(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('centerLatitude: $centerLatitude, ')
          ..write('centerLongitude: $centerLongitude, ')
          ..write('level: $level, ')
          ..write('parentPinId: $parentPinId, ')
          ..write('isActive: $isActive, ')
          ..write('userCount: $userCount, ')
          ..write('activeMatchRequests: $activeMatchRequests, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      slug,
      centerLatitude,
      centerLongitude,
      level,
      parentPinId,
      isActive,
      userCount,
      activeMatchRequests,
      createdAt,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Pin &&
          other.id == this.id &&
          other.name == this.name &&
          other.slug == this.slug &&
          other.centerLatitude == this.centerLatitude &&
          other.centerLongitude == this.centerLongitude &&
          other.level == this.level &&
          other.parentPinId == this.parentPinId &&
          other.isActive == this.isActive &&
          other.userCount == this.userCount &&
          other.activeMatchRequests == this.activeMatchRequests &&
          other.createdAt == this.createdAt &&
          other.cachedAt == this.cachedAt);
}

class PinsCompanion extends UpdateCompanion<Pin> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> slug;
  final Value<double> centerLatitude;
  final Value<double> centerLongitude;
  final Value<String> level;
  final Value<String?> parentPinId;
  final Value<bool> isActive;
  final Value<int> userCount;
  final Value<int?> activeMatchRequests;
  final Value<DateTime> createdAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const PinsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.slug = const Value.absent(),
    this.centerLatitude = const Value.absent(),
    this.centerLongitude = const Value.absent(),
    this.level = const Value.absent(),
    this.parentPinId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.userCount = const Value.absent(),
    this.activeMatchRequests = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PinsCompanion.insert({
    required String id,
    required String name,
    this.slug = const Value.absent(),
    required double centerLatitude,
    required double centerLongitude,
    required String level,
    this.parentPinId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.userCount = const Value.absent(),
    this.activeMatchRequests = const Value.absent(),
    required DateTime createdAt,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        centerLatitude = Value(centerLatitude),
        centerLongitude = Value(centerLongitude),
        level = Value(level),
        createdAt = Value(createdAt),
        cachedAt = Value(cachedAt);
  static Insertable<Pin> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? slug,
    Expression<double>? centerLatitude,
    Expression<double>? centerLongitude,
    Expression<String>? level,
    Expression<String>? parentPinId,
    Expression<bool>? isActive,
    Expression<int>? userCount,
    Expression<int>? activeMatchRequests,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (slug != null) 'slug': slug,
      if (centerLatitude != null) 'center_latitude': centerLatitude,
      if (centerLongitude != null) 'center_longitude': centerLongitude,
      if (level != null) 'level': level,
      if (parentPinId != null) 'parent_pin_id': parentPinId,
      if (isActive != null) 'is_active': isActive,
      if (userCount != null) 'user_count': userCount,
      if (activeMatchRequests != null)
        'active_match_requests': activeMatchRequests,
      if (createdAt != null) 'created_at': createdAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PinsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? slug,
      Value<double>? centerLatitude,
      Value<double>? centerLongitude,
      Value<String>? level,
      Value<String?>? parentPinId,
      Value<bool>? isActive,
      Value<int>? userCount,
      Value<int?>? activeMatchRequests,
      Value<DateTime>? createdAt,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return PinsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      level: level ?? this.level,
      parentPinId: parentPinId ?? this.parentPinId,
      isActive: isActive ?? this.isActive,
      userCount: userCount ?? this.userCount,
      activeMatchRequests: activeMatchRequests ?? this.activeMatchRequests,
      createdAt: createdAt ?? this.createdAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (centerLatitude.present) {
      map['center_latitude'] = Variable<double>(centerLatitude.value);
    }
    if (centerLongitude.present) {
      map['center_longitude'] = Variable<double>(centerLongitude.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (parentPinId.present) {
      map['parent_pin_id'] = Variable<String>(parentPinId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (userCount.present) {
      map['user_count'] = Variable<int>(userCount.value);
    }
    if (activeMatchRequests.present) {
      map['active_match_requests'] = Variable<int>(activeMatchRequests.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PinsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('slug: $slug, ')
          ..write('centerLatitude: $centerLatitude, ')
          ..write('centerLongitude: $centerLongitude, ')
          ..write('level: $level, ')
          ..write('parentPinId: $parentPinId, ')
          ..write('isActive: $isActive, ')
          ..write('userCount: $userCount, ')
          ..write('activeMatchRequests: $activeMatchRequests, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UsersTable extends Users with TableInfo<$UsersTable, User> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
      'email', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nicknameMeta =
      const VerificationMeta('nickname');
  @override
  late final GeneratedColumn<String> nickname = GeneratedColumn<String>(
      'nickname', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _profileImageUrlMeta =
      const VerificationMeta('profileImageUrl');
  @override
  late final GeneratedColumn<String> profileImageUrl = GeneratedColumn<String>(
      'profile_image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
      'phone', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('ACTIVE'));
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
      'gender', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _birthDateMeta =
      const VerificationMeta('birthDate');
  @override
  late final GeneratedColumn<DateTime> birthDate = GeneratedColumn<DateTime>(
      'birth_date', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastLoginAtMeta =
      const VerificationMeta('lastLoginAt');
  @override
  late final GeneratedColumn<DateTime> lastLoginAt = GeneratedColumn<DateTime>(
      'last_login_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sportsProfilesJsonMeta =
      const VerificationMeta('sportsProfilesJson');
  @override
  late final GeneratedColumn<String> sportsProfilesJson =
      GeneratedColumn<String>('sports_profiles_json', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('[]'));
  static const VerificationMeta _locationJsonMeta =
      const VerificationMeta('locationJson');
  @override
  late final GeneratedColumn<String> locationJson = GeneratedColumn<String>(
      'location_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        email,
        nickname,
        profileImageUrl,
        phone,
        status,
        gender,
        birthDate,
        createdAt,
        lastLoginAt,
        sportsProfilesJson,
        locationJson,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(Insertable<User> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
          _emailMeta, email.isAcceptableOrUnknown(data['email']!, _emailMeta));
    }
    if (data.containsKey('nickname')) {
      context.handle(_nicknameMeta,
          nickname.isAcceptableOrUnknown(data['nickname']!, _nicknameMeta));
    } else if (isInserting) {
      context.missing(_nicknameMeta);
    }
    if (data.containsKey('profile_image_url')) {
      context.handle(
          _profileImageUrlMeta,
          profileImageUrl.isAcceptableOrUnknown(
              data['profile_image_url']!, _profileImageUrlMeta));
    }
    if (data.containsKey('phone')) {
      context.handle(
          _phoneMeta, phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('gender')) {
      context.handle(_genderMeta,
          gender.isAcceptableOrUnknown(data['gender']!, _genderMeta));
    }
    if (data.containsKey('birth_date')) {
      context.handle(_birthDateMeta,
          birthDate.isAcceptableOrUnknown(data['birth_date']!, _birthDateMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_login_at')) {
      context.handle(
          _lastLoginAtMeta,
          lastLoginAt.isAcceptableOrUnknown(
              data['last_login_at']!, _lastLoginAtMeta));
    }
    if (data.containsKey('sports_profiles_json')) {
      context.handle(
          _sportsProfilesJsonMeta,
          sportsProfilesJson.isAcceptableOrUnknown(
              data['sports_profiles_json']!, _sportsProfilesJsonMeta));
    }
    if (data.containsKey('location_json')) {
      context.handle(
          _locationJsonMeta,
          locationJson.isAcceptableOrUnknown(
              data['location_json']!, _locationJsonMeta));
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  User map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return User(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      email: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}email']),
      nickname: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}nickname'])!,
      profileImageUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}profile_image_url']),
      phone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      gender: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}gender']),
      birthDate: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}birth_date']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastLoginAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_login_at']),
      sportsProfilesJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sports_profiles_json'])!,
      locationJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}location_json']),
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class User extends DataClass implements Insertable<User> {
  final String id;
  final String? email;
  final String nickname;
  final String? profileImageUrl;
  final String? phone;
  final String status;
  final String? gender;
  final DateTime? birthDate;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final String sportsProfilesJson;
  final String? locationJson;
  final DateTime cachedAt;
  const User(
      {required this.id,
      this.email,
      required this.nickname,
      this.profileImageUrl,
      this.phone,
      required this.status,
      this.gender,
      this.birthDate,
      required this.createdAt,
      this.lastLoginAt,
      required this.sportsProfilesJson,
      this.locationJson,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || email != null) {
      map['email'] = Variable<String>(email);
    }
    map['nickname'] = Variable<String>(nickname);
    if (!nullToAbsent || profileImageUrl != null) {
      map['profile_image_url'] = Variable<String>(profileImageUrl);
    }
    if (!nullToAbsent || phone != null) {
      map['phone'] = Variable<String>(phone);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || gender != null) {
      map['gender'] = Variable<String>(gender);
    }
    if (!nullToAbsent || birthDate != null) {
      map['birth_date'] = Variable<DateTime>(birthDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastLoginAt != null) {
      map['last_login_at'] = Variable<DateTime>(lastLoginAt);
    }
    map['sports_profiles_json'] = Variable<String>(sportsProfilesJson);
    if (!nullToAbsent || locationJson != null) {
      map['location_json'] = Variable<String>(locationJson);
    }
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      email:
          email == null && nullToAbsent ? const Value.absent() : Value(email),
      nickname: Value(nickname),
      profileImageUrl: profileImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(profileImageUrl),
      phone:
          phone == null && nullToAbsent ? const Value.absent() : Value(phone),
      status: Value(status),
      gender:
          gender == null && nullToAbsent ? const Value.absent() : Value(gender),
      birthDate: birthDate == null && nullToAbsent
          ? const Value.absent()
          : Value(birthDate),
      createdAt: Value(createdAt),
      lastLoginAt: lastLoginAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastLoginAt),
      sportsProfilesJson: Value(sportsProfilesJson),
      locationJson: locationJson == null && nullToAbsent
          ? const Value.absent()
          : Value(locationJson),
      cachedAt: Value(cachedAt),
    );
  }

  factory User.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return User(
      id: serializer.fromJson<String>(json['id']),
      email: serializer.fromJson<String?>(json['email']),
      nickname: serializer.fromJson<String>(json['nickname']),
      profileImageUrl: serializer.fromJson<String?>(json['profileImageUrl']),
      phone: serializer.fromJson<String?>(json['phone']),
      status: serializer.fromJson<String>(json['status']),
      gender: serializer.fromJson<String?>(json['gender']),
      birthDate: serializer.fromJson<DateTime?>(json['birthDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastLoginAt: serializer.fromJson<DateTime?>(json['lastLoginAt']),
      sportsProfilesJson:
          serializer.fromJson<String>(json['sportsProfilesJson']),
      locationJson: serializer.fromJson<String?>(json['locationJson']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'email': serializer.toJson<String?>(email),
      'nickname': serializer.toJson<String>(nickname),
      'profileImageUrl': serializer.toJson<String?>(profileImageUrl),
      'phone': serializer.toJson<String?>(phone),
      'status': serializer.toJson<String>(status),
      'gender': serializer.toJson<String?>(gender),
      'birthDate': serializer.toJson<DateTime?>(birthDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastLoginAt': serializer.toJson<DateTime?>(lastLoginAt),
      'sportsProfilesJson': serializer.toJson<String>(sportsProfilesJson),
      'locationJson': serializer.toJson<String?>(locationJson),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  User copyWith(
          {String? id,
          Value<String?> email = const Value.absent(),
          String? nickname,
          Value<String?> profileImageUrl = const Value.absent(),
          Value<String?> phone = const Value.absent(),
          String? status,
          Value<String?> gender = const Value.absent(),
          Value<DateTime?> birthDate = const Value.absent(),
          DateTime? createdAt,
          Value<DateTime?> lastLoginAt = const Value.absent(),
          String? sportsProfilesJson,
          Value<String?> locationJson = const Value.absent(),
          DateTime? cachedAt}) =>
      User(
        id: id ?? this.id,
        email: email.present ? email.value : this.email,
        nickname: nickname ?? this.nickname,
        profileImageUrl: profileImageUrl.present
            ? profileImageUrl.value
            : this.profileImageUrl,
        phone: phone.present ? phone.value : this.phone,
        status: status ?? this.status,
        gender: gender.present ? gender.value : this.gender,
        birthDate: birthDate.present ? birthDate.value : this.birthDate,
        createdAt: createdAt ?? this.createdAt,
        lastLoginAt: lastLoginAt.present ? lastLoginAt.value : this.lastLoginAt,
        sportsProfilesJson: sportsProfilesJson ?? this.sportsProfilesJson,
        locationJson:
            locationJson.present ? locationJson.value : this.locationJson,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  User copyWithCompanion(UsersCompanion data) {
    return User(
      id: data.id.present ? data.id.value : this.id,
      email: data.email.present ? data.email.value : this.email,
      nickname: data.nickname.present ? data.nickname.value : this.nickname,
      profileImageUrl: data.profileImageUrl.present
          ? data.profileImageUrl.value
          : this.profileImageUrl,
      phone: data.phone.present ? data.phone.value : this.phone,
      status: data.status.present ? data.status.value : this.status,
      gender: data.gender.present ? data.gender.value : this.gender,
      birthDate: data.birthDate.present ? data.birthDate.value : this.birthDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastLoginAt:
          data.lastLoginAt.present ? data.lastLoginAt.value : this.lastLoginAt,
      sportsProfilesJson: data.sportsProfilesJson.present
          ? data.sportsProfilesJson.value
          : this.sportsProfilesJson,
      locationJson: data.locationJson.present
          ? data.locationJson.value
          : this.locationJson,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('User(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('nickname: $nickname, ')
          ..write('profileImageUrl: $profileImageUrl, ')
          ..write('phone: $phone, ')
          ..write('status: $status, ')
          ..write('gender: $gender, ')
          ..write('birthDate: $birthDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastLoginAt: $lastLoginAt, ')
          ..write('sportsProfilesJson: $sportsProfilesJson, ')
          ..write('locationJson: $locationJson, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      email,
      nickname,
      profileImageUrl,
      phone,
      status,
      gender,
      birthDate,
      createdAt,
      lastLoginAt,
      sportsProfilesJson,
      locationJson,
      cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          other.id == this.id &&
          other.email == this.email &&
          other.nickname == this.nickname &&
          other.profileImageUrl == this.profileImageUrl &&
          other.phone == this.phone &&
          other.status == this.status &&
          other.gender == this.gender &&
          other.birthDate == this.birthDate &&
          other.createdAt == this.createdAt &&
          other.lastLoginAt == this.lastLoginAt &&
          other.sportsProfilesJson == this.sportsProfilesJson &&
          other.locationJson == this.locationJson &&
          other.cachedAt == this.cachedAt);
}

class UsersCompanion extends UpdateCompanion<User> {
  final Value<String> id;
  final Value<String?> email;
  final Value<String> nickname;
  final Value<String?> profileImageUrl;
  final Value<String?> phone;
  final Value<String> status;
  final Value<String?> gender;
  final Value<DateTime?> birthDate;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastLoginAt;
  final Value<String> sportsProfilesJson;
  final Value<String?> locationJson;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.email = const Value.absent(),
    this.nickname = const Value.absent(),
    this.profileImageUrl = const Value.absent(),
    this.phone = const Value.absent(),
    this.status = const Value.absent(),
    this.gender = const Value.absent(),
    this.birthDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastLoginAt = const Value.absent(),
    this.sportsProfilesJson = const Value.absent(),
    this.locationJson = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String id,
    this.email = const Value.absent(),
    required String nickname,
    this.profileImageUrl = const Value.absent(),
    this.phone = const Value.absent(),
    this.status = const Value.absent(),
    this.gender = const Value.absent(),
    this.birthDate = const Value.absent(),
    required DateTime createdAt,
    this.lastLoginAt = const Value.absent(),
    this.sportsProfilesJson = const Value.absent(),
    this.locationJson = const Value.absent(),
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        nickname = Value(nickname),
        createdAt = Value(createdAt),
        cachedAt = Value(cachedAt);
  static Insertable<User> custom({
    Expression<String>? id,
    Expression<String>? email,
    Expression<String>? nickname,
    Expression<String>? profileImageUrl,
    Expression<String>? phone,
    Expression<String>? status,
    Expression<String>? gender,
    Expression<DateTime>? birthDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastLoginAt,
    Expression<String>? sportsProfilesJson,
    Expression<String>? locationJson,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (email != null) 'email': email,
      if (nickname != null) 'nickname': nickname,
      if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
      if (phone != null) 'phone': phone,
      if (status != null) 'status': status,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birth_date': birthDate,
      if (createdAt != null) 'created_at': createdAt,
      if (lastLoginAt != null) 'last_login_at': lastLoginAt,
      if (sportsProfilesJson != null)
        'sports_profiles_json': sportsProfilesJson,
      if (locationJson != null) 'location_json': locationJson,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith(
      {Value<String>? id,
      Value<String?>? email,
      Value<String>? nickname,
      Value<String?>? profileImageUrl,
      Value<String?>? phone,
      Value<String>? status,
      Value<String?>? gender,
      Value<DateTime?>? birthDate,
      Value<DateTime>? createdAt,
      Value<DateTime?>? lastLoginAt,
      Value<String>? sportsProfilesJson,
      Value<String?>? locationJson,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return UsersCompanion(
      id: id ?? this.id,
      email: email ?? this.email,
      nickname: nickname ?? this.nickname,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      phone: phone ?? this.phone,
      status: status ?? this.status,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      sportsProfilesJson: sportsProfilesJson ?? this.sportsProfilesJson,
      locationJson: locationJson ?? this.locationJson,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (nickname.present) {
      map['nickname'] = Variable<String>(nickname.value);
    }
    if (profileImageUrl.present) {
      map['profile_image_url'] = Variable<String>(profileImageUrl.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (birthDate.present) {
      map['birth_date'] = Variable<DateTime>(birthDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastLoginAt.present) {
      map['last_login_at'] = Variable<DateTime>(lastLoginAt.value);
    }
    if (sportsProfilesJson.present) {
      map['sports_profiles_json'] = Variable<String>(sportsProfilesJson.value);
    }
    if (locationJson.present) {
      map['location_json'] = Variable<String>(locationJson.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('email: $email, ')
          ..write('nickname: $nickname, ')
          ..write('profileImageUrl: $profileImageUrl, ')
          ..write('phone: $phone, ')
          ..write('status: $status, ')
          ..write('gender: $gender, ')
          ..write('birthDate: $birthDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastLoginAt: $lastLoginAt, ')
          ..write('sportsProfilesJson: $sportsProfilesJson, ')
          ..write('locationJson: $locationJson, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatRoomsTable extends ChatRooms
    with TableInfo<$ChatRoomsTable, ChatRoom> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatRoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _matchIdMeta =
      const VerificationMeta('matchId');
  @override
  late final GeneratedColumn<String> matchId = GeneratedColumn<String>(
      'match_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _opponentJsonMeta =
      const VerificationMeta('opponentJson');
  @override
  late final GeneratedColumn<String> opponentJson = GeneratedColumn<String>(
      'opponent_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastMessageJsonMeta =
      const VerificationMeta('lastMessageJson');
  @override
  late final GeneratedColumn<String> lastMessageJson = GeneratedColumn<String>(
      'last_message_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        matchId,
        opponentJson,
        lastMessageJson,
        unreadCount,
        isActive,
        createdAt,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_rooms';
  @override
  VerificationContext validateIntegrity(Insertable<ChatRoom> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('match_id')) {
      context.handle(_matchIdMeta,
          matchId.isAcceptableOrUnknown(data['match_id']!, _matchIdMeta));
    } else if (isInserting) {
      context.missing(_matchIdMeta);
    }
    if (data.containsKey('opponent_json')) {
      context.handle(
          _opponentJsonMeta,
          opponentJson.isAcceptableOrUnknown(
              data['opponent_json']!, _opponentJsonMeta));
    } else if (isInserting) {
      context.missing(_opponentJsonMeta);
    }
    if (data.containsKey('last_message_json')) {
      context.handle(
          _lastMessageJsonMeta,
          lastMessageJson.isAcceptableOrUnknown(
              data['last_message_json']!, _lastMessageJsonMeta));
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatRoom map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatRoom(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      matchId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}match_id'])!,
      opponentJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}opponent_json'])!,
      lastMessageJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_message_json']),
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $ChatRoomsTable createAlias(String alias) {
    return $ChatRoomsTable(attachedDatabase, alias);
  }
}

class ChatRoom extends DataClass implements Insertable<ChatRoom> {
  final String id;
  final String matchId;
  final String opponentJson;
  final String? lastMessageJson;
  final int unreadCount;
  final bool isActive;
  final DateTime createdAt;
  final DateTime cachedAt;
  const ChatRoom(
      {required this.id,
      required this.matchId,
      required this.opponentJson,
      this.lastMessageJson,
      required this.unreadCount,
      required this.isActive,
      required this.createdAt,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['match_id'] = Variable<String>(matchId);
    map['opponent_json'] = Variable<String>(opponentJson);
    if (!nullToAbsent || lastMessageJson != null) {
      map['last_message_json'] = Variable<String>(lastMessageJson);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  ChatRoomsCompanion toCompanion(bool nullToAbsent) {
    return ChatRoomsCompanion(
      id: Value(id),
      matchId: Value(matchId),
      opponentJson: Value(opponentJson),
      lastMessageJson: lastMessageJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageJson),
      unreadCount: Value(unreadCount),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory ChatRoom.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatRoom(
      id: serializer.fromJson<String>(json['id']),
      matchId: serializer.fromJson<String>(json['matchId']),
      opponentJson: serializer.fromJson<String>(json['opponentJson']),
      lastMessageJson: serializer.fromJson<String?>(json['lastMessageJson']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'matchId': serializer.toJson<String>(matchId),
      'opponentJson': serializer.toJson<String>(opponentJson),
      'lastMessageJson': serializer.toJson<String?>(lastMessageJson),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  ChatRoom copyWith(
          {String? id,
          String? matchId,
          String? opponentJson,
          Value<String?> lastMessageJson = const Value.absent(),
          int? unreadCount,
          bool? isActive,
          DateTime? createdAt,
          DateTime? cachedAt}) =>
      ChatRoom(
        id: id ?? this.id,
        matchId: matchId ?? this.matchId,
        opponentJson: opponentJson ?? this.opponentJson,
        lastMessageJson: lastMessageJson.present
            ? lastMessageJson.value
            : this.lastMessageJson,
        unreadCount: unreadCount ?? this.unreadCount,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  ChatRoom copyWithCompanion(ChatRoomsCompanion data) {
    return ChatRoom(
      id: data.id.present ? data.id.value : this.id,
      matchId: data.matchId.present ? data.matchId.value : this.matchId,
      opponentJson: data.opponentJson.present
          ? data.opponentJson.value
          : this.opponentJson,
      lastMessageJson: data.lastMessageJson.present
          ? data.lastMessageJson.value
          : this.lastMessageJson,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatRoom(')
          ..write('id: $id, ')
          ..write('matchId: $matchId, ')
          ..write('opponentJson: $opponentJson, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, matchId, opponentJson, lastMessageJson,
      unreadCount, isActive, createdAt, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatRoom &&
          other.id == this.id &&
          other.matchId == this.matchId &&
          other.opponentJson == this.opponentJson &&
          other.lastMessageJson == this.lastMessageJson &&
          other.unreadCount == this.unreadCount &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.cachedAt == this.cachedAt);
}

class ChatRoomsCompanion extends UpdateCompanion<ChatRoom> {
  final Value<String> id;
  final Value<String> matchId;
  final Value<String> opponentJson;
  final Value<String?> lastMessageJson;
  final Value<int> unreadCount;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const ChatRoomsCompanion({
    this.id = const Value.absent(),
    this.matchId = const Value.absent(),
    this.opponentJson = const Value.absent(),
    this.lastMessageJson = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatRoomsCompanion.insert({
    required String id,
    required String matchId,
    required String opponentJson,
    this.lastMessageJson = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isActive = const Value.absent(),
    required DateTime createdAt,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        matchId = Value(matchId),
        opponentJson = Value(opponentJson),
        createdAt = Value(createdAt),
        cachedAt = Value(cachedAt);
  static Insertable<ChatRoom> custom({
    Expression<String>? id,
    Expression<String>? matchId,
    Expression<String>? opponentJson,
    Expression<String>? lastMessageJson,
    Expression<int>? unreadCount,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (matchId != null) 'match_id': matchId,
      if (opponentJson != null) 'opponent_json': opponentJson,
      if (lastMessageJson != null) 'last_message_json': lastMessageJson,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatRoomsCompanion copyWith(
      {Value<String>? id,
      Value<String>? matchId,
      Value<String>? opponentJson,
      Value<String?>? lastMessageJson,
      Value<int>? unreadCount,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return ChatRoomsCompanion(
      id: id ?? this.id,
      matchId: matchId ?? this.matchId,
      opponentJson: opponentJson ?? this.opponentJson,
      lastMessageJson: lastMessageJson ?? this.lastMessageJson,
      unreadCount: unreadCount ?? this.unreadCount,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (matchId.present) {
      map['match_id'] = Variable<String>(matchId.value);
    }
    if (opponentJson.present) {
      map['opponent_json'] = Variable<String>(opponentJson.value);
    }
    if (lastMessageJson.present) {
      map['last_message_json'] = Variable<String>(lastMessageJson.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatRoomsCompanion(')
          ..write('id: $id, ')
          ..write('matchId: $matchId, ')
          ..write('opponentJson: $opponentJson, ')
          ..write('lastMessageJson: $lastMessageJson, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chatRoomIdMeta =
      const VerificationMeta('chatRoomId');
  @override
  late final GeneratedColumn<String> chatRoomId = GeneratedColumn<String>(
      'chat_room_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderNicknameMeta =
      const VerificationMeta('senderNickname');
  @override
  late final GeneratedColumn<String> senderNickname = GeneratedColumn<String>(
      'sender_nickname', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderProfileImageUrlMeta =
      const VerificationMeta('senderProfileImageUrl');
  @override
  late final GeneratedColumn<String> senderProfileImageUrl =
      GeneratedColumn<String>('sender_profile_image_url', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('TEXT'));
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _extraDataMeta =
      const VerificationMeta('extraData');
  @override
  late final GeneratedColumn<String> extraData = GeneratedColumn<String>(
      'extra_data', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _readAtMeta = const VerificationMeta('readAt');
  @override
  late final GeneratedColumn<DateTime> readAt = GeneratedColumn<DateTime>(
      'read_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        chatRoomId,
        senderId,
        senderNickname,
        senderProfileImageUrl,
        messageType,
        content,
        imageUrl,
        extraData,
        isRead,
        readAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('chat_room_id')) {
      context.handle(
          _chatRoomIdMeta,
          chatRoomId.isAcceptableOrUnknown(
              data['chat_room_id']!, _chatRoomIdMeta));
    } else if (isInserting) {
      context.missing(_chatRoomIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('sender_nickname')) {
      context.handle(
          _senderNicknameMeta,
          senderNickname.isAcceptableOrUnknown(
              data['sender_nickname']!, _senderNicknameMeta));
    } else if (isInserting) {
      context.missing(_senderNicknameMeta);
    }
    if (data.containsKey('sender_profile_image_url')) {
      context.handle(
          _senderProfileImageUrlMeta,
          senderProfileImageUrl.isAcceptableOrUnknown(
              data['sender_profile_image_url']!, _senderProfileImageUrlMeta));
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    if (data.containsKey('extra_data')) {
      context.handle(_extraDataMeta,
          extraData.isAcceptableOrUnknown(data['extra_data']!, _extraDataMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('read_at')) {
      context.handle(_readAtMeta,
          readAt.isAcceptableOrUnknown(data['read_at']!, _readAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      chatRoomId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chat_room_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      senderNickname: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sender_nickname'])!,
      senderProfileImageUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sender_profile_image_url']),
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
      extraData: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extra_data']),
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      readAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}read_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String chatRoomId;
  final String senderId;
  final String senderNickname;
  final String? senderProfileImageUrl;
  final String messageType;
  final String content;
  final String? imageUrl;
  final String? extraData;
  final bool isRead;
  final DateTime? readAt;
  final DateTime createdAt;
  const Message(
      {required this.id,
      required this.chatRoomId,
      required this.senderId,
      required this.senderNickname,
      this.senderProfileImageUrl,
      required this.messageType,
      required this.content,
      this.imageUrl,
      this.extraData,
      required this.isRead,
      this.readAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['chat_room_id'] = Variable<String>(chatRoomId);
    map['sender_id'] = Variable<String>(senderId);
    map['sender_nickname'] = Variable<String>(senderNickname);
    if (!nullToAbsent || senderProfileImageUrl != null) {
      map['sender_profile_image_url'] = Variable<String>(senderProfileImageUrl);
    }
    map['message_type'] = Variable<String>(messageType);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    if (!nullToAbsent || extraData != null) {
      map['extra_data'] = Variable<String>(extraData);
    }
    map['is_read'] = Variable<bool>(isRead);
    if (!nullToAbsent || readAt != null) {
      map['read_at'] = Variable<DateTime>(readAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      chatRoomId: Value(chatRoomId),
      senderId: Value(senderId),
      senderNickname: Value(senderNickname),
      senderProfileImageUrl: senderProfileImageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(senderProfileImageUrl),
      messageType: Value(messageType),
      content: Value(content),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      extraData: extraData == null && nullToAbsent
          ? const Value.absent()
          : Value(extraData),
      isRead: Value(isRead),
      readAt:
          readAt == null && nullToAbsent ? const Value.absent() : Value(readAt),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      chatRoomId: serializer.fromJson<String>(json['chatRoomId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      senderNickname: serializer.fromJson<String>(json['senderNickname']),
      senderProfileImageUrl:
          serializer.fromJson<String?>(json['senderProfileImageUrl']),
      messageType: serializer.fromJson<String>(json['messageType']),
      content: serializer.fromJson<String>(json['content']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      extraData: serializer.fromJson<String?>(json['extraData']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      readAt: serializer.fromJson<DateTime?>(json['readAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'chatRoomId': serializer.toJson<String>(chatRoomId),
      'senderId': serializer.toJson<String>(senderId),
      'senderNickname': serializer.toJson<String>(senderNickname),
      'senderProfileImageUrl':
          serializer.toJson<String?>(senderProfileImageUrl),
      'messageType': serializer.toJson<String>(messageType),
      'content': serializer.toJson<String>(content),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'extraData': serializer.toJson<String?>(extraData),
      'isRead': serializer.toJson<bool>(isRead),
      'readAt': serializer.toJson<DateTime?>(readAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith(
          {String? id,
          String? chatRoomId,
          String? senderId,
          String? senderNickname,
          Value<String?> senderProfileImageUrl = const Value.absent(),
          String? messageType,
          String? content,
          Value<String?> imageUrl = const Value.absent(),
          Value<String?> extraData = const Value.absent(),
          bool? isRead,
          Value<DateTime?> readAt = const Value.absent(),
          DateTime? createdAt}) =>
      Message(
        id: id ?? this.id,
        chatRoomId: chatRoomId ?? this.chatRoomId,
        senderId: senderId ?? this.senderId,
        senderNickname: senderNickname ?? this.senderNickname,
        senderProfileImageUrl: senderProfileImageUrl.present
            ? senderProfileImageUrl.value
            : this.senderProfileImageUrl,
        messageType: messageType ?? this.messageType,
        content: content ?? this.content,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
        extraData: extraData.present ? extraData.value : this.extraData,
        isRead: isRead ?? this.isRead,
        readAt: readAt.present ? readAt.value : this.readAt,
        createdAt: createdAt ?? this.createdAt,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      chatRoomId:
          data.chatRoomId.present ? data.chatRoomId.value : this.chatRoomId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      senderNickname: data.senderNickname.present
          ? data.senderNickname.value
          : this.senderNickname,
      senderProfileImageUrl: data.senderProfileImageUrl.present
          ? data.senderProfileImageUrl.value
          : this.senderProfileImageUrl,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      content: data.content.present ? data.content.value : this.content,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      extraData: data.extraData.present ? data.extraData.value : this.extraData,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      readAt: data.readAt.present ? data.readAt.value : this.readAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('chatRoomId: $chatRoomId, ')
          ..write('senderId: $senderId, ')
          ..write('senderNickname: $senderNickname, ')
          ..write('senderProfileImageUrl: $senderProfileImageUrl, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('extraData: $extraData, ')
          ..write('isRead: $isRead, ')
          ..write('readAt: $readAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      chatRoomId,
      senderId,
      senderNickname,
      senderProfileImageUrl,
      messageType,
      content,
      imageUrl,
      extraData,
      isRead,
      readAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.chatRoomId == this.chatRoomId &&
          other.senderId == this.senderId &&
          other.senderNickname == this.senderNickname &&
          other.senderProfileImageUrl == this.senderProfileImageUrl &&
          other.messageType == this.messageType &&
          other.content == this.content &&
          other.imageUrl == this.imageUrl &&
          other.extraData == this.extraData &&
          other.isRead == this.isRead &&
          other.readAt == this.readAt &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> chatRoomId;
  final Value<String> senderId;
  final Value<String> senderNickname;
  final Value<String?> senderProfileImageUrl;
  final Value<String> messageType;
  final Value<String> content;
  final Value<String?> imageUrl;
  final Value<String?> extraData;
  final Value<bool> isRead;
  final Value<DateTime?> readAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.chatRoomId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.senderNickname = const Value.absent(),
    this.senderProfileImageUrl = const Value.absent(),
    this.messageType = const Value.absent(),
    this.content = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.extraData = const Value.absent(),
    this.isRead = const Value.absent(),
    this.readAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String chatRoomId,
    required String senderId,
    required String senderNickname,
    this.senderProfileImageUrl = const Value.absent(),
    this.messageType = const Value.absent(),
    required String content,
    this.imageUrl = const Value.absent(),
    this.extraData = const Value.absent(),
    this.isRead = const Value.absent(),
    this.readAt = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        chatRoomId = Value(chatRoomId),
        senderId = Value(senderId),
        senderNickname = Value(senderNickname),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? chatRoomId,
    Expression<String>? senderId,
    Expression<String>? senderNickname,
    Expression<String>? senderProfileImageUrl,
    Expression<String>? messageType,
    Expression<String>? content,
    Expression<String>? imageUrl,
    Expression<String>? extraData,
    Expression<bool>? isRead,
    Expression<DateTime>? readAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (chatRoomId != null) 'chat_room_id': chatRoomId,
      if (senderId != null) 'sender_id': senderId,
      if (senderNickname != null) 'sender_nickname': senderNickname,
      if (senderProfileImageUrl != null)
        'sender_profile_image_url': senderProfileImageUrl,
      if (messageType != null) 'message_type': messageType,
      if (content != null) 'content': content,
      if (imageUrl != null) 'image_url': imageUrl,
      if (extraData != null) 'extra_data': extraData,
      if (isRead != null) 'is_read': isRead,
      if (readAt != null) 'read_at': readAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? chatRoomId,
      Value<String>? senderId,
      Value<String>? senderNickname,
      Value<String?>? senderProfileImageUrl,
      Value<String>? messageType,
      Value<String>? content,
      Value<String?>? imageUrl,
      Value<String?>? extraData,
      Value<bool>? isRead,
      Value<DateTime?>? readAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      chatRoomId: chatRoomId ?? this.chatRoomId,
      senderId: senderId ?? this.senderId,
      senderNickname: senderNickname ?? this.senderNickname,
      senderProfileImageUrl:
          senderProfileImageUrl ?? this.senderProfileImageUrl,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      extraData: extraData ?? this.extraData,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (chatRoomId.present) {
      map['chat_room_id'] = Variable<String>(chatRoomId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (senderNickname.present) {
      map['sender_nickname'] = Variable<String>(senderNickname.value);
    }
    if (senderProfileImageUrl.present) {
      map['sender_profile_image_url'] =
          Variable<String>(senderProfileImageUrl.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (extraData.present) {
      map['extra_data'] = Variable<String>(extraData.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (readAt.present) {
      map['read_at'] = Variable<DateTime>(readAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('chatRoomId: $chatRoomId, ')
          ..write('senderId: $senderId, ')
          ..write('senderNickname: $senderNickname, ')
          ..write('senderProfileImageUrl: $senderProfileImageUrl, ')
          ..write('messageType: $messageType, ')
          ..write('content: $content, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('extraData: $extraData, ')
          ..write('isRead: $isRead, ')
          ..write('readAt: $readAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MatchesTable extends Matches with TableInfo<$MatchesTable, Matche> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MatchesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sportTypeMeta =
      const VerificationMeta('sportType');
  @override
  late final GeneratedColumn<String> sportType = GeneratedColumn<String>(
      'sport_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pinIdMeta = const VerificationMeta('pinId');
  @override
  late final GeneratedColumn<String> pinId = GeneratedColumn<String>(
      'pin_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _requesterIdMeta =
      const VerificationMeta('requesterId');
  @override
  late final GeneratedColumn<String> requesterId = GeneratedColumn<String>(
      'requester_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responderIdMeta =
      const VerificationMeta('responderId');
  @override
  late final GeneratedColumn<String> responderId = GeneratedColumn<String>(
      'responder_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _detailJsonMeta =
      const VerificationMeta('detailJson');
  @override
  late final GeneratedColumn<String> detailJson = GeneratedColumn<String>(
      'detail_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _scheduledAtMeta =
      const VerificationMeta('scheduledAt');
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
      'scheduled_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _cachedAtMeta =
      const VerificationMeta('cachedAt');
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
      'cached_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        status,
        sportType,
        pinId,
        requesterId,
        responderId,
        detailJson,
        scheduledAt,
        createdAt,
        cachedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'matches';
  @override
  VerificationContext validateIntegrity(Insertable<Matche> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('sport_type')) {
      context.handle(_sportTypeMeta,
          sportType.isAcceptableOrUnknown(data['sport_type']!, _sportTypeMeta));
    } else if (isInserting) {
      context.missing(_sportTypeMeta);
    }
    if (data.containsKey('pin_id')) {
      context.handle(
          _pinIdMeta, pinId.isAcceptableOrUnknown(data['pin_id']!, _pinIdMeta));
    }
    if (data.containsKey('requester_id')) {
      context.handle(
          _requesterIdMeta,
          requesterId.isAcceptableOrUnknown(
              data['requester_id']!, _requesterIdMeta));
    } else if (isInserting) {
      context.missing(_requesterIdMeta);
    }
    if (data.containsKey('responder_id')) {
      context.handle(
          _responderIdMeta,
          responderId.isAcceptableOrUnknown(
              data['responder_id']!, _responderIdMeta));
    }
    if (data.containsKey('detail_json')) {
      context.handle(
          _detailJsonMeta,
          detailJson.isAcceptableOrUnknown(
              data['detail_json']!, _detailJsonMeta));
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
          _scheduledAtMeta,
          scheduledAt.isAcceptableOrUnknown(
              data['scheduled_at']!, _scheduledAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(_cachedAtMeta,
          cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta));
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Matche map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Matche(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      sportType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sport_type'])!,
      pinId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pin_id']),
      requesterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}requester_id'])!,
      responderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}responder_id']),
      detailJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail_json']),
      scheduledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}scheduled_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      cachedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cached_at'])!,
    );
  }

  @override
  $MatchesTable createAlias(String alias) {
    return $MatchesTable(attachedDatabase, alias);
  }
}

class Matche extends DataClass implements Insertable<Matche> {
  final String id;
  final String status;
  final String sportType;
  final String? pinId;
  final String requesterId;
  final String? responderId;
  final String? detailJson;
  final DateTime? scheduledAt;
  final DateTime createdAt;
  final DateTime cachedAt;
  const Matche(
      {required this.id,
      required this.status,
      required this.sportType,
      this.pinId,
      required this.requesterId,
      this.responderId,
      this.detailJson,
      this.scheduledAt,
      required this.createdAt,
      required this.cachedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['status'] = Variable<String>(status);
    map['sport_type'] = Variable<String>(sportType);
    if (!nullToAbsent || pinId != null) {
      map['pin_id'] = Variable<String>(pinId);
    }
    map['requester_id'] = Variable<String>(requesterId);
    if (!nullToAbsent || responderId != null) {
      map['responder_id'] = Variable<String>(responderId);
    }
    if (!nullToAbsent || detailJson != null) {
      map['detail_json'] = Variable<String>(detailJson);
    }
    if (!nullToAbsent || scheduledAt != null) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  MatchesCompanion toCompanion(bool nullToAbsent) {
    return MatchesCompanion(
      id: Value(id),
      status: Value(status),
      sportType: Value(sportType),
      pinId:
          pinId == null && nullToAbsent ? const Value.absent() : Value(pinId),
      requesterId: Value(requesterId),
      responderId: responderId == null && nullToAbsent
          ? const Value.absent()
          : Value(responderId),
      detailJson: detailJson == null && nullToAbsent
          ? const Value.absent()
          : Value(detailJson),
      scheduledAt: scheduledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledAt),
      createdAt: Value(createdAt),
      cachedAt: Value(cachedAt),
    );
  }

  factory Matche.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Matche(
      id: serializer.fromJson<String>(json['id']),
      status: serializer.fromJson<String>(json['status']),
      sportType: serializer.fromJson<String>(json['sportType']),
      pinId: serializer.fromJson<String?>(json['pinId']),
      requesterId: serializer.fromJson<String>(json['requesterId']),
      responderId: serializer.fromJson<String?>(json['responderId']),
      detailJson: serializer.fromJson<String?>(json['detailJson']),
      scheduledAt: serializer.fromJson<DateTime?>(json['scheduledAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'status': serializer.toJson<String>(status),
      'sportType': serializer.toJson<String>(sportType),
      'pinId': serializer.toJson<String?>(pinId),
      'requesterId': serializer.toJson<String>(requesterId),
      'responderId': serializer.toJson<String?>(responderId),
      'detailJson': serializer.toJson<String?>(detailJson),
      'scheduledAt': serializer.toJson<DateTime?>(scheduledAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  Matche copyWith(
          {String? id,
          String? status,
          String? sportType,
          Value<String?> pinId = const Value.absent(),
          String? requesterId,
          Value<String?> responderId = const Value.absent(),
          Value<String?> detailJson = const Value.absent(),
          Value<DateTime?> scheduledAt = const Value.absent(),
          DateTime? createdAt,
          DateTime? cachedAt}) =>
      Matche(
        id: id ?? this.id,
        status: status ?? this.status,
        sportType: sportType ?? this.sportType,
        pinId: pinId.present ? pinId.value : this.pinId,
        requesterId: requesterId ?? this.requesterId,
        responderId: responderId.present ? responderId.value : this.responderId,
        detailJson: detailJson.present ? detailJson.value : this.detailJson,
        scheduledAt: scheduledAt.present ? scheduledAt.value : this.scheduledAt,
        createdAt: createdAt ?? this.createdAt,
        cachedAt: cachedAt ?? this.cachedAt,
      );
  Matche copyWithCompanion(MatchesCompanion data) {
    return Matche(
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      sportType: data.sportType.present ? data.sportType.value : this.sportType,
      pinId: data.pinId.present ? data.pinId.value : this.pinId,
      requesterId:
          data.requesterId.present ? data.requesterId.value : this.requesterId,
      responderId:
          data.responderId.present ? data.responderId.value : this.responderId,
      detailJson:
          data.detailJson.present ? data.detailJson.value : this.detailJson,
      scheduledAt:
          data.scheduledAt.present ? data.scheduledAt.value : this.scheduledAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Matche(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('sportType: $sportType, ')
          ..write('pinId: $pinId, ')
          ..write('requesterId: $requesterId, ')
          ..write('responderId: $responderId, ')
          ..write('detailJson: $detailJson, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, status, sportType, pinId, requesterId,
      responderId, detailJson, scheduledAt, createdAt, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Matche &&
          other.id == this.id &&
          other.status == this.status &&
          other.sportType == this.sportType &&
          other.pinId == this.pinId &&
          other.requesterId == this.requesterId &&
          other.responderId == this.responderId &&
          other.detailJson == this.detailJson &&
          other.scheduledAt == this.scheduledAt &&
          other.createdAt == this.createdAt &&
          other.cachedAt == this.cachedAt);
}

class MatchesCompanion extends UpdateCompanion<Matche> {
  final Value<String> id;
  final Value<String> status;
  final Value<String> sportType;
  final Value<String?> pinId;
  final Value<String> requesterId;
  final Value<String?> responderId;
  final Value<String?> detailJson;
  final Value<DateTime?> scheduledAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const MatchesCompanion({
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.sportType = const Value.absent(),
    this.pinId = const Value.absent(),
    this.requesterId = const Value.absent(),
    this.responderId = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MatchesCompanion.insert({
    required String id,
    required String status,
    required String sportType,
    this.pinId = const Value.absent(),
    required String requesterId,
    this.responderId = const Value.absent(),
    this.detailJson = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    required DateTime createdAt,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        status = Value(status),
        sportType = Value(sportType),
        requesterId = Value(requesterId),
        createdAt = Value(createdAt),
        cachedAt = Value(cachedAt);
  static Insertable<Matche> custom({
    Expression<String>? id,
    Expression<String>? status,
    Expression<String>? sportType,
    Expression<String>? pinId,
    Expression<String>? requesterId,
    Expression<String>? responderId,
    Expression<String>? detailJson,
    Expression<DateTime>? scheduledAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (sportType != null) 'sport_type': sportType,
      if (pinId != null) 'pin_id': pinId,
      if (requesterId != null) 'requester_id': requesterId,
      if (responderId != null) 'responder_id': responderId,
      if (detailJson != null) 'detail_json': detailJson,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (createdAt != null) 'created_at': createdAt,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MatchesCompanion copyWith(
      {Value<String>? id,
      Value<String>? status,
      Value<String>? sportType,
      Value<String?>? pinId,
      Value<String>? requesterId,
      Value<String?>? responderId,
      Value<String?>? detailJson,
      Value<DateTime?>? scheduledAt,
      Value<DateTime>? createdAt,
      Value<DateTime>? cachedAt,
      Value<int>? rowid}) {
    return MatchesCompanion(
      id: id ?? this.id,
      status: status ?? this.status,
      sportType: sportType ?? this.sportType,
      pinId: pinId ?? this.pinId,
      requesterId: requesterId ?? this.requesterId,
      responderId: responderId ?? this.responderId,
      detailJson: detailJson ?? this.detailJson,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      createdAt: createdAt ?? this.createdAt,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sportType.present) {
      map['sport_type'] = Variable<String>(sportType.value);
    }
    if (pinId.present) {
      map['pin_id'] = Variable<String>(pinId.value);
    }
    if (requesterId.present) {
      map['requester_id'] = Variable<String>(requesterId.value);
    }
    if (responderId.present) {
      map['responder_id'] = Variable<String>(responderId.value);
    }
    if (detailJson.present) {
      map['detail_json'] = Variable<String>(detailJson.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MatchesCompanion(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('sportType: $sportType, ')
          ..write('pinId: $pinId, ')
          ..write('requesterId: $requesterId, ')
          ..write('responderId: $responderId, ')
          ..write('detailJson: $detailJson, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflineQueueTable extends OfflineQueue
    with TableInfo<$OfflineQueueTable, OfflineQueueData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadJsonMeta =
      const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
      'payload_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('PENDING'));
  static const VerificationMeta _retryCountMeta =
      const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
      'retry_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        action,
        payloadJson,
        status,
        retryCount,
        lastError,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_queue';
  @override
  VerificationContext validateIntegrity(Insertable<OfflineQueueData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
          _payloadJsonMeta,
          payloadJson.isAcceptableOrUnknown(
              data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
          _retryCountMeta,
          retryCount.isAcceptableOrUnknown(
              data['retry_count']!, _retryCountMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OfflineQueueData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineQueueData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      payloadJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      retryCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}retry_count'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $OfflineQueueTable createAlias(String alias) {
    return $OfflineQueueTable(attachedDatabase, alias);
  }
}

class OfflineQueueData extends DataClass
    implements Insertable<OfflineQueueData> {
  final int id;
  final String action;
  final String payloadJson;
  final String status;
  final int retryCount;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OfflineQueueData(
      {required this.id,
      required this.action,
      required this.payloadJson,
      required this.status,
      required this.retryCount,
      this.lastError,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['action'] = Variable<String>(action);
    map['payload_json'] = Variable<String>(payloadJson);
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OfflineQueueCompanion toCompanion(bool nullToAbsent) {
    return OfflineQueueCompanion(
      id: Value(id),
      action: Value(action),
      payloadJson: Value(payloadJson),
      status: Value(status),
      retryCount: Value(retryCount),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OfflineQueueData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineQueueData(
      id: serializer.fromJson<int>(json['id']),
      action: serializer.fromJson<String>(json['action']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'action': serializer.toJson<String>(action),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OfflineQueueData copyWith(
          {int? id,
          String? action,
          String? payloadJson,
          String? status,
          int? retryCount,
          Value<String?> lastError = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      OfflineQueueData(
        id: id ?? this.id,
        action: action ?? this.action,
        payloadJson: payloadJson ?? this.payloadJson,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError.present ? lastError.value : this.lastError,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  OfflineQueueData copyWithCompanion(OfflineQueueCompanion data) {
    return OfflineQueueData(
      id: data.id.present ? data.id.value : this.id,
      action: data.action.present ? data.action.value : this.action,
      payloadJson:
          data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      status: data.status.present ? data.status.value : this.status,
      retryCount:
          data.retryCount.present ? data.retryCount.value : this.retryCount,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueData(')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, action, payloadJson, status, retryCount,
      lastError, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineQueueData &&
          other.id == this.id &&
          other.action == this.action &&
          other.payloadJson == this.payloadJson &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OfflineQueueCompanion extends UpdateCompanion<OfflineQueueData> {
  final Value<int> id;
  final Value<String> action;
  final Value<String> payloadJson;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const OfflineQueueCompanion({
    this.id = const Value.absent(),
    this.action = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  OfflineQueueCompanion.insert({
    this.id = const Value.absent(),
    required String action,
    required String payloadJson,
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  })  : action = Value(action),
        payloadJson = Value(payloadJson),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<OfflineQueueData> custom({
    Expression<int>? id,
    Expression<String>? action,
    Expression<String>? payloadJson,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (action != null) 'action': action,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  OfflineQueueCompanion copyWith(
      {Value<int>? id,
      Value<String>? action,
      Value<String>? payloadJson,
      Value<String>? status,
      Value<int>? retryCount,
      Value<String?>? lastError,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt}) {
    return OfflineQueueCompanion(
      id: id ?? this.id,
      action: action ?? this.action,
      payloadJson: payloadJson ?? this.payloadJson,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineQueueCompanion(')
          ..write('id: $id, ')
          ..write('action: $action, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CacheMetaTable cacheMeta = $CacheMetaTable(this);
  late final $PinsTable pins = $PinsTable(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ChatRoomsTable chatRooms = $ChatRoomsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $MatchesTable matches = $MatchesTable(this);
  late final $OfflineQueueTable offlineQueue = $OfflineQueueTable(this);
  late final UsersDao usersDao = UsersDao(this as AppDatabase);
  late final PinsDao pinsDao = PinsDao(this as AppDatabase);
  late final ChatDao chatDao = ChatDao(this as AppDatabase);
  late final MatchesDao matchesDao = MatchesDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [cacheMeta, pins, users, chatRooms, messages, matches, offlineQueue];
}

typedef $$CacheMetaTableCreateCompanionBuilder = CacheMetaCompanion Function({
  required String cacheKey,
  required DateTime lastFetchedAt,
  Value<String?> etag,
  Value<String?> cursor,
  Value<int> rowid,
});
typedef $$CacheMetaTableUpdateCompanionBuilder = CacheMetaCompanion Function({
  Value<String> cacheKey,
  Value<DateTime> lastFetchedAt,
  Value<String?> etag,
  Value<String?> cursor,
  Value<int> rowid,
});

class $$CacheMetaTableFilterComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get etag => $composableBuilder(
      column: $table.etag, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnFilters(column));
}

class $$CacheMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
      column: $table.cacheKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get etag => $composableBuilder(
      column: $table.etag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cursor => $composableBuilder(
      column: $table.cursor, builder: (column) => ColumnOrderings(column));
}

class $$CacheMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheMetaTable> {
  $$CacheMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<DateTime> get lastFetchedAt => $composableBuilder(
      column: $table.lastFetchedAt, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);
}

class $$CacheMetaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CacheMetaTable,
    CacheMetaData,
    $$CacheMetaTableFilterComposer,
    $$CacheMetaTableOrderingComposer,
    $$CacheMetaTableAnnotationComposer,
    $$CacheMetaTableCreateCompanionBuilder,
    $$CacheMetaTableUpdateCompanionBuilder,
    (
      CacheMetaData,
      BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>
    ),
    CacheMetaData,
    PrefetchHooks Function()> {
  $$CacheMetaTableTableManager(_$AppDatabase db, $CacheMetaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> cacheKey = const Value.absent(),
            Value<DateTime> lastFetchedAt = const Value.absent(),
            Value<String?> etag = const Value.absent(),
            Value<String?> cursor = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheMetaCompanion(
            cacheKey: cacheKey,
            lastFetchedAt: lastFetchedAt,
            etag: etag,
            cursor: cursor,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String cacheKey,
            required DateTime lastFetchedAt,
            Value<String?> etag = const Value.absent(),
            Value<String?> cursor = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CacheMetaCompanion.insert(
            cacheKey: cacheKey,
            lastFetchedAt: lastFetchedAt,
            etag: etag,
            cursor: cursor,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CacheMetaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CacheMetaTable,
    CacheMetaData,
    $$CacheMetaTableFilterComposer,
    $$CacheMetaTableOrderingComposer,
    $$CacheMetaTableAnnotationComposer,
    $$CacheMetaTableCreateCompanionBuilder,
    $$CacheMetaTableUpdateCompanionBuilder,
    (
      CacheMetaData,
      BaseReferences<_$AppDatabase, $CacheMetaTable, CacheMetaData>
    ),
    CacheMetaData,
    PrefetchHooks Function()>;
typedef $$PinsTableCreateCompanionBuilder = PinsCompanion Function({
  required String id,
  required String name,
  Value<String?> slug,
  required double centerLatitude,
  required double centerLongitude,
  required String level,
  Value<String?> parentPinId,
  Value<bool> isActive,
  Value<int> userCount,
  Value<int?> activeMatchRequests,
  required DateTime createdAt,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$PinsTableUpdateCompanionBuilder = PinsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String?> slug,
  Value<double> centerLatitude,
  Value<double> centerLongitude,
  Value<String> level,
  Value<String?> parentPinId,
  Value<bool> isActive,
  Value<int> userCount,
  Value<int?> activeMatchRequests,
  Value<DateTime> createdAt,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$PinsTableFilterComposer extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get slug => $composableBuilder(
      column: $table.slug, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get centerLatitude => $composableBuilder(
      column: $table.centerLatitude,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get centerLongitude => $composableBuilder(
      column: $table.centerLongitude,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentPinId => $composableBuilder(
      column: $table.parentPinId, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get userCount => $composableBuilder(
      column: $table.userCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get activeMatchRequests => $composableBuilder(
      column: $table.activeMatchRequests,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$PinsTableOrderingComposer extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get slug => $composableBuilder(
      column: $table.slug, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get centerLatitude => $composableBuilder(
      column: $table.centerLatitude,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get centerLongitude => $composableBuilder(
      column: $table.centerLongitude,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get level => $composableBuilder(
      column: $table.level, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentPinId => $composableBuilder(
      column: $table.parentPinId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get userCount => $composableBuilder(
      column: $table.userCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get activeMatchRequests => $composableBuilder(
      column: $table.activeMatchRequests,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$PinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PinsTable> {
  $$PinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<double> get centerLatitude => $composableBuilder(
      column: $table.centerLatitude, builder: (column) => column);

  GeneratedColumn<double> get centerLongitude => $composableBuilder(
      column: $table.centerLongitude, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get parentPinId => $composableBuilder(
      column: $table.parentPinId, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get userCount =>
      $composableBuilder(column: $table.userCount, builder: (column) => column);

  GeneratedColumn<int> get activeMatchRequests => $composableBuilder(
      column: $table.activeMatchRequests, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$PinsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PinsTable,
    Pin,
    $$PinsTableFilterComposer,
    $$PinsTableOrderingComposer,
    $$PinsTableAnnotationComposer,
    $$PinsTableCreateCompanionBuilder,
    $$PinsTableUpdateCompanionBuilder,
    (Pin, BaseReferences<_$AppDatabase, $PinsTable, Pin>),
    Pin,
    PrefetchHooks Function()> {
  $$PinsTableTableManager(_$AppDatabase db, $PinsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> slug = const Value.absent(),
            Value<double> centerLatitude = const Value.absent(),
            Value<double> centerLongitude = const Value.absent(),
            Value<String> level = const Value.absent(),
            Value<String?> parentPinId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> userCount = const Value.absent(),
            Value<int?> activeMatchRequests = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PinsCompanion(
            id: id,
            name: name,
            slug: slug,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            level: level,
            parentPinId: parentPinId,
            isActive: isActive,
            userCount: userCount,
            activeMatchRequests: activeMatchRequests,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> slug = const Value.absent(),
            required double centerLatitude,
            required double centerLongitude,
            required String level,
            Value<String?> parentPinId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<int> userCount = const Value.absent(),
            Value<int?> activeMatchRequests = const Value.absent(),
            required DateTime createdAt,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PinsCompanion.insert(
            id: id,
            name: name,
            slug: slug,
            centerLatitude: centerLatitude,
            centerLongitude: centerLongitude,
            level: level,
            parentPinId: parentPinId,
            isActive: isActive,
            userCount: userCount,
            activeMatchRequests: activeMatchRequests,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PinsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PinsTable,
    Pin,
    $$PinsTableFilterComposer,
    $$PinsTableOrderingComposer,
    $$PinsTableAnnotationComposer,
    $$PinsTableCreateCompanionBuilder,
    $$PinsTableUpdateCompanionBuilder,
    (Pin, BaseReferences<_$AppDatabase, $PinsTable, Pin>),
    Pin,
    PrefetchHooks Function()>;
typedef $$UsersTableCreateCompanionBuilder = UsersCompanion Function({
  required String id,
  Value<String?> email,
  required String nickname,
  Value<String?> profileImageUrl,
  Value<String?> phone,
  Value<String> status,
  Value<String?> gender,
  Value<DateTime?> birthDate,
  required DateTime createdAt,
  Value<DateTime?> lastLoginAt,
  Value<String> sportsProfilesJson,
  Value<String?> locationJson,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$UsersTableUpdateCompanionBuilder = UsersCompanion Function({
  Value<String> id,
  Value<String?> email,
  Value<String> nickname,
  Value<String?> profileImageUrl,
  Value<String?> phone,
  Value<String> status,
  Value<String?> gender,
  Value<DateTime?> birthDate,
  Value<DateTime> createdAt,
  Value<DateTime?> lastLoginAt,
  Value<String> sportsProfilesJson,
  Value<String?> locationJson,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nickname => $composableBuilder(
      column: $table.nickname, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get profileImageUrl => $composableBuilder(
      column: $table.profileImageUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get gender => $composableBuilder(
      column: $table.gender, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get birthDate => $composableBuilder(
      column: $table.birthDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastLoginAt => $composableBuilder(
      column: $table.lastLoginAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sportsProfilesJson => $composableBuilder(
      column: $table.sportsProfilesJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get locationJson => $composableBuilder(
      column: $table.locationJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$UsersTableOrderingComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get email => $composableBuilder(
      column: $table.email, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nickname => $composableBuilder(
      column: $table.nickname, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get profileImageUrl => $composableBuilder(
      column: $table.profileImageUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phone => $composableBuilder(
      column: $table.phone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get gender => $composableBuilder(
      column: $table.gender, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get birthDate => $composableBuilder(
      column: $table.birthDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastLoginAt => $composableBuilder(
      column: $table.lastLoginAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sportsProfilesJson => $composableBuilder(
      column: $table.sportsProfilesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get locationJson => $composableBuilder(
      column: $table.locationJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$UsersTableAnnotationComposer
    extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get nickname =>
      $composableBuilder(column: $table.nickname, builder: (column) => column);

  GeneratedColumn<String> get profileImageUrl => $composableBuilder(
      column: $table.profileImageUrl, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<DateTime> get birthDate =>
      $composableBuilder(column: $table.birthDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastLoginAt => $composableBuilder(
      column: $table.lastLoginAt, builder: (column) => column);

  GeneratedColumn<String> get sportsProfilesJson => $composableBuilder(
      column: $table.sportsProfilesJson, builder: (column) => column);

  GeneratedColumn<String> get locationJson => $composableBuilder(
      column: $table.locationJson, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$UsersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UsersTable,
    User,
    $$UsersTableFilterComposer,
    $$UsersTableOrderingComposer,
    $$UsersTableAnnotationComposer,
    $$UsersTableCreateCompanionBuilder,
    $$UsersTableUpdateCompanionBuilder,
    (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
    User,
    PrefetchHooks Function()> {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> email = const Value.absent(),
            Value<String> nickname = const Value.absent(),
            Value<String?> profileImageUrl = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> gender = const Value.absent(),
            Value<DateTime?> birthDate = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastLoginAt = const Value.absent(),
            Value<String> sportsProfilesJson = const Value.absent(),
            Value<String?> locationJson = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UsersCompanion(
            id: id,
            email: email,
            nickname: nickname,
            profileImageUrl: profileImageUrl,
            phone: phone,
            status: status,
            gender: gender,
            birthDate: birthDate,
            createdAt: createdAt,
            lastLoginAt: lastLoginAt,
            sportsProfilesJson: sportsProfilesJson,
            locationJson: locationJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> email = const Value.absent(),
            required String nickname,
            Value<String?> profileImageUrl = const Value.absent(),
            Value<String?> phone = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> gender = const Value.absent(),
            Value<DateTime?> birthDate = const Value.absent(),
            required DateTime createdAt,
            Value<DateTime?> lastLoginAt = const Value.absent(),
            Value<String> sportsProfilesJson = const Value.absent(),
            Value<String?> locationJson = const Value.absent(),
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UsersCompanion.insert(
            id: id,
            email: email,
            nickname: nickname,
            profileImageUrl: profileImageUrl,
            phone: phone,
            status: status,
            gender: gender,
            birthDate: birthDate,
            createdAt: createdAt,
            lastLoginAt: lastLoginAt,
            sportsProfilesJson: sportsProfilesJson,
            locationJson: locationJson,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UsersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UsersTable,
    User,
    $$UsersTableFilterComposer,
    $$UsersTableOrderingComposer,
    $$UsersTableAnnotationComposer,
    $$UsersTableCreateCompanionBuilder,
    $$UsersTableUpdateCompanionBuilder,
    (User, BaseReferences<_$AppDatabase, $UsersTable, User>),
    User,
    PrefetchHooks Function()>;
typedef $$ChatRoomsTableCreateCompanionBuilder = ChatRoomsCompanion Function({
  required String id,
  required String matchId,
  required String opponentJson,
  Value<String?> lastMessageJson,
  Value<int> unreadCount,
  Value<bool> isActive,
  required DateTime createdAt,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$ChatRoomsTableUpdateCompanionBuilder = ChatRoomsCompanion Function({
  Value<String> id,
  Value<String> matchId,
  Value<String> opponentJson,
  Value<String?> lastMessageJson,
  Value<int> unreadCount,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$ChatRoomsTableFilterComposer
    extends Composer<_$AppDatabase, $ChatRoomsTable> {
  $$ChatRoomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get matchId => $composableBuilder(
      column: $table.matchId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get opponentJson => $composableBuilder(
      column: $table.opponentJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageJson => $composableBuilder(
      column: $table.lastMessageJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$ChatRoomsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatRoomsTable> {
  $$ChatRoomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get matchId => $composableBuilder(
      column: $table.matchId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get opponentJson => $composableBuilder(
      column: $table.opponentJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageJson => $composableBuilder(
      column: $table.lastMessageJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$ChatRoomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatRoomsTable> {
  $$ChatRoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get matchId =>
      $composableBuilder(column: $table.matchId, builder: (column) => column);

  GeneratedColumn<String> get opponentJson => $composableBuilder(
      column: $table.opponentJson, builder: (column) => column);

  GeneratedColumn<String> get lastMessageJson => $composableBuilder(
      column: $table.lastMessageJson, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$ChatRoomsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatRoomsTable,
    ChatRoom,
    $$ChatRoomsTableFilterComposer,
    $$ChatRoomsTableOrderingComposer,
    $$ChatRoomsTableAnnotationComposer,
    $$ChatRoomsTableCreateCompanionBuilder,
    $$ChatRoomsTableUpdateCompanionBuilder,
    (ChatRoom, BaseReferences<_$AppDatabase, $ChatRoomsTable, ChatRoom>),
    ChatRoom,
    PrefetchHooks Function()> {
  $$ChatRoomsTableTableManager(_$AppDatabase db, $ChatRoomsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatRoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatRoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatRoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> matchId = const Value.absent(),
            Value<String> opponentJson = const Value.absent(),
            Value<String?> lastMessageJson = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatRoomsCompanion(
            id: id,
            matchId: matchId,
            opponentJson: opponentJson,
            lastMessageJson: lastMessageJson,
            unreadCount: unreadCount,
            isActive: isActive,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String matchId,
            required String opponentJson,
            Value<String?> lastMessageJson = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            required DateTime createdAt,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatRoomsCompanion.insert(
            id: id,
            matchId: matchId,
            opponentJson: opponentJson,
            lastMessageJson: lastMessageJson,
            unreadCount: unreadCount,
            isActive: isActive,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatRoomsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatRoomsTable,
    ChatRoom,
    $$ChatRoomsTableFilterComposer,
    $$ChatRoomsTableOrderingComposer,
    $$ChatRoomsTableAnnotationComposer,
    $$ChatRoomsTableCreateCompanionBuilder,
    $$ChatRoomsTableUpdateCompanionBuilder,
    (ChatRoom, BaseReferences<_$AppDatabase, $ChatRoomsTable, ChatRoom>),
    ChatRoom,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String chatRoomId,
  required String senderId,
  required String senderNickname,
  Value<String?> senderProfileImageUrl,
  Value<String> messageType,
  required String content,
  Value<String?> imageUrl,
  Value<String?> extraData,
  Value<bool> isRead,
  Value<DateTime?> readAt,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> chatRoomId,
  Value<String> senderId,
  Value<String> senderNickname,
  Value<String?> senderProfileImageUrl,
  Value<String> messageType,
  Value<String> content,
  Value<String?> imageUrl,
  Value<String?> extraData,
  Value<bool> isRead,
  Value<DateTime?> readAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chatRoomId => $composableBuilder(
      column: $table.chatRoomId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderProfileImageUrl => $composableBuilder(
      column: $table.senderProfileImageUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get readAt => $composableBuilder(
      column: $table.readAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chatRoomId => $composableBuilder(
      column: $table.chatRoomId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderProfileImageUrl => $composableBuilder(
      column: $table.senderProfileImageUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get extraData => $composableBuilder(
      column: $table.extraData, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get readAt => $composableBuilder(
      column: $table.readAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get chatRoomId => $composableBuilder(
      column: $table.chatRoomId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get senderNickname => $composableBuilder(
      column: $table.senderNickname, builder: (column) => column);

  GeneratedColumn<String> get senderProfileImageUrl => $composableBuilder(
      column: $table.senderProfileImageUrl, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<String> get extraData =>
      $composableBuilder(column: $table.extraData, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<DateTime> get readAt =>
      $composableBuilder(column: $table.readAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> chatRoomId = const Value.absent(),
            Value<String> senderId = const Value.absent(),
            Value<String> senderNickname = const Value.absent(),
            Value<String?> senderProfileImageUrl = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<String?> extraData = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<DateTime?> readAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            chatRoomId: chatRoomId,
            senderId: senderId,
            senderNickname: senderNickname,
            senderProfileImageUrl: senderProfileImageUrl,
            messageType: messageType,
            content: content,
            imageUrl: imageUrl,
            extraData: extraData,
            isRead: isRead,
            readAt: readAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String chatRoomId,
            required String senderId,
            required String senderNickname,
            Value<String?> senderProfileImageUrl = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            required String content,
            Value<String?> imageUrl = const Value.absent(),
            Value<String?> extraData = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<DateTime?> readAt = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            chatRoomId: chatRoomId,
            senderId: senderId,
            senderNickname: senderNickname,
            senderProfileImageUrl: senderProfileImageUrl,
            messageType: messageType,
            content: content,
            imageUrl: imageUrl,
            extraData: extraData,
            isRead: isRead,
            readAt: readAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$MatchesTableCreateCompanionBuilder = MatchesCompanion Function({
  required String id,
  required String status,
  required String sportType,
  Value<String?> pinId,
  required String requesterId,
  Value<String?> responderId,
  Value<String?> detailJson,
  Value<DateTime?> scheduledAt,
  required DateTime createdAt,
  required DateTime cachedAt,
  Value<int> rowid,
});
typedef $$MatchesTableUpdateCompanionBuilder = MatchesCompanion Function({
  Value<String> id,
  Value<String> status,
  Value<String> sportType,
  Value<String?> pinId,
  Value<String> requesterId,
  Value<String?> responderId,
  Value<String?> detailJson,
  Value<DateTime?> scheduledAt,
  Value<DateTime> createdAt,
  Value<DateTime> cachedAt,
  Value<int> rowid,
});

class $$MatchesTableFilterComposer
    extends Composer<_$AppDatabase, $MatchesTable> {
  $$MatchesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sportType => $composableBuilder(
      column: $table.sportType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pinId => $composableBuilder(
      column: $table.pinId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get requesterId => $composableBuilder(
      column: $table.requesterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responderId => $composableBuilder(
      column: $table.responderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnFilters(column));
}

class $$MatchesTableOrderingComposer
    extends Composer<_$AppDatabase, $MatchesTable> {
  $$MatchesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sportType => $composableBuilder(
      column: $table.sportType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pinId => $composableBuilder(
      column: $table.pinId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get requesterId => $composableBuilder(
      column: $table.requesterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responderId => $composableBuilder(
      column: $table.responderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
      column: $table.cachedAt, builder: (column) => ColumnOrderings(column));
}

class $$MatchesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MatchesTable> {
  $$MatchesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get sportType =>
      $composableBuilder(column: $table.sportType, builder: (column) => column);

  GeneratedColumn<String> get pinId =>
      $composableBuilder(column: $table.pinId, builder: (column) => column);

  GeneratedColumn<String> get requesterId => $composableBuilder(
      column: $table.requesterId, builder: (column) => column);

  GeneratedColumn<String> get responderId => $composableBuilder(
      column: $table.responderId, builder: (column) => column);

  GeneratedColumn<String> get detailJson => $composableBuilder(
      column: $table.detailJson, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
      column: $table.scheduledAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$MatchesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MatchesTable,
    Matche,
    $$MatchesTableFilterComposer,
    $$MatchesTableOrderingComposer,
    $$MatchesTableAnnotationComposer,
    $$MatchesTableCreateCompanionBuilder,
    $$MatchesTableUpdateCompanionBuilder,
    (Matche, BaseReferences<_$AppDatabase, $MatchesTable, Matche>),
    Matche,
    PrefetchHooks Function()> {
  $$MatchesTableTableManager(_$AppDatabase db, $MatchesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MatchesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MatchesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MatchesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String> sportType = const Value.absent(),
            Value<String?> pinId = const Value.absent(),
            Value<String> requesterId = const Value.absent(),
            Value<String?> responderId = const Value.absent(),
            Value<String?> detailJson = const Value.absent(),
            Value<DateTime?> scheduledAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> cachedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MatchesCompanion(
            id: id,
            status: status,
            sportType: sportType,
            pinId: pinId,
            requesterId: requesterId,
            responderId: responderId,
            detailJson: detailJson,
            scheduledAt: scheduledAt,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String status,
            required String sportType,
            Value<String?> pinId = const Value.absent(),
            required String requesterId,
            Value<String?> responderId = const Value.absent(),
            Value<String?> detailJson = const Value.absent(),
            Value<DateTime?> scheduledAt = const Value.absent(),
            required DateTime createdAt,
            required DateTime cachedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              MatchesCompanion.insert(
            id: id,
            status: status,
            sportType: sportType,
            pinId: pinId,
            requesterId: requesterId,
            responderId: responderId,
            detailJson: detailJson,
            scheduledAt: scheduledAt,
            createdAt: createdAt,
            cachedAt: cachedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MatchesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MatchesTable,
    Matche,
    $$MatchesTableFilterComposer,
    $$MatchesTableOrderingComposer,
    $$MatchesTableAnnotationComposer,
    $$MatchesTableCreateCompanionBuilder,
    $$MatchesTableUpdateCompanionBuilder,
    (Matche, BaseReferences<_$AppDatabase, $MatchesTable, Matche>),
    Matche,
    PrefetchHooks Function()>;
typedef $$OfflineQueueTableCreateCompanionBuilder = OfflineQueueCompanion
    Function({
  Value<int> id,
  required String action,
  required String payloadJson,
  Value<String> status,
  Value<int> retryCount,
  Value<String?> lastError,
  required DateTime createdAt,
  required DateTime updatedAt,
});
typedef $$OfflineQueueTableUpdateCompanionBuilder = OfflineQueueCompanion
    Function({
  Value<int> id,
  Value<String> action,
  Value<String> payloadJson,
  Value<String> status,
  Value<int> retryCount,
  Value<String?> lastError,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
});

class $$OfflineQueueTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$OfflineQueueTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$OfflineQueueTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineQueueTable> {
  $$OfflineQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
      column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
      column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OfflineQueueTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OfflineQueueTable,
    OfflineQueueData,
    $$OfflineQueueTableFilterComposer,
    $$OfflineQueueTableOrderingComposer,
    $$OfflineQueueTableAnnotationComposer,
    $$OfflineQueueTableCreateCompanionBuilder,
    $$OfflineQueueTableUpdateCompanionBuilder,
    (
      OfflineQueueData,
      BaseReferences<_$AppDatabase, $OfflineQueueTable, OfflineQueueData>
    ),
    OfflineQueueData,
    PrefetchHooks Function()> {
  $$OfflineQueueTableTableManager(_$AppDatabase db, $OfflineQueueTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String> payloadJson = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              OfflineQueueCompanion(
            id: id,
            action: action,
            payloadJson: payloadJson,
            status: status,
            retryCount: retryCount,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String action,
            required String payloadJson,
            Value<String> status = const Value.absent(),
            Value<int> retryCount = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
          }) =>
              OfflineQueueCompanion.insert(
            id: id,
            action: action,
            payloadJson: payloadJson,
            status: status,
            retryCount: retryCount,
            lastError: lastError,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OfflineQueueTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OfflineQueueTable,
    OfflineQueueData,
    $$OfflineQueueTableFilterComposer,
    $$OfflineQueueTableOrderingComposer,
    $$OfflineQueueTableAnnotationComposer,
    $$OfflineQueueTableCreateCompanionBuilder,
    $$OfflineQueueTableUpdateCompanionBuilder,
    (
      OfflineQueueData,
      BaseReferences<_$AppDatabase, $OfflineQueueTable, OfflineQueueData>
    ),
    OfflineQueueData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CacheMetaTableTableManager get cacheMeta =>
      $$CacheMetaTableTableManager(_db, _db.cacheMeta);
  $$PinsTableTableManager get pins => $$PinsTableTableManager(_db, _db.pins);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db, _db.users);
  $$ChatRoomsTableTableManager get chatRooms =>
      $$ChatRoomsTableTableManager(_db, _db.chatRooms);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$MatchesTableTableManager get matches =>
      $$MatchesTableTableManager(_db, _db.matches);
  $$OfflineQueueTableTableManager get offlineQueue =>
      $$OfflineQueueTableTableManager(_db, _db.offlineQueue);
}
