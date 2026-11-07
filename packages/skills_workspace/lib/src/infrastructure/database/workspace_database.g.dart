// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_database.dart';

// ignore_for_file: type=lint
class $WorkspaceMetadataTable extends WorkspaceMetadata
    with TableInfo<$WorkspaceMetadataTable, WorkspaceMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkspaceMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  @override
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repositoryRevisionMeta =
      const VerificationMeta('repositoryRevision');
  @override
  late final GeneratedColumn<int> repositoryRevision = GeneratedColumn<int>(
    'repository_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destructionEpochMeta = const VerificationMeta(
    'destructionEpoch',
  );
  @override
  late final GeneratedColumn<int> destructionEpoch = GeneratedColumn<int>(
    'destruction_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singleton,
    repositoryRevision,
    destructionEpoch,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workspace_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkspaceMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('repository_revision')) {
      context.handle(
        _repositoryRevisionMeta,
        repositoryRevision.isAcceptableOrUnknown(
          data['repository_revision']!,
          _repositoryRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_repositoryRevisionMeta);
    }
    if (data.containsKey('destruction_epoch')) {
      context.handle(
        _destructionEpochMeta,
        destructionEpoch.isAcceptableOrUnknown(
          data['destruction_epoch']!,
          _destructionEpochMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destructionEpochMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  WorkspaceMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkspaceMetadataData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      repositoryRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}repository_revision'],
      )!,
      destructionEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}destruction_epoch'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $WorkspaceMetadataTable createAlias(String alias) {
    return $WorkspaceMetadataTable(attachedDatabase, alias);
  }
}

class WorkspaceMetadataData extends DataClass
    implements Insertable<WorkspaceMetadataData> {
  final int singleton;
  final int repositoryRevision;
  final int destructionEpoch;
  final int createdAtMicros;
  final int updatedAtMicros;
  const WorkspaceMetadataData({
    required this.singleton,
    required this.repositoryRevision,
    required this.destructionEpoch,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['repository_revision'] = Variable<int>(repositoryRevision);
    map['destruction_epoch'] = Variable<int>(destructionEpoch);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  WorkspaceMetadataCompanion toCompanion(bool nullToAbsent) {
    return WorkspaceMetadataCompanion(
      singleton: Value(singleton),
      repositoryRevision: Value(repositoryRevision),
      destructionEpoch: Value(destructionEpoch),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory WorkspaceMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkspaceMetadataData(
      singleton: serializer.fromJson<int>(json['singleton']),
      repositoryRevision: serializer.fromJson<int>(json['repositoryRevision']),
      destructionEpoch: serializer.fromJson<int>(json['destructionEpoch']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'repositoryRevision': serializer.toJson<int>(repositoryRevision),
      'destructionEpoch': serializer.toJson<int>(destructionEpoch),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  WorkspaceMetadataData copyWith({
    int? singleton,
    int? repositoryRevision,
    int? destructionEpoch,
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => WorkspaceMetadataData(
    singleton: singleton ?? this.singleton,
    repositoryRevision: repositoryRevision ?? this.repositoryRevision,
    destructionEpoch: destructionEpoch ?? this.destructionEpoch,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  WorkspaceMetadataData copyWithCompanion(WorkspaceMetadataCompanion data) {
    return WorkspaceMetadataData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      repositoryRevision: data.repositoryRevision.present
          ? data.repositoryRevision.value
          : this.repositoryRevision,
      destructionEpoch: data.destructionEpoch.present
          ? data.destructionEpoch.value
          : this.destructionEpoch,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceMetadataData(')
          ..write('singleton: $singleton, ')
          ..write('repositoryRevision: $repositoryRevision, ')
          ..write('destructionEpoch: $destructionEpoch, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singleton,
    repositoryRevision,
    destructionEpoch,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkspaceMetadataData &&
          other.singleton == this.singleton &&
          other.repositoryRevision == this.repositoryRevision &&
          other.destructionEpoch == this.destructionEpoch &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class WorkspaceMetadataCompanion
    extends UpdateCompanion<WorkspaceMetadataData> {
  final Value<int> singleton;
  final Value<int> repositoryRevision;
  final Value<int> destructionEpoch;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  const WorkspaceMetadataCompanion({
    this.singleton = const Value.absent(),
    this.repositoryRevision = const Value.absent(),
    this.destructionEpoch = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
  });
  WorkspaceMetadataCompanion.insert({
    this.singleton = const Value.absent(),
    required int repositoryRevision,
    required int destructionEpoch,
    required int createdAtMicros,
    required int updatedAtMicros,
  }) : repositoryRevision = Value(repositoryRevision),
       destructionEpoch = Value(destructionEpoch),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<WorkspaceMetadataData> custom({
    Expression<int>? singleton,
    Expression<int>? repositoryRevision,
    Expression<int>? destructionEpoch,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (repositoryRevision != null) 'repository_revision': repositoryRevision,
      if (destructionEpoch != null) 'destruction_epoch': destructionEpoch,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
    });
  }

  WorkspaceMetadataCompanion copyWith({
    Value<int>? singleton,
    Value<int>? repositoryRevision,
    Value<int>? destructionEpoch,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
  }) {
    return WorkspaceMetadataCompanion(
      singleton: singleton ?? this.singleton,
      repositoryRevision: repositoryRevision ?? this.repositoryRevision,
      destructionEpoch: destructionEpoch ?? this.destructionEpoch,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (repositoryRevision.present) {
      map['repository_revision'] = Variable<int>(repositoryRevision.value);
    }
    if (destructionEpoch.present) {
      map['destruction_epoch'] = Variable<int>(destructionEpoch.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkspaceMetadataCompanion(')
          ..write('singleton: $singleton, ')
          ..write('repositoryRevision: $repositoryRevision, ')
          ..write('destructionEpoch: $destructionEpoch, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }
}

class $SourceLineagesTable extends SourceLineages
    with TableInfo<$SourceLineagesTable, SourceLineage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceLineagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _objectFormatMeta = const VerificationMeta(
    'objectFormat',
  );
  @override
  late final GeneratedColumn<String> objectFormat = GeneratedColumn<String>(
    'object_format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    managedSkillId,
    objectFormat,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_lineages';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceLineage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('object_format')) {
      context.handle(
        _objectFormatMeta,
        objectFormat.isAcceptableOrUnknown(
          data['object_format']!,
          _objectFormatMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_objectFormatMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {managedSkillId, id},
  ];
  @override
  SourceLineage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceLineage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      objectFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_format'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $SourceLineagesTable createAlias(String alias) {
    return $SourceLineagesTable(attachedDatabase, alias);
  }
}

class SourceLineage extends DataClass implements Insertable<SourceLineage> {
  final String id;
  final String managedSkillId;
  final String objectFormat;
  final int createdAtMicros;
  const SourceLineage({
    required this.id,
    required this.managedSkillId,
    required this.objectFormat,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['object_format'] = Variable<String>(objectFormat);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  SourceLineagesCompanion toCompanion(bool nullToAbsent) {
    return SourceLineagesCompanion(
      id: Value(id),
      managedSkillId: Value(managedSkillId),
      objectFormat: Value(objectFormat),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory SourceLineage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceLineage(
      id: serializer.fromJson<String>(json['id']),
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      objectFormat: serializer.fromJson<String>(json['objectFormat']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'objectFormat': serializer.toJson<String>(objectFormat),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  SourceLineage copyWith({
    String? id,
    String? managedSkillId,
    String? objectFormat,
    int? createdAtMicros,
  }) => SourceLineage(
    id: id ?? this.id,
    managedSkillId: managedSkillId ?? this.managedSkillId,
    objectFormat: objectFormat ?? this.objectFormat,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  SourceLineage copyWithCompanion(SourceLineagesCompanion data) {
    return SourceLineage(
      id: data.id.present ? data.id.value : this.id,
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      objectFormat: data.objectFormat.present
          ? data.objectFormat.value
          : this.objectFormat,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceLineage(')
          ..write('id: $id, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('objectFormat: $objectFormat, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, managedSkillId, objectFormat, createdAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceLineage &&
          other.id == this.id &&
          other.managedSkillId == this.managedSkillId &&
          other.objectFormat == this.objectFormat &&
          other.createdAtMicros == this.createdAtMicros);
}

class SourceLineagesCompanion extends UpdateCompanion<SourceLineage> {
  final Value<String> id;
  final Value<String> managedSkillId;
  final Value<String> objectFormat;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const SourceLineagesCompanion({
    this.id = const Value.absent(),
    this.managedSkillId = const Value.absent(),
    this.objectFormat = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceLineagesCompanion.insert({
    required String id,
    required String managedSkillId,
    required String objectFormat,
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       managedSkillId = Value(managedSkillId),
       objectFormat = Value(objectFormat),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<SourceLineage> custom({
    Expression<String>? id,
    Expression<String>? managedSkillId,
    Expression<String>? objectFormat,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (objectFormat != null) 'object_format': objectFormat,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceLineagesCompanion copyWith({
    Value<String>? id,
    Value<String>? managedSkillId,
    Value<String>? objectFormat,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return SourceLineagesCompanion(
      id: id ?? this.id,
      managedSkillId: managedSkillId ?? this.managedSkillId,
      objectFormat: objectFormat ?? this.objectFormat,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (objectFormat.present) {
      map['object_format'] = Variable<String>(objectFormat.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceLineagesCompanion(')
          ..write('id: $id, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('objectFormat: $objectFormat, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ManagedSkillsTable extends ManagedSkills
    with TableInfo<$ManagedSkillsTable, ManagedSkill> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ManagedSkillsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotKeyMeta = const VerificationMeta(
    'slotKey',
  );
  @override
  late final GeneratedColumn<String> slotKey = GeneratedColumn<String>(
    'slot_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _declaredNameMeta = const VerificationMeta(
    'declaredName',
  );
  @override
  late final GeneratedColumn<String> declaredName = GeneratedColumn<String>(
    'declared_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeSourceLineageIdMeta =
      const VerificationMeta('activeSourceLineageId');
  @override
  late final GeneratedColumn<String> activeSourceLineageId =
      GeneratedColumn<String>(
        'active_source_lineage_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    slotKey,
    declaredName,
    displayName,
    description,
    activeSourceLineageId,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'managed_skills';
  @override
  VerificationContext validateIntegrity(
    Insertable<ManagedSkill> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('slot_key')) {
      context.handle(
        _slotKeyMeta,
        slotKey.isAcceptableOrUnknown(data['slot_key']!, _slotKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_slotKeyMeta);
    }
    if (data.containsKey('declared_name')) {
      context.handle(
        _declaredNameMeta,
        declaredName.isAcceptableOrUnknown(
          data['declared_name']!,
          _declaredNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_declaredNameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('active_source_lineage_id')) {
      context.handle(
        _activeSourceLineageIdMeta,
        activeSourceLineageId.isAcceptableOrUnknown(
          data['active_source_lineage_id']!,
          _activeSourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activeSourceLineageIdMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ManagedSkill map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ManagedSkill(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      slotKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slot_key'],
      )!,
      declaredName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}declared_name'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      activeSourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}active_source_lineage_id'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $ManagedSkillsTable createAlias(String alias) {
    return $ManagedSkillsTable(attachedDatabase, alias);
  }
}

class ManagedSkill extends DataClass implements Insertable<ManagedSkill> {
  final String id;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final String activeSourceLineageId;
  final int createdAtMicros;
  final int updatedAtMicros;
  const ManagedSkill({
    required this.id,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.activeSourceLineageId,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['slot_key'] = Variable<String>(slotKey);
    map['declared_name'] = Variable<String>(declaredName);
    map['display_name'] = Variable<String>(displayName);
    map['description'] = Variable<String>(description);
    map['active_source_lineage_id'] = Variable<String>(activeSourceLineageId);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  ManagedSkillsCompanion toCompanion(bool nullToAbsent) {
    return ManagedSkillsCompanion(
      id: Value(id),
      slotKey: Value(slotKey),
      declaredName: Value(declaredName),
      displayName: Value(displayName),
      description: Value(description),
      activeSourceLineageId: Value(activeSourceLineageId),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory ManagedSkill.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ManagedSkill(
      id: serializer.fromJson<String>(json['id']),
      slotKey: serializer.fromJson<String>(json['slotKey']),
      declaredName: serializer.fromJson<String>(json['declaredName']),
      displayName: serializer.fromJson<String>(json['displayName']),
      description: serializer.fromJson<String>(json['description']),
      activeSourceLineageId: serializer.fromJson<String>(
        json['activeSourceLineageId'],
      ),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'slotKey': serializer.toJson<String>(slotKey),
      'declaredName': serializer.toJson<String>(declaredName),
      'displayName': serializer.toJson<String>(displayName),
      'description': serializer.toJson<String>(description),
      'activeSourceLineageId': serializer.toJson<String>(activeSourceLineageId),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  ManagedSkill copyWith({
    String? id,
    String? slotKey,
    String? declaredName,
    String? displayName,
    String? description,
    String? activeSourceLineageId,
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => ManagedSkill(
    id: id ?? this.id,
    slotKey: slotKey ?? this.slotKey,
    declaredName: declaredName ?? this.declaredName,
    displayName: displayName ?? this.displayName,
    description: description ?? this.description,
    activeSourceLineageId: activeSourceLineageId ?? this.activeSourceLineageId,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  ManagedSkill copyWithCompanion(ManagedSkillsCompanion data) {
    return ManagedSkill(
      id: data.id.present ? data.id.value : this.id,
      slotKey: data.slotKey.present ? data.slotKey.value : this.slotKey,
      declaredName: data.declaredName.present
          ? data.declaredName.value
          : this.declaredName,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      description: data.description.present
          ? data.description.value
          : this.description,
      activeSourceLineageId: data.activeSourceLineageId.present
          ? data.activeSourceLineageId.value
          : this.activeSourceLineageId,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ManagedSkill(')
          ..write('id: $id, ')
          ..write('slotKey: $slotKey, ')
          ..write('declaredName: $declaredName, ')
          ..write('displayName: $displayName, ')
          ..write('description: $description, ')
          ..write('activeSourceLineageId: $activeSourceLineageId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    slotKey,
    declaredName,
    displayName,
    description,
    activeSourceLineageId,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ManagedSkill &&
          other.id == this.id &&
          other.slotKey == this.slotKey &&
          other.declaredName == this.declaredName &&
          other.displayName == this.displayName &&
          other.description == this.description &&
          other.activeSourceLineageId == this.activeSourceLineageId &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class ManagedSkillsCompanion extends UpdateCompanion<ManagedSkill> {
  final Value<String> id;
  final Value<String> slotKey;
  final Value<String> declaredName;
  final Value<String> displayName;
  final Value<String> description;
  final Value<String> activeSourceLineageId;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const ManagedSkillsCompanion({
    this.id = const Value.absent(),
    this.slotKey = const Value.absent(),
    this.declaredName = const Value.absent(),
    this.displayName = const Value.absent(),
    this.description = const Value.absent(),
    this.activeSourceLineageId = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ManagedSkillsCompanion.insert({
    required String id,
    required String slotKey,
    required String declaredName,
    required String displayName,
    required String description,
    required String activeSourceLineageId,
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       slotKey = Value(slotKey),
       declaredName = Value(declaredName),
       displayName = Value(displayName),
       description = Value(description),
       activeSourceLineageId = Value(activeSourceLineageId),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<ManagedSkill> custom({
    Expression<String>? id,
    Expression<String>? slotKey,
    Expression<String>? declaredName,
    Expression<String>? displayName,
    Expression<String>? description,
    Expression<String>? activeSourceLineageId,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (slotKey != null) 'slot_key': slotKey,
      if (declaredName != null) 'declared_name': declaredName,
      if (displayName != null) 'display_name': displayName,
      if (description != null) 'description': description,
      if (activeSourceLineageId != null)
        'active_source_lineage_id': activeSourceLineageId,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ManagedSkillsCompanion copyWith({
    Value<String>? id,
    Value<String>? slotKey,
    Value<String>? declaredName,
    Value<String>? displayName,
    Value<String>? description,
    Value<String>? activeSourceLineageId,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return ManagedSkillsCompanion(
      id: id ?? this.id,
      slotKey: slotKey ?? this.slotKey,
      declaredName: declaredName ?? this.declaredName,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      activeSourceLineageId:
          activeSourceLineageId ?? this.activeSourceLineageId,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (slotKey.present) {
      map['slot_key'] = Variable<String>(slotKey.value);
    }
    if (declaredName.present) {
      map['declared_name'] = Variable<String>(declaredName.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (activeSourceLineageId.present) {
      map['active_source_lineage_id'] = Variable<String>(
        activeSourceLineageId.value,
      );
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ManagedSkillsCompanion(')
          ..write('id: $id, ')
          ..write('slotKey: $slotKey, ')
          ..write('declaredName: $declaredName, ')
          ..write('displayName: $displayName, ')
          ..write('description: $description, ')
          ..write('activeSourceLineageId: $activeSourceLineageId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillSourcesTable extends SkillSources
    with TableInfo<$SkillSourcesTable, SkillSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES source_lineages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadSchemaVersionMeta =
      const VerificationMeta('payloadSchemaVersion');
  @override
  late final GeneratedColumn<int> payloadSchemaVersion = GeneratedColumn<int>(
    'payload_schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceLineageId,
    kind,
    payloadSchemaVersion,
    payloadJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SkillSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLineageIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('payload_schema_version')) {
      context.handle(
        _payloadSchemaVersionMeta,
        payloadSchemaVersion.isAcceptableOrUnknown(
          data['payload_schema_version']!,
          _payloadSchemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadSchemaVersionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceLineageId};
  @override
  SkillSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillSource(
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      payloadSchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}payload_schema_version'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
    );
  }

  @override
  $SkillSourcesTable createAlias(String alias) {
    return $SkillSourcesTable(attachedDatabase, alias);
  }
}

class SkillSource extends DataClass implements Insertable<SkillSource> {
  final String sourceLineageId;
  final String kind;
  final int payloadSchemaVersion;
  final String payloadJson;
  const SkillSource({
    required this.sourceLineageId,
    required this.kind,
    required this.payloadSchemaVersion,
    required this.payloadJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_lineage_id'] = Variable<String>(sourceLineageId);
    map['kind'] = Variable<String>(kind);
    map['payload_schema_version'] = Variable<int>(payloadSchemaVersion);
    map['payload_json'] = Variable<String>(payloadJson);
    return map;
  }

  SkillSourcesCompanion toCompanion(bool nullToAbsent) {
    return SkillSourcesCompanion(
      sourceLineageId: Value(sourceLineageId),
      kind: Value(kind),
      payloadSchemaVersion: Value(payloadSchemaVersion),
      payloadJson: Value(payloadJson),
    );
  }

  factory SkillSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillSource(
      sourceLineageId: serializer.fromJson<String>(json['sourceLineageId']),
      kind: serializer.fromJson<String>(json['kind']),
      payloadSchemaVersion: serializer.fromJson<int>(
        json['payloadSchemaVersion'],
      ),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceLineageId': serializer.toJson<String>(sourceLineageId),
      'kind': serializer.toJson<String>(kind),
      'payloadSchemaVersion': serializer.toJson<int>(payloadSchemaVersion),
      'payloadJson': serializer.toJson<String>(payloadJson),
    };
  }

  SkillSource copyWith({
    String? sourceLineageId,
    String? kind,
    int? payloadSchemaVersion,
    String? payloadJson,
  }) => SkillSource(
    sourceLineageId: sourceLineageId ?? this.sourceLineageId,
    kind: kind ?? this.kind,
    payloadSchemaVersion: payloadSchemaVersion ?? this.payloadSchemaVersion,
    payloadJson: payloadJson ?? this.payloadJson,
  );
  SkillSource copyWithCompanion(SkillSourcesCompanion data) {
    return SkillSource(
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      kind: data.kind.present ? data.kind.value : this.kind,
      payloadSchemaVersion: data.payloadSchemaVersion.present
          ? data.payloadSchemaVersion.value
          : this.payloadSchemaVersion,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillSource(')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('kind: $kind, ')
          ..write('payloadSchemaVersion: $payloadSchemaVersion, ')
          ..write('payloadJson: $payloadJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sourceLineageId, kind, payloadSchemaVersion, payloadJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillSource &&
          other.sourceLineageId == this.sourceLineageId &&
          other.kind == this.kind &&
          other.payloadSchemaVersion == this.payloadSchemaVersion &&
          other.payloadJson == this.payloadJson);
}

class SkillSourcesCompanion extends UpdateCompanion<SkillSource> {
  final Value<String> sourceLineageId;
  final Value<String> kind;
  final Value<int> payloadSchemaVersion;
  final Value<String> payloadJson;
  final Value<int> rowid;
  const SkillSourcesCompanion({
    this.sourceLineageId = const Value.absent(),
    this.kind = const Value.absent(),
    this.payloadSchemaVersion = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillSourcesCompanion.insert({
    required String sourceLineageId,
    required String kind,
    required int payloadSchemaVersion,
    required String payloadJson,
    this.rowid = const Value.absent(),
  }) : sourceLineageId = Value(sourceLineageId),
       kind = Value(kind),
       payloadSchemaVersion = Value(payloadSchemaVersion),
       payloadJson = Value(payloadJson);
  static Insertable<SkillSource> custom({
    Expression<String>? sourceLineageId,
    Expression<String>? kind,
    Expression<int>? payloadSchemaVersion,
    Expression<String>? payloadJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (kind != null) 'kind': kind,
      if (payloadSchemaVersion != null)
        'payload_schema_version': payloadSchemaVersion,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillSourcesCompanion copyWith({
    Value<String>? sourceLineageId,
    Value<String>? kind,
    Value<int>? payloadSchemaVersion,
    Value<String>? payloadJson,
    Value<int>? rowid,
  }) {
    return SkillSourcesCompanion(
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      kind: kind ?? this.kind,
      payloadSchemaVersion: payloadSchemaVersion ?? this.payloadSchemaVersion,
      payloadJson: payloadJson ?? this.payloadJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (payloadSchemaVersion.present) {
      map['payload_schema_version'] = Variable<int>(payloadSchemaVersion.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillSourcesCompanion(')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('kind: $kind, ')
          ..write('payloadSchemaVersion: $payloadSchemaVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RevisionMetadataTable extends RevisionMetadata
    with TableInfo<$RevisionMetadataTable, RevisionMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevisionMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES source_lineages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _objectIdMeta = const VerificationMeta(
    'objectId',
  );
  @override
  late final GeneratedColumn<String> objectId = GeneratedColumn<String>(
    'object_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileCountMeta = const VerificationMeta(
    'fileCount',
  );
  @override
  late final GeneratedColumn<int> fileCount = GeneratedColumn<int>(
    'file_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _declaredNameMeta = const VerificationMeta(
    'declaredName',
  );
  @override
  late final GeneratedColumn<String> declaredName = GeneratedColumn<String>(
    'declared_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validationStateMeta = const VerificationMeta(
    'validationState',
  );
  @override
  late final GeneratedColumn<String> validationState = GeneratedColumn<String>(
    'validation_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validationCodeMeta = const VerificationMeta(
    'validationCode',
  );
  @override
  late final GeneratedColumn<String> validationCode = GeneratedColumn<String>(
    'validation_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sourceLineageId,
    objectId,
    contentHash,
    fileCount,
    byteSize,
    declaredName,
    validationState,
    validationCode,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revision_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<RevisionMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLineageIdMeta);
    }
    if (data.containsKey('object_id')) {
      context.handle(
        _objectIdMeta,
        objectId.isAcceptableOrUnknown(data['object_id']!, _objectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_objectIdMeta);
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('file_count')) {
      context.handle(
        _fileCountMeta,
        fileCount.isAcceptableOrUnknown(data['file_count']!, _fileCountMeta),
      );
    } else if (isInserting) {
      context.missing(_fileCountMeta);
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_byteSizeMeta);
    }
    if (data.containsKey('declared_name')) {
      context.handle(
        _declaredNameMeta,
        declaredName.isAcceptableOrUnknown(
          data['declared_name']!,
          _declaredNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_declaredNameMeta);
    }
    if (data.containsKey('validation_state')) {
      context.handle(
        _validationStateMeta,
        validationState.isAcceptableOrUnknown(
          data['validation_state']!,
          _validationStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_validationStateMeta);
    }
    if (data.containsKey('validation_code')) {
      context.handle(
        _validationCodeMeta,
        validationCode.isAcceptableOrUnknown(
          data['validation_code']!,
          _validationCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceLineageId, objectId};
  @override
  RevisionMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RevisionMetadataData(
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      )!,
      objectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}object_id'],
      )!,
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      fileCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_count'],
      )!,
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      declaredName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}declared_name'],
      )!,
      validationState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}validation_state'],
      )!,
      validationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}validation_code'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $RevisionMetadataTable createAlias(String alias) {
    return $RevisionMetadataTable(attachedDatabase, alias);
  }
}

class RevisionMetadataData extends DataClass
    implements Insertable<RevisionMetadataData> {
  final String sourceLineageId;
  final String objectId;
  final String contentHash;
  final int fileCount;
  final int byteSize;
  final String declaredName;
  final String validationState;
  final String? validationCode;
  final int createdAtMicros;
  const RevisionMetadataData({
    required this.sourceLineageId,
    required this.objectId,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
    required this.declaredName,
    required this.validationState,
    this.validationCode,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_lineage_id'] = Variable<String>(sourceLineageId);
    map['object_id'] = Variable<String>(objectId);
    map['content_hash'] = Variable<String>(contentHash);
    map['file_count'] = Variable<int>(fileCount);
    map['byte_size'] = Variable<int>(byteSize);
    map['declared_name'] = Variable<String>(declaredName);
    map['validation_state'] = Variable<String>(validationState);
    if (!nullToAbsent || validationCode != null) {
      map['validation_code'] = Variable<String>(validationCode);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  RevisionMetadataCompanion toCompanion(bool nullToAbsent) {
    return RevisionMetadataCompanion(
      sourceLineageId: Value(sourceLineageId),
      objectId: Value(objectId),
      contentHash: Value(contentHash),
      fileCount: Value(fileCount),
      byteSize: Value(byteSize),
      declaredName: Value(declaredName),
      validationState: Value(validationState),
      validationCode: validationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(validationCode),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory RevisionMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RevisionMetadataData(
      sourceLineageId: serializer.fromJson<String>(json['sourceLineageId']),
      objectId: serializer.fromJson<String>(json['objectId']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      fileCount: serializer.fromJson<int>(json['fileCount']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      declaredName: serializer.fromJson<String>(json['declaredName']),
      validationState: serializer.fromJson<String>(json['validationState']),
      validationCode: serializer.fromJson<String?>(json['validationCode']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceLineageId': serializer.toJson<String>(sourceLineageId),
      'objectId': serializer.toJson<String>(objectId),
      'contentHash': serializer.toJson<String>(contentHash),
      'fileCount': serializer.toJson<int>(fileCount),
      'byteSize': serializer.toJson<int>(byteSize),
      'declaredName': serializer.toJson<String>(declaredName),
      'validationState': serializer.toJson<String>(validationState),
      'validationCode': serializer.toJson<String?>(validationCode),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  RevisionMetadataData copyWith({
    String? sourceLineageId,
    String? objectId,
    String? contentHash,
    int? fileCount,
    int? byteSize,
    String? declaredName,
    String? validationState,
    Value<String?> validationCode = const Value.absent(),
    int? createdAtMicros,
  }) => RevisionMetadataData(
    sourceLineageId: sourceLineageId ?? this.sourceLineageId,
    objectId: objectId ?? this.objectId,
    contentHash: contentHash ?? this.contentHash,
    fileCount: fileCount ?? this.fileCount,
    byteSize: byteSize ?? this.byteSize,
    declaredName: declaredName ?? this.declaredName,
    validationState: validationState ?? this.validationState,
    validationCode: validationCode.present
        ? validationCode.value
        : this.validationCode,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  RevisionMetadataData copyWithCompanion(RevisionMetadataCompanion data) {
    return RevisionMetadataData(
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      objectId: data.objectId.present ? data.objectId.value : this.objectId,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      fileCount: data.fileCount.present ? data.fileCount.value : this.fileCount,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      declaredName: data.declaredName.present
          ? data.declaredName.value
          : this.declaredName,
      validationState: data.validationState.present
          ? data.validationState.value
          : this.validationState,
      validationCode: data.validationCode.present
          ? data.validationCode.value
          : this.validationCode,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RevisionMetadataData(')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('objectId: $objectId, ')
          ..write('contentHash: $contentHash, ')
          ..write('fileCount: $fileCount, ')
          ..write('byteSize: $byteSize, ')
          ..write('declaredName: $declaredName, ')
          ..write('validationState: $validationState, ')
          ..write('validationCode: $validationCode, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sourceLineageId,
    objectId,
    contentHash,
    fileCount,
    byteSize,
    declaredName,
    validationState,
    validationCode,
    createdAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RevisionMetadataData &&
          other.sourceLineageId == this.sourceLineageId &&
          other.objectId == this.objectId &&
          other.contentHash == this.contentHash &&
          other.fileCount == this.fileCount &&
          other.byteSize == this.byteSize &&
          other.declaredName == this.declaredName &&
          other.validationState == this.validationState &&
          other.validationCode == this.validationCode &&
          other.createdAtMicros == this.createdAtMicros);
}

class RevisionMetadataCompanion extends UpdateCompanion<RevisionMetadataData> {
  final Value<String> sourceLineageId;
  final Value<String> objectId;
  final Value<String> contentHash;
  final Value<int> fileCount;
  final Value<int> byteSize;
  final Value<String> declaredName;
  final Value<String> validationState;
  final Value<String?> validationCode;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const RevisionMetadataCompanion({
    this.sourceLineageId = const Value.absent(),
    this.objectId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.fileCount = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.declaredName = const Value.absent(),
    this.validationState = const Value.absent(),
    this.validationCode = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevisionMetadataCompanion.insert({
    required String sourceLineageId,
    required String objectId,
    required String contentHash,
    required int fileCount,
    required int byteSize,
    required String declaredName,
    required String validationState,
    this.validationCode = const Value.absent(),
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : sourceLineageId = Value(sourceLineageId),
       objectId = Value(objectId),
       contentHash = Value(contentHash),
       fileCount = Value(fileCount),
       byteSize = Value(byteSize),
       declaredName = Value(declaredName),
       validationState = Value(validationState),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<RevisionMetadataData> custom({
    Expression<String>? sourceLineageId,
    Expression<String>? objectId,
    Expression<String>? contentHash,
    Expression<int>? fileCount,
    Expression<int>? byteSize,
    Expression<String>? declaredName,
    Expression<String>? validationState,
    Expression<String>? validationCode,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (objectId != null) 'object_id': objectId,
      if (contentHash != null) 'content_hash': contentHash,
      if (fileCount != null) 'file_count': fileCount,
      if (byteSize != null) 'byte_size': byteSize,
      if (declaredName != null) 'declared_name': declaredName,
      if (validationState != null) 'validation_state': validationState,
      if (validationCode != null) 'validation_code': validationCode,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevisionMetadataCompanion copyWith({
    Value<String>? sourceLineageId,
    Value<String>? objectId,
    Value<String>? contentHash,
    Value<int>? fileCount,
    Value<int>? byteSize,
    Value<String>? declaredName,
    Value<String>? validationState,
    Value<String?>? validationCode,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return RevisionMetadataCompanion(
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      objectId: objectId ?? this.objectId,
      contentHash: contentHash ?? this.contentHash,
      fileCount: fileCount ?? this.fileCount,
      byteSize: byteSize ?? this.byteSize,
      declaredName: declaredName ?? this.declaredName,
      validationState: validationState ?? this.validationState,
      validationCode: validationCode ?? this.validationCode,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (objectId.present) {
      map['object_id'] = Variable<String>(objectId.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (fileCount.present) {
      map['file_count'] = Variable<int>(fileCount.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (declaredName.present) {
      map['declared_name'] = Variable<String>(declaredName.value);
    }
    if (validationState.present) {
      map['validation_state'] = Variable<String>(validationState.value);
    }
    if (validationCode.present) {
      map['validation_code'] = Variable<String>(validationCode.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevisionMetadataCompanion(')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('objectId: $objectId, ')
          ..write('contentHash: $contentHash, ')
          ..write('fileCount: $fileCount, ')
          ..write('byteSize: $byteSize, ')
          ..write('declaredName: $declaredName, ')
          ..write('validationState: $validationState, ')
          ..write('validationCode: $validationCode, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CurrentRevisionSelectionTable extends CurrentRevisionSelection
    with
        TableInfo<
          $CurrentRevisionSelectionTable,
          CurrentRevisionSelectionData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CurrentRevisionSelectionTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _upstreamObjectIdMeta = const VerificationMeta(
    'upstreamObjectId',
  );
  @override
  late final GeneratedColumn<String> upstreamObjectId = GeneratedColumn<String>(
    'upstream_object_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _effectiveObjectIdMeta = const VerificationMeta(
    'effectiveObjectId',
  );
  @override
  late final GeneratedColumn<String> effectiveObjectId =
      GeneratedColumn<String>(
        'effective_object_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    sourceLineageId,
    upstreamObjectId,
    effectiveObjectId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'current_revision_selection';
  @override
  VerificationContext validateIntegrity(
    Insertable<CurrentRevisionSelectionData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLineageIdMeta);
    }
    if (data.containsKey('upstream_object_id')) {
      context.handle(
        _upstreamObjectIdMeta,
        upstreamObjectId.isAcceptableOrUnknown(
          data['upstream_object_id']!,
          _upstreamObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_upstreamObjectIdMeta);
    }
    if (data.containsKey('effective_object_id')) {
      context.handle(
        _effectiveObjectIdMeta,
        effectiveObjectId.isAcceptableOrUnknown(
          data['effective_object_id']!,
          _effectiveObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_effectiveObjectIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId};
  @override
  CurrentRevisionSelectionData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CurrentRevisionSelectionData(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      )!,
      upstreamObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}upstream_object_id'],
      )!,
      effectiveObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}effective_object_id'],
      )!,
    );
  }

  @override
  $CurrentRevisionSelectionTable createAlias(String alias) {
    return $CurrentRevisionSelectionTable(attachedDatabase, alias);
  }
}

class CurrentRevisionSelectionData extends DataClass
    implements Insertable<CurrentRevisionSelectionData> {
  final String managedSkillId;
  final String sourceLineageId;
  final String upstreamObjectId;
  final String effectiveObjectId;
  const CurrentRevisionSelectionData({
    required this.managedSkillId,
    required this.sourceLineageId,
    required this.upstreamObjectId,
    required this.effectiveObjectId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['source_lineage_id'] = Variable<String>(sourceLineageId);
    map['upstream_object_id'] = Variable<String>(upstreamObjectId);
    map['effective_object_id'] = Variable<String>(effectiveObjectId);
    return map;
  }

  CurrentRevisionSelectionCompanion toCompanion(bool nullToAbsent) {
    return CurrentRevisionSelectionCompanion(
      managedSkillId: Value(managedSkillId),
      sourceLineageId: Value(sourceLineageId),
      upstreamObjectId: Value(upstreamObjectId),
      effectiveObjectId: Value(effectiveObjectId),
    );
  }

  factory CurrentRevisionSelectionData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CurrentRevisionSelectionData(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      sourceLineageId: serializer.fromJson<String>(json['sourceLineageId']),
      upstreamObjectId: serializer.fromJson<String>(json['upstreamObjectId']),
      effectiveObjectId: serializer.fromJson<String>(json['effectiveObjectId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'sourceLineageId': serializer.toJson<String>(sourceLineageId),
      'upstreamObjectId': serializer.toJson<String>(upstreamObjectId),
      'effectiveObjectId': serializer.toJson<String>(effectiveObjectId),
    };
  }

  CurrentRevisionSelectionData copyWith({
    String? managedSkillId,
    String? sourceLineageId,
    String? upstreamObjectId,
    String? effectiveObjectId,
  }) => CurrentRevisionSelectionData(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    sourceLineageId: sourceLineageId ?? this.sourceLineageId,
    upstreamObjectId: upstreamObjectId ?? this.upstreamObjectId,
    effectiveObjectId: effectiveObjectId ?? this.effectiveObjectId,
  );
  CurrentRevisionSelectionData copyWithCompanion(
    CurrentRevisionSelectionCompanion data,
  ) {
    return CurrentRevisionSelectionData(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      upstreamObjectId: data.upstreamObjectId.present
          ? data.upstreamObjectId.value
          : this.upstreamObjectId,
      effectiveObjectId: data.effectiveObjectId.present
          ? data.effectiveObjectId.value
          : this.effectiveObjectId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CurrentRevisionSelectionData(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('upstreamObjectId: $upstreamObjectId, ')
          ..write('effectiveObjectId: $effectiveObjectId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    sourceLineageId,
    upstreamObjectId,
    effectiveObjectId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CurrentRevisionSelectionData &&
          other.managedSkillId == this.managedSkillId &&
          other.sourceLineageId == this.sourceLineageId &&
          other.upstreamObjectId == this.upstreamObjectId &&
          other.effectiveObjectId == this.effectiveObjectId);
}

class CurrentRevisionSelectionCompanion
    extends UpdateCompanion<CurrentRevisionSelectionData> {
  final Value<String> managedSkillId;
  final Value<String> sourceLineageId;
  final Value<String> upstreamObjectId;
  final Value<String> effectiveObjectId;
  final Value<int> rowid;
  const CurrentRevisionSelectionCompanion({
    this.managedSkillId = const Value.absent(),
    this.sourceLineageId = const Value.absent(),
    this.upstreamObjectId = const Value.absent(),
    this.effectiveObjectId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CurrentRevisionSelectionCompanion.insert({
    required String managedSkillId,
    required String sourceLineageId,
    required String upstreamObjectId,
    required String effectiveObjectId,
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       sourceLineageId = Value(sourceLineageId),
       upstreamObjectId = Value(upstreamObjectId),
       effectiveObjectId = Value(effectiveObjectId);
  static Insertable<CurrentRevisionSelectionData> custom({
    Expression<String>? managedSkillId,
    Expression<String>? sourceLineageId,
    Expression<String>? upstreamObjectId,
    Expression<String>? effectiveObjectId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (upstreamObjectId != null) 'upstream_object_id': upstreamObjectId,
      if (effectiveObjectId != null) 'effective_object_id': effectiveObjectId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CurrentRevisionSelectionCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? sourceLineageId,
    Value<String>? upstreamObjectId,
    Value<String>? effectiveObjectId,
    Value<int>? rowid,
  }) {
    return CurrentRevisionSelectionCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      upstreamObjectId: upstreamObjectId ?? this.upstreamObjectId,
      effectiveObjectId: effectiveObjectId ?? this.effectiveObjectId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (upstreamObjectId.present) {
      map['upstream_object_id'] = Variable<String>(upstreamObjectId.value);
    }
    if (effectiveObjectId.present) {
      map['effective_object_id'] = Variable<String>(effectiveObjectId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CurrentRevisionSelectionCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('upstreamObjectId: $upstreamObjectId, ')
          ..write('effectiveObjectId: $effectiveObjectId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftWorkspacesTable extends DraftWorkspaces
    with TableInfo<$DraftWorkspacesTable, DraftWorkspace> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftWorkspacesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseObjectIdMeta = const VerificationMeta(
    'baseObjectId',
  );
  @override
  late final GeneratedColumn<String> baseObjectId = GeneratedColumn<String>(
    'base_object_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _purposeMeta = const VerificationMeta(
    'purpose',
  );
  @override
  late final GeneratedColumn<String> purpose = GeneratedColumn<String>(
    'purpose',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    sourceLineageId,
    baseObjectId,
    purpose,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'draft_workspaces';
  @override
  VerificationContext validateIntegrity(
    Insertable<DraftWorkspace> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLineageIdMeta);
    }
    if (data.containsKey('base_object_id')) {
      context.handle(
        _baseObjectIdMeta,
        baseObjectId.isAcceptableOrUnknown(
          data['base_object_id']!,
          _baseObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseObjectIdMeta);
    }
    if (data.containsKey('purpose')) {
      context.handle(
        _purposeMeta,
        purpose.isAcceptableOrUnknown(data['purpose']!, _purposeMeta),
      );
    } else if (isInserting) {
      context.missing(_purposeMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId};
  @override
  DraftWorkspace map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DraftWorkspace(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      )!,
      baseObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_object_id'],
      )!,
      purpose: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}purpose'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $DraftWorkspacesTable createAlias(String alias) {
    return $DraftWorkspacesTable(attachedDatabase, alias);
  }
}

class DraftWorkspace extends DataClass implements Insertable<DraftWorkspace> {
  final String managedSkillId;
  final String sourceLineageId;
  final String baseObjectId;
  final String purpose;
  final int createdAtMicros;
  final int updatedAtMicros;
  const DraftWorkspace({
    required this.managedSkillId,
    required this.sourceLineageId,
    required this.baseObjectId,
    required this.purpose,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['source_lineage_id'] = Variable<String>(sourceLineageId);
    map['base_object_id'] = Variable<String>(baseObjectId);
    map['purpose'] = Variable<String>(purpose);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  DraftWorkspacesCompanion toCompanion(bool nullToAbsent) {
    return DraftWorkspacesCompanion(
      managedSkillId: Value(managedSkillId),
      sourceLineageId: Value(sourceLineageId),
      baseObjectId: Value(baseObjectId),
      purpose: Value(purpose),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory DraftWorkspace.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DraftWorkspace(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      sourceLineageId: serializer.fromJson<String>(json['sourceLineageId']),
      baseObjectId: serializer.fromJson<String>(json['baseObjectId']),
      purpose: serializer.fromJson<String>(json['purpose']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'sourceLineageId': serializer.toJson<String>(sourceLineageId),
      'baseObjectId': serializer.toJson<String>(baseObjectId),
      'purpose': serializer.toJson<String>(purpose),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  DraftWorkspace copyWith({
    String? managedSkillId,
    String? sourceLineageId,
    String? baseObjectId,
    String? purpose,
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => DraftWorkspace(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    sourceLineageId: sourceLineageId ?? this.sourceLineageId,
    baseObjectId: baseObjectId ?? this.baseObjectId,
    purpose: purpose ?? this.purpose,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  DraftWorkspace copyWithCompanion(DraftWorkspacesCompanion data) {
    return DraftWorkspace(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      baseObjectId: data.baseObjectId.present
          ? data.baseObjectId.value
          : this.baseObjectId,
      purpose: data.purpose.present ? data.purpose.value : this.purpose,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DraftWorkspace(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('baseObjectId: $baseObjectId, ')
          ..write('purpose: $purpose, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    sourceLineageId,
    baseObjectId,
    purpose,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DraftWorkspace &&
          other.managedSkillId == this.managedSkillId &&
          other.sourceLineageId == this.sourceLineageId &&
          other.baseObjectId == this.baseObjectId &&
          other.purpose == this.purpose &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class DraftWorkspacesCompanion extends UpdateCompanion<DraftWorkspace> {
  final Value<String> managedSkillId;
  final Value<String> sourceLineageId;
  final Value<String> baseObjectId;
  final Value<String> purpose;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const DraftWorkspacesCompanion({
    this.managedSkillId = const Value.absent(),
    this.sourceLineageId = const Value.absent(),
    this.baseObjectId = const Value.absent(),
    this.purpose = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftWorkspacesCompanion.insert({
    required String managedSkillId,
    required String sourceLineageId,
    required String baseObjectId,
    required String purpose,
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       sourceLineageId = Value(sourceLineageId),
       baseObjectId = Value(baseObjectId),
       purpose = Value(purpose),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<DraftWorkspace> custom({
    Expression<String>? managedSkillId,
    Expression<String>? sourceLineageId,
    Expression<String>? baseObjectId,
    Expression<String>? purpose,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (baseObjectId != null) 'base_object_id': baseObjectId,
      if (purpose != null) 'purpose': purpose,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftWorkspacesCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? sourceLineageId,
    Value<String>? baseObjectId,
    Value<String>? purpose,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return DraftWorkspacesCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      baseObjectId: baseObjectId ?? this.baseObjectId,
      purpose: purpose ?? this.purpose,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (baseObjectId.present) {
      map['base_object_id'] = Variable<String>(baseObjectId.value);
    }
    if (purpose.present) {
      map['purpose'] = Variable<String>(purpose.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DraftWorkspacesCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('baseObjectId: $baseObjectId, ')
          ..write('purpose: $purpose, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UpdateCandidateSessionsTable extends UpdateCandidateSessions
    with TableInfo<$UpdateCandidateSessionsTable, UpdateCandidateSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UpdateCandidateSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previousUpstreamObjectIdMeta =
      const VerificationMeta('previousUpstreamObjectId');
  @override
  late final GeneratedColumn<String> previousUpstreamObjectId =
      GeneratedColumn<String>(
        'previous_upstream_object_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _previousEffectiveObjectIdMeta =
      const VerificationMeta('previousEffectiveObjectId');
  @override
  late final GeneratedColumn<String> previousEffectiveObjectId =
      GeneratedColumn<String>(
        'previous_effective_object_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _incomingUpstreamObjectIdMeta =
      const VerificationMeta('incomingUpstreamObjectId');
  @override
  late final GeneratedColumn<String> incomingUpstreamObjectId =
      GeneratedColumn<String>(
        'incoming_upstream_object_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _candidateObjectIdMeta = const VerificationMeta(
    'candidateObjectId',
  );
  @override
  late final GeneratedColumn<String> candidateObjectId =
      GeneratedColumn<String>(
        'candidate_object_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validationCodeMeta = const VerificationMeta(
    'validationCode',
  );
  @override
  late final GeneratedColumn<String> validationCode = GeneratedColumn<String>(
    'validation_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    sourceLineageId,
    previousUpstreamObjectId,
    previousEffectiveObjectId,
    incomingUpstreamObjectId,
    candidateObjectId,
    status,
    validationCode,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'update_candidate_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<UpdateCandidateSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceLineageIdMeta);
    }
    if (data.containsKey('previous_upstream_object_id')) {
      context.handle(
        _previousUpstreamObjectIdMeta,
        previousUpstreamObjectId.isAcceptableOrUnknown(
          data['previous_upstream_object_id']!,
          _previousUpstreamObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_previousUpstreamObjectIdMeta);
    }
    if (data.containsKey('previous_effective_object_id')) {
      context.handle(
        _previousEffectiveObjectIdMeta,
        previousEffectiveObjectId.isAcceptableOrUnknown(
          data['previous_effective_object_id']!,
          _previousEffectiveObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_previousEffectiveObjectIdMeta);
    }
    if (data.containsKey('incoming_upstream_object_id')) {
      context.handle(
        _incomingUpstreamObjectIdMeta,
        incomingUpstreamObjectId.isAcceptableOrUnknown(
          data['incoming_upstream_object_id']!,
          _incomingUpstreamObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_incomingUpstreamObjectIdMeta);
    }
    if (data.containsKey('candidate_object_id')) {
      context.handle(
        _candidateObjectIdMeta,
        candidateObjectId.isAcceptableOrUnknown(
          data['candidate_object_id']!,
          _candidateObjectIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_candidateObjectIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('validation_code')) {
      context.handle(
        _validationCodeMeta,
        validationCode.isAcceptableOrUnknown(
          data['validation_code']!,
          _validationCodeMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId};
  @override
  UpdateCandidateSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UpdateCandidateSession(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      )!,
      previousUpstreamObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_upstream_object_id'],
      )!,
      previousEffectiveObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}previous_effective_object_id'],
      )!,
      incomingUpstreamObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incoming_upstream_object_id'],
      )!,
      candidateObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}candidate_object_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      validationCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}validation_code'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $UpdateCandidateSessionsTable createAlias(String alias) {
    return $UpdateCandidateSessionsTable(attachedDatabase, alias);
  }
}

class UpdateCandidateSession extends DataClass
    implements Insertable<UpdateCandidateSession> {
  final String managedSkillId;
  final String sourceLineageId;
  final String previousUpstreamObjectId;
  final String previousEffectiveObjectId;
  final String incomingUpstreamObjectId;
  final String candidateObjectId;
  final String status;
  final String? validationCode;
  final int createdAtMicros;
  final int updatedAtMicros;
  const UpdateCandidateSession({
    required this.managedSkillId,
    required this.sourceLineageId,
    required this.previousUpstreamObjectId,
    required this.previousEffectiveObjectId,
    required this.incomingUpstreamObjectId,
    required this.candidateObjectId,
    required this.status,
    this.validationCode,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['source_lineage_id'] = Variable<String>(sourceLineageId);
    map['previous_upstream_object_id'] = Variable<String>(
      previousUpstreamObjectId,
    );
    map['previous_effective_object_id'] = Variable<String>(
      previousEffectiveObjectId,
    );
    map['incoming_upstream_object_id'] = Variable<String>(
      incomingUpstreamObjectId,
    );
    map['candidate_object_id'] = Variable<String>(candidateObjectId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || validationCode != null) {
      map['validation_code'] = Variable<String>(validationCode);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  UpdateCandidateSessionsCompanion toCompanion(bool nullToAbsent) {
    return UpdateCandidateSessionsCompanion(
      managedSkillId: Value(managedSkillId),
      sourceLineageId: Value(sourceLineageId),
      previousUpstreamObjectId: Value(previousUpstreamObjectId),
      previousEffectiveObjectId: Value(previousEffectiveObjectId),
      incomingUpstreamObjectId: Value(incomingUpstreamObjectId),
      candidateObjectId: Value(candidateObjectId),
      status: Value(status),
      validationCode: validationCode == null && nullToAbsent
          ? const Value.absent()
          : Value(validationCode),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory UpdateCandidateSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UpdateCandidateSession(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      sourceLineageId: serializer.fromJson<String>(json['sourceLineageId']),
      previousUpstreamObjectId: serializer.fromJson<String>(
        json['previousUpstreamObjectId'],
      ),
      previousEffectiveObjectId: serializer.fromJson<String>(
        json['previousEffectiveObjectId'],
      ),
      incomingUpstreamObjectId: serializer.fromJson<String>(
        json['incomingUpstreamObjectId'],
      ),
      candidateObjectId: serializer.fromJson<String>(json['candidateObjectId']),
      status: serializer.fromJson<String>(json['status']),
      validationCode: serializer.fromJson<String?>(json['validationCode']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'sourceLineageId': serializer.toJson<String>(sourceLineageId),
      'previousUpstreamObjectId': serializer.toJson<String>(
        previousUpstreamObjectId,
      ),
      'previousEffectiveObjectId': serializer.toJson<String>(
        previousEffectiveObjectId,
      ),
      'incomingUpstreamObjectId': serializer.toJson<String>(
        incomingUpstreamObjectId,
      ),
      'candidateObjectId': serializer.toJson<String>(candidateObjectId),
      'status': serializer.toJson<String>(status),
      'validationCode': serializer.toJson<String?>(validationCode),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  UpdateCandidateSession copyWith({
    String? managedSkillId,
    String? sourceLineageId,
    String? previousUpstreamObjectId,
    String? previousEffectiveObjectId,
    String? incomingUpstreamObjectId,
    String? candidateObjectId,
    String? status,
    Value<String?> validationCode = const Value.absent(),
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => UpdateCandidateSession(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    sourceLineageId: sourceLineageId ?? this.sourceLineageId,
    previousUpstreamObjectId:
        previousUpstreamObjectId ?? this.previousUpstreamObjectId,
    previousEffectiveObjectId:
        previousEffectiveObjectId ?? this.previousEffectiveObjectId,
    incomingUpstreamObjectId:
        incomingUpstreamObjectId ?? this.incomingUpstreamObjectId,
    candidateObjectId: candidateObjectId ?? this.candidateObjectId,
    status: status ?? this.status,
    validationCode: validationCode.present
        ? validationCode.value
        : this.validationCode,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  UpdateCandidateSession copyWithCompanion(
    UpdateCandidateSessionsCompanion data,
  ) {
    return UpdateCandidateSession(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      previousUpstreamObjectId: data.previousUpstreamObjectId.present
          ? data.previousUpstreamObjectId.value
          : this.previousUpstreamObjectId,
      previousEffectiveObjectId: data.previousEffectiveObjectId.present
          ? data.previousEffectiveObjectId.value
          : this.previousEffectiveObjectId,
      incomingUpstreamObjectId: data.incomingUpstreamObjectId.present
          ? data.incomingUpstreamObjectId.value
          : this.incomingUpstreamObjectId,
      candidateObjectId: data.candidateObjectId.present
          ? data.candidateObjectId.value
          : this.candidateObjectId,
      status: data.status.present ? data.status.value : this.status,
      validationCode: data.validationCode.present
          ? data.validationCode.value
          : this.validationCode,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UpdateCandidateSession(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('previousUpstreamObjectId: $previousUpstreamObjectId, ')
          ..write('previousEffectiveObjectId: $previousEffectiveObjectId, ')
          ..write('incomingUpstreamObjectId: $incomingUpstreamObjectId, ')
          ..write('candidateObjectId: $candidateObjectId, ')
          ..write('status: $status, ')
          ..write('validationCode: $validationCode, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    sourceLineageId,
    previousUpstreamObjectId,
    previousEffectiveObjectId,
    incomingUpstreamObjectId,
    candidateObjectId,
    status,
    validationCode,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UpdateCandidateSession &&
          other.managedSkillId == this.managedSkillId &&
          other.sourceLineageId == this.sourceLineageId &&
          other.previousUpstreamObjectId == this.previousUpstreamObjectId &&
          other.previousEffectiveObjectId == this.previousEffectiveObjectId &&
          other.incomingUpstreamObjectId == this.incomingUpstreamObjectId &&
          other.candidateObjectId == this.candidateObjectId &&
          other.status == this.status &&
          other.validationCode == this.validationCode &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class UpdateCandidateSessionsCompanion
    extends UpdateCompanion<UpdateCandidateSession> {
  final Value<String> managedSkillId;
  final Value<String> sourceLineageId;
  final Value<String> previousUpstreamObjectId;
  final Value<String> previousEffectiveObjectId;
  final Value<String> incomingUpstreamObjectId;
  final Value<String> candidateObjectId;
  final Value<String> status;
  final Value<String?> validationCode;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const UpdateCandidateSessionsCompanion({
    this.managedSkillId = const Value.absent(),
    this.sourceLineageId = const Value.absent(),
    this.previousUpstreamObjectId = const Value.absent(),
    this.previousEffectiveObjectId = const Value.absent(),
    this.incomingUpstreamObjectId = const Value.absent(),
    this.candidateObjectId = const Value.absent(),
    this.status = const Value.absent(),
    this.validationCode = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UpdateCandidateSessionsCompanion.insert({
    required String managedSkillId,
    required String sourceLineageId,
    required String previousUpstreamObjectId,
    required String previousEffectiveObjectId,
    required String incomingUpstreamObjectId,
    required String candidateObjectId,
    required String status,
    this.validationCode = const Value.absent(),
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       sourceLineageId = Value(sourceLineageId),
       previousUpstreamObjectId = Value(previousUpstreamObjectId),
       previousEffectiveObjectId = Value(previousEffectiveObjectId),
       incomingUpstreamObjectId = Value(incomingUpstreamObjectId),
       candidateObjectId = Value(candidateObjectId),
       status = Value(status),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<UpdateCandidateSession> custom({
    Expression<String>? managedSkillId,
    Expression<String>? sourceLineageId,
    Expression<String>? previousUpstreamObjectId,
    Expression<String>? previousEffectiveObjectId,
    Expression<String>? incomingUpstreamObjectId,
    Expression<String>? candidateObjectId,
    Expression<String>? status,
    Expression<String>? validationCode,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (previousUpstreamObjectId != null)
        'previous_upstream_object_id': previousUpstreamObjectId,
      if (previousEffectiveObjectId != null)
        'previous_effective_object_id': previousEffectiveObjectId,
      if (incomingUpstreamObjectId != null)
        'incoming_upstream_object_id': incomingUpstreamObjectId,
      if (candidateObjectId != null) 'candidate_object_id': candidateObjectId,
      if (status != null) 'status': status,
      if (validationCode != null) 'validation_code': validationCode,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UpdateCandidateSessionsCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? sourceLineageId,
    Value<String>? previousUpstreamObjectId,
    Value<String>? previousEffectiveObjectId,
    Value<String>? incomingUpstreamObjectId,
    Value<String>? candidateObjectId,
    Value<String>? status,
    Value<String?>? validationCode,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return UpdateCandidateSessionsCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      previousUpstreamObjectId:
          previousUpstreamObjectId ?? this.previousUpstreamObjectId,
      previousEffectiveObjectId:
          previousEffectiveObjectId ?? this.previousEffectiveObjectId,
      incomingUpstreamObjectId:
          incomingUpstreamObjectId ?? this.incomingUpstreamObjectId,
      candidateObjectId: candidateObjectId ?? this.candidateObjectId,
      status: status ?? this.status,
      validationCode: validationCode ?? this.validationCode,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (previousUpstreamObjectId.present) {
      map['previous_upstream_object_id'] = Variable<String>(
        previousUpstreamObjectId.value,
      );
    }
    if (previousEffectiveObjectId.present) {
      map['previous_effective_object_id'] = Variable<String>(
        previousEffectiveObjectId.value,
      );
    }
    if (incomingUpstreamObjectId.present) {
      map['incoming_upstream_object_id'] = Variable<String>(
        incomingUpstreamObjectId.value,
      );
    }
    if (candidateObjectId.present) {
      map['candidate_object_id'] = Variable<String>(candidateObjectId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (validationCode.present) {
      map['validation_code'] = Variable<String>(validationCode.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UpdateCandidateSessionsCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('previousUpstreamObjectId: $previousUpstreamObjectId, ')
          ..write('previousEffectiveObjectId: $previousEffectiveObjectId, ')
          ..write('incomingUpstreamObjectId: $incomingUpstreamObjectId, ')
          ..write('candidateObjectId: $candidateObjectId, ')
          ..write('status: $status, ')
          ..write('validationCode: $validationCode, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UpdateCandidateItemsTable extends UpdateCandidateItems
    with TableInfo<$UpdateCandidateItemsTable, UpdateCandidateItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UpdateCandidateItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseObjectIdMeta = const VerificationMeta(
    'baseObjectId',
  );
  @override
  late final GeneratedColumn<String> baseObjectId = GeneratedColumn<String>(
    'base_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _oursObjectIdMeta = const VerificationMeta(
    'oursObjectId',
  );
  @override
  late final GeneratedColumn<String> oursObjectId = GeneratedColumn<String>(
    'ours_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _theirsObjectIdMeta = const VerificationMeta(
    'theirsObjectId',
  );
  @override
  late final GeneratedColumn<String> theirsObjectId = GeneratedColumn<String>(
    'theirs_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    path,
    kind,
    state,
    baseObjectId,
    oursObjectId,
    theirsObjectId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'update_candidate_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<UpdateCandidateItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('base_object_id')) {
      context.handle(
        _baseObjectIdMeta,
        baseObjectId.isAcceptableOrUnknown(
          data['base_object_id']!,
          _baseObjectIdMeta,
        ),
      );
    }
    if (data.containsKey('ours_object_id')) {
      context.handle(
        _oursObjectIdMeta,
        oursObjectId.isAcceptableOrUnknown(
          data['ours_object_id']!,
          _oursObjectIdMeta,
        ),
      );
    }
    if (data.containsKey('theirs_object_id')) {
      context.handle(
        _theirsObjectIdMeta,
        theirsObjectId.isAcceptableOrUnknown(
          data['theirs_object_id']!,
          _theirsObjectIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId, path};
  @override
  UpdateCandidateItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UpdateCandidateItem(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      baseObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_object_id'],
      ),
      oursObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ours_object_id'],
      ),
      theirsObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theirs_object_id'],
      ),
    );
  }

  @override
  $UpdateCandidateItemsTable createAlias(String alias) {
    return $UpdateCandidateItemsTable(attachedDatabase, alias);
  }
}

class UpdateCandidateItem extends DataClass
    implements Insertable<UpdateCandidateItem> {
  final String managedSkillId;
  final String path;
  final String kind;
  final String state;
  final String? baseObjectId;
  final String? oursObjectId;
  final String? theirsObjectId;
  const UpdateCandidateItem({
    required this.managedSkillId,
    required this.path,
    required this.kind,
    required this.state,
    this.baseObjectId,
    this.oursObjectId,
    this.theirsObjectId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['path'] = Variable<String>(path);
    map['kind'] = Variable<String>(kind);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || baseObjectId != null) {
      map['base_object_id'] = Variable<String>(baseObjectId);
    }
    if (!nullToAbsent || oursObjectId != null) {
      map['ours_object_id'] = Variable<String>(oursObjectId);
    }
    if (!nullToAbsent || theirsObjectId != null) {
      map['theirs_object_id'] = Variable<String>(theirsObjectId);
    }
    return map;
  }

  UpdateCandidateItemsCompanion toCompanion(bool nullToAbsent) {
    return UpdateCandidateItemsCompanion(
      managedSkillId: Value(managedSkillId),
      path: Value(path),
      kind: Value(kind),
      state: Value(state),
      baseObjectId: baseObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(baseObjectId),
      oursObjectId: oursObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(oursObjectId),
      theirsObjectId: theirsObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(theirsObjectId),
    );
  }

  factory UpdateCandidateItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UpdateCandidateItem(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      path: serializer.fromJson<String>(json['path']),
      kind: serializer.fromJson<String>(json['kind']),
      state: serializer.fromJson<String>(json['state']),
      baseObjectId: serializer.fromJson<String?>(json['baseObjectId']),
      oursObjectId: serializer.fromJson<String?>(json['oursObjectId']),
      theirsObjectId: serializer.fromJson<String?>(json['theirsObjectId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'path': serializer.toJson<String>(path),
      'kind': serializer.toJson<String>(kind),
      'state': serializer.toJson<String>(state),
      'baseObjectId': serializer.toJson<String?>(baseObjectId),
      'oursObjectId': serializer.toJson<String?>(oursObjectId),
      'theirsObjectId': serializer.toJson<String?>(theirsObjectId),
    };
  }

  UpdateCandidateItem copyWith({
    String? managedSkillId,
    String? path,
    String? kind,
    String? state,
    Value<String?> baseObjectId = const Value.absent(),
    Value<String?> oursObjectId = const Value.absent(),
    Value<String?> theirsObjectId = const Value.absent(),
  }) => UpdateCandidateItem(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    path: path ?? this.path,
    kind: kind ?? this.kind,
    state: state ?? this.state,
    baseObjectId: baseObjectId.present ? baseObjectId.value : this.baseObjectId,
    oursObjectId: oursObjectId.present ? oursObjectId.value : this.oursObjectId,
    theirsObjectId: theirsObjectId.present
        ? theirsObjectId.value
        : this.theirsObjectId,
  );
  UpdateCandidateItem copyWithCompanion(UpdateCandidateItemsCompanion data) {
    return UpdateCandidateItem(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      path: data.path.present ? data.path.value : this.path,
      kind: data.kind.present ? data.kind.value : this.kind,
      state: data.state.present ? data.state.value : this.state,
      baseObjectId: data.baseObjectId.present
          ? data.baseObjectId.value
          : this.baseObjectId,
      oursObjectId: data.oursObjectId.present
          ? data.oursObjectId.value
          : this.oursObjectId,
      theirsObjectId: data.theirsObjectId.present
          ? data.theirsObjectId.value
          : this.theirsObjectId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UpdateCandidateItem(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('path: $path, ')
          ..write('kind: $kind, ')
          ..write('state: $state, ')
          ..write('baseObjectId: $baseObjectId, ')
          ..write('oursObjectId: $oursObjectId, ')
          ..write('theirsObjectId: $theirsObjectId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    path,
    kind,
    state,
    baseObjectId,
    oursObjectId,
    theirsObjectId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UpdateCandidateItem &&
          other.managedSkillId == this.managedSkillId &&
          other.path == this.path &&
          other.kind == this.kind &&
          other.state == this.state &&
          other.baseObjectId == this.baseObjectId &&
          other.oursObjectId == this.oursObjectId &&
          other.theirsObjectId == this.theirsObjectId);
}

class UpdateCandidateItemsCompanion
    extends UpdateCompanion<UpdateCandidateItem> {
  final Value<String> managedSkillId;
  final Value<String> path;
  final Value<String> kind;
  final Value<String> state;
  final Value<String?> baseObjectId;
  final Value<String?> oursObjectId;
  final Value<String?> theirsObjectId;
  final Value<int> rowid;
  const UpdateCandidateItemsCompanion({
    this.managedSkillId = const Value.absent(),
    this.path = const Value.absent(),
    this.kind = const Value.absent(),
    this.state = const Value.absent(),
    this.baseObjectId = const Value.absent(),
    this.oursObjectId = const Value.absent(),
    this.theirsObjectId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UpdateCandidateItemsCompanion.insert({
    required String managedSkillId,
    required String path,
    required String kind,
    required String state,
    this.baseObjectId = const Value.absent(),
    this.oursObjectId = const Value.absent(),
    this.theirsObjectId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       path = Value(path),
       kind = Value(kind),
       state = Value(state);
  static Insertable<UpdateCandidateItem> custom({
    Expression<String>? managedSkillId,
    Expression<String>? path,
    Expression<String>? kind,
    Expression<String>? state,
    Expression<String>? baseObjectId,
    Expression<String>? oursObjectId,
    Expression<String>? theirsObjectId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (path != null) 'path': path,
      if (kind != null) 'kind': kind,
      if (state != null) 'state': state,
      if (baseObjectId != null) 'base_object_id': baseObjectId,
      if (oursObjectId != null) 'ours_object_id': oursObjectId,
      if (theirsObjectId != null) 'theirs_object_id': theirsObjectId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UpdateCandidateItemsCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? path,
    Value<String>? kind,
    Value<String>? state,
    Value<String?>? baseObjectId,
    Value<String?>? oursObjectId,
    Value<String?>? theirsObjectId,
    Value<int>? rowid,
  }) {
    return UpdateCandidateItemsCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      path: path ?? this.path,
      kind: kind ?? this.kind,
      state: state ?? this.state,
      baseObjectId: baseObjectId ?? this.baseObjectId,
      oursObjectId: oursObjectId ?? this.oursObjectId,
      theirsObjectId: theirsObjectId ?? this.theirsObjectId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (baseObjectId.present) {
      map['base_object_id'] = Variable<String>(baseObjectId.value);
    }
    if (oursObjectId.present) {
      map['ours_object_id'] = Variable<String>(oursObjectId.value);
    }
    if (theirsObjectId.present) {
      map['theirs_object_id'] = Variable<String>(theirsObjectId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UpdateCandidateItemsCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('path: $path, ')
          ..write('kind: $kind, ')
          ..write('state: $state, ')
          ..write('baseObjectId: $baseObjectId, ')
          ..write('oursObjectId: $oursObjectId, ')
          ..write('theirsObjectId: $theirsObjectId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectRootsTable extends ProjectRoots
    with TableInfo<$ProjectRootsTable, ProjectRoot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectRootsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _canonicalPathMeta = const VerificationMeta(
    'canonicalPath',
  );
  @override
  late final GeneratedColumn<String> canonicalPath = GeneratedColumn<String>(
    'canonical_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    canonicalPath,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'project_roots';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRoot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('canonical_path')) {
      context.handle(
        _canonicalPathMeta,
        canonicalPath.isAcceptableOrUnknown(
          data['canonical_path']!,
          _canonicalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalPathMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProjectRoot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRoot(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      canonicalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_path'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $ProjectRootsTable createAlias(String alias) {
    return $ProjectRootsTable(attachedDatabase, alias);
  }
}

class ProjectRoot extends DataClass implements Insertable<ProjectRoot> {
  final String id;
  final String canonicalPath;
  final int createdAtMicros;
  final int updatedAtMicros;
  const ProjectRoot({
    required this.id,
    required this.canonicalPath,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['canonical_path'] = Variable<String>(canonicalPath);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  ProjectRootsCompanion toCompanion(bool nullToAbsent) {
    return ProjectRootsCompanion(
      id: Value(id),
      canonicalPath: Value(canonicalPath),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory ProjectRoot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRoot(
      id: serializer.fromJson<String>(json['id']),
      canonicalPath: serializer.fromJson<String>(json['canonicalPath']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'canonicalPath': serializer.toJson<String>(canonicalPath),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  ProjectRoot copyWith({
    String? id,
    String? canonicalPath,
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => ProjectRoot(
    id: id ?? this.id,
    canonicalPath: canonicalPath ?? this.canonicalPath,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  ProjectRoot copyWithCompanion(ProjectRootsCompanion data) {
    return ProjectRoot(
      id: data.id.present ? data.id.value : this.id,
      canonicalPath: data.canonicalPath.present
          ? data.canonicalPath.value
          : this.canonicalPath,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRoot(')
          ..write('id: $id, ')
          ..write('canonicalPath: $canonicalPath, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, canonicalPath, createdAtMicros, updatedAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRoot &&
          other.id == this.id &&
          other.canonicalPath == this.canonicalPath &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class ProjectRootsCompanion extends UpdateCompanion<ProjectRoot> {
  final Value<String> id;
  final Value<String> canonicalPath;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const ProjectRootsCompanion({
    this.id = const Value.absent(),
    this.canonicalPath = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectRootsCompanion.insert({
    required String id,
    required String canonicalPath,
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       canonicalPath = Value(canonicalPath),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<ProjectRoot> custom({
    Expression<String>? id,
    Expression<String>? canonicalPath,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (canonicalPath != null) 'canonical_path': canonicalPath,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectRootsCompanion copyWith({
    Value<String>? id,
    Value<String>? canonicalPath,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return ProjectRootsCompanion(
      id: id ?? this.id,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (canonicalPath.present) {
      map['canonical_path'] = Variable<String>(canonicalPath.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRootsCompanion(')
          ..write('id: $id, ')
          ..write('canonicalPath: $canonicalPath, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivationLocationsTable extends ActivationLocations
    with TableInfo<$ActivationLocationsTable, ActivationLocation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivationLocationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _canonicalPathMeta = const VerificationMeta(
    'canonicalPath',
  );
  @override
  late final GeneratedColumn<String> canonicalPath = GeneratedColumn<String>(
    'canonical_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectRootIdMeta = const VerificationMeta(
    'projectRootId',
  );
  @override
  late final GeneratedColumn<String> projectRootId = GeneratedColumn<String>(
    'project_root_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _projectRootPathMeta = const VerificationMeta(
    'projectRootPath',
  );
  @override
  late final GeneratedColumn<String> projectRootPath = GeneratedColumn<String>(
    'project_root_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    managedSkillId,
    canonicalPath,
    scope,
    mode,
    projectRootId,
    projectRootPath,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activation_locations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivationLocation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('canonical_path')) {
      context.handle(
        _canonicalPathMeta,
        canonicalPath.isAcceptableOrUnknown(
          data['canonical_path']!,
          _canonicalPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalPathMeta);
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('project_root_id')) {
      context.handle(
        _projectRootIdMeta,
        projectRootId.isAcceptableOrUnknown(
          data['project_root_id']!,
          _projectRootIdMeta,
        ),
      );
    }
    if (data.containsKey('project_root_path')) {
      context.handle(
        _projectRootPathMeta,
        projectRootPath.isAcceptableOrUnknown(
          data['project_root_path']!,
          _projectRootPathMeta,
        ),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {managedSkillId, canonicalPath},
  ];
  @override
  ActivationLocation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivationLocation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      canonicalPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_path'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      projectRootId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_root_id'],
      ),
      projectRootPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_root_path'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $ActivationLocationsTable createAlias(String alias) {
    return $ActivationLocationsTable(attachedDatabase, alias);
  }
}

class ActivationLocation extends DataClass
    implements Insertable<ActivationLocation> {
  final String id;
  final String managedSkillId;
  final String canonicalPath;
  final String scope;
  final String mode;
  final String? projectRootId;
  final String? projectRootPath;
  final int createdAtMicros;
  const ActivationLocation({
    required this.id,
    required this.managedSkillId,
    required this.canonicalPath,
    required this.scope,
    required this.mode,
    this.projectRootId,
    this.projectRootPath,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['canonical_path'] = Variable<String>(canonicalPath);
    map['scope'] = Variable<String>(scope);
    map['mode'] = Variable<String>(mode);
    if (!nullToAbsent || projectRootId != null) {
      map['project_root_id'] = Variable<String>(projectRootId);
    }
    if (!nullToAbsent || projectRootPath != null) {
      map['project_root_path'] = Variable<String>(projectRootPath);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  ActivationLocationsCompanion toCompanion(bool nullToAbsent) {
    return ActivationLocationsCompanion(
      id: Value(id),
      managedSkillId: Value(managedSkillId),
      canonicalPath: Value(canonicalPath),
      scope: Value(scope),
      mode: Value(mode),
      projectRootId: projectRootId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectRootId),
      projectRootPath: projectRootPath == null && nullToAbsent
          ? const Value.absent()
          : Value(projectRootPath),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory ActivationLocation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivationLocation(
      id: serializer.fromJson<String>(json['id']),
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      canonicalPath: serializer.fromJson<String>(json['canonicalPath']),
      scope: serializer.fromJson<String>(json['scope']),
      mode: serializer.fromJson<String>(json['mode']),
      projectRootId: serializer.fromJson<String?>(json['projectRootId']),
      projectRootPath: serializer.fromJson<String?>(json['projectRootPath']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'canonicalPath': serializer.toJson<String>(canonicalPath),
      'scope': serializer.toJson<String>(scope),
      'mode': serializer.toJson<String>(mode),
      'projectRootId': serializer.toJson<String?>(projectRootId),
      'projectRootPath': serializer.toJson<String?>(projectRootPath),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  ActivationLocation copyWith({
    String? id,
    String? managedSkillId,
    String? canonicalPath,
    String? scope,
    String? mode,
    Value<String?> projectRootId = const Value.absent(),
    Value<String?> projectRootPath = const Value.absent(),
    int? createdAtMicros,
  }) => ActivationLocation(
    id: id ?? this.id,
    managedSkillId: managedSkillId ?? this.managedSkillId,
    canonicalPath: canonicalPath ?? this.canonicalPath,
    scope: scope ?? this.scope,
    mode: mode ?? this.mode,
    projectRootId: projectRootId.present
        ? projectRootId.value
        : this.projectRootId,
    projectRootPath: projectRootPath.present
        ? projectRootPath.value
        : this.projectRootPath,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  ActivationLocation copyWithCompanion(ActivationLocationsCompanion data) {
    return ActivationLocation(
      id: data.id.present ? data.id.value : this.id,
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      canonicalPath: data.canonicalPath.present
          ? data.canonicalPath.value
          : this.canonicalPath,
      scope: data.scope.present ? data.scope.value : this.scope,
      mode: data.mode.present ? data.mode.value : this.mode,
      projectRootId: data.projectRootId.present
          ? data.projectRootId.value
          : this.projectRootId,
      projectRootPath: data.projectRootPath.present
          ? data.projectRootPath.value
          : this.projectRootPath,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivationLocation(')
          ..write('id: $id, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('canonicalPath: $canonicalPath, ')
          ..write('scope: $scope, ')
          ..write('mode: $mode, ')
          ..write('projectRootId: $projectRootId, ')
          ..write('projectRootPath: $projectRootPath, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    managedSkillId,
    canonicalPath,
    scope,
    mode,
    projectRootId,
    projectRootPath,
    createdAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivationLocation &&
          other.id == this.id &&
          other.managedSkillId == this.managedSkillId &&
          other.canonicalPath == this.canonicalPath &&
          other.scope == this.scope &&
          other.mode == this.mode &&
          other.projectRootId == this.projectRootId &&
          other.projectRootPath == this.projectRootPath &&
          other.createdAtMicros == this.createdAtMicros);
}

class ActivationLocationsCompanion extends UpdateCompanion<ActivationLocation> {
  final Value<String> id;
  final Value<String> managedSkillId;
  final Value<String> canonicalPath;
  final Value<String> scope;
  final Value<String> mode;
  final Value<String?> projectRootId;
  final Value<String?> projectRootPath;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const ActivationLocationsCompanion({
    this.id = const Value.absent(),
    this.managedSkillId = const Value.absent(),
    this.canonicalPath = const Value.absent(),
    this.scope = const Value.absent(),
    this.mode = const Value.absent(),
    this.projectRootId = const Value.absent(),
    this.projectRootPath = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivationLocationsCompanion.insert({
    required String id,
    required String managedSkillId,
    required String canonicalPath,
    required String scope,
    required String mode,
    this.projectRootId = const Value.absent(),
    this.projectRootPath = const Value.absent(),
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       managedSkillId = Value(managedSkillId),
       canonicalPath = Value(canonicalPath),
       scope = Value(scope),
       mode = Value(mode),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<ActivationLocation> custom({
    Expression<String>? id,
    Expression<String>? managedSkillId,
    Expression<String>? canonicalPath,
    Expression<String>? scope,
    Expression<String>? mode,
    Expression<String>? projectRootId,
    Expression<String>? projectRootPath,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (canonicalPath != null) 'canonical_path': canonicalPath,
      if (scope != null) 'scope': scope,
      if (mode != null) 'mode': mode,
      if (projectRootId != null) 'project_root_id': projectRootId,
      if (projectRootPath != null) 'project_root_path': projectRootPath,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivationLocationsCompanion copyWith({
    Value<String>? id,
    Value<String>? managedSkillId,
    Value<String>? canonicalPath,
    Value<String>? scope,
    Value<String>? mode,
    Value<String?>? projectRootId,
    Value<String?>? projectRootPath,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return ActivationLocationsCompanion(
      id: id ?? this.id,
      managedSkillId: managedSkillId ?? this.managedSkillId,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      scope: scope ?? this.scope,
      mode: mode ?? this.mode,
      projectRootId: projectRootId ?? this.projectRootId,
      projectRootPath: projectRootPath ?? this.projectRootPath,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (canonicalPath.present) {
      map['canonical_path'] = Variable<String>(canonicalPath.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (projectRootId.present) {
      map['project_root_id'] = Variable<String>(projectRootId.value);
    }
    if (projectRootPath.present) {
      map['project_root_path'] = Variable<String>(projectRootPath.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivationLocationsCompanion(')
          ..write('id: $id, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('canonicalPath: $canonicalPath, ')
          ..write('scope: $scope, ')
          ..write('mode: $mode, ')
          ..write('projectRootId: $projectRootId, ')
          ..write('projectRootPath: $projectRootPath, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActivationAgentsTable extends ActivationAgents
    with TableInfo<$ActivationAgentsTable, ActivationAgent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActivationAgentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _activationLocationIdMeta =
      const VerificationMeta('activationLocationId');
  @override
  late final GeneratedColumn<String> activationLocationId =
      GeneratedColumn<String>(
        'activation_location_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES activation_locations (id) ON DELETE CASCADE',
        ),
      );
  static const VerificationMeta _agentIdMeta = const VerificationMeta(
    'agentId',
  );
  @override
  late final GeneratedColumn<String> agentId = GeneratedColumn<String>(
    'agent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [activationLocationId, agentId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'activation_agents';
  @override
  VerificationContext validateIntegrity(
    Insertable<ActivationAgent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('activation_location_id')) {
      context.handle(
        _activationLocationIdMeta,
        activationLocationId.isAcceptableOrUnknown(
          data['activation_location_id']!,
          _activationLocationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_activationLocationIdMeta);
    }
    if (data.containsKey('agent_id')) {
      context.handle(
        _agentIdMeta,
        agentId.isAcceptableOrUnknown(data['agent_id']!, _agentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_agentIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {activationLocationId, agentId};
  @override
  ActivationAgent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActivationAgent(
      activationLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}activation_location_id'],
      )!,
      agentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}agent_id'],
      )!,
    );
  }

  @override
  $ActivationAgentsTable createAlias(String alias) {
    return $ActivationAgentsTable(attachedDatabase, alias);
  }
}

class ActivationAgent extends DataClass implements Insertable<ActivationAgent> {
  final String activationLocationId;
  final String agentId;
  const ActivationAgent({
    required this.activationLocationId,
    required this.agentId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['activation_location_id'] = Variable<String>(activationLocationId);
    map['agent_id'] = Variable<String>(agentId);
    return map;
  }

  ActivationAgentsCompanion toCompanion(bool nullToAbsent) {
    return ActivationAgentsCompanion(
      activationLocationId: Value(activationLocationId),
      agentId: Value(agentId),
    );
  }

  factory ActivationAgent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActivationAgent(
      activationLocationId: serializer.fromJson<String>(
        json['activationLocationId'],
      ),
      agentId: serializer.fromJson<String>(json['agentId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'activationLocationId': serializer.toJson<String>(activationLocationId),
      'agentId': serializer.toJson<String>(agentId),
    };
  }

  ActivationAgent copyWith({String? activationLocationId, String? agentId}) =>
      ActivationAgent(
        activationLocationId: activationLocationId ?? this.activationLocationId,
        agentId: agentId ?? this.agentId,
      );
  ActivationAgent copyWithCompanion(ActivationAgentsCompanion data) {
    return ActivationAgent(
      activationLocationId: data.activationLocationId.present
          ? data.activationLocationId.value
          : this.activationLocationId,
      agentId: data.agentId.present ? data.agentId.value : this.agentId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActivationAgent(')
          ..write('activationLocationId: $activationLocationId, ')
          ..write('agentId: $agentId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(activationLocationId, agentId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActivationAgent &&
          other.activationLocationId == this.activationLocationId &&
          other.agentId == this.agentId);
}

class ActivationAgentsCompanion extends UpdateCompanion<ActivationAgent> {
  final Value<String> activationLocationId;
  final Value<String> agentId;
  final Value<int> rowid;
  const ActivationAgentsCompanion({
    this.activationLocationId = const Value.absent(),
    this.agentId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActivationAgentsCompanion.insert({
    required String activationLocationId,
    required String agentId,
    this.rowid = const Value.absent(),
  }) : activationLocationId = Value(activationLocationId),
       agentId = Value(agentId);
  static Insertable<ActivationAgent> custom({
    Expression<String>? activationLocationId,
    Expression<String>? agentId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (activationLocationId != null)
        'activation_location_id': activationLocationId,
      if (agentId != null) 'agent_id': agentId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActivationAgentsCompanion copyWith({
    Value<String>? activationLocationId,
    Value<String>? agentId,
    Value<int>? rowid,
  }) {
    return ActivationAgentsCompanion(
      activationLocationId: activationLocationId ?? this.activationLocationId,
      agentId: agentId ?? this.agentId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (activationLocationId.present) {
      map['activation_location_id'] = Variable<String>(
        activationLocationId.value,
      );
    }
    if (agentId.present) {
      map['agent_id'] = Variable<String>(agentId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActivationAgentsCompanion(')
          ..write('activationLocationId: $activationLocationId, ')
          ..write('agentId: $agentId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillUserDataTable extends SkillUserData
    with TableInfo<$SkillUserDataTable, SkillUserDataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillUserDataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoriteChangedAtMicrosMeta =
      const VerificationMeta('favoriteChangedAtMicros');
  @override
  late final GeneratedColumn<int> favoriteChangedAtMicros =
      GeneratedColumn<int>(
        'favorite_changed_at_micros',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteUpdatedAtMicrosMeta =
      const VerificationMeta('noteUpdatedAtMicros');
  @override
  late final GeneratedColumn<int> noteUpdatedAtMicros = GeneratedColumn<int>(
    'note_updated_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    favorite,
    favoriteChangedAtMicros,
    note,
    noteUpdatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_user_data';
  @override
  VerificationContext validateIntegrity(
    Insertable<SkillUserDataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('favorite_changed_at_micros')) {
      context.handle(
        _favoriteChangedAtMicrosMeta,
        favoriteChangedAtMicros.isAcceptableOrUnknown(
          data['favorite_changed_at_micros']!,
          _favoriteChangedAtMicrosMeta,
        ),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('note_updated_at_micros')) {
      context.handle(
        _noteUpdatedAtMicrosMeta,
        noteUpdatedAtMicros.isAcceptableOrUnknown(
          data['note_updated_at_micros']!,
          _noteUpdatedAtMicrosMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId};
  @override
  SkillUserDataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillUserDataData(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      favoriteChangedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorite_changed_at_micros'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      noteUpdatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}note_updated_at_micros'],
      ),
    );
  }

  @override
  $SkillUserDataTable createAlias(String alias) {
    return $SkillUserDataTable(attachedDatabase, alias);
  }
}

class SkillUserDataData extends DataClass
    implements Insertable<SkillUserDataData> {
  final String managedSkillId;
  final bool favorite;
  final int? favoriteChangedAtMicros;
  final String? note;
  final int? noteUpdatedAtMicros;
  const SkillUserDataData({
    required this.managedSkillId,
    required this.favorite,
    this.favoriteChangedAtMicros,
    this.note,
    this.noteUpdatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || favoriteChangedAtMicros != null) {
      map['favorite_changed_at_micros'] = Variable<int>(
        favoriteChangedAtMicros,
      );
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || noteUpdatedAtMicros != null) {
      map['note_updated_at_micros'] = Variable<int>(noteUpdatedAtMicros);
    }
    return map;
  }

  SkillUserDataCompanion toCompanion(bool nullToAbsent) {
    return SkillUserDataCompanion(
      managedSkillId: Value(managedSkillId),
      favorite: Value(favorite),
      favoriteChangedAtMicros: favoriteChangedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(favoriteChangedAtMicros),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      noteUpdatedAtMicros: noteUpdatedAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(noteUpdatedAtMicros),
    );
  }

  factory SkillUserDataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillUserDataData(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      favoriteChangedAtMicros: serializer.fromJson<int?>(
        json['favoriteChangedAtMicros'],
      ),
      note: serializer.fromJson<String?>(json['note']),
      noteUpdatedAtMicros: serializer.fromJson<int?>(
        json['noteUpdatedAtMicros'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'favorite': serializer.toJson<bool>(favorite),
      'favoriteChangedAtMicros': serializer.toJson<int?>(
        favoriteChangedAtMicros,
      ),
      'note': serializer.toJson<String?>(note),
      'noteUpdatedAtMicros': serializer.toJson<int?>(noteUpdatedAtMicros),
    };
  }

  SkillUserDataData copyWith({
    String? managedSkillId,
    bool? favorite,
    Value<int?> favoriteChangedAtMicros = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<int?> noteUpdatedAtMicros = const Value.absent(),
  }) => SkillUserDataData(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    favorite: favorite ?? this.favorite,
    favoriteChangedAtMicros: favoriteChangedAtMicros.present
        ? favoriteChangedAtMicros.value
        : this.favoriteChangedAtMicros,
    note: note.present ? note.value : this.note,
    noteUpdatedAtMicros: noteUpdatedAtMicros.present
        ? noteUpdatedAtMicros.value
        : this.noteUpdatedAtMicros,
  );
  SkillUserDataData copyWithCompanion(SkillUserDataCompanion data) {
    return SkillUserDataData(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      favoriteChangedAtMicros: data.favoriteChangedAtMicros.present
          ? data.favoriteChangedAtMicros.value
          : this.favoriteChangedAtMicros,
      note: data.note.present ? data.note.value : this.note,
      noteUpdatedAtMicros: data.noteUpdatedAtMicros.present
          ? data.noteUpdatedAtMicros.value
          : this.noteUpdatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillUserDataData(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('favorite: $favorite, ')
          ..write('favoriteChangedAtMicros: $favoriteChangedAtMicros, ')
          ..write('note: $note, ')
          ..write('noteUpdatedAtMicros: $noteUpdatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    favorite,
    favoriteChangedAtMicros,
    note,
    noteUpdatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillUserDataData &&
          other.managedSkillId == this.managedSkillId &&
          other.favorite == this.favorite &&
          other.favoriteChangedAtMicros == this.favoriteChangedAtMicros &&
          other.note == this.note &&
          other.noteUpdatedAtMicros == this.noteUpdatedAtMicros);
}

class SkillUserDataCompanion extends UpdateCompanion<SkillUserDataData> {
  final Value<String> managedSkillId;
  final Value<bool> favorite;
  final Value<int?> favoriteChangedAtMicros;
  final Value<String?> note;
  final Value<int?> noteUpdatedAtMicros;
  final Value<int> rowid;
  const SkillUserDataCompanion({
    this.managedSkillId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.favoriteChangedAtMicros = const Value.absent(),
    this.note = const Value.absent(),
    this.noteUpdatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillUserDataCompanion.insert({
    required String managedSkillId,
    this.favorite = const Value.absent(),
    this.favoriteChangedAtMicros = const Value.absent(),
    this.note = const Value.absent(),
    this.noteUpdatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId);
  static Insertable<SkillUserDataData> custom({
    Expression<String>? managedSkillId,
    Expression<bool>? favorite,
    Expression<int>? favoriteChangedAtMicros,
    Expression<String>? note,
    Expression<int>? noteUpdatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (favorite != null) 'favorite': favorite,
      if (favoriteChangedAtMicros != null)
        'favorite_changed_at_micros': favoriteChangedAtMicros,
      if (note != null) 'note': note,
      if (noteUpdatedAtMicros != null)
        'note_updated_at_micros': noteUpdatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillUserDataCompanion copyWith({
    Value<String>? managedSkillId,
    Value<bool>? favorite,
    Value<int?>? favoriteChangedAtMicros,
    Value<String?>? note,
    Value<int?>? noteUpdatedAtMicros,
    Value<int>? rowid,
  }) {
    return SkillUserDataCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      favorite: favorite ?? this.favorite,
      favoriteChangedAtMicros:
          favoriteChangedAtMicros ?? this.favoriteChangedAtMicros,
      note: note ?? this.note,
      noteUpdatedAtMicros: noteUpdatedAtMicros ?? this.noteUpdatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (favoriteChangedAtMicros.present) {
      map['favorite_changed_at_micros'] = Variable<int>(
        favoriteChangedAtMicros.value,
      );
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (noteUpdatedAtMicros.present) {
      map['note_updated_at_micros'] = Variable<int>(noteUpdatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillUserDataCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('favorite: $favorite, ')
          ..write('favoriteChangedAtMicros: $favoriteChangedAtMicros, ')
          ..write('note: $note, ')
          ..write('noteUpdatedAtMicros: $noteUpdatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillUpdateCheckRecordsTable extends SkillUpdateCheckRecords
    with TableInfo<$SkillUpdateCheckRecordsTable, SkillUpdateCheckRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillUpdateCheckRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _basisFingerprintMeta = const VerificationMeta(
    'basisFingerprint',
  );
  @override
  late final GeneratedColumn<String> basisFingerprint = GeneratedColumn<String>(
    'basis_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentContentHashMeta =
      const VerificationMeta('currentContentHash');
  @override
  late final GeneratedColumn<String> currentContentHash =
      GeneratedColumn<String>(
        'current_content_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _availableContentHashMeta =
      const VerificationMeta('availableContentHash');
  @override
  late final GeneratedColumn<String> availableContentHash =
      GeneratedColumn<String>(
        'available_content_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _resolvedSourceRevisionMeta =
      const VerificationMeta('resolvedSourceRevision');
  @override
  late final GeneratedColumn<String> resolvedSourceRevision =
      GeneratedColumn<String>(
        'resolved_source_revision',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _checkedAtMicrosMeta = const VerificationMeta(
    'checkedAtMicros',
  );
  @override
  late final GeneratedColumn<int> checkedAtMicros = GeneratedColumn<int>(
    'checked_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    basisFingerprint,
    status,
    currentContentHash,
    availableContentHash,
    resolvedSourceRevision,
    checkedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_update_check_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<SkillUpdateCheckRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('basis_fingerprint')) {
      context.handle(
        _basisFingerprintMeta,
        basisFingerprint.isAcceptableOrUnknown(
          data['basis_fingerprint']!,
          _basisFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_basisFingerprintMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('current_content_hash')) {
      context.handle(
        _currentContentHashMeta,
        currentContentHash.isAcceptableOrUnknown(
          data['current_content_hash']!,
          _currentContentHashMeta,
        ),
      );
    }
    if (data.containsKey('available_content_hash')) {
      context.handle(
        _availableContentHashMeta,
        availableContentHash.isAcceptableOrUnknown(
          data['available_content_hash']!,
          _availableContentHashMeta,
        ),
      );
    }
    if (data.containsKey('resolved_source_revision')) {
      context.handle(
        _resolvedSourceRevisionMeta,
        resolvedSourceRevision.isAcceptableOrUnknown(
          data['resolved_source_revision']!,
          _resolvedSourceRevisionMeta,
        ),
      );
    }
    if (data.containsKey('checked_at_micros')) {
      context.handle(
        _checkedAtMicrosMeta,
        checkedAtMicros.isAcceptableOrUnknown(
          data['checked_at_micros']!,
          _checkedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_checkedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId};
  @override
  SkillUpdateCheckRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillUpdateCheckRecord(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      basisFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}basis_fingerprint'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      currentContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_content_hash'],
      ),
      availableContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}available_content_hash'],
      ),
      resolvedSourceRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolved_source_revision'],
      ),
      checkedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}checked_at_micros'],
      )!,
    );
  }

  @override
  $SkillUpdateCheckRecordsTable createAlias(String alias) {
    return $SkillUpdateCheckRecordsTable(attachedDatabase, alias);
  }
}

class SkillUpdateCheckRecord extends DataClass
    implements Insertable<SkillUpdateCheckRecord> {
  final String managedSkillId;
  final String basisFingerprint;
  final String status;
  final String? currentContentHash;
  final String? availableContentHash;
  final String? resolvedSourceRevision;
  final int checkedAtMicros;
  const SkillUpdateCheckRecord({
    required this.managedSkillId,
    required this.basisFingerprint,
    required this.status,
    this.currentContentHash,
    this.availableContentHash,
    this.resolvedSourceRevision,
    required this.checkedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['basis_fingerprint'] = Variable<String>(basisFingerprint);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || currentContentHash != null) {
      map['current_content_hash'] = Variable<String>(currentContentHash);
    }
    if (!nullToAbsent || availableContentHash != null) {
      map['available_content_hash'] = Variable<String>(availableContentHash);
    }
    if (!nullToAbsent || resolvedSourceRevision != null) {
      map['resolved_source_revision'] = Variable<String>(
        resolvedSourceRevision,
      );
    }
    map['checked_at_micros'] = Variable<int>(checkedAtMicros);
    return map;
  }

  SkillUpdateCheckRecordsCompanion toCompanion(bool nullToAbsent) {
    return SkillUpdateCheckRecordsCompanion(
      managedSkillId: Value(managedSkillId),
      basisFingerprint: Value(basisFingerprint),
      status: Value(status),
      currentContentHash: currentContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(currentContentHash),
      availableContentHash: availableContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(availableContentHash),
      resolvedSourceRevision: resolvedSourceRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedSourceRevision),
      checkedAtMicros: Value(checkedAtMicros),
    );
  }

  factory SkillUpdateCheckRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillUpdateCheckRecord(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      basisFingerprint: serializer.fromJson<String>(json['basisFingerprint']),
      status: serializer.fromJson<String>(json['status']),
      currentContentHash: serializer.fromJson<String?>(
        json['currentContentHash'],
      ),
      availableContentHash: serializer.fromJson<String?>(
        json['availableContentHash'],
      ),
      resolvedSourceRevision: serializer.fromJson<String?>(
        json['resolvedSourceRevision'],
      ),
      checkedAtMicros: serializer.fromJson<int>(json['checkedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'basisFingerprint': serializer.toJson<String>(basisFingerprint),
      'status': serializer.toJson<String>(status),
      'currentContentHash': serializer.toJson<String?>(currentContentHash),
      'availableContentHash': serializer.toJson<String?>(availableContentHash),
      'resolvedSourceRevision': serializer.toJson<String?>(
        resolvedSourceRevision,
      ),
      'checkedAtMicros': serializer.toJson<int>(checkedAtMicros),
    };
  }

  SkillUpdateCheckRecord copyWith({
    String? managedSkillId,
    String? basisFingerprint,
    String? status,
    Value<String?> currentContentHash = const Value.absent(),
    Value<String?> availableContentHash = const Value.absent(),
    Value<String?> resolvedSourceRevision = const Value.absent(),
    int? checkedAtMicros,
  }) => SkillUpdateCheckRecord(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    basisFingerprint: basisFingerprint ?? this.basisFingerprint,
    status: status ?? this.status,
    currentContentHash: currentContentHash.present
        ? currentContentHash.value
        : this.currentContentHash,
    availableContentHash: availableContentHash.present
        ? availableContentHash.value
        : this.availableContentHash,
    resolvedSourceRevision: resolvedSourceRevision.present
        ? resolvedSourceRevision.value
        : this.resolvedSourceRevision,
    checkedAtMicros: checkedAtMicros ?? this.checkedAtMicros,
  );
  SkillUpdateCheckRecord copyWithCompanion(
    SkillUpdateCheckRecordsCompanion data,
  ) {
    return SkillUpdateCheckRecord(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      basisFingerprint: data.basisFingerprint.present
          ? data.basisFingerprint.value
          : this.basisFingerprint,
      status: data.status.present ? data.status.value : this.status,
      currentContentHash: data.currentContentHash.present
          ? data.currentContentHash.value
          : this.currentContentHash,
      availableContentHash: data.availableContentHash.present
          ? data.availableContentHash.value
          : this.availableContentHash,
      resolvedSourceRevision: data.resolvedSourceRevision.present
          ? data.resolvedSourceRevision.value
          : this.resolvedSourceRevision,
      checkedAtMicros: data.checkedAtMicros.present
          ? data.checkedAtMicros.value
          : this.checkedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillUpdateCheckRecord(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('basisFingerprint: $basisFingerprint, ')
          ..write('status: $status, ')
          ..write('currentContentHash: $currentContentHash, ')
          ..write('availableContentHash: $availableContentHash, ')
          ..write('resolvedSourceRevision: $resolvedSourceRevision, ')
          ..write('checkedAtMicros: $checkedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    managedSkillId,
    basisFingerprint,
    status,
    currentContentHash,
    availableContentHash,
    resolvedSourceRevision,
    checkedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillUpdateCheckRecord &&
          other.managedSkillId == this.managedSkillId &&
          other.basisFingerprint == this.basisFingerprint &&
          other.status == this.status &&
          other.currentContentHash == this.currentContentHash &&
          other.availableContentHash == this.availableContentHash &&
          other.resolvedSourceRevision == this.resolvedSourceRevision &&
          other.checkedAtMicros == this.checkedAtMicros);
}

class SkillUpdateCheckRecordsCompanion
    extends UpdateCompanion<SkillUpdateCheckRecord> {
  final Value<String> managedSkillId;
  final Value<String> basisFingerprint;
  final Value<String> status;
  final Value<String?> currentContentHash;
  final Value<String?> availableContentHash;
  final Value<String?> resolvedSourceRevision;
  final Value<int> checkedAtMicros;
  final Value<int> rowid;
  const SkillUpdateCheckRecordsCompanion({
    this.managedSkillId = const Value.absent(),
    this.basisFingerprint = const Value.absent(),
    this.status = const Value.absent(),
    this.currentContentHash = const Value.absent(),
    this.availableContentHash = const Value.absent(),
    this.resolvedSourceRevision = const Value.absent(),
    this.checkedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillUpdateCheckRecordsCompanion.insert({
    required String managedSkillId,
    required String basisFingerprint,
    required String status,
    this.currentContentHash = const Value.absent(),
    this.availableContentHash = const Value.absent(),
    this.resolvedSourceRevision = const Value.absent(),
    required int checkedAtMicros,
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       basisFingerprint = Value(basisFingerprint),
       status = Value(status),
       checkedAtMicros = Value(checkedAtMicros);
  static Insertable<SkillUpdateCheckRecord> custom({
    Expression<String>? managedSkillId,
    Expression<String>? basisFingerprint,
    Expression<String>? status,
    Expression<String>? currentContentHash,
    Expression<String>? availableContentHash,
    Expression<String>? resolvedSourceRevision,
    Expression<int>? checkedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (basisFingerprint != null) 'basis_fingerprint': basisFingerprint,
      if (status != null) 'status': status,
      if (currentContentHash != null)
        'current_content_hash': currentContentHash,
      if (availableContentHash != null)
        'available_content_hash': availableContentHash,
      if (resolvedSourceRevision != null)
        'resolved_source_revision': resolvedSourceRevision,
      if (checkedAtMicros != null) 'checked_at_micros': checkedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillUpdateCheckRecordsCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? basisFingerprint,
    Value<String>? status,
    Value<String?>? currentContentHash,
    Value<String?>? availableContentHash,
    Value<String?>? resolvedSourceRevision,
    Value<int>? checkedAtMicros,
    Value<int>? rowid,
  }) {
    return SkillUpdateCheckRecordsCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      basisFingerprint: basisFingerprint ?? this.basisFingerprint,
      status: status ?? this.status,
      currentContentHash: currentContentHash ?? this.currentContentHash,
      availableContentHash: availableContentHash ?? this.availableContentHash,
      resolvedSourceRevision:
          resolvedSourceRevision ?? this.resolvedSourceRevision,
      checkedAtMicros: checkedAtMicros ?? this.checkedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (basisFingerprint.present) {
      map['basis_fingerprint'] = Variable<String>(basisFingerprint.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (currentContentHash.present) {
      map['current_content_hash'] = Variable<String>(currentContentHash.value);
    }
    if (availableContentHash.present) {
      map['available_content_hash'] = Variable<String>(
        availableContentHash.value,
      );
    }
    if (resolvedSourceRevision.present) {
      map['resolved_source_revision'] = Variable<String>(
        resolvedSourceRevision.value,
      );
    }
    if (checkedAtMicros.present) {
      map['checked_at_micros'] = Variable<int>(checkedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillUpdateCheckRecordsCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('basisFingerprint: $basisFingerprint, ')
          ..write('status: $status, ')
          ..write('currentContentHash: $currentContentHash, ')
          ..write('availableContentHash: $availableContentHash, ')
          ..write('resolvedSourceRevision: $resolvedSourceRevision, ')
          ..write('checkedAtMicros: $checkedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillUpdateCheckMetadataTable extends SkillUpdateCheckMetadata
    with
        TableInfo<
          $SkillUpdateCheckMetadataTable,
          SkillUpdateCheckMetadataData
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillUpdateCheckMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  @override
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastFullSweepAtMicrosMeta =
      const VerificationMeta('lastFullSweepAtMicros');
  @override
  late final GeneratedColumn<int> lastFullSweepAtMicros = GeneratedColumn<int>(
    'last_full_sweep_at_micros',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [singleton, lastFullSweepAtMicros];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_update_check_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SkillUpdateCheckMetadataData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('last_full_sweep_at_micros')) {
      context.handle(
        _lastFullSweepAtMicrosMeta,
        lastFullSweepAtMicros.isAcceptableOrUnknown(
          data['last_full_sweep_at_micros']!,
          _lastFullSweepAtMicrosMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  SkillUpdateCheckMetadataData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillUpdateCheckMetadataData(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      lastFullSweepAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_full_sweep_at_micros'],
      ),
    );
  }

  @override
  $SkillUpdateCheckMetadataTable createAlias(String alias) {
    return $SkillUpdateCheckMetadataTable(attachedDatabase, alias);
  }
}

class SkillUpdateCheckMetadataData extends DataClass
    implements Insertable<SkillUpdateCheckMetadataData> {
  final int singleton;
  final int? lastFullSweepAtMicros;
  const SkillUpdateCheckMetadataData({
    required this.singleton,
    this.lastFullSweepAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    if (!nullToAbsent || lastFullSweepAtMicros != null) {
      map['last_full_sweep_at_micros'] = Variable<int>(lastFullSweepAtMicros);
    }
    return map;
  }

  SkillUpdateCheckMetadataCompanion toCompanion(bool nullToAbsent) {
    return SkillUpdateCheckMetadataCompanion(
      singleton: Value(singleton),
      lastFullSweepAtMicros: lastFullSweepAtMicros == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFullSweepAtMicros),
    );
  }

  factory SkillUpdateCheckMetadataData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillUpdateCheckMetadataData(
      singleton: serializer.fromJson<int>(json['singleton']),
      lastFullSweepAtMicros: serializer.fromJson<int?>(
        json['lastFullSweepAtMicros'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'lastFullSweepAtMicros': serializer.toJson<int?>(lastFullSweepAtMicros),
    };
  }

  SkillUpdateCheckMetadataData copyWith({
    int? singleton,
    Value<int?> lastFullSweepAtMicros = const Value.absent(),
  }) => SkillUpdateCheckMetadataData(
    singleton: singleton ?? this.singleton,
    lastFullSweepAtMicros: lastFullSweepAtMicros.present
        ? lastFullSweepAtMicros.value
        : this.lastFullSweepAtMicros,
  );
  SkillUpdateCheckMetadataData copyWithCompanion(
    SkillUpdateCheckMetadataCompanion data,
  ) {
    return SkillUpdateCheckMetadataData(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      lastFullSweepAtMicros: data.lastFullSweepAtMicros.present
          ? data.lastFullSweepAtMicros.value
          : this.lastFullSweepAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillUpdateCheckMetadataData(')
          ..write('singleton: $singleton, ')
          ..write('lastFullSweepAtMicros: $lastFullSweepAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, lastFullSweepAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillUpdateCheckMetadataData &&
          other.singleton == this.singleton &&
          other.lastFullSweepAtMicros == this.lastFullSweepAtMicros);
}

class SkillUpdateCheckMetadataCompanion
    extends UpdateCompanion<SkillUpdateCheckMetadataData> {
  final Value<int> singleton;
  final Value<int?> lastFullSweepAtMicros;
  const SkillUpdateCheckMetadataCompanion({
    this.singleton = const Value.absent(),
    this.lastFullSweepAtMicros = const Value.absent(),
  });
  SkillUpdateCheckMetadataCompanion.insert({
    this.singleton = const Value.absent(),
    this.lastFullSweepAtMicros = const Value.absent(),
  });
  static Insertable<SkillUpdateCheckMetadataData> custom({
    Expression<int>? singleton,
    Expression<int>? lastFullSweepAtMicros,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (lastFullSweepAtMicros != null)
        'last_full_sweep_at_micros': lastFullSweepAtMicros,
    });
  }

  SkillUpdateCheckMetadataCompanion copyWith({
    Value<int>? singleton,
    Value<int?>? lastFullSweepAtMicros,
  }) {
    return SkillUpdateCheckMetadataCompanion(
      singleton: singleton ?? this.singleton,
      lastFullSweepAtMicros:
          lastFullSweepAtMicros ?? this.lastFullSweepAtMicros,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (lastFullSweepAtMicros.present) {
      map['last_full_sweep_at_micros'] = Variable<int>(
        lastFullSweepAtMicros.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillUpdateCheckMetadataCompanion(')
          ..write('singleton: $singleton, ')
          ..write('lastFullSweepAtMicros: $lastFullSweepAtMicros')
          ..write(')'))
        .toString();
  }
}

class $PersonalTagsTable extends PersonalTags
    with TableInfo<$PersonalTagsTable, PersonalTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PersonalTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _normalizedKeyMeta = const VerificationMeta(
    'normalizedKey',
  );
  @override
  late final GeneratedColumn<String> normalizedKey = GeneratedColumn<String>(
    'normalized_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    normalizedKey,
    displayName,
    color,
    createdAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'personal_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<PersonalTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('normalized_key')) {
      context.handle(
        _normalizedKeyMeta,
        normalizedKey.isAcceptableOrUnknown(
          data['normalized_key']!,
          _normalizedKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_normalizedKeyMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PersonalTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PersonalTag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      normalizedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}normalized_key'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $PersonalTagsTable createAlias(String alias) {
    return $PersonalTagsTable(attachedDatabase, alias);
  }
}

class PersonalTag extends DataClass implements Insertable<PersonalTag> {
  final String id;
  final String normalizedKey;
  final String displayName;
  final String? color;
  final int createdAtMicros;
  final int updatedAtMicros;
  const PersonalTag({
    required this.id,
    required this.normalizedKey,
    required this.displayName,
    this.color,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['normalized_key'] = Variable<String>(normalizedKey);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  PersonalTagsCompanion toCompanion(bool nullToAbsent) {
    return PersonalTagsCompanion(
      id: Value(id),
      normalizedKey: Value(normalizedKey),
      displayName: Value(displayName),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      createdAtMicros: Value(createdAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory PersonalTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PersonalTag(
      id: serializer.fromJson<String>(json['id']),
      normalizedKey: serializer.fromJson<String>(json['normalizedKey']),
      displayName: serializer.fromJson<String>(json['displayName']),
      color: serializer.fromJson<String?>(json['color']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'normalizedKey': serializer.toJson<String>(normalizedKey),
      'displayName': serializer.toJson<String>(displayName),
      'color': serializer.toJson<String?>(color),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  PersonalTag copyWith({
    String? id,
    String? normalizedKey,
    String? displayName,
    Value<String?> color = const Value.absent(),
    int? createdAtMicros,
    int? updatedAtMicros,
  }) => PersonalTag(
    id: id ?? this.id,
    normalizedKey: normalizedKey ?? this.normalizedKey,
    displayName: displayName ?? this.displayName,
    color: color.present ? color.value : this.color,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  PersonalTag copyWithCompanion(PersonalTagsCompanion data) {
    return PersonalTag(
      id: data.id.present ? data.id.value : this.id,
      normalizedKey: data.normalizedKey.present
          ? data.normalizedKey.value
          : this.normalizedKey,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      color: data.color.present ? data.color.value : this.color,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PersonalTag(')
          ..write('id: $id, ')
          ..write('normalizedKey: $normalizedKey, ')
          ..write('displayName: $displayName, ')
          ..write('color: $color, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    normalizedKey,
    displayName,
    color,
    createdAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PersonalTag &&
          other.id == this.id &&
          other.normalizedKey == this.normalizedKey &&
          other.displayName == this.displayName &&
          other.color == this.color &&
          other.createdAtMicros == this.createdAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class PersonalTagsCompanion extends UpdateCompanion<PersonalTag> {
  final Value<String> id;
  final Value<String> normalizedKey;
  final Value<String> displayName;
  final Value<String?> color;
  final Value<int> createdAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const PersonalTagsCompanion({
    this.id = const Value.absent(),
    this.normalizedKey = const Value.absent(),
    this.displayName = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PersonalTagsCompanion.insert({
    required String id,
    required String normalizedKey,
    required String displayName,
    this.color = const Value.absent(),
    required int createdAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       normalizedKey = Value(normalizedKey),
       displayName = Value(displayName),
       createdAtMicros = Value(createdAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<PersonalTag> custom({
    Expression<String>? id,
    Expression<String>? normalizedKey,
    Expression<String>? displayName,
    Expression<String>? color,
    Expression<int>? createdAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (normalizedKey != null) 'normalized_key': normalizedKey,
      if (displayName != null) 'display_name': displayName,
      if (color != null) 'color': color,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PersonalTagsCompanion copyWith({
    Value<String>? id,
    Value<String>? normalizedKey,
    Value<String>? displayName,
    Value<String?>? color,
    Value<int>? createdAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return PersonalTagsCompanion(
      id: id ?? this.id,
      normalizedKey: normalizedKey ?? this.normalizedKey,
      displayName: displayName ?? this.displayName,
      color: color ?? this.color,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (normalizedKey.present) {
      map['normalized_key'] = Variable<String>(normalizedKey.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PersonalTagsCompanion(')
          ..write('id: $id, ')
          ..write('normalizedKey: $normalizedKey, ')
          ..write('displayName: $displayName, ')
          ..write('color: $color, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SkillTagAssignmentsTable extends SkillTagAssignments
    with TableInfo<$SkillTagAssignmentsTable, SkillTagAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SkillTagAssignmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _personalTagIdMeta = const VerificationMeta(
    'personalTagId',
  );
  @override
  late final GeneratedColumn<String> personalTagId = GeneratedColumn<String>(
    'personal_tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES personal_tags (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _createdAtMicrosMeta = const VerificationMeta(
    'createdAtMicros',
  );
  @override
  late final GeneratedColumn<int> createdAtMicros = GeneratedColumn<int>(
    'created_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    managedSkillId,
    personalTagId,
    createdAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'skill_tag_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<SkillTagAssignment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('personal_tag_id')) {
      context.handle(
        _personalTagIdMeta,
        personalTagId.isAcceptableOrUnknown(
          data['personal_tag_id']!,
          _personalTagIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_personalTagIdMeta);
    }
    if (data.containsKey('created_at_micros')) {
      context.handle(
        _createdAtMicrosMeta,
        createdAtMicros.isAcceptableOrUnknown(
          data['created_at_micros']!,
          _createdAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {managedSkillId, personalTagId};
  @override
  SkillTagAssignment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SkillTagAssignment(
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      personalTagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}personal_tag_id'],
      )!,
      createdAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_micros'],
      )!,
    );
  }

  @override
  $SkillTagAssignmentsTable createAlias(String alias) {
    return $SkillTagAssignmentsTable(attachedDatabase, alias);
  }
}

class SkillTagAssignment extends DataClass
    implements Insertable<SkillTagAssignment> {
  final String managedSkillId;
  final String personalTagId;
  final int createdAtMicros;
  const SkillTagAssignment({
    required this.managedSkillId,
    required this.personalTagId,
    required this.createdAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    map['personal_tag_id'] = Variable<String>(personalTagId);
    map['created_at_micros'] = Variable<int>(createdAtMicros);
    return map;
  }

  SkillTagAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return SkillTagAssignmentsCompanion(
      managedSkillId: Value(managedSkillId),
      personalTagId: Value(personalTagId),
      createdAtMicros: Value(createdAtMicros),
    );
  }

  factory SkillTagAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SkillTagAssignment(
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      personalTagId: serializer.fromJson<String>(json['personalTagId']),
      createdAtMicros: serializer.fromJson<int>(json['createdAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'personalTagId': serializer.toJson<String>(personalTagId),
      'createdAtMicros': serializer.toJson<int>(createdAtMicros),
    };
  }

  SkillTagAssignment copyWith({
    String? managedSkillId,
    String? personalTagId,
    int? createdAtMicros,
  }) => SkillTagAssignment(
    managedSkillId: managedSkillId ?? this.managedSkillId,
    personalTagId: personalTagId ?? this.personalTagId,
    createdAtMicros: createdAtMicros ?? this.createdAtMicros,
  );
  SkillTagAssignment copyWithCompanion(SkillTagAssignmentsCompanion data) {
    return SkillTagAssignment(
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      personalTagId: data.personalTagId.present
          ? data.personalTagId.value
          : this.personalTagId,
      createdAtMicros: data.createdAtMicros.present
          ? data.createdAtMicros.value
          : this.createdAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SkillTagAssignment(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('personalTagId: $personalTagId, ')
          ..write('createdAtMicros: $createdAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(managedSkillId, personalTagId, createdAtMicros);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SkillTagAssignment &&
          other.managedSkillId == this.managedSkillId &&
          other.personalTagId == this.personalTagId &&
          other.createdAtMicros == this.createdAtMicros);
}

class SkillTagAssignmentsCompanion extends UpdateCompanion<SkillTagAssignment> {
  final Value<String> managedSkillId;
  final Value<String> personalTagId;
  final Value<int> createdAtMicros;
  final Value<int> rowid;
  const SkillTagAssignmentsCompanion({
    this.managedSkillId = const Value.absent(),
    this.personalTagId = const Value.absent(),
    this.createdAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SkillTagAssignmentsCompanion.insert({
    required String managedSkillId,
    required String personalTagId,
    required int createdAtMicros,
    this.rowid = const Value.absent(),
  }) : managedSkillId = Value(managedSkillId),
       personalTagId = Value(personalTagId),
       createdAtMicros = Value(createdAtMicros);
  static Insertable<SkillTagAssignment> custom({
    Expression<String>? managedSkillId,
    Expression<String>? personalTagId,
    Expression<int>? createdAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (personalTagId != null) 'personal_tag_id': personalTagId,
      if (createdAtMicros != null) 'created_at_micros': createdAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SkillTagAssignmentsCompanion copyWith({
    Value<String>? managedSkillId,
    Value<String>? personalTagId,
    Value<int>? createdAtMicros,
    Value<int>? rowid,
  }) {
    return SkillTagAssignmentsCompanion(
      managedSkillId: managedSkillId ?? this.managedSkillId,
      personalTagId: personalTagId ?? this.personalTagId,
      createdAtMicros: createdAtMicros ?? this.createdAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (personalTagId.present) {
      map['personal_tag_id'] = Variable<String>(personalTagId.value);
    }
    if (createdAtMicros.present) {
      map['created_at_micros'] = Variable<int>(createdAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SkillTagAssignmentsCompanion(')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('personalTagId: $personalTagId, ')
          ..write('createdAtMicros: $createdAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperationJournalsTable extends OperationJournals
    with TableInfo<$OperationJournalsTable, OperationJournal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperationJournalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planSchemaVersionMeta = const VerificationMeta(
    'planSchemaVersion',
  );
  @override
  late final GeneratedColumn<int> planSchemaVersion = GeneratedColumn<int>(
    'plan_schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planJsonMeta = const VerificationMeta(
    'planJson',
  );
  @override
  late final GeneratedColumn<String> planJson = GeneratedColumn<String>(
    'plan_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationGenerationMeta =
      const VerificationMeta('operationGeneration');
  @override
  late final GeneratedColumn<int> operationGeneration = GeneratedColumn<int>(
    'operation_generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _committedRepositoryRevisionMeta =
      const VerificationMeta('committedRepositoryRevision');
  @override
  late final GeneratedColumn<int> committedRepositoryRevision =
      GeneratedColumn<int>(
        'committed_repository_revision',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _startedAtMicrosMeta = const VerificationMeta(
    'startedAtMicros',
  );
  @override
  late final GeneratedColumn<int> startedAtMicros = GeneratedColumn<int>(
    'started_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMicrosMeta = const VerificationMeta(
    'updatedAtMicros',
  );
  @override
  late final GeneratedColumn<int> updatedAtMicros = GeneratedColumn<int>(
    'updated_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    kind,
    phase,
    planSchemaVersion,
    planJson,
    operationGeneration,
    committedRepositoryRevision,
    startedAtMicros,
    updatedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operation_journals';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationJournal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('plan_schema_version')) {
      context.handle(
        _planSchemaVersionMeta,
        planSchemaVersion.isAcceptableOrUnknown(
          data['plan_schema_version']!,
          _planSchemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_planSchemaVersionMeta);
    }
    if (data.containsKey('plan_json')) {
      context.handle(
        _planJsonMeta,
        planJson.isAcceptableOrUnknown(data['plan_json']!, _planJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_planJsonMeta);
    }
    if (data.containsKey('operation_generation')) {
      context.handle(
        _operationGenerationMeta,
        operationGeneration.isAcceptableOrUnknown(
          data['operation_generation']!,
          _operationGenerationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationGenerationMeta);
    }
    if (data.containsKey('committed_repository_revision')) {
      context.handle(
        _committedRepositoryRevisionMeta,
        committedRepositoryRevision.isAcceptableOrUnknown(
          data['committed_repository_revision']!,
          _committedRepositoryRevisionMeta,
        ),
      );
    }
    if (data.containsKey('started_at_micros')) {
      context.handle(
        _startedAtMicrosMeta,
        startedAtMicros.isAcceptableOrUnknown(
          data['started_at_micros']!,
          _startedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtMicrosMeta);
    }
    if (data.containsKey('updated_at_micros')) {
      context.handle(
        _updatedAtMicrosMeta,
        updatedAtMicros.isAcceptableOrUnknown(
          data['updated_at_micros']!,
          _updatedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  OperationJournal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationJournal(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      planSchemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}plan_schema_version'],
      )!,
      planJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_json'],
      )!,
      operationGeneration: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}operation_generation'],
      )!,
      committedRepositoryRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}committed_repository_revision'],
      ),
      startedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_micros'],
      )!,
      updatedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_micros'],
      )!,
    );
  }

  @override
  $OperationJournalsTable createAlias(String alias) {
    return $OperationJournalsTable(attachedDatabase, alias);
  }
}

class OperationJournal extends DataClass
    implements Insertable<OperationJournal> {
  final String operationId;
  final String kind;
  final String phase;
  final int planSchemaVersion;
  final String planJson;
  final int operationGeneration;
  final int? committedRepositoryRevision;
  final int startedAtMicros;
  final int updatedAtMicros;
  const OperationJournal({
    required this.operationId,
    required this.kind,
    required this.phase,
    required this.planSchemaVersion,
    required this.planJson,
    required this.operationGeneration,
    this.committedRepositoryRevision,
    required this.startedAtMicros,
    required this.updatedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['kind'] = Variable<String>(kind);
    map['phase'] = Variable<String>(phase);
    map['plan_schema_version'] = Variable<int>(planSchemaVersion);
    map['plan_json'] = Variable<String>(planJson);
    map['operation_generation'] = Variable<int>(operationGeneration);
    if (!nullToAbsent || committedRepositoryRevision != null) {
      map['committed_repository_revision'] = Variable<int>(
        committedRepositoryRevision,
      );
    }
    map['started_at_micros'] = Variable<int>(startedAtMicros);
    map['updated_at_micros'] = Variable<int>(updatedAtMicros);
    return map;
  }

  OperationJournalsCompanion toCompanion(bool nullToAbsent) {
    return OperationJournalsCompanion(
      operationId: Value(operationId),
      kind: Value(kind),
      phase: Value(phase),
      planSchemaVersion: Value(planSchemaVersion),
      planJson: Value(planJson),
      operationGeneration: Value(operationGeneration),
      committedRepositoryRevision:
          committedRepositoryRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(committedRepositoryRevision),
      startedAtMicros: Value(startedAtMicros),
      updatedAtMicros: Value(updatedAtMicros),
    );
  }

  factory OperationJournal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationJournal(
      operationId: serializer.fromJson<String>(json['operationId']),
      kind: serializer.fromJson<String>(json['kind']),
      phase: serializer.fromJson<String>(json['phase']),
      planSchemaVersion: serializer.fromJson<int>(json['planSchemaVersion']),
      planJson: serializer.fromJson<String>(json['planJson']),
      operationGeneration: serializer.fromJson<int>(
        json['operationGeneration'],
      ),
      committedRepositoryRevision: serializer.fromJson<int?>(
        json['committedRepositoryRevision'],
      ),
      startedAtMicros: serializer.fromJson<int>(json['startedAtMicros']),
      updatedAtMicros: serializer.fromJson<int>(json['updatedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'kind': serializer.toJson<String>(kind),
      'phase': serializer.toJson<String>(phase),
      'planSchemaVersion': serializer.toJson<int>(planSchemaVersion),
      'planJson': serializer.toJson<String>(planJson),
      'operationGeneration': serializer.toJson<int>(operationGeneration),
      'committedRepositoryRevision': serializer.toJson<int?>(
        committedRepositoryRevision,
      ),
      'startedAtMicros': serializer.toJson<int>(startedAtMicros),
      'updatedAtMicros': serializer.toJson<int>(updatedAtMicros),
    };
  }

  OperationJournal copyWith({
    String? operationId,
    String? kind,
    String? phase,
    int? planSchemaVersion,
    String? planJson,
    int? operationGeneration,
    Value<int?> committedRepositoryRevision = const Value.absent(),
    int? startedAtMicros,
    int? updatedAtMicros,
  }) => OperationJournal(
    operationId: operationId ?? this.operationId,
    kind: kind ?? this.kind,
    phase: phase ?? this.phase,
    planSchemaVersion: planSchemaVersion ?? this.planSchemaVersion,
    planJson: planJson ?? this.planJson,
    operationGeneration: operationGeneration ?? this.operationGeneration,
    committedRepositoryRevision: committedRepositoryRevision.present
        ? committedRepositoryRevision.value
        : this.committedRepositoryRevision,
    startedAtMicros: startedAtMicros ?? this.startedAtMicros,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
  );
  OperationJournal copyWithCompanion(OperationJournalsCompanion data) {
    return OperationJournal(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      kind: data.kind.present ? data.kind.value : this.kind,
      phase: data.phase.present ? data.phase.value : this.phase,
      planSchemaVersion: data.planSchemaVersion.present
          ? data.planSchemaVersion.value
          : this.planSchemaVersion,
      planJson: data.planJson.present ? data.planJson.value : this.planJson,
      operationGeneration: data.operationGeneration.present
          ? data.operationGeneration.value
          : this.operationGeneration,
      committedRepositoryRevision: data.committedRepositoryRevision.present
          ? data.committedRepositoryRevision.value
          : this.committedRepositoryRevision,
      startedAtMicros: data.startedAtMicros.present
          ? data.startedAtMicros.value
          : this.startedAtMicros,
      updatedAtMicros: data.updatedAtMicros.present
          ? data.updatedAtMicros.value
          : this.updatedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationJournal(')
          ..write('operationId: $operationId, ')
          ..write('kind: $kind, ')
          ..write('phase: $phase, ')
          ..write('planSchemaVersion: $planSchemaVersion, ')
          ..write('planJson: $planJson, ')
          ..write('operationGeneration: $operationGeneration, ')
          ..write('committedRepositoryRevision: $committedRepositoryRevision, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    kind,
    phase,
    planSchemaVersion,
    planJson,
    operationGeneration,
    committedRepositoryRevision,
    startedAtMicros,
    updatedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationJournal &&
          other.operationId == this.operationId &&
          other.kind == this.kind &&
          other.phase == this.phase &&
          other.planSchemaVersion == this.planSchemaVersion &&
          other.planJson == this.planJson &&
          other.operationGeneration == this.operationGeneration &&
          other.committedRepositoryRevision ==
              this.committedRepositoryRevision &&
          other.startedAtMicros == this.startedAtMicros &&
          other.updatedAtMicros == this.updatedAtMicros);
}

class OperationJournalsCompanion extends UpdateCompanion<OperationJournal> {
  final Value<String> operationId;
  final Value<String> kind;
  final Value<String> phase;
  final Value<int> planSchemaVersion;
  final Value<String> planJson;
  final Value<int> operationGeneration;
  final Value<int?> committedRepositoryRevision;
  final Value<int> startedAtMicros;
  final Value<int> updatedAtMicros;
  final Value<int> rowid;
  const OperationJournalsCompanion({
    this.operationId = const Value.absent(),
    this.kind = const Value.absent(),
    this.phase = const Value.absent(),
    this.planSchemaVersion = const Value.absent(),
    this.planJson = const Value.absent(),
    this.operationGeneration = const Value.absent(),
    this.committedRepositoryRevision = const Value.absent(),
    this.startedAtMicros = const Value.absent(),
    this.updatedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperationJournalsCompanion.insert({
    required String operationId,
    required String kind,
    required String phase,
    required int planSchemaVersion,
    required String planJson,
    required int operationGeneration,
    this.committedRepositoryRevision = const Value.absent(),
    required int startedAtMicros,
    required int updatedAtMicros,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       kind = Value(kind),
       phase = Value(phase),
       planSchemaVersion = Value(planSchemaVersion),
       planJson = Value(planJson),
       operationGeneration = Value(operationGeneration),
       startedAtMicros = Value(startedAtMicros),
       updatedAtMicros = Value(updatedAtMicros);
  static Insertable<OperationJournal> custom({
    Expression<String>? operationId,
    Expression<String>? kind,
    Expression<String>? phase,
    Expression<int>? planSchemaVersion,
    Expression<String>? planJson,
    Expression<int>? operationGeneration,
    Expression<int>? committedRepositoryRevision,
    Expression<int>? startedAtMicros,
    Expression<int>? updatedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (kind != null) 'kind': kind,
      if (phase != null) 'phase': phase,
      if (planSchemaVersion != null) 'plan_schema_version': planSchemaVersion,
      if (planJson != null) 'plan_json': planJson,
      if (operationGeneration != null)
        'operation_generation': operationGeneration,
      if (committedRepositoryRevision != null)
        'committed_repository_revision': committedRepositoryRevision,
      if (startedAtMicros != null) 'started_at_micros': startedAtMicros,
      if (updatedAtMicros != null) 'updated_at_micros': updatedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperationJournalsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? kind,
    Value<String>? phase,
    Value<int>? planSchemaVersion,
    Value<String>? planJson,
    Value<int>? operationGeneration,
    Value<int?>? committedRepositoryRevision,
    Value<int>? startedAtMicros,
    Value<int>? updatedAtMicros,
    Value<int>? rowid,
  }) {
    return OperationJournalsCompanion(
      operationId: operationId ?? this.operationId,
      kind: kind ?? this.kind,
      phase: phase ?? this.phase,
      planSchemaVersion: planSchemaVersion ?? this.planSchemaVersion,
      planJson: planJson ?? this.planJson,
      operationGeneration: operationGeneration ?? this.operationGeneration,
      committedRepositoryRevision:
          committedRepositoryRevision ?? this.committedRepositoryRevision,
      startedAtMicros: startedAtMicros ?? this.startedAtMicros,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (planSchemaVersion.present) {
      map['plan_schema_version'] = Variable<int>(planSchemaVersion.value);
    }
    if (planJson.present) {
      map['plan_json'] = Variable<String>(planJson.value);
    }
    if (operationGeneration.present) {
      map['operation_generation'] = Variable<int>(operationGeneration.value);
    }
    if (committedRepositoryRevision.present) {
      map['committed_repository_revision'] = Variable<int>(
        committedRepositoryRevision.value,
      );
    }
    if (startedAtMicros.present) {
      map['started_at_micros'] = Variable<int>(startedAtMicros.value);
    }
    if (updatedAtMicros.present) {
      map['updated_at_micros'] = Variable<int>(updatedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperationJournalsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('kind: $kind, ')
          ..write('phase: $phase, ')
          ..write('planSchemaVersion: $planSchemaVersion, ')
          ..write('planJson: $planJson, ')
          ..write('operationGeneration: $operationGeneration, ')
          ..write('committedRepositoryRevision: $committedRepositoryRevision, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('updatedAtMicros: $updatedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperationJournalStepsTable extends OperationJournalSteps
    with TableInfo<$OperationJournalStepsTable, OperationJournalStep> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperationJournalStepsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES operation_journals (operation_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepIdMeta = const VerificationMeta('stepId');
  @override
  late final GeneratedColumn<String> stepId = GeneratedColumn<String>(
    'step_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recoveryReferenceMeta = const VerificationMeta(
    'recoveryReference',
  );
  @override
  late final GeneratedColumn<String> recoveryReference =
      GeneratedColumn<String>(
        'recovery_reference',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    sequence,
    stepId,
    kind,
    status,
    recoveryReference,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operation_journal_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationJournalStep> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('step_id')) {
      context.handle(
        _stepIdMeta,
        stepId.isAcceptableOrUnknown(data['step_id']!, _stepIdMeta),
      );
    } else if (isInserting) {
      context.missing(_stepIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('recovery_reference')) {
      context.handle(
        _recoveryReferenceMeta,
        recoveryReference.isAcceptableOrUnknown(
          data['recovery_reference']!,
          _recoveryReferenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recoveryReferenceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId, sequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {operationId, stepId},
  ];
  @override
  OperationJournalStep map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationJournalStep(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      stepId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}step_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      recoveryReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recovery_reference'],
      )!,
    );
  }

  @override
  $OperationJournalStepsTable createAlias(String alias) {
    return $OperationJournalStepsTable(attachedDatabase, alias);
  }
}

class OperationJournalStep extends DataClass
    implements Insertable<OperationJournalStep> {
  final String operationId;
  final int sequence;
  final String stepId;
  final String kind;
  final String status;
  final String recoveryReference;
  const OperationJournalStep({
    required this.operationId,
    required this.sequence,
    required this.stepId,
    required this.kind,
    required this.status,
    required this.recoveryReference,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['sequence'] = Variable<int>(sequence);
    map['step_id'] = Variable<String>(stepId);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['recovery_reference'] = Variable<String>(recoveryReference);
    return map;
  }

  OperationJournalStepsCompanion toCompanion(bool nullToAbsent) {
    return OperationJournalStepsCompanion(
      operationId: Value(operationId),
      sequence: Value(sequence),
      stepId: Value(stepId),
      kind: Value(kind),
      status: Value(status),
      recoveryReference: Value(recoveryReference),
    );
  }

  factory OperationJournalStep.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationJournalStep(
      operationId: serializer.fromJson<String>(json['operationId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      stepId: serializer.fromJson<String>(json['stepId']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      recoveryReference: serializer.fromJson<String>(json['recoveryReference']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'sequence': serializer.toJson<int>(sequence),
      'stepId': serializer.toJson<String>(stepId),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'recoveryReference': serializer.toJson<String>(recoveryReference),
    };
  }

  OperationJournalStep copyWith({
    String? operationId,
    int? sequence,
    String? stepId,
    String? kind,
    String? status,
    String? recoveryReference,
  }) => OperationJournalStep(
    operationId: operationId ?? this.operationId,
    sequence: sequence ?? this.sequence,
    stepId: stepId ?? this.stepId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    recoveryReference: recoveryReference ?? this.recoveryReference,
  );
  OperationJournalStep copyWithCompanion(OperationJournalStepsCompanion data) {
    return OperationJournalStep(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      stepId: data.stepId.present ? data.stepId.value : this.stepId,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      recoveryReference: data.recoveryReference.present
          ? data.recoveryReference.value
          : this.recoveryReference,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationJournalStep(')
          ..write('operationId: $operationId, ')
          ..write('sequence: $sequence, ')
          ..write('stepId: $stepId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('recoveryReference: $recoveryReference')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    sequence,
    stepId,
    kind,
    status,
    recoveryReference,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationJournalStep &&
          other.operationId == this.operationId &&
          other.sequence == this.sequence &&
          other.stepId == this.stepId &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.recoveryReference == this.recoveryReference);
}

class OperationJournalStepsCompanion
    extends UpdateCompanion<OperationJournalStep> {
  final Value<String> operationId;
  final Value<int> sequence;
  final Value<String> stepId;
  final Value<String> kind;
  final Value<String> status;
  final Value<String> recoveryReference;
  final Value<int> rowid;
  const OperationJournalStepsCompanion({
    this.operationId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.stepId = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.recoveryReference = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperationJournalStepsCompanion.insert({
    required String operationId,
    required int sequence,
    required String stepId,
    required String kind,
    required String status,
    required String recoveryReference,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       sequence = Value(sequence),
       stepId = Value(stepId),
       kind = Value(kind),
       status = Value(status),
       recoveryReference = Value(recoveryReference);
  static Insertable<OperationJournalStep> custom({
    Expression<String>? operationId,
    Expression<int>? sequence,
    Expression<String>? stepId,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<String>? recoveryReference,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (sequence != null) 'sequence': sequence,
      if (stepId != null) 'step_id': stepId,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (recoveryReference != null) 'recovery_reference': recoveryReference,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperationJournalStepsCompanion copyWith({
    Value<String>? operationId,
    Value<int>? sequence,
    Value<String>? stepId,
    Value<String>? kind,
    Value<String>? status,
    Value<String>? recoveryReference,
    Value<int>? rowid,
  }) {
    return OperationJournalStepsCompanion(
      operationId: operationId ?? this.operationId,
      sequence: sequence ?? this.sequence,
      stepId: stepId ?? this.stepId,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      recoveryReference: recoveryReference ?? this.recoveryReference,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (stepId.present) {
      map['step_id'] = Variable<String>(stepId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (recoveryReference.present) {
      map['recovery_reference'] = Variable<String>(recoveryReference.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperationJournalStepsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('sequence: $sequence, ')
          ..write('stepId: $stepId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('recoveryReference: $recoveryReference, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperationRecordsTable extends OperationRecords
    with TableInfo<$OperationRecordsTable, OperationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retainWithoutSubjectsMeta =
      const VerificationMeta('retainWithoutSubjects');
  @override
  late final GeneratedColumn<bool> retainWithoutSubjects =
      GeneratedColumn<bool>(
        'retain_without_subjects',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("retain_without_subjects" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _startedAtMicrosMeta = const VerificationMeta(
    'startedAtMicros',
  );
  @override
  late final GeneratedColumn<int> startedAtMicros = GeneratedColumn<int>(
    'started_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMicrosMeta = const VerificationMeta(
    'completedAtMicros',
  );
  @override
  late final GeneratedColumn<int> completedAtMicros = GeneratedColumn<int>(
    'completed_at_micros',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    operationId,
    kind,
    status,
    retainWithoutSubjects,
    startedAtMicros,
    completedAtMicros,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('retain_without_subjects')) {
      context.handle(
        _retainWithoutSubjectsMeta,
        retainWithoutSubjects.isAcceptableOrUnknown(
          data['retain_without_subjects']!,
          _retainWithoutSubjectsMeta,
        ),
      );
    }
    if (data.containsKey('started_at_micros')) {
      context.handle(
        _startedAtMicrosMeta,
        startedAtMicros.isAcceptableOrUnknown(
          data['started_at_micros']!,
          _startedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtMicrosMeta);
    }
    if (data.containsKey('completed_at_micros')) {
      context.handle(
        _completedAtMicrosMeta,
        completedAtMicros.isAcceptableOrUnknown(
          data['completed_at_micros']!,
          _completedAtMicrosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedAtMicrosMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  OperationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationRecord(
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retainWithoutSubjects: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}retain_without_subjects'],
      )!,
      startedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_micros'],
      )!,
      completedAtMicros: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_micros'],
      )!,
    );
  }

  @override
  $OperationRecordsTable createAlias(String alias) {
    return $OperationRecordsTable(attachedDatabase, alias);
  }
}

class OperationRecord extends DataClass implements Insertable<OperationRecord> {
  final String operationId;
  final String kind;
  final String status;
  final bool retainWithoutSubjects;
  final int startedAtMicros;
  final int completedAtMicros;
  const OperationRecord({
    required this.operationId,
    required this.kind,
    required this.status,
    required this.retainWithoutSubjects,
    required this.startedAtMicros,
    required this.completedAtMicros,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['kind'] = Variable<String>(kind);
    map['status'] = Variable<String>(status);
    map['retain_without_subjects'] = Variable<bool>(retainWithoutSubjects);
    map['started_at_micros'] = Variable<int>(startedAtMicros);
    map['completed_at_micros'] = Variable<int>(completedAtMicros);
    return map;
  }

  OperationRecordsCompanion toCompanion(bool nullToAbsent) {
    return OperationRecordsCompanion(
      operationId: Value(operationId),
      kind: Value(kind),
      status: Value(status),
      retainWithoutSubjects: Value(retainWithoutSubjects),
      startedAtMicros: Value(startedAtMicros),
      completedAtMicros: Value(completedAtMicros),
    );
  }

  factory OperationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationRecord(
      operationId: serializer.fromJson<String>(json['operationId']),
      kind: serializer.fromJson<String>(json['kind']),
      status: serializer.fromJson<String>(json['status']),
      retainWithoutSubjects: serializer.fromJson<bool>(
        json['retainWithoutSubjects'],
      ),
      startedAtMicros: serializer.fromJson<int>(json['startedAtMicros']),
      completedAtMicros: serializer.fromJson<int>(json['completedAtMicros']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'kind': serializer.toJson<String>(kind),
      'status': serializer.toJson<String>(status),
      'retainWithoutSubjects': serializer.toJson<bool>(retainWithoutSubjects),
      'startedAtMicros': serializer.toJson<int>(startedAtMicros),
      'completedAtMicros': serializer.toJson<int>(completedAtMicros),
    };
  }

  OperationRecord copyWith({
    String? operationId,
    String? kind,
    String? status,
    bool? retainWithoutSubjects,
    int? startedAtMicros,
    int? completedAtMicros,
  }) => OperationRecord(
    operationId: operationId ?? this.operationId,
    kind: kind ?? this.kind,
    status: status ?? this.status,
    retainWithoutSubjects: retainWithoutSubjects ?? this.retainWithoutSubjects,
    startedAtMicros: startedAtMicros ?? this.startedAtMicros,
    completedAtMicros: completedAtMicros ?? this.completedAtMicros,
  );
  OperationRecord copyWithCompanion(OperationRecordsCompanion data) {
    return OperationRecord(
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      kind: data.kind.present ? data.kind.value : this.kind,
      status: data.status.present ? data.status.value : this.status,
      retainWithoutSubjects: data.retainWithoutSubjects.present
          ? data.retainWithoutSubjects.value
          : this.retainWithoutSubjects,
      startedAtMicros: data.startedAtMicros.present
          ? data.startedAtMicros.value
          : this.startedAtMicros,
      completedAtMicros: data.completedAtMicros.present
          ? data.completedAtMicros.value
          : this.completedAtMicros,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationRecord(')
          ..write('operationId: $operationId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('retainWithoutSubjects: $retainWithoutSubjects, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('completedAtMicros: $completedAtMicros')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    operationId,
    kind,
    status,
    retainWithoutSubjects,
    startedAtMicros,
    completedAtMicros,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationRecord &&
          other.operationId == this.operationId &&
          other.kind == this.kind &&
          other.status == this.status &&
          other.retainWithoutSubjects == this.retainWithoutSubjects &&
          other.startedAtMicros == this.startedAtMicros &&
          other.completedAtMicros == this.completedAtMicros);
}

class OperationRecordsCompanion extends UpdateCompanion<OperationRecord> {
  final Value<String> operationId;
  final Value<String> kind;
  final Value<String> status;
  final Value<bool> retainWithoutSubjects;
  final Value<int> startedAtMicros;
  final Value<int> completedAtMicros;
  final Value<int> rowid;
  const OperationRecordsCompanion({
    this.operationId = const Value.absent(),
    this.kind = const Value.absent(),
    this.status = const Value.absent(),
    this.retainWithoutSubjects = const Value.absent(),
    this.startedAtMicros = const Value.absent(),
    this.completedAtMicros = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperationRecordsCompanion.insert({
    required String operationId,
    required String kind,
    required String status,
    this.retainWithoutSubjects = const Value.absent(),
    required int startedAtMicros,
    required int completedAtMicros,
    this.rowid = const Value.absent(),
  }) : operationId = Value(operationId),
       kind = Value(kind),
       status = Value(status),
       startedAtMicros = Value(startedAtMicros),
       completedAtMicros = Value(completedAtMicros);
  static Insertable<OperationRecord> custom({
    Expression<String>? operationId,
    Expression<String>? kind,
    Expression<String>? status,
    Expression<bool>? retainWithoutSubjects,
    Expression<int>? startedAtMicros,
    Expression<int>? completedAtMicros,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (retainWithoutSubjects != null)
        'retain_without_subjects': retainWithoutSubjects,
      if (startedAtMicros != null) 'started_at_micros': startedAtMicros,
      if (completedAtMicros != null) 'completed_at_micros': completedAtMicros,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperationRecordsCompanion copyWith({
    Value<String>? operationId,
    Value<String>? kind,
    Value<String>? status,
    Value<bool>? retainWithoutSubjects,
    Value<int>? startedAtMicros,
    Value<int>? completedAtMicros,
    Value<int>? rowid,
  }) {
    return OperationRecordsCompanion(
      operationId: operationId ?? this.operationId,
      kind: kind ?? this.kind,
      status: status ?? this.status,
      retainWithoutSubjects:
          retainWithoutSubjects ?? this.retainWithoutSubjects,
      startedAtMicros: startedAtMicros ?? this.startedAtMicros,
      completedAtMicros: completedAtMicros ?? this.completedAtMicros,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retainWithoutSubjects.present) {
      map['retain_without_subjects'] = Variable<bool>(
        retainWithoutSubjects.value,
      );
    }
    if (startedAtMicros.present) {
      map['started_at_micros'] = Variable<int>(startedAtMicros.value);
    }
    if (completedAtMicros.present) {
      map['completed_at_micros'] = Variable<int>(completedAtMicros.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperationRecordsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('kind: $kind, ')
          ..write('status: $status, ')
          ..write('retainWithoutSubjects: $retainWithoutSubjects, ')
          ..write('startedAtMicros: $startedAtMicros, ')
          ..write('completedAtMicros: $completedAtMicros, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OperationSubjectsTable extends OperationSubjects
    with TableInfo<$OperationSubjectsTable, OperationSubject> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OperationSubjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _subjectIdMeta = const VerificationMeta(
    'subjectId',
  );
  @override
  late final GeneratedColumn<String> subjectId = GeneratedColumn<String>(
    'subject_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationIdMeta = const VerificationMeta(
    'operationId',
  );
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
    'operation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES operation_records (operation_id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _managedSkillIdMeta = const VerificationMeta(
    'managedSkillId',
  );
  @override
  late final GeneratedColumn<String> managedSkillId = GeneratedColumn<String>(
    'managed_skill_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES managed_skills (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sourceLineageIdMeta = const VerificationMeta(
    'sourceLineageId',
  );
  @override
  late final GeneratedColumn<String> sourceLineageId = GeneratedColumn<String>(
    'source_lineage_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES source_lineages (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _beforeObjectIdMeta = const VerificationMeta(
    'beforeObjectId',
  );
  @override
  late final GeneratedColumn<String> beforeObjectId = GeneratedColumn<String>(
    'before_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _afterObjectIdMeta = const VerificationMeta(
    'afterObjectId',
  );
  @override
  late final GeneratedColumn<String> afterObjectId = GeneratedColumn<String>(
    'after_object_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _beforeContentHashMeta = const VerificationMeta(
    'beforeContentHash',
  );
  @override
  late final GeneratedColumn<String> beforeContentHash =
      GeneratedColumn<String>(
        'before_content_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _afterContentHashMeta = const VerificationMeta(
    'afterContentHash',
  );
  @override
  late final GeneratedColumn<String> afterContentHash = GeneratedColumn<String>(
    'after_content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    subjectId,
    operationId,
    managedSkillId,
    sourceLineageId,
    beforeObjectId,
    afterObjectId,
    beforeContentHash,
    afterContentHash,
    displayName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'operation_subjects';
  @override
  VerificationContext validateIntegrity(
    Insertable<OperationSubject> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('subject_id')) {
      context.handle(
        _subjectIdMeta,
        subjectId.isAcceptableOrUnknown(data['subject_id']!, _subjectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectIdMeta);
    }
    if (data.containsKey('operation_id')) {
      context.handle(
        _operationIdMeta,
        operationId.isAcceptableOrUnknown(
          data['operation_id']!,
          _operationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('managed_skill_id')) {
      context.handle(
        _managedSkillIdMeta,
        managedSkillId.isAcceptableOrUnknown(
          data['managed_skill_id']!,
          _managedSkillIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_managedSkillIdMeta);
    }
    if (data.containsKey('source_lineage_id')) {
      context.handle(
        _sourceLineageIdMeta,
        sourceLineageId.isAcceptableOrUnknown(
          data['source_lineage_id']!,
          _sourceLineageIdMeta,
        ),
      );
    }
    if (data.containsKey('before_object_id')) {
      context.handle(
        _beforeObjectIdMeta,
        beforeObjectId.isAcceptableOrUnknown(
          data['before_object_id']!,
          _beforeObjectIdMeta,
        ),
      );
    }
    if (data.containsKey('after_object_id')) {
      context.handle(
        _afterObjectIdMeta,
        afterObjectId.isAcceptableOrUnknown(
          data['after_object_id']!,
          _afterObjectIdMeta,
        ),
      );
    }
    if (data.containsKey('before_content_hash')) {
      context.handle(
        _beforeContentHashMeta,
        beforeContentHash.isAcceptableOrUnknown(
          data['before_content_hash']!,
          _beforeContentHashMeta,
        ),
      );
    }
    if (data.containsKey('after_content_hash')) {
      context.handle(
        _afterContentHashMeta,
        afterContentHash.isAcceptableOrUnknown(
          data['after_content_hash']!,
          _afterContentHashMeta,
        ),
      );
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {subjectId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {operationId, managedSkillId},
  ];
  @override
  OperationSubject map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OperationSubject(
      subjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject_id'],
      )!,
      operationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_id'],
      )!,
      managedSkillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}managed_skill_id'],
      )!,
      sourceLineageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lineage_id'],
      ),
      beforeObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_object_id'],
      ),
      afterObjectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_object_id'],
      ),
      beforeContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}before_content_hash'],
      ),
      afterContentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}after_content_hash'],
      ),
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
    );
  }

  @override
  $OperationSubjectsTable createAlias(String alias) {
    return $OperationSubjectsTable(attachedDatabase, alias);
  }
}

class OperationSubject extends DataClass
    implements Insertable<OperationSubject> {
  final String subjectId;
  final String operationId;
  final String managedSkillId;
  final String? sourceLineageId;
  final String? beforeObjectId;
  final String? afterObjectId;
  final String? beforeContentHash;
  final String? afterContentHash;
  final String displayName;
  const OperationSubject({
    required this.subjectId,
    required this.operationId,
    required this.managedSkillId,
    this.sourceLineageId,
    this.beforeObjectId,
    this.afterObjectId,
    this.beforeContentHash,
    this.afterContentHash,
    required this.displayName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['subject_id'] = Variable<String>(subjectId);
    map['operation_id'] = Variable<String>(operationId);
    map['managed_skill_id'] = Variable<String>(managedSkillId);
    if (!nullToAbsent || sourceLineageId != null) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId);
    }
    if (!nullToAbsent || beforeObjectId != null) {
      map['before_object_id'] = Variable<String>(beforeObjectId);
    }
    if (!nullToAbsent || afterObjectId != null) {
      map['after_object_id'] = Variable<String>(afterObjectId);
    }
    if (!nullToAbsent || beforeContentHash != null) {
      map['before_content_hash'] = Variable<String>(beforeContentHash);
    }
    if (!nullToAbsent || afterContentHash != null) {
      map['after_content_hash'] = Variable<String>(afterContentHash);
    }
    map['display_name'] = Variable<String>(displayName);
    return map;
  }

  OperationSubjectsCompanion toCompanion(bool nullToAbsent) {
    return OperationSubjectsCompanion(
      subjectId: Value(subjectId),
      operationId: Value(operationId),
      managedSkillId: Value(managedSkillId),
      sourceLineageId: sourceLineageId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceLineageId),
      beforeObjectId: beforeObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeObjectId),
      afterObjectId: afterObjectId == null && nullToAbsent
          ? const Value.absent()
          : Value(afterObjectId),
      beforeContentHash: beforeContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(beforeContentHash),
      afterContentHash: afterContentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(afterContentHash),
      displayName: Value(displayName),
    );
  }

  factory OperationSubject.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OperationSubject(
      subjectId: serializer.fromJson<String>(json['subjectId']),
      operationId: serializer.fromJson<String>(json['operationId']),
      managedSkillId: serializer.fromJson<String>(json['managedSkillId']),
      sourceLineageId: serializer.fromJson<String?>(json['sourceLineageId']),
      beforeObjectId: serializer.fromJson<String?>(json['beforeObjectId']),
      afterObjectId: serializer.fromJson<String?>(json['afterObjectId']),
      beforeContentHash: serializer.fromJson<String?>(
        json['beforeContentHash'],
      ),
      afterContentHash: serializer.fromJson<String?>(json['afterContentHash']),
      displayName: serializer.fromJson<String>(json['displayName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'subjectId': serializer.toJson<String>(subjectId),
      'operationId': serializer.toJson<String>(operationId),
      'managedSkillId': serializer.toJson<String>(managedSkillId),
      'sourceLineageId': serializer.toJson<String?>(sourceLineageId),
      'beforeObjectId': serializer.toJson<String?>(beforeObjectId),
      'afterObjectId': serializer.toJson<String?>(afterObjectId),
      'beforeContentHash': serializer.toJson<String?>(beforeContentHash),
      'afterContentHash': serializer.toJson<String?>(afterContentHash),
      'displayName': serializer.toJson<String>(displayName),
    };
  }

  OperationSubject copyWith({
    String? subjectId,
    String? operationId,
    String? managedSkillId,
    Value<String?> sourceLineageId = const Value.absent(),
    Value<String?> beforeObjectId = const Value.absent(),
    Value<String?> afterObjectId = const Value.absent(),
    Value<String?> beforeContentHash = const Value.absent(),
    Value<String?> afterContentHash = const Value.absent(),
    String? displayName,
  }) => OperationSubject(
    subjectId: subjectId ?? this.subjectId,
    operationId: operationId ?? this.operationId,
    managedSkillId: managedSkillId ?? this.managedSkillId,
    sourceLineageId: sourceLineageId.present
        ? sourceLineageId.value
        : this.sourceLineageId,
    beforeObjectId: beforeObjectId.present
        ? beforeObjectId.value
        : this.beforeObjectId,
    afterObjectId: afterObjectId.present
        ? afterObjectId.value
        : this.afterObjectId,
    beforeContentHash: beforeContentHash.present
        ? beforeContentHash.value
        : this.beforeContentHash,
    afterContentHash: afterContentHash.present
        ? afterContentHash.value
        : this.afterContentHash,
    displayName: displayName ?? this.displayName,
  );
  OperationSubject copyWithCompanion(OperationSubjectsCompanion data) {
    return OperationSubject(
      subjectId: data.subjectId.present ? data.subjectId.value : this.subjectId,
      operationId: data.operationId.present
          ? data.operationId.value
          : this.operationId,
      managedSkillId: data.managedSkillId.present
          ? data.managedSkillId.value
          : this.managedSkillId,
      sourceLineageId: data.sourceLineageId.present
          ? data.sourceLineageId.value
          : this.sourceLineageId,
      beforeObjectId: data.beforeObjectId.present
          ? data.beforeObjectId.value
          : this.beforeObjectId,
      afterObjectId: data.afterObjectId.present
          ? data.afterObjectId.value
          : this.afterObjectId,
      beforeContentHash: data.beforeContentHash.present
          ? data.beforeContentHash.value
          : this.beforeContentHash,
      afterContentHash: data.afterContentHash.present
          ? data.afterContentHash.value
          : this.afterContentHash,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OperationSubject(')
          ..write('subjectId: $subjectId, ')
          ..write('operationId: $operationId, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('beforeObjectId: $beforeObjectId, ')
          ..write('afterObjectId: $afterObjectId, ')
          ..write('beforeContentHash: $beforeContentHash, ')
          ..write('afterContentHash: $afterContentHash, ')
          ..write('displayName: $displayName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    subjectId,
    operationId,
    managedSkillId,
    sourceLineageId,
    beforeObjectId,
    afterObjectId,
    beforeContentHash,
    afterContentHash,
    displayName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OperationSubject &&
          other.subjectId == this.subjectId &&
          other.operationId == this.operationId &&
          other.managedSkillId == this.managedSkillId &&
          other.sourceLineageId == this.sourceLineageId &&
          other.beforeObjectId == this.beforeObjectId &&
          other.afterObjectId == this.afterObjectId &&
          other.beforeContentHash == this.beforeContentHash &&
          other.afterContentHash == this.afterContentHash &&
          other.displayName == this.displayName);
}

class OperationSubjectsCompanion extends UpdateCompanion<OperationSubject> {
  final Value<String> subjectId;
  final Value<String> operationId;
  final Value<String> managedSkillId;
  final Value<String?> sourceLineageId;
  final Value<String?> beforeObjectId;
  final Value<String?> afterObjectId;
  final Value<String?> beforeContentHash;
  final Value<String?> afterContentHash;
  final Value<String> displayName;
  final Value<int> rowid;
  const OperationSubjectsCompanion({
    this.subjectId = const Value.absent(),
    this.operationId = const Value.absent(),
    this.managedSkillId = const Value.absent(),
    this.sourceLineageId = const Value.absent(),
    this.beforeObjectId = const Value.absent(),
    this.afterObjectId = const Value.absent(),
    this.beforeContentHash = const Value.absent(),
    this.afterContentHash = const Value.absent(),
    this.displayName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OperationSubjectsCompanion.insert({
    required String subjectId,
    required String operationId,
    required String managedSkillId,
    this.sourceLineageId = const Value.absent(),
    this.beforeObjectId = const Value.absent(),
    this.afterObjectId = const Value.absent(),
    this.beforeContentHash = const Value.absent(),
    this.afterContentHash = const Value.absent(),
    required String displayName,
    this.rowid = const Value.absent(),
  }) : subjectId = Value(subjectId),
       operationId = Value(operationId),
       managedSkillId = Value(managedSkillId),
       displayName = Value(displayName);
  static Insertable<OperationSubject> custom({
    Expression<String>? subjectId,
    Expression<String>? operationId,
    Expression<String>? managedSkillId,
    Expression<String>? sourceLineageId,
    Expression<String>? beforeObjectId,
    Expression<String>? afterObjectId,
    Expression<String>? beforeContentHash,
    Expression<String>? afterContentHash,
    Expression<String>? displayName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (subjectId != null) 'subject_id': subjectId,
      if (operationId != null) 'operation_id': operationId,
      if (managedSkillId != null) 'managed_skill_id': managedSkillId,
      if (sourceLineageId != null) 'source_lineage_id': sourceLineageId,
      if (beforeObjectId != null) 'before_object_id': beforeObjectId,
      if (afterObjectId != null) 'after_object_id': afterObjectId,
      if (beforeContentHash != null) 'before_content_hash': beforeContentHash,
      if (afterContentHash != null) 'after_content_hash': afterContentHash,
      if (displayName != null) 'display_name': displayName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OperationSubjectsCompanion copyWith({
    Value<String>? subjectId,
    Value<String>? operationId,
    Value<String>? managedSkillId,
    Value<String?>? sourceLineageId,
    Value<String?>? beforeObjectId,
    Value<String?>? afterObjectId,
    Value<String?>? beforeContentHash,
    Value<String?>? afterContentHash,
    Value<String>? displayName,
    Value<int>? rowid,
  }) {
    return OperationSubjectsCompanion(
      subjectId: subjectId ?? this.subjectId,
      operationId: operationId ?? this.operationId,
      managedSkillId: managedSkillId ?? this.managedSkillId,
      sourceLineageId: sourceLineageId ?? this.sourceLineageId,
      beforeObjectId: beforeObjectId ?? this.beforeObjectId,
      afterObjectId: afterObjectId ?? this.afterObjectId,
      beforeContentHash: beforeContentHash ?? this.beforeContentHash,
      afterContentHash: afterContentHash ?? this.afterContentHash,
      displayName: displayName ?? this.displayName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (subjectId.present) {
      map['subject_id'] = Variable<String>(subjectId.value);
    }
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (managedSkillId.present) {
      map['managed_skill_id'] = Variable<String>(managedSkillId.value);
    }
    if (sourceLineageId.present) {
      map['source_lineage_id'] = Variable<String>(sourceLineageId.value);
    }
    if (beforeObjectId.present) {
      map['before_object_id'] = Variable<String>(beforeObjectId.value);
    }
    if (afterObjectId.present) {
      map['after_object_id'] = Variable<String>(afterObjectId.value);
    }
    if (beforeContentHash.present) {
      map['before_content_hash'] = Variable<String>(beforeContentHash.value);
    }
    if (afterContentHash.present) {
      map['after_content_hash'] = Variable<String>(afterContentHash.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OperationSubjectsCompanion(')
          ..write('subjectId: $subjectId, ')
          ..write('operationId: $operationId, ')
          ..write('managedSkillId: $managedSkillId, ')
          ..write('sourceLineageId: $sourceLineageId, ')
          ..write('beforeObjectId: $beforeObjectId, ')
          ..write('afterObjectId: $afterObjectId, ')
          ..write('beforeContentHash: $beforeContentHash, ')
          ..write('afterContentHash: $afterContentHash, ')
          ..write('displayName: $displayName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$WorkspaceDatabase extends GeneratedDatabase {
  _$WorkspaceDatabase(QueryExecutor e) : super(e);
  $WorkspaceDatabaseManager get managers => $WorkspaceDatabaseManager(this);
  late final $WorkspaceMetadataTable workspaceMetadata =
      $WorkspaceMetadataTable(this);
  late final $SourceLineagesTable sourceLineages = $SourceLineagesTable(this);
  late final $ManagedSkillsTable managedSkills = $ManagedSkillsTable(this);
  late final $SkillSourcesTable skillSources = $SkillSourcesTable(this);
  late final $RevisionMetadataTable revisionMetadata = $RevisionMetadataTable(
    this,
  );
  late final $CurrentRevisionSelectionTable currentRevisionSelection =
      $CurrentRevisionSelectionTable(this);
  late final $DraftWorkspacesTable draftWorkspaces = $DraftWorkspacesTable(
    this,
  );
  late final $UpdateCandidateSessionsTable updateCandidateSessions =
      $UpdateCandidateSessionsTable(this);
  late final $UpdateCandidateItemsTable updateCandidateItems =
      $UpdateCandidateItemsTable(this);
  late final $ProjectRootsTable projectRoots = $ProjectRootsTable(this);
  late final $ActivationLocationsTable activationLocations =
      $ActivationLocationsTable(this);
  late final $ActivationAgentsTable activationAgents = $ActivationAgentsTable(
    this,
  );
  late final $SkillUserDataTable skillUserData = $SkillUserDataTable(this);
  late final $SkillUpdateCheckRecordsTable skillUpdateCheckRecords =
      $SkillUpdateCheckRecordsTable(this);
  late final $SkillUpdateCheckMetadataTable skillUpdateCheckMetadata =
      $SkillUpdateCheckMetadataTable(this);
  late final $PersonalTagsTable personalTags = $PersonalTagsTable(this);
  late final $SkillTagAssignmentsTable skillTagAssignments =
      $SkillTagAssignmentsTable(this);
  late final $OperationJournalsTable operationJournals =
      $OperationJournalsTable(this);
  late final $OperationJournalStepsTable operationJournalSteps =
      $OperationJournalStepsTable(this);
  late final $OperationRecordsTable operationRecords = $OperationRecordsTable(
    this,
  );
  late final $OperationSubjectsTable operationSubjects =
      $OperationSubjectsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workspaceMetadata,
    sourceLineages,
    managedSkills,
    skillSources,
    revisionMetadata,
    currentRevisionSelection,
    draftWorkspaces,
    updateCandidateSessions,
    updateCandidateItems,
    projectRoots,
    activationLocations,
    activationAgents,
    skillUserData,
    skillUpdateCheckRecords,
    skillUpdateCheckMetadata,
    personalTags,
    skillTagAssignments,
    operationJournals,
    operationJournalSteps,
    operationRecords,
    operationSubjects,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('source_lineages', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'source_lineages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('skill_sources', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'source_lineages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('revision_metadata', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('current_revision_selection', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('draft_workspaces', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('update_candidate_sessions', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('activation_locations', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'activation_locations',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('activation_agents', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('skill_user_data', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [
        TableUpdate('skill_update_check_records', kind: UpdateKind.delete),
      ],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('skill_tag_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'personal_tags',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('skill_tag_assignments', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'operation_journals',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('operation_journal_steps', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'operation_records',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('operation_subjects', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'managed_skills',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('operation_subjects', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'source_lineages',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('operation_subjects', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$WorkspaceMetadataTableCreateCompanionBuilder =
    WorkspaceMetadataCompanion Function({
      Value<int> singleton,
      required int repositoryRevision,
      required int destructionEpoch,
      required int createdAtMicros,
      required int updatedAtMicros,
    });
typedef $$WorkspaceMetadataTableUpdateCompanionBuilder =
    WorkspaceMetadataCompanion Function({
      Value<int> singleton,
      Value<int> repositoryRevision,
      Value<int> destructionEpoch,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
    });

class $$WorkspaceMetadataTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $WorkspaceMetadataTable> {
  $$WorkspaceMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get repositoryRevision => $composableBuilder(
    column: $table.repositoryRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get destructionEpoch => $composableBuilder(
    column: $table.destructionEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkspaceMetadataTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $WorkspaceMetadataTable> {
  $$WorkspaceMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get repositoryRevision => $composableBuilder(
    column: $table.repositoryRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get destructionEpoch => $composableBuilder(
    column: $table.destructionEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkspaceMetadataTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $WorkspaceMetadataTable> {
  $$WorkspaceMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<int> get repositoryRevision => $composableBuilder(
    column: $table.repositoryRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get destructionEpoch => $composableBuilder(
    column: $table.destructionEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );
}

class $$WorkspaceMetadataTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $WorkspaceMetadataTable,
          WorkspaceMetadataData,
          $$WorkspaceMetadataTableFilterComposer,
          $$WorkspaceMetadataTableOrderingComposer,
          $$WorkspaceMetadataTableAnnotationComposer,
          $$WorkspaceMetadataTableCreateCompanionBuilder,
          $$WorkspaceMetadataTableUpdateCompanionBuilder,
          (
            WorkspaceMetadataData,
            BaseReferences<
              _$WorkspaceDatabase,
              $WorkspaceMetadataTable,
              WorkspaceMetadataData
            >,
          ),
          WorkspaceMetadataData,
          PrefetchHooks Function()
        > {
  $$WorkspaceMetadataTableTableManager(
    _$WorkspaceDatabase db,
    $WorkspaceMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkspaceMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkspaceMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkspaceMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<int> repositoryRevision = const Value.absent(),
                Value<int> destructionEpoch = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
              }) => WorkspaceMetadataCompanion(
                singleton: singleton,
                repositoryRevision: repositoryRevision,
                destructionEpoch: destructionEpoch,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required int repositoryRevision,
                required int destructionEpoch,
                required int createdAtMicros,
                required int updatedAtMicros,
              }) => WorkspaceMetadataCompanion.insert(
                singleton: singleton,
                repositoryRevision: repositoryRevision,
                destructionEpoch: destructionEpoch,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkspaceMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $WorkspaceMetadataTable,
      WorkspaceMetadataData,
      $$WorkspaceMetadataTableFilterComposer,
      $$WorkspaceMetadataTableOrderingComposer,
      $$WorkspaceMetadataTableAnnotationComposer,
      $$WorkspaceMetadataTableCreateCompanionBuilder,
      $$WorkspaceMetadataTableUpdateCompanionBuilder,
      (
        WorkspaceMetadataData,
        BaseReferences<
          _$WorkspaceDatabase,
          $WorkspaceMetadataTable,
          WorkspaceMetadataData
        >,
      ),
      WorkspaceMetadataData,
      PrefetchHooks Function()
    >;
typedef $$SourceLineagesTableCreateCompanionBuilder =
    SourceLineagesCompanion Function({
      required String id,
      required String managedSkillId,
      required String objectFormat,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$SourceLineagesTableUpdateCompanionBuilder =
    SourceLineagesCompanion Function({
      Value<String> id,
      Value<String> managedSkillId,
      Value<String> objectFormat,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$SourceLineagesTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $SourceLineagesTable,
          SourceLineage
        > {
  $$SourceLineagesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) => db
      .managedSkills
      .createAlias('source_lineages__managed_skill_id__managed_skills__id');

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SkillSourcesTable, List<SkillSource>>
  _skillSourcesRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.skillSources,
        aliasName: 'source_lineages__id__skill_sources__source_lineage_id',
      );

  $$SkillSourcesTableProcessedTableManager get skillSourcesRefs {
    final manager = $$SkillSourcesTableTableManager($_db, $_db.skillSources)
        .filter(
          (f) => f.sourceLineageId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(_skillSourcesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RevisionMetadataTable, List<RevisionMetadataData>>
  _revisionMetadataRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.revisionMetadata,
        aliasName: 'source_lineages__id__revision_metadata__source_lineage_id',
      );

  $$RevisionMetadataTableProcessedTableManager get revisionMetadataRefs {
    final manager =
        $$RevisionMetadataTableTableManager($_db, $_db.revisionMetadata).filter(
          (f) => f.sourceLineageId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _revisionMetadataRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OperationSubjectsTable, List<OperationSubject>>
  _operationSubjectsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.operationSubjects,
        aliasName: 'source_lineages__id__operation_subjects__source_lineage_id',
      );

  $$OperationSubjectsTableProcessedTableManager get operationSubjectsRefs {
    final manager =
        $$OperationSubjectsTableTableManager(
          $_db,
          $_db.operationSubjects,
        ).filter(
          (f) => f.sourceLineageId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _operationSubjectsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SourceLineagesTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SourceLineagesTable> {
  $$SourceLineagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get objectFormat => $composableBuilder(
    column: $table.objectFormat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> skillSourcesRefs(
    Expression<bool> Function($$SkillSourcesTableFilterComposer f) f,
  ) {
    final $$SkillSourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillSources,
      getReferencedColumn: (t) => t.sourceLineageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillSourcesTableFilterComposer(
            $db: $db,
            $table: $db.skillSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> revisionMetadataRefs(
    Expression<bool> Function($$RevisionMetadataTableFilterComposer f) f,
  ) {
    final $$RevisionMetadataTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revisionMetadata,
      getReferencedColumn: (t) => t.sourceLineageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevisionMetadataTableFilterComposer(
            $db: $db,
            $table: $db.revisionMetadata,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> operationSubjectsRefs(
    Expression<bool> Function($$OperationSubjectsTableFilterComposer f) f,
  ) {
    final $$OperationSubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.operationSubjects,
      getReferencedColumn: (t) => t.sourceLineageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationSubjectsTableFilterComposer(
            $db: $db,
            $table: $db.operationSubjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SourceLineagesTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SourceLineagesTable> {
  $$SourceLineagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get objectFormat => $composableBuilder(
    column: $table.objectFormat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SourceLineagesTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SourceLineagesTable> {
  $$SourceLineagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get objectFormat => $composableBuilder(
    column: $table.objectFormat,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> skillSourcesRefs<T extends Object>(
    Expression<T> Function($$SkillSourcesTableAnnotationComposer a) f,
  ) {
    final $$SkillSourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillSources,
      getReferencedColumn: (t) => t.sourceLineageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillSourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.skillSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> revisionMetadataRefs<T extends Object>(
    Expression<T> Function($$RevisionMetadataTableAnnotationComposer a) f,
  ) {
    final $$RevisionMetadataTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.revisionMetadata,
      getReferencedColumn: (t) => t.sourceLineageId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RevisionMetadataTableAnnotationComposer(
            $db: $db,
            $table: $db.revisionMetadata,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> operationSubjectsRefs<T extends Object>(
    Expression<T> Function($$OperationSubjectsTableAnnotationComposer a) f,
  ) {
    final $$OperationSubjectsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.operationSubjects,
          getReferencedColumn: (t) => t.sourceLineageId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationSubjectsTableAnnotationComposer(
                $db: $db,
                $table: $db.operationSubjects,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SourceLineagesTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SourceLineagesTable,
          SourceLineage,
          $$SourceLineagesTableFilterComposer,
          $$SourceLineagesTableOrderingComposer,
          $$SourceLineagesTableAnnotationComposer,
          $$SourceLineagesTableCreateCompanionBuilder,
          $$SourceLineagesTableUpdateCompanionBuilder,
          (SourceLineage, $$SourceLineagesTableReferences),
          SourceLineage,
          PrefetchHooks Function({
            bool managedSkillId,
            bool skillSourcesRefs,
            bool revisionMetadataRefs,
            bool operationSubjectsRefs,
          })
        > {
  $$SourceLineagesTableTableManager(
    _$WorkspaceDatabase db,
    $SourceLineagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceLineagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceLineagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourceLineagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> managedSkillId = const Value.absent(),
                Value<String> objectFormat = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceLineagesCompanion(
                id: id,
                managedSkillId: managedSkillId,
                objectFormat: objectFormat,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String managedSkillId,
                required String objectFormat,
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => SourceLineagesCompanion.insert(
                id: id,
                managedSkillId: managedSkillId,
                objectFormat: objectFormat,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SourceLineagesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                managedSkillId = false,
                skillSourcesRefs = false,
                revisionMetadataRefs = false,
                operationSubjectsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (skillSourcesRefs) db.skillSources,
                    if (revisionMetadataRefs) db.revisionMetadata,
                    if (operationSubjectsRefs) db.operationSubjects,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (managedSkillId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.managedSkillId,
                                    referencedTable:
                                        $$SourceLineagesTableReferences
                                            ._managedSkillIdTable(db),
                                    referencedColumn:
                                        $$SourceLineagesTableReferences
                                            ._managedSkillIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (skillSourcesRefs)
                        await $_getPrefetchedData<
                          SourceLineage,
                          $SourceLineagesTable,
                          SkillSource
                        >(
                          currentTable: table,
                          referencedTable: $$SourceLineagesTableReferences
                              ._skillSourcesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SourceLineagesTableReferences(
                                db,
                                table,
                                p0,
                              ).skillSourcesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceLineageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (revisionMetadataRefs)
                        await $_getPrefetchedData<
                          SourceLineage,
                          $SourceLineagesTable,
                          RevisionMetadataData
                        >(
                          currentTable: table,
                          referencedTable: $$SourceLineagesTableReferences
                              ._revisionMetadataRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SourceLineagesTableReferences(
                                db,
                                table,
                                p0,
                              ).revisionMetadataRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceLineageId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (operationSubjectsRefs)
                        await $_getPrefetchedData<
                          SourceLineage,
                          $SourceLineagesTable,
                          OperationSubject
                        >(
                          currentTable: table,
                          referencedTable: $$SourceLineagesTableReferences
                              ._operationSubjectsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SourceLineagesTableReferences(
                                db,
                                table,
                                p0,
                              ).operationSubjectsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sourceLineageId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SourceLineagesTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SourceLineagesTable,
      SourceLineage,
      $$SourceLineagesTableFilterComposer,
      $$SourceLineagesTableOrderingComposer,
      $$SourceLineagesTableAnnotationComposer,
      $$SourceLineagesTableCreateCompanionBuilder,
      $$SourceLineagesTableUpdateCompanionBuilder,
      (SourceLineage, $$SourceLineagesTableReferences),
      SourceLineage,
      PrefetchHooks Function({
        bool managedSkillId,
        bool skillSourcesRefs,
        bool revisionMetadataRefs,
        bool operationSubjectsRefs,
      })
    >;
typedef $$ManagedSkillsTableCreateCompanionBuilder =
    ManagedSkillsCompanion Function({
      required String id,
      required String slotKey,
      required String declaredName,
      required String displayName,
      required String description,
      required String activeSourceLineageId,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$ManagedSkillsTableUpdateCompanionBuilder =
    ManagedSkillsCompanion Function({
      Value<String> id,
      Value<String> slotKey,
      Value<String> declaredName,
      Value<String> displayName,
      Value<String> description,
      Value<String> activeSourceLineageId,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$ManagedSkillsTableReferences
    extends
        BaseReferences<_$WorkspaceDatabase, $ManagedSkillsTable, ManagedSkill> {
  $$ManagedSkillsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$SourceLineagesTable, List<SourceLineage>>
  _sourceLineagesRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sourceLineages,
        aliasName: 'managed_skills__id__source_lineages__managed_skill_id',
      );

  $$SourceLineagesTableProcessedTableManager get sourceLineagesRefs {
    final manager = $$SourceLineagesTableTableManager(
      $_db,
      $_db.sourceLineages,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sourceLineagesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $CurrentRevisionSelectionTable,
    List<CurrentRevisionSelectionData>
  >
  _currentRevisionSelectionRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.currentRevisionSelection,
        aliasName:
            'managed_skills__id__current_revision_selection__managed_skill_id',
      );

  $$CurrentRevisionSelectionTableProcessedTableManager
  get currentRevisionSelectionRefs {
    final manager = $$CurrentRevisionSelectionTableTableManager(
      $_db,
      $_db.currentRevisionSelection,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _currentRevisionSelectionRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DraftWorkspacesTable, List<DraftWorkspace>>
  _draftWorkspacesRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.draftWorkspaces,
        aliasName: 'managed_skills__id__draft_workspaces__managed_skill_id',
      );

  $$DraftWorkspacesTableProcessedTableManager get draftWorkspacesRefs {
    final manager = $$DraftWorkspacesTableTableManager(
      $_db,
      $_db.draftWorkspaces,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _draftWorkspacesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $UpdateCandidateSessionsTable,
    List<UpdateCandidateSession>
  >
  _updateCandidateSessionsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.updateCandidateSessions,
        aliasName:
            'managed_skills__id__update_candidate_sessions__managed_skill_id',
      );

  $$UpdateCandidateSessionsTableProcessedTableManager
  get updateCandidateSessionsRefs {
    final manager = $$UpdateCandidateSessionsTableTableManager(
      $_db,
      $_db.updateCandidateSessions,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _updateCandidateSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ActivationLocationsTable,
    List<ActivationLocation>
  >
  _activationLocationsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.activationLocations,
        aliasName: 'managed_skills__id__activation_locations__managed_skill_id',
      );

  $$ActivationLocationsTableProcessedTableManager get activationLocationsRefs {
    final manager = $$ActivationLocationsTableTableManager(
      $_db,
      $_db.activationLocations,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _activationLocationsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SkillUserDataTable, List<SkillUserDataData>>
  _skillUserDataRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.skillUserData,
        aliasName: 'managed_skills__id__skill_user_data__managed_skill_id',
      );

  $$SkillUserDataTableProcessedTableManager get skillUserDataRefs {
    final manager = $$SkillUserDataTableTableManager(
      $_db,
      $_db.skillUserData,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_skillUserDataRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SkillUpdateCheckRecordsTable,
    List<SkillUpdateCheckRecord>
  >
  _skillUpdateCheckRecordsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.skillUpdateCheckRecords,
        aliasName:
            'managed_skills__id__skill_update_check_records__managed_skill_id',
      );

  $$SkillUpdateCheckRecordsTableProcessedTableManager
  get skillUpdateCheckRecordsRefs {
    final manager = $$SkillUpdateCheckRecordsTableTableManager(
      $_db,
      $_db.skillUpdateCheckRecords,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _skillUpdateCheckRecordsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SkillTagAssignmentsTable,
    List<SkillTagAssignment>
  >
  _skillTagAssignmentsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.skillTagAssignments,
        aliasName:
            'managed_skills__id__skill_tag_assignments__managed_skill_id',
      );

  $$SkillTagAssignmentsTableProcessedTableManager get skillTagAssignmentsRefs {
    final manager = $$SkillTagAssignmentsTableTableManager(
      $_db,
      $_db.skillTagAssignments,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _skillTagAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OperationSubjectsTable, List<OperationSubject>>
  _operationSubjectsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.operationSubjects,
        aliasName: 'managed_skills__id__operation_subjects__managed_skill_id',
      );

  $$OperationSubjectsTableProcessedTableManager get operationSubjectsRefs {
    final manager = $$OperationSubjectsTableTableManager(
      $_db,
      $_db.operationSubjects,
    ).filter((f) => f.managedSkillId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _operationSubjectsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ManagedSkillsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $ManagedSkillsTable> {
  $$ManagedSkillsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slotKey => $composableBuilder(
    column: $table.slotKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get activeSourceLineageId => $composableBuilder(
    column: $table.activeSourceLineageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sourceLineagesRefs(
    Expression<bool> Function($$SourceLineagesTableFilterComposer f) f,
  ) {
    final $$SourceLineagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableFilterComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> currentRevisionSelectionRefs(
    Expression<bool> Function($$CurrentRevisionSelectionTableFilterComposer f)
    f,
  ) {
    final $$CurrentRevisionSelectionTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.currentRevisionSelection,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CurrentRevisionSelectionTableFilterComposer(
                $db: $db,
                $table: $db.currentRevisionSelection,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> draftWorkspacesRefs(
    Expression<bool> Function($$DraftWorkspacesTableFilterComposer f) f,
  ) {
    final $$DraftWorkspacesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.draftWorkspaces,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DraftWorkspacesTableFilterComposer(
            $db: $db,
            $table: $db.draftWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> updateCandidateSessionsRefs(
    Expression<bool> Function($$UpdateCandidateSessionsTableFilterComposer f) f,
  ) {
    final $$UpdateCandidateSessionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.updateCandidateSessions,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UpdateCandidateSessionsTableFilterComposer(
                $db: $db,
                $table: $db.updateCandidateSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> activationLocationsRefs(
    Expression<bool> Function($$ActivationLocationsTableFilterComposer f) f,
  ) {
    final $$ActivationLocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activationLocations,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivationLocationsTableFilterComposer(
            $db: $db,
            $table: $db.activationLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> skillUserDataRefs(
    Expression<bool> Function($$SkillUserDataTableFilterComposer f) f,
  ) {
    final $$SkillUserDataTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillUserData,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillUserDataTableFilterComposer(
            $db: $db,
            $table: $db.skillUserData,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> skillUpdateCheckRecordsRefs(
    Expression<bool> Function($$SkillUpdateCheckRecordsTableFilterComposer f) f,
  ) {
    final $$SkillUpdateCheckRecordsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.skillUpdateCheckRecords,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SkillUpdateCheckRecordsTableFilterComposer(
                $db: $db,
                $table: $db.skillUpdateCheckRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> skillTagAssignmentsRefs(
    Expression<bool> Function($$SkillTagAssignmentsTableFilterComposer f) f,
  ) {
    final $$SkillTagAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillTagAssignments,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillTagAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.skillTagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> operationSubjectsRefs(
    Expression<bool> Function($$OperationSubjectsTableFilterComposer f) f,
  ) {
    final $$OperationSubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.operationSubjects,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationSubjectsTableFilterComposer(
            $db: $db,
            $table: $db.operationSubjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ManagedSkillsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $ManagedSkillsTable> {
  $$ManagedSkillsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slotKey => $composableBuilder(
    column: $table.slotKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get activeSourceLineageId => $composableBuilder(
    column: $table.activeSourceLineageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ManagedSkillsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $ManagedSkillsTable> {
  $$ManagedSkillsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get slotKey =>
      $composableBuilder(column: $table.slotKey, builder: (column) => column);

  GeneratedColumn<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get activeSourceLineageId => $composableBuilder(
    column: $table.activeSourceLineageId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  Expression<T> sourceLineagesRefs<T extends Object>(
    Expression<T> Function($$SourceLineagesTableAnnotationComposer a) f,
  ) {
    final $$SourceLineagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableAnnotationComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> currentRevisionSelectionRefs<T extends Object>(
    Expression<T> Function($$CurrentRevisionSelectionTableAnnotationComposer a)
    f,
  ) {
    final $$CurrentRevisionSelectionTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.currentRevisionSelection,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$CurrentRevisionSelectionTableAnnotationComposer(
                $db: $db,
                $table: $db.currentRevisionSelection,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> draftWorkspacesRefs<T extends Object>(
    Expression<T> Function($$DraftWorkspacesTableAnnotationComposer a) f,
  ) {
    final $$DraftWorkspacesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.draftWorkspaces,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DraftWorkspacesTableAnnotationComposer(
            $db: $db,
            $table: $db.draftWorkspaces,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> updateCandidateSessionsRefs<T extends Object>(
    Expression<T> Function($$UpdateCandidateSessionsTableAnnotationComposer a)
    f,
  ) {
    final $$UpdateCandidateSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.updateCandidateSessions,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$UpdateCandidateSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.updateCandidateSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> activationLocationsRefs<T extends Object>(
    Expression<T> Function($$ActivationLocationsTableAnnotationComposer a) f,
  ) {
    final $$ActivationLocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.activationLocations,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivationLocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.activationLocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> skillUserDataRefs<T extends Object>(
    Expression<T> Function($$SkillUserDataTableAnnotationComposer a) f,
  ) {
    final $$SkillUserDataTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillUserData,
      getReferencedColumn: (t) => t.managedSkillId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillUserDataTableAnnotationComposer(
            $db: $db,
            $table: $db.skillUserData,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> skillUpdateCheckRecordsRefs<T extends Object>(
    Expression<T> Function($$SkillUpdateCheckRecordsTableAnnotationComposer a)
    f,
  ) {
    final $$SkillUpdateCheckRecordsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.skillUpdateCheckRecords,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SkillUpdateCheckRecordsTableAnnotationComposer(
                $db: $db,
                $table: $db.skillUpdateCheckRecords,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> skillTagAssignmentsRefs<T extends Object>(
    Expression<T> Function($$SkillTagAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$SkillTagAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.skillTagAssignments,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SkillTagAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.skillTagAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> operationSubjectsRefs<T extends Object>(
    Expression<T> Function($$OperationSubjectsTableAnnotationComposer a) f,
  ) {
    final $$OperationSubjectsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.operationSubjects,
          getReferencedColumn: (t) => t.managedSkillId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationSubjectsTableAnnotationComposer(
                $db: $db,
                $table: $db.operationSubjects,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$ManagedSkillsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $ManagedSkillsTable,
          ManagedSkill,
          $$ManagedSkillsTableFilterComposer,
          $$ManagedSkillsTableOrderingComposer,
          $$ManagedSkillsTableAnnotationComposer,
          $$ManagedSkillsTableCreateCompanionBuilder,
          $$ManagedSkillsTableUpdateCompanionBuilder,
          (ManagedSkill, $$ManagedSkillsTableReferences),
          ManagedSkill,
          PrefetchHooks Function({
            bool sourceLineagesRefs,
            bool currentRevisionSelectionRefs,
            bool draftWorkspacesRefs,
            bool updateCandidateSessionsRefs,
            bool activationLocationsRefs,
            bool skillUserDataRefs,
            bool skillUpdateCheckRecordsRefs,
            bool skillTagAssignmentsRefs,
            bool operationSubjectsRefs,
          })
        > {
  $$ManagedSkillsTableTableManager(
    _$WorkspaceDatabase db,
    $ManagedSkillsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ManagedSkillsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ManagedSkillsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ManagedSkillsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> slotKey = const Value.absent(),
                Value<String> declaredName = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> activeSourceLineageId = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ManagedSkillsCompanion(
                id: id,
                slotKey: slotKey,
                declaredName: declaredName,
                displayName: displayName,
                description: description,
                activeSourceLineageId: activeSourceLineageId,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String slotKey,
                required String declaredName,
                required String displayName,
                required String description,
                required String activeSourceLineageId,
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ManagedSkillsCompanion.insert(
                id: id,
                slotKey: slotKey,
                declaredName: declaredName,
                displayName: displayName,
                description: description,
                activeSourceLineageId: activeSourceLineageId,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ManagedSkillsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sourceLineagesRefs = false,
                currentRevisionSelectionRefs = false,
                draftWorkspacesRefs = false,
                updateCandidateSessionsRefs = false,
                activationLocationsRefs = false,
                skillUserDataRefs = false,
                skillUpdateCheckRecordsRefs = false,
                skillTagAssignmentsRefs = false,
                operationSubjectsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sourceLineagesRefs) db.sourceLineages,
                    if (currentRevisionSelectionRefs)
                      db.currentRevisionSelection,
                    if (draftWorkspacesRefs) db.draftWorkspaces,
                    if (updateCandidateSessionsRefs) db.updateCandidateSessions,
                    if (activationLocationsRefs) db.activationLocations,
                    if (skillUserDataRefs) db.skillUserData,
                    if (skillUpdateCheckRecordsRefs) db.skillUpdateCheckRecords,
                    if (skillTagAssignmentsRefs) db.skillTagAssignments,
                    if (operationSubjectsRefs) db.operationSubjects,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sourceLineagesRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          SourceLineage
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._sourceLineagesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).sourceLineagesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (currentRevisionSelectionRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          CurrentRevisionSelectionData
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._currentRevisionSelectionRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).currentRevisionSelectionRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (draftWorkspacesRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          DraftWorkspace
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._draftWorkspacesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).draftWorkspacesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (updateCandidateSessionsRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          UpdateCandidateSession
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._updateCandidateSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).updateCandidateSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (activationLocationsRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          ActivationLocation
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._activationLocationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).activationLocationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (skillUserDataRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          SkillUserDataData
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._skillUserDataRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).skillUserDataRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (skillUpdateCheckRecordsRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          SkillUpdateCheckRecord
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._skillUpdateCheckRecordsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).skillUpdateCheckRecordsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (skillTagAssignmentsRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          SkillTagAssignment
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._skillTagAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).skillTagAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (operationSubjectsRefs)
                        await $_getPrefetchedData<
                          ManagedSkill,
                          $ManagedSkillsTable,
                          OperationSubject
                        >(
                          currentTable: table,
                          referencedTable: $$ManagedSkillsTableReferences
                              ._operationSubjectsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ManagedSkillsTableReferences(
                                db,
                                table,
                                p0,
                              ).operationSubjectsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.managedSkillId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ManagedSkillsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $ManagedSkillsTable,
      ManagedSkill,
      $$ManagedSkillsTableFilterComposer,
      $$ManagedSkillsTableOrderingComposer,
      $$ManagedSkillsTableAnnotationComposer,
      $$ManagedSkillsTableCreateCompanionBuilder,
      $$ManagedSkillsTableUpdateCompanionBuilder,
      (ManagedSkill, $$ManagedSkillsTableReferences),
      ManagedSkill,
      PrefetchHooks Function({
        bool sourceLineagesRefs,
        bool currentRevisionSelectionRefs,
        bool draftWorkspacesRefs,
        bool updateCandidateSessionsRefs,
        bool activationLocationsRefs,
        bool skillUserDataRefs,
        bool skillUpdateCheckRecordsRefs,
        bool skillTagAssignmentsRefs,
        bool operationSubjectsRefs,
      })
    >;
typedef $$SkillSourcesTableCreateCompanionBuilder =
    SkillSourcesCompanion Function({
      required String sourceLineageId,
      required String kind,
      required int payloadSchemaVersion,
      required String payloadJson,
      Value<int> rowid,
    });
typedef $$SkillSourcesTableUpdateCompanionBuilder =
    SkillSourcesCompanion Function({
      Value<String> sourceLineageId,
      Value<String> kind,
      Value<int> payloadSchemaVersion,
      Value<String> payloadJson,
      Value<int> rowid,
    });

final class $$SkillSourcesTableReferences
    extends
        BaseReferences<_$WorkspaceDatabase, $SkillSourcesTable, SkillSource> {
  $$SkillSourcesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SourceLineagesTable _sourceLineageIdTable(_$WorkspaceDatabase db) =>
      db.sourceLineages.createAlias(
        'skill_sources__source_lineage_id__source_lineages__id',
      );

  $$SourceLineagesTableProcessedTableManager get sourceLineageId {
    final $_column = $_itemColumn<String>('source_lineage_id')!;

    final manager = $$SourceLineagesTableTableManager(
      $_db,
      $_db.sourceLineages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceLineageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SkillSourcesTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SkillSourcesTable> {
  $$SkillSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  $$SourceLineagesTableFilterComposer get sourceLineageId {
    final $$SourceLineagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableFilterComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillSourcesTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SkillSourcesTable> {
  $$SkillSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$SourceLineagesTableOrderingComposer get sourceLineageId {
    final $$SourceLineagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableOrderingComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillSourcesTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SkillSourcesTable> {
  $$SkillSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get payloadSchemaVersion => $composableBuilder(
    column: $table.payloadSchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  $$SourceLineagesTableAnnotationComposer get sourceLineageId {
    final $$SourceLineagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableAnnotationComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillSourcesTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SkillSourcesTable,
          SkillSource,
          $$SkillSourcesTableFilterComposer,
          $$SkillSourcesTableOrderingComposer,
          $$SkillSourcesTableAnnotationComposer,
          $$SkillSourcesTableCreateCompanionBuilder,
          $$SkillSourcesTableUpdateCompanionBuilder,
          (SkillSource, $$SkillSourcesTableReferences),
          SkillSource,
          PrefetchHooks Function({bool sourceLineageId})
        > {
  $$SkillSourcesTableTableManager(
    _$WorkspaceDatabase db,
    $SkillSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SkillSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SkillSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceLineageId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> payloadSchemaVersion = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillSourcesCompanion(
                sourceLineageId: sourceLineageId,
                kind: kind,
                payloadSchemaVersion: payloadSchemaVersion,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceLineageId,
                required String kind,
                required int payloadSchemaVersion,
                required String payloadJson,
                Value<int> rowid = const Value.absent(),
              }) => SkillSourcesCompanion.insert(
                sourceLineageId: sourceLineageId,
                kind: kind,
                payloadSchemaVersion: payloadSchemaVersion,
                payloadJson: payloadJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SkillSourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sourceLineageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sourceLineageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sourceLineageId,
                                referencedTable: $$SkillSourcesTableReferences
                                    ._sourceLineageIdTable(db),
                                referencedColumn: $$SkillSourcesTableReferences
                                    ._sourceLineageIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SkillSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SkillSourcesTable,
      SkillSource,
      $$SkillSourcesTableFilterComposer,
      $$SkillSourcesTableOrderingComposer,
      $$SkillSourcesTableAnnotationComposer,
      $$SkillSourcesTableCreateCompanionBuilder,
      $$SkillSourcesTableUpdateCompanionBuilder,
      (SkillSource, $$SkillSourcesTableReferences),
      SkillSource,
      PrefetchHooks Function({bool sourceLineageId})
    >;
typedef $$RevisionMetadataTableCreateCompanionBuilder =
    RevisionMetadataCompanion Function({
      required String sourceLineageId,
      required String objectId,
      required String contentHash,
      required int fileCount,
      required int byteSize,
      required String declaredName,
      required String validationState,
      Value<String?> validationCode,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$RevisionMetadataTableUpdateCompanionBuilder =
    RevisionMetadataCompanion Function({
      Value<String> sourceLineageId,
      Value<String> objectId,
      Value<String> contentHash,
      Value<int> fileCount,
      Value<int> byteSize,
      Value<String> declaredName,
      Value<String> validationState,
      Value<String?> validationCode,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$RevisionMetadataTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $RevisionMetadataTable,
          RevisionMetadataData
        > {
  $$RevisionMetadataTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SourceLineagesTable _sourceLineageIdTable(_$WorkspaceDatabase db) =>
      db.sourceLineages.createAlias(
        'revision_metadata__source_lineage_id__source_lineages__id',
      );

  $$SourceLineagesTableProcessedTableManager get sourceLineageId {
    final $_column = $_itemColumn<String>('source_lineage_id')!;

    final manager = $$SourceLineagesTableTableManager(
      $_db,
      $_db.sourceLineages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceLineageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RevisionMetadataTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $RevisionMetadataTable> {
  $$RevisionMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileCount => $composableBuilder(
    column: $table.fileCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get validationState => $composableBuilder(
    column: $table.validationState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$SourceLineagesTableFilterComposer get sourceLineageId {
    final $$SourceLineagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableFilterComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionMetadataTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $RevisionMetadataTable> {
  $$RevisionMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get objectId => $composableBuilder(
    column: $table.objectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileCount => $composableBuilder(
    column: $table.fileCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get validationState => $composableBuilder(
    column: $table.validationState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$SourceLineagesTableOrderingComposer get sourceLineageId {
    final $$SourceLineagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableOrderingComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionMetadataTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $RevisionMetadataTable> {
  $$RevisionMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get objectId =>
      $composableBuilder(column: $table.objectId, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileCount =>
      $composableBuilder(column: $table.fileCount, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<String> get declaredName => $composableBuilder(
    column: $table.declaredName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get validationState => $composableBuilder(
    column: $table.validationState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$SourceLineagesTableAnnotationComposer get sourceLineageId {
    final $$SourceLineagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableAnnotationComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RevisionMetadataTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $RevisionMetadataTable,
          RevisionMetadataData,
          $$RevisionMetadataTableFilterComposer,
          $$RevisionMetadataTableOrderingComposer,
          $$RevisionMetadataTableAnnotationComposer,
          $$RevisionMetadataTableCreateCompanionBuilder,
          $$RevisionMetadataTableUpdateCompanionBuilder,
          (RevisionMetadataData, $$RevisionMetadataTableReferences),
          RevisionMetadataData,
          PrefetchHooks Function({bool sourceLineageId})
        > {
  $$RevisionMetadataTableTableManager(
    _$WorkspaceDatabase db,
    $RevisionMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevisionMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevisionMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevisionMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sourceLineageId = const Value.absent(),
                Value<String> objectId = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<int> fileCount = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<String> declaredName = const Value.absent(),
                Value<String> validationState = const Value.absent(),
                Value<String?> validationCode = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevisionMetadataCompanion(
                sourceLineageId: sourceLineageId,
                objectId: objectId,
                contentHash: contentHash,
                fileCount: fileCount,
                byteSize: byteSize,
                declaredName: declaredName,
                validationState: validationState,
                validationCode: validationCode,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sourceLineageId,
                required String objectId,
                required String contentHash,
                required int fileCount,
                required int byteSize,
                required String declaredName,
                required String validationState,
                Value<String?> validationCode = const Value.absent(),
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => RevisionMetadataCompanion.insert(
                sourceLineageId: sourceLineageId,
                objectId: objectId,
                contentHash: contentHash,
                fileCount: fileCount,
                byteSize: byteSize,
                declaredName: declaredName,
                validationState: validationState,
                validationCode: validationCode,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RevisionMetadataTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sourceLineageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sourceLineageId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sourceLineageId,
                                referencedTable:
                                    $$RevisionMetadataTableReferences
                                        ._sourceLineageIdTable(db),
                                referencedColumn:
                                    $$RevisionMetadataTableReferences
                                        ._sourceLineageIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RevisionMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $RevisionMetadataTable,
      RevisionMetadataData,
      $$RevisionMetadataTableFilterComposer,
      $$RevisionMetadataTableOrderingComposer,
      $$RevisionMetadataTableAnnotationComposer,
      $$RevisionMetadataTableCreateCompanionBuilder,
      $$RevisionMetadataTableUpdateCompanionBuilder,
      (RevisionMetadataData, $$RevisionMetadataTableReferences),
      RevisionMetadataData,
      PrefetchHooks Function({bool sourceLineageId})
    >;
typedef $$CurrentRevisionSelectionTableCreateCompanionBuilder =
    CurrentRevisionSelectionCompanion Function({
      required String managedSkillId,
      required String sourceLineageId,
      required String upstreamObjectId,
      required String effectiveObjectId,
      Value<int> rowid,
    });
typedef $$CurrentRevisionSelectionTableUpdateCompanionBuilder =
    CurrentRevisionSelectionCompanion Function({
      Value<String> managedSkillId,
      Value<String> sourceLineageId,
      Value<String> upstreamObjectId,
      Value<String> effectiveObjectId,
      Value<int> rowid,
    });

final class $$CurrentRevisionSelectionTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $CurrentRevisionSelectionTable,
          CurrentRevisionSelectionData
        > {
  $$CurrentRevisionSelectionTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) =>
      db.managedSkills.createAlias(
        'current_revision_selection__managed_skill_id__managed_skills__id',
      );

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CurrentRevisionSelectionTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $CurrentRevisionSelectionTable> {
  $$CurrentRevisionSelectionTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get upstreamObjectId => $composableBuilder(
    column: $table.upstreamObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get effectiveObjectId => $composableBuilder(
    column: $table.effectiveObjectId,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CurrentRevisionSelectionTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $CurrentRevisionSelectionTable> {
  $$CurrentRevisionSelectionTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get upstreamObjectId => $composableBuilder(
    column: $table.upstreamObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get effectiveObjectId => $composableBuilder(
    column: $table.effectiveObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CurrentRevisionSelectionTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $CurrentRevisionSelectionTable> {
  $$CurrentRevisionSelectionTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get upstreamObjectId => $composableBuilder(
    column: $table.upstreamObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get effectiveObjectId => $composableBuilder(
    column: $table.effectiveObjectId,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CurrentRevisionSelectionTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $CurrentRevisionSelectionTable,
          CurrentRevisionSelectionData,
          $$CurrentRevisionSelectionTableFilterComposer,
          $$CurrentRevisionSelectionTableOrderingComposer,
          $$CurrentRevisionSelectionTableAnnotationComposer,
          $$CurrentRevisionSelectionTableCreateCompanionBuilder,
          $$CurrentRevisionSelectionTableUpdateCompanionBuilder,
          (
            CurrentRevisionSelectionData,
            $$CurrentRevisionSelectionTableReferences,
          ),
          CurrentRevisionSelectionData,
          PrefetchHooks Function({bool managedSkillId})
        > {
  $$CurrentRevisionSelectionTableTableManager(
    _$WorkspaceDatabase db,
    $CurrentRevisionSelectionTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CurrentRevisionSelectionTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CurrentRevisionSelectionTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CurrentRevisionSelectionTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> sourceLineageId = const Value.absent(),
                Value<String> upstreamObjectId = const Value.absent(),
                Value<String> effectiveObjectId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CurrentRevisionSelectionCompanion(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                upstreamObjectId: upstreamObjectId,
                effectiveObjectId: effectiveObjectId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String sourceLineageId,
                required String upstreamObjectId,
                required String effectiveObjectId,
                Value<int> rowid = const Value.absent(),
              }) => CurrentRevisionSelectionCompanion.insert(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                upstreamObjectId: upstreamObjectId,
                effectiveObjectId: effectiveObjectId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CurrentRevisionSelectionTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({managedSkillId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (managedSkillId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.managedSkillId,
                                referencedTable:
                                    $$CurrentRevisionSelectionTableReferences
                                        ._managedSkillIdTable(db),
                                referencedColumn:
                                    $$CurrentRevisionSelectionTableReferences
                                        ._managedSkillIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CurrentRevisionSelectionTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $CurrentRevisionSelectionTable,
      CurrentRevisionSelectionData,
      $$CurrentRevisionSelectionTableFilterComposer,
      $$CurrentRevisionSelectionTableOrderingComposer,
      $$CurrentRevisionSelectionTableAnnotationComposer,
      $$CurrentRevisionSelectionTableCreateCompanionBuilder,
      $$CurrentRevisionSelectionTableUpdateCompanionBuilder,
      (CurrentRevisionSelectionData, $$CurrentRevisionSelectionTableReferences),
      CurrentRevisionSelectionData,
      PrefetchHooks Function({bool managedSkillId})
    >;
typedef $$DraftWorkspacesTableCreateCompanionBuilder =
    DraftWorkspacesCompanion Function({
      required String managedSkillId,
      required String sourceLineageId,
      required String baseObjectId,
      required String purpose,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$DraftWorkspacesTableUpdateCompanionBuilder =
    DraftWorkspacesCompanion Function({
      Value<String> managedSkillId,
      Value<String> sourceLineageId,
      Value<String> baseObjectId,
      Value<String> purpose,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$DraftWorkspacesTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $DraftWorkspacesTable,
          DraftWorkspace
        > {
  $$DraftWorkspacesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) => db
      .managedSkills
      .createAlias('draft_workspaces__managed_skill_id__managed_skills__id');

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DraftWorkspacesTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $DraftWorkspacesTable> {
  $$DraftWorkspacesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DraftWorkspacesTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $DraftWorkspacesTable> {
  $$DraftWorkspacesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get purpose => $composableBuilder(
    column: $table.purpose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DraftWorkspacesTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $DraftWorkspacesTable> {
  $$DraftWorkspacesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get purpose =>
      $composableBuilder(column: $table.purpose, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DraftWorkspacesTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $DraftWorkspacesTable,
          DraftWorkspace,
          $$DraftWorkspacesTableFilterComposer,
          $$DraftWorkspacesTableOrderingComposer,
          $$DraftWorkspacesTableAnnotationComposer,
          $$DraftWorkspacesTableCreateCompanionBuilder,
          $$DraftWorkspacesTableUpdateCompanionBuilder,
          (DraftWorkspace, $$DraftWorkspacesTableReferences),
          DraftWorkspace,
          PrefetchHooks Function({bool managedSkillId})
        > {
  $$DraftWorkspacesTableTableManager(
    _$WorkspaceDatabase db,
    $DraftWorkspacesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftWorkspacesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftWorkspacesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftWorkspacesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> sourceLineageId = const Value.absent(),
                Value<String> baseObjectId = const Value.absent(),
                Value<String> purpose = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftWorkspacesCompanion(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                baseObjectId: baseObjectId,
                purpose: purpose,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String sourceLineageId,
                required String baseObjectId,
                required String purpose,
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => DraftWorkspacesCompanion.insert(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                baseObjectId: baseObjectId,
                purpose: purpose,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DraftWorkspacesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({managedSkillId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (managedSkillId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.managedSkillId,
                                referencedTable:
                                    $$DraftWorkspacesTableReferences
                                        ._managedSkillIdTable(db),
                                referencedColumn:
                                    $$DraftWorkspacesTableReferences
                                        ._managedSkillIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DraftWorkspacesTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $DraftWorkspacesTable,
      DraftWorkspace,
      $$DraftWorkspacesTableFilterComposer,
      $$DraftWorkspacesTableOrderingComposer,
      $$DraftWorkspacesTableAnnotationComposer,
      $$DraftWorkspacesTableCreateCompanionBuilder,
      $$DraftWorkspacesTableUpdateCompanionBuilder,
      (DraftWorkspace, $$DraftWorkspacesTableReferences),
      DraftWorkspace,
      PrefetchHooks Function({bool managedSkillId})
    >;
typedef $$UpdateCandidateSessionsTableCreateCompanionBuilder =
    UpdateCandidateSessionsCompanion Function({
      required String managedSkillId,
      required String sourceLineageId,
      required String previousUpstreamObjectId,
      required String previousEffectiveObjectId,
      required String incomingUpstreamObjectId,
      required String candidateObjectId,
      required String status,
      Value<String?> validationCode,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$UpdateCandidateSessionsTableUpdateCompanionBuilder =
    UpdateCandidateSessionsCompanion Function({
      Value<String> managedSkillId,
      Value<String> sourceLineageId,
      Value<String> previousUpstreamObjectId,
      Value<String> previousEffectiveObjectId,
      Value<String> incomingUpstreamObjectId,
      Value<String> candidateObjectId,
      Value<String> status,
      Value<String?> validationCode,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$UpdateCandidateSessionsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $UpdateCandidateSessionsTable,
          UpdateCandidateSession
        > {
  $$UpdateCandidateSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) =>
      db.managedSkills.createAlias(
        'update_candidate_sessions__managed_skill_id__managed_skills__id',
      );

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$UpdateCandidateSessionsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateSessionsTable> {
  $$UpdateCandidateSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousUpstreamObjectId => $composableBuilder(
    column: $table.previousUpstreamObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get previousEffectiveObjectId => $composableBuilder(
    column: $table.previousEffectiveObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incomingUpstreamObjectId => $composableBuilder(
    column: $table.incomingUpstreamObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get candidateObjectId => $composableBuilder(
    column: $table.candidateObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UpdateCandidateSessionsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateSessionsTable> {
  $$UpdateCandidateSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousUpstreamObjectId => $composableBuilder(
    column: $table.previousUpstreamObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get previousEffectiveObjectId => $composableBuilder(
    column: $table.previousEffectiveObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incomingUpstreamObjectId => $composableBuilder(
    column: $table.incomingUpstreamObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get candidateObjectId => $composableBuilder(
    column: $table.candidateObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UpdateCandidateSessionsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateSessionsTable> {
  $$UpdateCandidateSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sourceLineageId => $composableBuilder(
    column: $table.sourceLineageId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousUpstreamObjectId => $composableBuilder(
    column: $table.previousUpstreamObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get previousEffectiveObjectId => $composableBuilder(
    column: $table.previousEffectiveObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get incomingUpstreamObjectId => $composableBuilder(
    column: $table.incomingUpstreamObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get candidateObjectId => $composableBuilder(
    column: $table.candidateObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get validationCode => $composableBuilder(
    column: $table.validationCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$UpdateCandidateSessionsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $UpdateCandidateSessionsTable,
          UpdateCandidateSession,
          $$UpdateCandidateSessionsTableFilterComposer,
          $$UpdateCandidateSessionsTableOrderingComposer,
          $$UpdateCandidateSessionsTableAnnotationComposer,
          $$UpdateCandidateSessionsTableCreateCompanionBuilder,
          $$UpdateCandidateSessionsTableUpdateCompanionBuilder,
          (UpdateCandidateSession, $$UpdateCandidateSessionsTableReferences),
          UpdateCandidateSession,
          PrefetchHooks Function({bool managedSkillId})
        > {
  $$UpdateCandidateSessionsTableTableManager(
    _$WorkspaceDatabase db,
    $UpdateCandidateSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UpdateCandidateSessionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$UpdateCandidateSessionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UpdateCandidateSessionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> sourceLineageId = const Value.absent(),
                Value<String> previousUpstreamObjectId = const Value.absent(),
                Value<String> previousEffectiveObjectId = const Value.absent(),
                Value<String> incomingUpstreamObjectId = const Value.absent(),
                Value<String> candidateObjectId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> validationCode = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UpdateCandidateSessionsCompanion(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                previousUpstreamObjectId: previousUpstreamObjectId,
                previousEffectiveObjectId: previousEffectiveObjectId,
                incomingUpstreamObjectId: incomingUpstreamObjectId,
                candidateObjectId: candidateObjectId,
                status: status,
                validationCode: validationCode,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String sourceLineageId,
                required String previousUpstreamObjectId,
                required String previousEffectiveObjectId,
                required String incomingUpstreamObjectId,
                required String candidateObjectId,
                required String status,
                Value<String?> validationCode = const Value.absent(),
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => UpdateCandidateSessionsCompanion.insert(
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                previousUpstreamObjectId: previousUpstreamObjectId,
                previousEffectiveObjectId: previousEffectiveObjectId,
                incomingUpstreamObjectId: incomingUpstreamObjectId,
                candidateObjectId: candidateObjectId,
                status: status,
                validationCode: validationCode,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$UpdateCandidateSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({managedSkillId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (managedSkillId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.managedSkillId,
                                referencedTable:
                                    $$UpdateCandidateSessionsTableReferences
                                        ._managedSkillIdTable(db),
                                referencedColumn:
                                    $$UpdateCandidateSessionsTableReferences
                                        ._managedSkillIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$UpdateCandidateSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $UpdateCandidateSessionsTable,
      UpdateCandidateSession,
      $$UpdateCandidateSessionsTableFilterComposer,
      $$UpdateCandidateSessionsTableOrderingComposer,
      $$UpdateCandidateSessionsTableAnnotationComposer,
      $$UpdateCandidateSessionsTableCreateCompanionBuilder,
      $$UpdateCandidateSessionsTableUpdateCompanionBuilder,
      (UpdateCandidateSession, $$UpdateCandidateSessionsTableReferences),
      UpdateCandidateSession,
      PrefetchHooks Function({bool managedSkillId})
    >;
typedef $$UpdateCandidateItemsTableCreateCompanionBuilder =
    UpdateCandidateItemsCompanion Function({
      required String managedSkillId,
      required String path,
      required String kind,
      required String state,
      Value<String?> baseObjectId,
      Value<String?> oursObjectId,
      Value<String?> theirsObjectId,
      Value<int> rowid,
    });
typedef $$UpdateCandidateItemsTableUpdateCompanionBuilder =
    UpdateCandidateItemsCompanion Function({
      Value<String> managedSkillId,
      Value<String> path,
      Value<String> kind,
      Value<String> state,
      Value<String?> baseObjectId,
      Value<String?> oursObjectId,
      Value<String?> theirsObjectId,
      Value<int> rowid,
    });

class $$UpdateCandidateItemsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateItemsTable> {
  $$UpdateCandidateItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get managedSkillId => $composableBuilder(
    column: $table.managedSkillId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oursObjectId => $composableBuilder(
    column: $table.oursObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get theirsObjectId => $composableBuilder(
    column: $table.theirsObjectId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UpdateCandidateItemsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateItemsTable> {
  $$UpdateCandidateItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get managedSkillId => $composableBuilder(
    column: $table.managedSkillId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oursObjectId => $composableBuilder(
    column: $table.oursObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get theirsObjectId => $composableBuilder(
    column: $table.theirsObjectId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UpdateCandidateItemsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $UpdateCandidateItemsTable> {
  $$UpdateCandidateItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get managedSkillId => $composableBuilder(
    column: $table.managedSkillId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get baseObjectId => $composableBuilder(
    column: $table.baseObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get oursObjectId => $composableBuilder(
    column: $table.oursObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get theirsObjectId => $composableBuilder(
    column: $table.theirsObjectId,
    builder: (column) => column,
  );
}

class $$UpdateCandidateItemsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $UpdateCandidateItemsTable,
          UpdateCandidateItem,
          $$UpdateCandidateItemsTableFilterComposer,
          $$UpdateCandidateItemsTableOrderingComposer,
          $$UpdateCandidateItemsTableAnnotationComposer,
          $$UpdateCandidateItemsTableCreateCompanionBuilder,
          $$UpdateCandidateItemsTableUpdateCompanionBuilder,
          (
            UpdateCandidateItem,
            BaseReferences<
              _$WorkspaceDatabase,
              $UpdateCandidateItemsTable,
              UpdateCandidateItem
            >,
          ),
          UpdateCandidateItem,
          PrefetchHooks Function()
        > {
  $$UpdateCandidateItemsTableTableManager(
    _$WorkspaceDatabase db,
    $UpdateCandidateItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UpdateCandidateItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UpdateCandidateItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UpdateCandidateItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> baseObjectId = const Value.absent(),
                Value<String?> oursObjectId = const Value.absent(),
                Value<String?> theirsObjectId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UpdateCandidateItemsCompanion(
                managedSkillId: managedSkillId,
                path: path,
                kind: kind,
                state: state,
                baseObjectId: baseObjectId,
                oursObjectId: oursObjectId,
                theirsObjectId: theirsObjectId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String path,
                required String kind,
                required String state,
                Value<String?> baseObjectId = const Value.absent(),
                Value<String?> oursObjectId = const Value.absent(),
                Value<String?> theirsObjectId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UpdateCandidateItemsCompanion.insert(
                managedSkillId: managedSkillId,
                path: path,
                kind: kind,
                state: state,
                baseObjectId: baseObjectId,
                oursObjectId: oursObjectId,
                theirsObjectId: theirsObjectId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UpdateCandidateItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $UpdateCandidateItemsTable,
      UpdateCandidateItem,
      $$UpdateCandidateItemsTableFilterComposer,
      $$UpdateCandidateItemsTableOrderingComposer,
      $$UpdateCandidateItemsTableAnnotationComposer,
      $$UpdateCandidateItemsTableCreateCompanionBuilder,
      $$UpdateCandidateItemsTableUpdateCompanionBuilder,
      (
        UpdateCandidateItem,
        BaseReferences<
          _$WorkspaceDatabase,
          $UpdateCandidateItemsTable,
          UpdateCandidateItem
        >,
      ),
      UpdateCandidateItem,
      PrefetchHooks Function()
    >;
typedef $$ProjectRootsTableCreateCompanionBuilder =
    ProjectRootsCompanion Function({
      required String id,
      required String canonicalPath,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$ProjectRootsTableUpdateCompanionBuilder =
    ProjectRootsCompanion Function({
      Value<String> id,
      Value<String> canonicalPath,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

class $$ProjectRootsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $ProjectRootsTable> {
  $$ProjectRootsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectRootsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $ProjectRootsTable> {
  $$ProjectRootsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectRootsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $ProjectRootsTable> {
  $$ProjectRootsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );
}

class $$ProjectRootsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $ProjectRootsTable,
          ProjectRoot,
          $$ProjectRootsTableFilterComposer,
          $$ProjectRootsTableOrderingComposer,
          $$ProjectRootsTableAnnotationComposer,
          $$ProjectRootsTableCreateCompanionBuilder,
          $$ProjectRootsTableUpdateCompanionBuilder,
          (
            ProjectRoot,
            BaseReferences<
              _$WorkspaceDatabase,
              $ProjectRootsTable,
              ProjectRoot
            >,
          ),
          ProjectRoot,
          PrefetchHooks Function()
        > {
  $$ProjectRootsTableTableManager(
    _$WorkspaceDatabase db,
    $ProjectRootsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectRootsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectRootsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectRootsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> canonicalPath = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectRootsCompanion(
                id: id,
                canonicalPath: canonicalPath,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String canonicalPath,
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ProjectRootsCompanion.insert(
                id: id,
                canonicalPath: canonicalPath,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectRootsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $ProjectRootsTable,
      ProjectRoot,
      $$ProjectRootsTableFilterComposer,
      $$ProjectRootsTableOrderingComposer,
      $$ProjectRootsTableAnnotationComposer,
      $$ProjectRootsTableCreateCompanionBuilder,
      $$ProjectRootsTableUpdateCompanionBuilder,
      (
        ProjectRoot,
        BaseReferences<_$WorkspaceDatabase, $ProjectRootsTable, ProjectRoot>,
      ),
      ProjectRoot,
      PrefetchHooks Function()
    >;
typedef $$ActivationLocationsTableCreateCompanionBuilder =
    ActivationLocationsCompanion Function({
      required String id,
      required String managedSkillId,
      required String canonicalPath,
      required String scope,
      required String mode,
      Value<String?> projectRootId,
      Value<String?> projectRootPath,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$ActivationLocationsTableUpdateCompanionBuilder =
    ActivationLocationsCompanion Function({
      Value<String> id,
      Value<String> managedSkillId,
      Value<String> canonicalPath,
      Value<String> scope,
      Value<String> mode,
      Value<String?> projectRootId,
      Value<String?> projectRootPath,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$ActivationLocationsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $ActivationLocationsTable,
          ActivationLocation
        > {
  $$ActivationLocationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) =>
      db.managedSkills.createAlias(
        'activation_locations__managed_skill_id__managed_skills__id',
      );

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$ActivationAgentsTable, List<ActivationAgent>>
  _activationAgentsRefsTable(
    _$WorkspaceDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.activationAgents,
    aliasName:
        'activation_locations__id__activation_agents__activation_location_id',
  );

  $$ActivationAgentsTableProcessedTableManager get activationAgentsRefs {
    final manager =
        $$ActivationAgentsTableTableManager($_db, $_db.activationAgents).filter(
          (f) =>
              f.activationLocationId.id.sqlEquals($_itemColumn<String>('id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _activationAgentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ActivationLocationsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $ActivationLocationsTable> {
  $$ActivationLocationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectRootId => $composableBuilder(
    column: $table.projectRootId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectRootPath => $composableBuilder(
    column: $table.projectRootPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> activationAgentsRefs(
    Expression<bool> Function($$ActivationAgentsTableFilterComposer f) f,
  ) {
    final $$ActivationAgentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activationAgents,
      getReferencedColumn: (t) => t.activationLocationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivationAgentsTableFilterComposer(
            $db: $db,
            $table: $db.activationAgents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivationLocationsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $ActivationLocationsTable> {
  $$ActivationLocationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectRootId => $composableBuilder(
    column: $table.projectRootId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectRootPath => $composableBuilder(
    column: $table.projectRootPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivationLocationsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $ActivationLocationsTable> {
  $$ActivationLocationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get canonicalPath => $composableBuilder(
    column: $table.canonicalPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get projectRootId => $composableBuilder(
    column: $table.projectRootId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectRootPath => $composableBuilder(
    column: $table.projectRootPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> activationAgentsRefs<T extends Object>(
    Expression<T> Function($$ActivationAgentsTableAnnotationComposer a) f,
  ) {
    final $$ActivationAgentsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.activationAgents,
      getReferencedColumn: (t) => t.activationLocationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivationAgentsTableAnnotationComposer(
            $db: $db,
            $table: $db.activationAgents,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ActivationLocationsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $ActivationLocationsTable,
          ActivationLocation,
          $$ActivationLocationsTableFilterComposer,
          $$ActivationLocationsTableOrderingComposer,
          $$ActivationLocationsTableAnnotationComposer,
          $$ActivationLocationsTableCreateCompanionBuilder,
          $$ActivationLocationsTableUpdateCompanionBuilder,
          (ActivationLocation, $$ActivationLocationsTableReferences),
          ActivationLocation,
          PrefetchHooks Function({
            bool managedSkillId,
            bool activationAgentsRefs,
          })
        > {
  $$ActivationLocationsTableTableManager(
    _$WorkspaceDatabase db,
    $ActivationLocationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivationLocationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivationLocationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ActivationLocationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> managedSkillId = const Value.absent(),
                Value<String> canonicalPath = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String?> projectRootId = const Value.absent(),
                Value<String?> projectRootPath = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivationLocationsCompanion(
                id: id,
                managedSkillId: managedSkillId,
                canonicalPath: canonicalPath,
                scope: scope,
                mode: mode,
                projectRootId: projectRootId,
                projectRootPath: projectRootPath,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String managedSkillId,
                required String canonicalPath,
                required String scope,
                required String mode,
                Value<String?> projectRootId = const Value.absent(),
                Value<String?> projectRootPath = const Value.absent(),
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => ActivationLocationsCompanion.insert(
                id: id,
                managedSkillId: managedSkillId,
                canonicalPath: canonicalPath,
                scope: scope,
                mode: mode,
                projectRootId: projectRootId,
                projectRootPath: projectRootPath,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivationLocationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({managedSkillId = false, activationAgentsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (activationAgentsRefs) db.activationAgents,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (managedSkillId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.managedSkillId,
                                    referencedTable:
                                        $$ActivationLocationsTableReferences
                                            ._managedSkillIdTable(db),
                                    referencedColumn:
                                        $$ActivationLocationsTableReferences
                                            ._managedSkillIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (activationAgentsRefs)
                        await $_getPrefetchedData<
                          ActivationLocation,
                          $ActivationLocationsTable,
                          ActivationAgent
                        >(
                          currentTable: table,
                          referencedTable: $$ActivationLocationsTableReferences
                              ._activationAgentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ActivationLocationsTableReferences(
                                db,
                                table,
                                p0,
                              ).activationAgentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.activationLocationId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ActivationLocationsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $ActivationLocationsTable,
      ActivationLocation,
      $$ActivationLocationsTableFilterComposer,
      $$ActivationLocationsTableOrderingComposer,
      $$ActivationLocationsTableAnnotationComposer,
      $$ActivationLocationsTableCreateCompanionBuilder,
      $$ActivationLocationsTableUpdateCompanionBuilder,
      (ActivationLocation, $$ActivationLocationsTableReferences),
      ActivationLocation,
      PrefetchHooks Function({bool managedSkillId, bool activationAgentsRefs})
    >;
typedef $$ActivationAgentsTableCreateCompanionBuilder =
    ActivationAgentsCompanion Function({
      required String activationLocationId,
      required String agentId,
      Value<int> rowid,
    });
typedef $$ActivationAgentsTableUpdateCompanionBuilder =
    ActivationAgentsCompanion Function({
      Value<String> activationLocationId,
      Value<String> agentId,
      Value<int> rowid,
    });

final class $$ActivationAgentsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $ActivationAgentsTable,
          ActivationAgent
        > {
  $$ActivationAgentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ActivationLocationsTable _activationLocationIdTable(
    _$WorkspaceDatabase db,
  ) => db.activationLocations.createAlias(
    'activation_agents__activation_location_id__activation_locations__id',
  );

  $$ActivationLocationsTableProcessedTableManager get activationLocationId {
    final $_column = $_itemColumn<String>('activation_location_id')!;

    final manager = $$ActivationLocationsTableTableManager(
      $_db,
      $_db.activationLocations,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _activationLocationIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ActivationAgentsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $ActivationAgentsTable> {
  $$ActivationAgentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnFilters(column),
  );

  $$ActivationLocationsTableFilterComposer get activationLocationId {
    final $$ActivationLocationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.activationLocationId,
      referencedTable: $db.activationLocations,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ActivationLocationsTableFilterComposer(
            $db: $db,
            $table: $db.activationLocations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ActivationAgentsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $ActivationAgentsTable> {
  $$ActivationAgentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get agentId => $composableBuilder(
    column: $table.agentId,
    builder: (column) => ColumnOrderings(column),
  );

  $$ActivationLocationsTableOrderingComposer get activationLocationId {
    final $$ActivationLocationsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.activationLocationId,
          referencedTable: $db.activationLocations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivationLocationsTableOrderingComposer(
                $db: $db,
                $table: $db.activationLocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ActivationAgentsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $ActivationAgentsTable> {
  $$ActivationAgentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get agentId =>
      $composableBuilder(column: $table.agentId, builder: (column) => column);

  $$ActivationLocationsTableAnnotationComposer get activationLocationId {
    final $$ActivationLocationsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.activationLocationId,
          referencedTable: $db.activationLocations,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ActivationLocationsTableAnnotationComposer(
                $db: $db,
                $table: $db.activationLocations,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$ActivationAgentsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $ActivationAgentsTable,
          ActivationAgent,
          $$ActivationAgentsTableFilterComposer,
          $$ActivationAgentsTableOrderingComposer,
          $$ActivationAgentsTableAnnotationComposer,
          $$ActivationAgentsTableCreateCompanionBuilder,
          $$ActivationAgentsTableUpdateCompanionBuilder,
          (ActivationAgent, $$ActivationAgentsTableReferences),
          ActivationAgent,
          PrefetchHooks Function({bool activationLocationId})
        > {
  $$ActivationAgentsTableTableManager(
    _$WorkspaceDatabase db,
    $ActivationAgentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActivationAgentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActivationAgentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActivationAgentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> activationLocationId = const Value.absent(),
                Value<String> agentId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ActivationAgentsCompanion(
                activationLocationId: activationLocationId,
                agentId: agentId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String activationLocationId,
                required String agentId,
                Value<int> rowid = const Value.absent(),
              }) => ActivationAgentsCompanion.insert(
                activationLocationId: activationLocationId,
                agentId: agentId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ActivationAgentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({activationLocationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (activationLocationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.activationLocationId,
                                referencedTable:
                                    $$ActivationAgentsTableReferences
                                        ._activationLocationIdTable(db),
                                referencedColumn:
                                    $$ActivationAgentsTableReferences
                                        ._activationLocationIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ActivationAgentsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $ActivationAgentsTable,
      ActivationAgent,
      $$ActivationAgentsTableFilterComposer,
      $$ActivationAgentsTableOrderingComposer,
      $$ActivationAgentsTableAnnotationComposer,
      $$ActivationAgentsTableCreateCompanionBuilder,
      $$ActivationAgentsTableUpdateCompanionBuilder,
      (ActivationAgent, $$ActivationAgentsTableReferences),
      ActivationAgent,
      PrefetchHooks Function({bool activationLocationId})
    >;
typedef $$SkillUserDataTableCreateCompanionBuilder =
    SkillUserDataCompanion Function({
      required String managedSkillId,
      Value<bool> favorite,
      Value<int?> favoriteChangedAtMicros,
      Value<String?> note,
      Value<int?> noteUpdatedAtMicros,
      Value<int> rowid,
    });
typedef $$SkillUserDataTableUpdateCompanionBuilder =
    SkillUserDataCompanion Function({
      Value<String> managedSkillId,
      Value<bool> favorite,
      Value<int?> favoriteChangedAtMicros,
      Value<String?> note,
      Value<int?> noteUpdatedAtMicros,
      Value<int> rowid,
    });

final class $$SkillUserDataTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $SkillUserDataTable,
          SkillUserDataData
        > {
  $$SkillUserDataTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) => db
      .managedSkills
      .createAlias('skill_user_data__managed_skill_id__managed_skills__id');

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SkillUserDataTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SkillUserDataTable> {
  $$SkillUserDataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favoriteChangedAtMicros => $composableBuilder(
    column: $table.favoriteChangedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get noteUpdatedAtMicros => $composableBuilder(
    column: $table.noteUpdatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUserDataTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SkillUserDataTable> {
  $$SkillUserDataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favoriteChangedAtMicros => $composableBuilder(
    column: $table.favoriteChangedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get noteUpdatedAtMicros => $composableBuilder(
    column: $table.noteUpdatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUserDataTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SkillUserDataTable> {
  $$SkillUserDataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<int> get favoriteChangedAtMicros => $composableBuilder(
    column: $table.favoriteChangedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get noteUpdatedAtMicros => $composableBuilder(
    column: $table.noteUpdatedAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUserDataTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SkillUserDataTable,
          SkillUserDataData,
          $$SkillUserDataTableFilterComposer,
          $$SkillUserDataTableOrderingComposer,
          $$SkillUserDataTableAnnotationComposer,
          $$SkillUserDataTableCreateCompanionBuilder,
          $$SkillUserDataTableUpdateCompanionBuilder,
          (SkillUserDataData, $$SkillUserDataTableReferences),
          SkillUserDataData,
          PrefetchHooks Function({bool managedSkillId})
        > {
  $$SkillUserDataTableTableManager(
    _$WorkspaceDatabase db,
    $SkillUserDataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillUserDataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SkillUserDataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SkillUserDataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<int?> favoriteChangedAtMicros = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> noteUpdatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillUserDataCompanion(
                managedSkillId: managedSkillId,
                favorite: favorite,
                favoriteChangedAtMicros: favoriteChangedAtMicros,
                note: note,
                noteUpdatedAtMicros: noteUpdatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                Value<bool> favorite = const Value.absent(),
                Value<int?> favoriteChangedAtMicros = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> noteUpdatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillUserDataCompanion.insert(
                managedSkillId: managedSkillId,
                favorite: favorite,
                favoriteChangedAtMicros: favoriteChangedAtMicros,
                note: note,
                noteUpdatedAtMicros: noteUpdatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SkillUserDataTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({managedSkillId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (managedSkillId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.managedSkillId,
                                referencedTable: $$SkillUserDataTableReferences
                                    ._managedSkillIdTable(db),
                                referencedColumn: $$SkillUserDataTableReferences
                                    ._managedSkillIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SkillUserDataTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SkillUserDataTable,
      SkillUserDataData,
      $$SkillUserDataTableFilterComposer,
      $$SkillUserDataTableOrderingComposer,
      $$SkillUserDataTableAnnotationComposer,
      $$SkillUserDataTableCreateCompanionBuilder,
      $$SkillUserDataTableUpdateCompanionBuilder,
      (SkillUserDataData, $$SkillUserDataTableReferences),
      SkillUserDataData,
      PrefetchHooks Function({bool managedSkillId})
    >;
typedef $$SkillUpdateCheckRecordsTableCreateCompanionBuilder =
    SkillUpdateCheckRecordsCompanion Function({
      required String managedSkillId,
      required String basisFingerprint,
      required String status,
      Value<String?> currentContentHash,
      Value<String?> availableContentHash,
      Value<String?> resolvedSourceRevision,
      required int checkedAtMicros,
      Value<int> rowid,
    });
typedef $$SkillUpdateCheckRecordsTableUpdateCompanionBuilder =
    SkillUpdateCheckRecordsCompanion Function({
      Value<String> managedSkillId,
      Value<String> basisFingerprint,
      Value<String> status,
      Value<String?> currentContentHash,
      Value<String?> availableContentHash,
      Value<String?> resolvedSourceRevision,
      Value<int> checkedAtMicros,
      Value<int> rowid,
    });

final class $$SkillUpdateCheckRecordsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $SkillUpdateCheckRecordsTable,
          SkillUpdateCheckRecord
        > {
  $$SkillUpdateCheckRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) =>
      db.managedSkills.createAlias(
        'skill_update_check_records__managed_skill_id__managed_skills__id',
      );

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SkillUpdateCheckRecordsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckRecordsTable> {
  $$SkillUpdateCheckRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get basisFingerprint => $composableBuilder(
    column: $table.basisFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentContentHash => $composableBuilder(
    column: $table.currentContentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get availableContentHash => $composableBuilder(
    column: $table.availableContentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolvedSourceRevision => $composableBuilder(
    column: $table.resolvedSourceRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get checkedAtMicros => $composableBuilder(
    column: $table.checkedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUpdateCheckRecordsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckRecordsTable> {
  $$SkillUpdateCheckRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get basisFingerprint => $composableBuilder(
    column: $table.basisFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentContentHash => $composableBuilder(
    column: $table.currentContentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get availableContentHash => $composableBuilder(
    column: $table.availableContentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolvedSourceRevision => $composableBuilder(
    column: $table.resolvedSourceRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get checkedAtMicros => $composableBuilder(
    column: $table.checkedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUpdateCheckRecordsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckRecordsTable> {
  $$SkillUpdateCheckRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get basisFingerprint => $composableBuilder(
    column: $table.basisFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get currentContentHash => $composableBuilder(
    column: $table.currentContentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get availableContentHash => $composableBuilder(
    column: $table.availableContentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resolvedSourceRevision => $composableBuilder(
    column: $table.resolvedSourceRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get checkedAtMicros => $composableBuilder(
    column: $table.checkedAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillUpdateCheckRecordsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SkillUpdateCheckRecordsTable,
          SkillUpdateCheckRecord,
          $$SkillUpdateCheckRecordsTableFilterComposer,
          $$SkillUpdateCheckRecordsTableOrderingComposer,
          $$SkillUpdateCheckRecordsTableAnnotationComposer,
          $$SkillUpdateCheckRecordsTableCreateCompanionBuilder,
          $$SkillUpdateCheckRecordsTableUpdateCompanionBuilder,
          (SkillUpdateCheckRecord, $$SkillUpdateCheckRecordsTableReferences),
          SkillUpdateCheckRecord,
          PrefetchHooks Function({bool managedSkillId})
        > {
  $$SkillUpdateCheckRecordsTableTableManager(
    _$WorkspaceDatabase db,
    $SkillUpdateCheckRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillUpdateCheckRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SkillUpdateCheckRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SkillUpdateCheckRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> basisFingerprint = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> currentContentHash = const Value.absent(),
                Value<String?> availableContentHash = const Value.absent(),
                Value<String?> resolvedSourceRevision = const Value.absent(),
                Value<int> checkedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillUpdateCheckRecordsCompanion(
                managedSkillId: managedSkillId,
                basisFingerprint: basisFingerprint,
                status: status,
                currentContentHash: currentContentHash,
                availableContentHash: availableContentHash,
                resolvedSourceRevision: resolvedSourceRevision,
                checkedAtMicros: checkedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String basisFingerprint,
                required String status,
                Value<String?> currentContentHash = const Value.absent(),
                Value<String?> availableContentHash = const Value.absent(),
                Value<String?> resolvedSourceRevision = const Value.absent(),
                required int checkedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => SkillUpdateCheckRecordsCompanion.insert(
                managedSkillId: managedSkillId,
                basisFingerprint: basisFingerprint,
                status: status,
                currentContentHash: currentContentHash,
                availableContentHash: availableContentHash,
                resolvedSourceRevision: resolvedSourceRevision,
                checkedAtMicros: checkedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SkillUpdateCheckRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({managedSkillId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (managedSkillId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.managedSkillId,
                                referencedTable:
                                    $$SkillUpdateCheckRecordsTableReferences
                                        ._managedSkillIdTable(db),
                                referencedColumn:
                                    $$SkillUpdateCheckRecordsTableReferences
                                        ._managedSkillIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SkillUpdateCheckRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SkillUpdateCheckRecordsTable,
      SkillUpdateCheckRecord,
      $$SkillUpdateCheckRecordsTableFilterComposer,
      $$SkillUpdateCheckRecordsTableOrderingComposer,
      $$SkillUpdateCheckRecordsTableAnnotationComposer,
      $$SkillUpdateCheckRecordsTableCreateCompanionBuilder,
      $$SkillUpdateCheckRecordsTableUpdateCompanionBuilder,
      (SkillUpdateCheckRecord, $$SkillUpdateCheckRecordsTableReferences),
      SkillUpdateCheckRecord,
      PrefetchHooks Function({bool managedSkillId})
    >;
typedef $$SkillUpdateCheckMetadataTableCreateCompanionBuilder =
    SkillUpdateCheckMetadataCompanion Function({
      Value<int> singleton,
      Value<int?> lastFullSweepAtMicros,
    });
typedef $$SkillUpdateCheckMetadataTableUpdateCompanionBuilder =
    SkillUpdateCheckMetadataCompanion Function({
      Value<int> singleton,
      Value<int?> lastFullSweepAtMicros,
    });

class $$SkillUpdateCheckMetadataTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckMetadataTable> {
  $$SkillUpdateCheckMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastFullSweepAtMicros => $composableBuilder(
    column: $table.lastFullSweepAtMicros,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SkillUpdateCheckMetadataTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckMetadataTable> {
  $$SkillUpdateCheckMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastFullSweepAtMicros => $composableBuilder(
    column: $table.lastFullSweepAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SkillUpdateCheckMetadataTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SkillUpdateCheckMetadataTable> {
  $$SkillUpdateCheckMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<int> get lastFullSweepAtMicros => $composableBuilder(
    column: $table.lastFullSweepAtMicros,
    builder: (column) => column,
  );
}

class $$SkillUpdateCheckMetadataTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SkillUpdateCheckMetadataTable,
          SkillUpdateCheckMetadataData,
          $$SkillUpdateCheckMetadataTableFilterComposer,
          $$SkillUpdateCheckMetadataTableOrderingComposer,
          $$SkillUpdateCheckMetadataTableAnnotationComposer,
          $$SkillUpdateCheckMetadataTableCreateCompanionBuilder,
          $$SkillUpdateCheckMetadataTableUpdateCompanionBuilder,
          (
            SkillUpdateCheckMetadataData,
            BaseReferences<
              _$WorkspaceDatabase,
              $SkillUpdateCheckMetadataTable,
              SkillUpdateCheckMetadataData
            >,
          ),
          SkillUpdateCheckMetadataData,
          PrefetchHooks Function()
        > {
  $$SkillUpdateCheckMetadataTableTableManager(
    _$WorkspaceDatabase db,
    $SkillUpdateCheckMetadataTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillUpdateCheckMetadataTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SkillUpdateCheckMetadataTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SkillUpdateCheckMetadataTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<int?> lastFullSweepAtMicros = const Value.absent(),
              }) => SkillUpdateCheckMetadataCompanion(
                singleton: singleton,
                lastFullSweepAtMicros: lastFullSweepAtMicros,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<int?> lastFullSweepAtMicros = const Value.absent(),
              }) => SkillUpdateCheckMetadataCompanion.insert(
                singleton: singleton,
                lastFullSweepAtMicros: lastFullSweepAtMicros,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SkillUpdateCheckMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SkillUpdateCheckMetadataTable,
      SkillUpdateCheckMetadataData,
      $$SkillUpdateCheckMetadataTableFilterComposer,
      $$SkillUpdateCheckMetadataTableOrderingComposer,
      $$SkillUpdateCheckMetadataTableAnnotationComposer,
      $$SkillUpdateCheckMetadataTableCreateCompanionBuilder,
      $$SkillUpdateCheckMetadataTableUpdateCompanionBuilder,
      (
        SkillUpdateCheckMetadataData,
        BaseReferences<
          _$WorkspaceDatabase,
          $SkillUpdateCheckMetadataTable,
          SkillUpdateCheckMetadataData
        >,
      ),
      SkillUpdateCheckMetadataData,
      PrefetchHooks Function()
    >;
typedef $$PersonalTagsTableCreateCompanionBuilder =
    PersonalTagsCompanion Function({
      required String id,
      required String normalizedKey,
      required String displayName,
      Value<String?> color,
      required int createdAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$PersonalTagsTableUpdateCompanionBuilder =
    PersonalTagsCompanion Function({
      Value<String> id,
      Value<String> normalizedKey,
      Value<String> displayName,
      Value<String?> color,
      Value<int> createdAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$PersonalTagsTableReferences
    extends
        BaseReferences<_$WorkspaceDatabase, $PersonalTagsTable, PersonalTag> {
  $$PersonalTagsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<
    $SkillTagAssignmentsTable,
    List<SkillTagAssignment>
  >
  _skillTagAssignmentsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.skillTagAssignments,
        aliasName: 'personal_tags__id__skill_tag_assignments__personal_tag_id',
      );

  $$SkillTagAssignmentsTableProcessedTableManager get skillTagAssignmentsRefs {
    final manager = $$SkillTagAssignmentsTableTableManager(
      $_db,
      $_db.skillTagAssignments,
    ).filter((f) => f.personalTagId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _skillTagAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PersonalTagsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $PersonalTagsTable> {
  $$PersonalTagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> skillTagAssignmentsRefs(
    Expression<bool> Function($$SkillTagAssignmentsTableFilterComposer f) f,
  ) {
    final $$SkillTagAssignmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.skillTagAssignments,
      getReferencedColumn: (t) => t.personalTagId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SkillTagAssignmentsTableFilterComposer(
            $db: $db,
            $table: $db.skillTagAssignments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PersonalTagsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $PersonalTagsTable> {
  $$PersonalTagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PersonalTagsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $PersonalTagsTable> {
  $$PersonalTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get normalizedKey => $composableBuilder(
    column: $table.normalizedKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  Expression<T> skillTagAssignmentsRefs<T extends Object>(
    Expression<T> Function($$SkillTagAssignmentsTableAnnotationComposer a) f,
  ) {
    final $$SkillTagAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.skillTagAssignments,
          getReferencedColumn: (t) => t.personalTagId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SkillTagAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.skillTagAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$PersonalTagsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $PersonalTagsTable,
          PersonalTag,
          $$PersonalTagsTableFilterComposer,
          $$PersonalTagsTableOrderingComposer,
          $$PersonalTagsTableAnnotationComposer,
          $$PersonalTagsTableCreateCompanionBuilder,
          $$PersonalTagsTableUpdateCompanionBuilder,
          (PersonalTag, $$PersonalTagsTableReferences),
          PersonalTag,
          PrefetchHooks Function({bool skillTagAssignmentsRefs})
        > {
  $$PersonalTagsTableTableManager(
    _$WorkspaceDatabase db,
    $PersonalTagsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PersonalTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PersonalTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PersonalTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> normalizedKey = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PersonalTagsCompanion(
                id: id,
                normalizedKey: normalizedKey,
                displayName: displayName,
                color: color,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String normalizedKey,
                required String displayName,
                Value<String?> color = const Value.absent(),
                required int createdAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => PersonalTagsCompanion.insert(
                id: id,
                normalizedKey: normalizedKey,
                displayName: displayName,
                color: color,
                createdAtMicros: createdAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PersonalTagsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({skillTagAssignmentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (skillTagAssignmentsRefs) db.skillTagAssignments,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (skillTagAssignmentsRefs)
                    await $_getPrefetchedData<
                      PersonalTag,
                      $PersonalTagsTable,
                      SkillTagAssignment
                    >(
                      currentTable: table,
                      referencedTable: $$PersonalTagsTableReferences
                          ._skillTagAssignmentsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PersonalTagsTableReferences(
                            db,
                            table,
                            p0,
                          ).skillTagAssignmentsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.personalTagId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PersonalTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $PersonalTagsTable,
      PersonalTag,
      $$PersonalTagsTableFilterComposer,
      $$PersonalTagsTableOrderingComposer,
      $$PersonalTagsTableAnnotationComposer,
      $$PersonalTagsTableCreateCompanionBuilder,
      $$PersonalTagsTableUpdateCompanionBuilder,
      (PersonalTag, $$PersonalTagsTableReferences),
      PersonalTag,
      PrefetchHooks Function({bool skillTagAssignmentsRefs})
    >;
typedef $$SkillTagAssignmentsTableCreateCompanionBuilder =
    SkillTagAssignmentsCompanion Function({
      required String managedSkillId,
      required String personalTagId,
      required int createdAtMicros,
      Value<int> rowid,
    });
typedef $$SkillTagAssignmentsTableUpdateCompanionBuilder =
    SkillTagAssignmentsCompanion Function({
      Value<String> managedSkillId,
      Value<String> personalTagId,
      Value<int> createdAtMicros,
      Value<int> rowid,
    });

final class $$SkillTagAssignmentsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $SkillTagAssignmentsTable,
          SkillTagAssignment
        > {
  $$SkillTagAssignmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) =>
      db.managedSkills.createAlias(
        'skill_tag_assignments__managed_skill_id__managed_skills__id',
      );

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PersonalTagsTable _personalTagIdTable(_$WorkspaceDatabase db) => db
      .personalTags
      .createAlias('skill_tag_assignments__personal_tag_id__personal_tags__id');

  $$PersonalTagsTableProcessedTableManager get personalTagId {
    final $_column = $_itemColumn<String>('personal_tag_id')!;

    final manager = $$PersonalTagsTableTableManager(
      $_db,
      $_db.personalTags,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personalTagIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SkillTagAssignmentsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $SkillTagAssignmentsTable> {
  $$SkillTagAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonalTagsTableFilterComposer get personalTagId {
    final $$PersonalTagsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personalTagId,
      referencedTable: $db.personalTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonalTagsTableFilterComposer(
            $db: $db,
            $table: $db.personalTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillTagAssignmentsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $SkillTagAssignmentsTable> {
  $$SkillTagAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonalTagsTableOrderingComposer get personalTagId {
    final $$PersonalTagsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personalTagId,
      referencedTable: $db.personalTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonalTagsTableOrderingComposer(
            $db: $db,
            $table: $db.personalTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillTagAssignmentsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $SkillTagAssignmentsTable> {
  $$SkillTagAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAtMicros => $composableBuilder(
    column: $table.createdAtMicros,
    builder: (column) => column,
  );

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PersonalTagsTableAnnotationComposer get personalTagId {
    final $$PersonalTagsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personalTagId,
      referencedTable: $db.personalTags,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PersonalTagsTableAnnotationComposer(
            $db: $db,
            $table: $db.personalTags,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SkillTagAssignmentsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $SkillTagAssignmentsTable,
          SkillTagAssignment,
          $$SkillTagAssignmentsTableFilterComposer,
          $$SkillTagAssignmentsTableOrderingComposer,
          $$SkillTagAssignmentsTableAnnotationComposer,
          $$SkillTagAssignmentsTableCreateCompanionBuilder,
          $$SkillTagAssignmentsTableUpdateCompanionBuilder,
          (SkillTagAssignment, $$SkillTagAssignmentsTableReferences),
          SkillTagAssignment,
          PrefetchHooks Function({bool managedSkillId, bool personalTagId})
        > {
  $$SkillTagAssignmentsTableTableManager(
    _$WorkspaceDatabase db,
    $SkillTagAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SkillTagAssignmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SkillTagAssignmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SkillTagAssignmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> managedSkillId = const Value.absent(),
                Value<String> personalTagId = const Value.absent(),
                Value<int> createdAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SkillTagAssignmentsCompanion(
                managedSkillId: managedSkillId,
                personalTagId: personalTagId,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String managedSkillId,
                required String personalTagId,
                required int createdAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => SkillTagAssignmentsCompanion.insert(
                managedSkillId: managedSkillId,
                personalTagId: personalTagId,
                createdAtMicros: createdAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SkillTagAssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({managedSkillId = false, personalTagId = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (managedSkillId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.managedSkillId,
                                    referencedTable:
                                        $$SkillTagAssignmentsTableReferences
                                            ._managedSkillIdTable(db),
                                    referencedColumn:
                                        $$SkillTagAssignmentsTableReferences
                                            ._managedSkillIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (personalTagId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.personalTagId,
                                    referencedTable:
                                        $$SkillTagAssignmentsTableReferences
                                            ._personalTagIdTable(db),
                                    referencedColumn:
                                        $$SkillTagAssignmentsTableReferences
                                            ._personalTagIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$SkillTagAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $SkillTagAssignmentsTable,
      SkillTagAssignment,
      $$SkillTagAssignmentsTableFilterComposer,
      $$SkillTagAssignmentsTableOrderingComposer,
      $$SkillTagAssignmentsTableAnnotationComposer,
      $$SkillTagAssignmentsTableCreateCompanionBuilder,
      $$SkillTagAssignmentsTableUpdateCompanionBuilder,
      (SkillTagAssignment, $$SkillTagAssignmentsTableReferences),
      SkillTagAssignment,
      PrefetchHooks Function({bool managedSkillId, bool personalTagId})
    >;
typedef $$OperationJournalsTableCreateCompanionBuilder =
    OperationJournalsCompanion Function({
      required String operationId,
      required String kind,
      required String phase,
      required int planSchemaVersion,
      required String planJson,
      required int operationGeneration,
      Value<int?> committedRepositoryRevision,
      required int startedAtMicros,
      required int updatedAtMicros,
      Value<int> rowid,
    });
typedef $$OperationJournalsTableUpdateCompanionBuilder =
    OperationJournalsCompanion Function({
      Value<String> operationId,
      Value<String> kind,
      Value<String> phase,
      Value<int> planSchemaVersion,
      Value<String> planJson,
      Value<int> operationGeneration,
      Value<int?> committedRepositoryRevision,
      Value<int> startedAtMicros,
      Value<int> updatedAtMicros,
      Value<int> rowid,
    });

final class $$OperationJournalsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $OperationJournalsTable,
          OperationJournal
        > {
  $$OperationJournalsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $OperationJournalStepsTable,
    List<OperationJournalStep>
  >
  _operationJournalStepsRefsTable(
    _$WorkspaceDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.operationJournalSteps,
    aliasName:
        'operation_journals__operation_id__operation_journal_steps__operation_id',
  );

  $$OperationJournalStepsTableProcessedTableManager
  get operationJournalStepsRefs {
    final manager =
        $$OperationJournalStepsTableTableManager(
          $_db,
          $_db.operationJournalSteps,
        ).filter(
          (f) => f.operationId.operationId.sqlEquals(
            $_itemColumn<String>('operation_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _operationJournalStepsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OperationJournalsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalsTable> {
  $$OperationJournalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get planSchemaVersion => $composableBuilder(
    column: $table.planSchemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planJson => $composableBuilder(
    column: $table.planJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get operationGeneration => $composableBuilder(
    column: $table.operationGeneration,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get committedRepositoryRevision => $composableBuilder(
    column: $table.committedRepositoryRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> operationJournalStepsRefs(
    Expression<bool> Function($$OperationJournalStepsTableFilterComposer f) f,
  ) {
    final $$OperationJournalStepsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.operationJournalSteps,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationJournalStepsTableFilterComposer(
                $db: $db,
                $table: $db.operationJournalSteps,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$OperationJournalsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalsTable> {
  $$OperationJournalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get planSchemaVersion => $composableBuilder(
    column: $table.planSchemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planJson => $composableBuilder(
    column: $table.planJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get operationGeneration => $composableBuilder(
    column: $table.operationGeneration,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get committedRepositoryRevision => $composableBuilder(
    column: $table.committedRepositoryRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OperationJournalsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalsTable> {
  $$OperationJournalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<int> get planSchemaVersion => $composableBuilder(
    column: $table.planSchemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planJson =>
      $composableBuilder(column: $table.planJson, builder: (column) => column);

  GeneratedColumn<int> get operationGeneration => $composableBuilder(
    column: $table.operationGeneration,
    builder: (column) => column,
  );

  GeneratedColumn<int> get committedRepositoryRevision => $composableBuilder(
    column: $table.committedRepositoryRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMicros => $composableBuilder(
    column: $table.updatedAtMicros,
    builder: (column) => column,
  );

  Expression<T> operationJournalStepsRefs<T extends Object>(
    Expression<T> Function($$OperationJournalStepsTableAnnotationComposer a) f,
  ) {
    final $$OperationJournalStepsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.operationJournalSteps,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationJournalStepsTableAnnotationComposer(
                $db: $db,
                $table: $db.operationJournalSteps,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$OperationJournalsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $OperationJournalsTable,
          OperationJournal,
          $$OperationJournalsTableFilterComposer,
          $$OperationJournalsTableOrderingComposer,
          $$OperationJournalsTableAnnotationComposer,
          $$OperationJournalsTableCreateCompanionBuilder,
          $$OperationJournalsTableUpdateCompanionBuilder,
          (OperationJournal, $$OperationJournalsTableReferences),
          OperationJournal,
          PrefetchHooks Function({bool operationJournalStepsRefs})
        > {
  $$OperationJournalsTableTableManager(
    _$WorkspaceDatabase db,
    $OperationJournalsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperationJournalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OperationJournalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OperationJournalsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<int> planSchemaVersion = const Value.absent(),
                Value<String> planJson = const Value.absent(),
                Value<int> operationGeneration = const Value.absent(),
                Value<int?> committedRepositoryRevision = const Value.absent(),
                Value<int> startedAtMicros = const Value.absent(),
                Value<int> updatedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperationJournalsCompanion(
                operationId: operationId,
                kind: kind,
                phase: phase,
                planSchemaVersion: planSchemaVersion,
                planJson: planJson,
                operationGeneration: operationGeneration,
                committedRepositoryRevision: committedRepositoryRevision,
                startedAtMicros: startedAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String kind,
                required String phase,
                required int planSchemaVersion,
                required String planJson,
                required int operationGeneration,
                Value<int?> committedRepositoryRevision = const Value.absent(),
                required int startedAtMicros,
                required int updatedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => OperationJournalsCompanion.insert(
                operationId: operationId,
                kind: kind,
                phase: phase,
                planSchemaVersion: planSchemaVersion,
                planJson: planJson,
                operationGeneration: operationGeneration,
                committedRepositoryRevision: committedRepositoryRevision,
                startedAtMicros: startedAtMicros,
                updatedAtMicros: updatedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OperationJournalsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({operationJournalStepsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (operationJournalStepsRefs) db.operationJournalSteps,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (operationJournalStepsRefs)
                    await $_getPrefetchedData<
                      OperationJournal,
                      $OperationJournalsTable,
                      OperationJournalStep
                    >(
                      currentTable: table,
                      referencedTable: $$OperationJournalsTableReferences
                          ._operationJournalStepsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$OperationJournalsTableReferences(
                            db,
                            table,
                            p0,
                          ).operationJournalStepsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.operationId == item.operationId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$OperationJournalsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $OperationJournalsTable,
      OperationJournal,
      $$OperationJournalsTableFilterComposer,
      $$OperationJournalsTableOrderingComposer,
      $$OperationJournalsTableAnnotationComposer,
      $$OperationJournalsTableCreateCompanionBuilder,
      $$OperationJournalsTableUpdateCompanionBuilder,
      (OperationJournal, $$OperationJournalsTableReferences),
      OperationJournal,
      PrefetchHooks Function({bool operationJournalStepsRefs})
    >;
typedef $$OperationJournalStepsTableCreateCompanionBuilder =
    OperationJournalStepsCompanion Function({
      required String operationId,
      required int sequence,
      required String stepId,
      required String kind,
      required String status,
      required String recoveryReference,
      Value<int> rowid,
    });
typedef $$OperationJournalStepsTableUpdateCompanionBuilder =
    OperationJournalStepsCompanion Function({
      Value<String> operationId,
      Value<int> sequence,
      Value<String> stepId,
      Value<String> kind,
      Value<String> status,
      Value<String> recoveryReference,
      Value<int> rowid,
    });

final class $$OperationJournalStepsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $OperationJournalStepsTable,
          OperationJournalStep
        > {
  $$OperationJournalStepsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OperationJournalsTable _operationIdTable(
    _$WorkspaceDatabase db,
  ) => db.operationJournals.createAlias(
    'operation_journal_steps__operation_id__operation_journals__operation_id',
  );

  $$OperationJournalsTableProcessedTableManager get operationId {
    final $_column = $_itemColumn<String>('operation_id')!;

    final manager = $$OperationJournalsTableTableManager(
      $_db,
      $_db.operationJournals,
    ).filter((f) => f.operationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_operationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OperationJournalStepsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalStepsTable> {
  $$OperationJournalStepsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stepId => $composableBuilder(
    column: $table.stepId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recoveryReference => $composableBuilder(
    column: $table.recoveryReference,
    builder: (column) => ColumnFilters(column),
  );

  $$OperationJournalsTableFilterComposer get operationId {
    final $$OperationJournalsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationJournals,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationJournalsTableFilterComposer(
            $db: $db,
            $table: $db.operationJournals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationJournalStepsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalStepsTable> {
  $$OperationJournalStepsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stepId => $composableBuilder(
    column: $table.stepId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recoveryReference => $composableBuilder(
    column: $table.recoveryReference,
    builder: (column) => ColumnOrderings(column),
  );

  $$OperationJournalsTableOrderingComposer get operationId {
    final $$OperationJournalsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationJournals,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationJournalsTableOrderingComposer(
            $db: $db,
            $table: $db.operationJournals,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationJournalStepsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $OperationJournalStepsTable> {
  $$OperationJournalStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get stepId =>
      $composableBuilder(column: $table.stepId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get recoveryReference => $composableBuilder(
    column: $table.recoveryReference,
    builder: (column) => column,
  );

  $$OperationJournalsTableAnnotationComposer get operationId {
    final $$OperationJournalsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.operationJournals,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationJournalsTableAnnotationComposer(
                $db: $db,
                $table: $db.operationJournals,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OperationJournalStepsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $OperationJournalStepsTable,
          OperationJournalStep,
          $$OperationJournalStepsTableFilterComposer,
          $$OperationJournalStepsTableOrderingComposer,
          $$OperationJournalStepsTableAnnotationComposer,
          $$OperationJournalStepsTableCreateCompanionBuilder,
          $$OperationJournalStepsTableUpdateCompanionBuilder,
          (OperationJournalStep, $$OperationJournalStepsTableReferences),
          OperationJournalStep,
          PrefetchHooks Function({bool operationId})
        > {
  $$OperationJournalStepsTableTableManager(
    _$WorkspaceDatabase db,
    $OperationJournalStepsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperationJournalStepsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OperationJournalStepsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OperationJournalStepsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> stepId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> recoveryReference = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperationJournalStepsCompanion(
                operationId: operationId,
                sequence: sequence,
                stepId: stepId,
                kind: kind,
                status: status,
                recoveryReference: recoveryReference,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required int sequence,
                required String stepId,
                required String kind,
                required String status,
                required String recoveryReference,
                Value<int> rowid = const Value.absent(),
              }) => OperationJournalStepsCompanion.insert(
                operationId: operationId,
                sequence: sequence,
                stepId: stepId,
                kind: kind,
                status: status,
                recoveryReference: recoveryReference,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OperationJournalStepsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({operationId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (operationId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.operationId,
                                referencedTable:
                                    $$OperationJournalStepsTableReferences
                                        ._operationIdTable(db),
                                referencedColumn:
                                    $$OperationJournalStepsTableReferences
                                        ._operationIdTable(db)
                                        .operationId,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OperationJournalStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $OperationJournalStepsTable,
      OperationJournalStep,
      $$OperationJournalStepsTableFilterComposer,
      $$OperationJournalStepsTableOrderingComposer,
      $$OperationJournalStepsTableAnnotationComposer,
      $$OperationJournalStepsTableCreateCompanionBuilder,
      $$OperationJournalStepsTableUpdateCompanionBuilder,
      (OperationJournalStep, $$OperationJournalStepsTableReferences),
      OperationJournalStep,
      PrefetchHooks Function({bool operationId})
    >;
typedef $$OperationRecordsTableCreateCompanionBuilder =
    OperationRecordsCompanion Function({
      required String operationId,
      required String kind,
      required String status,
      Value<bool> retainWithoutSubjects,
      required int startedAtMicros,
      required int completedAtMicros,
      Value<int> rowid,
    });
typedef $$OperationRecordsTableUpdateCompanionBuilder =
    OperationRecordsCompanion Function({
      Value<String> operationId,
      Value<String> kind,
      Value<String> status,
      Value<bool> retainWithoutSubjects,
      Value<int> startedAtMicros,
      Value<int> completedAtMicros,
      Value<int> rowid,
    });

final class $$OperationRecordsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $OperationRecordsTable,
          OperationRecord
        > {
  $$OperationRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$OperationSubjectsTable, List<OperationSubject>>
  _operationSubjectsRefsTable(_$WorkspaceDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.operationSubjects,
        aliasName:
            'operation_records__operation_id__operation_subjects__operation_id',
      );

  $$OperationSubjectsTableProcessedTableManager get operationSubjectsRefs {
    final manager =
        $$OperationSubjectsTableTableManager(
          $_db,
          $_db.operationSubjects,
        ).filter(
          (f) => f.operationId.operationId.sqlEquals(
            $_itemColumn<String>('operation_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _operationSubjectsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OperationRecordsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $OperationRecordsTable> {
  $$OperationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get retainWithoutSubjects => $composableBuilder(
    column: $table.retainWithoutSubjects,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtMicros => $composableBuilder(
    column: $table.completedAtMicros,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> operationSubjectsRefs(
    Expression<bool> Function($$OperationSubjectsTableFilterComposer f) f,
  ) {
    final $$OperationSubjectsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationSubjects,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationSubjectsTableFilterComposer(
            $db: $db,
            $table: $db.operationSubjects,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OperationRecordsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $OperationRecordsTable> {
  $$OperationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get retainWithoutSubjects => $composableBuilder(
    column: $table.retainWithoutSubjects,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtMicros => $composableBuilder(
    column: $table.completedAtMicros,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OperationRecordsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $OperationRecordsTable> {
  $$OperationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
    column: $table.operationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get retainWithoutSubjects => $composableBuilder(
    column: $table.retainWithoutSubjects,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startedAtMicros => $composableBuilder(
    column: $table.startedAtMicros,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtMicros => $composableBuilder(
    column: $table.completedAtMicros,
    builder: (column) => column,
  );

  Expression<T> operationSubjectsRefs<T extends Object>(
    Expression<T> Function($$OperationSubjectsTableAnnotationComposer a) f,
  ) {
    final $$OperationSubjectsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.operationId,
          referencedTable: $db.operationSubjects,
          getReferencedColumn: (t) => t.operationId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OperationSubjectsTableAnnotationComposer(
                $db: $db,
                $table: $db.operationSubjects,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$OperationRecordsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $OperationRecordsTable,
          OperationRecord,
          $$OperationRecordsTableFilterComposer,
          $$OperationRecordsTableOrderingComposer,
          $$OperationRecordsTableAnnotationComposer,
          $$OperationRecordsTableCreateCompanionBuilder,
          $$OperationRecordsTableUpdateCompanionBuilder,
          (OperationRecord, $$OperationRecordsTableReferences),
          OperationRecord,
          PrefetchHooks Function({bool operationSubjectsRefs})
        > {
  $$OperationRecordsTableTableManager(
    _$WorkspaceDatabase db,
    $OperationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperationRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OperationRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OperationRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> operationId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> retainWithoutSubjects = const Value.absent(),
                Value<int> startedAtMicros = const Value.absent(),
                Value<int> completedAtMicros = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperationRecordsCompanion(
                operationId: operationId,
                kind: kind,
                status: status,
                retainWithoutSubjects: retainWithoutSubjects,
                startedAtMicros: startedAtMicros,
                completedAtMicros: completedAtMicros,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String operationId,
                required String kind,
                required String status,
                Value<bool> retainWithoutSubjects = const Value.absent(),
                required int startedAtMicros,
                required int completedAtMicros,
                Value<int> rowid = const Value.absent(),
              }) => OperationRecordsCompanion.insert(
                operationId: operationId,
                kind: kind,
                status: status,
                retainWithoutSubjects: retainWithoutSubjects,
                startedAtMicros: startedAtMicros,
                completedAtMicros: completedAtMicros,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OperationRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({operationSubjectsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (operationSubjectsRefs) db.operationSubjects,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (operationSubjectsRefs)
                    await $_getPrefetchedData<
                      OperationRecord,
                      $OperationRecordsTable,
                      OperationSubject
                    >(
                      currentTable: table,
                      referencedTable: $$OperationRecordsTableReferences
                          ._operationSubjectsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$OperationRecordsTableReferences(
                            db,
                            table,
                            p0,
                          ).operationSubjectsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.operationId == item.operationId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$OperationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $OperationRecordsTable,
      OperationRecord,
      $$OperationRecordsTableFilterComposer,
      $$OperationRecordsTableOrderingComposer,
      $$OperationRecordsTableAnnotationComposer,
      $$OperationRecordsTableCreateCompanionBuilder,
      $$OperationRecordsTableUpdateCompanionBuilder,
      (OperationRecord, $$OperationRecordsTableReferences),
      OperationRecord,
      PrefetchHooks Function({bool operationSubjectsRefs})
    >;
typedef $$OperationSubjectsTableCreateCompanionBuilder =
    OperationSubjectsCompanion Function({
      required String subjectId,
      required String operationId,
      required String managedSkillId,
      Value<String?> sourceLineageId,
      Value<String?> beforeObjectId,
      Value<String?> afterObjectId,
      Value<String?> beforeContentHash,
      Value<String?> afterContentHash,
      required String displayName,
      Value<int> rowid,
    });
typedef $$OperationSubjectsTableUpdateCompanionBuilder =
    OperationSubjectsCompanion Function({
      Value<String> subjectId,
      Value<String> operationId,
      Value<String> managedSkillId,
      Value<String?> sourceLineageId,
      Value<String?> beforeObjectId,
      Value<String?> afterObjectId,
      Value<String?> beforeContentHash,
      Value<String?> afterContentHash,
      Value<String> displayName,
      Value<int> rowid,
    });

final class $$OperationSubjectsTableReferences
    extends
        BaseReferences<
          _$WorkspaceDatabase,
          $OperationSubjectsTable,
          OperationSubject
        > {
  $$OperationSubjectsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OperationRecordsTable _operationIdTable(_$WorkspaceDatabase db) =>
      db.operationRecords.createAlias(
        'operation_subjects__operation_id__operation_records__operation_id',
      );

  $$OperationRecordsTableProcessedTableManager get operationId {
    final $_column = $_itemColumn<String>('operation_id')!;

    final manager = $$OperationRecordsTableTableManager(
      $_db,
      $_db.operationRecords,
    ).filter((f) => f.operationId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_operationIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ManagedSkillsTable _managedSkillIdTable(_$WorkspaceDatabase db) => db
      .managedSkills
      .createAlias('operation_subjects__managed_skill_id__managed_skills__id');

  $$ManagedSkillsTableProcessedTableManager get managedSkillId {
    final $_column = $_itemColumn<String>('managed_skill_id')!;

    final manager = $$ManagedSkillsTableTableManager(
      $_db,
      $_db.managedSkills,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_managedSkillIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SourceLineagesTable _sourceLineageIdTable(_$WorkspaceDatabase db) =>
      db.sourceLineages.createAlias(
        'operation_subjects__source_lineage_id__source_lineages__id',
      );

  $$SourceLineagesTableProcessedTableManager? get sourceLineageId {
    final $_column = $_itemColumn<String>('source_lineage_id');
    if ($_column == null) return null;
    final manager = $$SourceLineagesTableTableManager(
      $_db,
      $_db.sourceLineages,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceLineageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OperationSubjectsTableFilterComposer
    extends Composer<_$WorkspaceDatabase, $OperationSubjectsTable> {
  $$OperationSubjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeObjectId => $composableBuilder(
    column: $table.beforeObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterObjectId => $composableBuilder(
    column: $table.afterObjectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get beforeContentHash => $composableBuilder(
    column: $table.beforeContentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get afterContentHash => $composableBuilder(
    column: $table.afterContentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  $$OperationRecordsTableFilterComposer get operationId {
    final $$OperationRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationRecords,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationRecordsTableFilterComposer(
            $db: $db,
            $table: $db.operationRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ManagedSkillsTableFilterComposer get managedSkillId {
    final $$ManagedSkillsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableFilterComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SourceLineagesTableFilterComposer get sourceLineageId {
    final $$SourceLineagesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableFilterComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationSubjectsTableOrderingComposer
    extends Composer<_$WorkspaceDatabase, $OperationSubjectsTable> {
  $$OperationSubjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get subjectId => $composableBuilder(
    column: $table.subjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeObjectId => $composableBuilder(
    column: $table.beforeObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterObjectId => $composableBuilder(
    column: $table.afterObjectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get beforeContentHash => $composableBuilder(
    column: $table.beforeContentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get afterContentHash => $composableBuilder(
    column: $table.afterContentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  $$OperationRecordsTableOrderingComposer get operationId {
    final $$OperationRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationRecords,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.operationRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ManagedSkillsTableOrderingComposer get managedSkillId {
    final $$ManagedSkillsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableOrderingComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SourceLineagesTableOrderingComposer get sourceLineageId {
    final $$SourceLineagesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableOrderingComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationSubjectsTableAnnotationComposer
    extends Composer<_$WorkspaceDatabase, $OperationSubjectsTable> {
  $$OperationSubjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get subjectId =>
      $composableBuilder(column: $table.subjectId, builder: (column) => column);

  GeneratedColumn<String> get beforeObjectId => $composableBuilder(
    column: $table.beforeObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterObjectId => $composableBuilder(
    column: $table.afterObjectId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get beforeContentHash => $composableBuilder(
    column: $table.beforeContentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get afterContentHash => $composableBuilder(
    column: $table.afterContentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  $$OperationRecordsTableAnnotationComposer get operationId {
    final $$OperationRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.operationId,
      referencedTable: $db.operationRecords,
      getReferencedColumn: (t) => t.operationId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OperationRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.operationRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ManagedSkillsTableAnnotationComposer get managedSkillId {
    final $$ManagedSkillsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.managedSkillId,
      referencedTable: $db.managedSkills,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ManagedSkillsTableAnnotationComposer(
            $db: $db,
            $table: $db.managedSkills,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SourceLineagesTableAnnotationComposer get sourceLineageId {
    final $$SourceLineagesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceLineageId,
      referencedTable: $db.sourceLineages,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourceLineagesTableAnnotationComposer(
            $db: $db,
            $table: $db.sourceLineages,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OperationSubjectsTableTableManager
    extends
        RootTableManager<
          _$WorkspaceDatabase,
          $OperationSubjectsTable,
          OperationSubject,
          $$OperationSubjectsTableFilterComposer,
          $$OperationSubjectsTableOrderingComposer,
          $$OperationSubjectsTableAnnotationComposer,
          $$OperationSubjectsTableCreateCompanionBuilder,
          $$OperationSubjectsTableUpdateCompanionBuilder,
          (OperationSubject, $$OperationSubjectsTableReferences),
          OperationSubject,
          PrefetchHooks Function({
            bool operationId,
            bool managedSkillId,
            bool sourceLineageId,
          })
        > {
  $$OperationSubjectsTableTableManager(
    _$WorkspaceDatabase db,
    $OperationSubjectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OperationSubjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OperationSubjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OperationSubjectsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> subjectId = const Value.absent(),
                Value<String> operationId = const Value.absent(),
                Value<String> managedSkillId = const Value.absent(),
                Value<String?> sourceLineageId = const Value.absent(),
                Value<String?> beforeObjectId = const Value.absent(),
                Value<String?> afterObjectId = const Value.absent(),
                Value<String?> beforeContentHash = const Value.absent(),
                Value<String?> afterContentHash = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OperationSubjectsCompanion(
                subjectId: subjectId,
                operationId: operationId,
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                beforeObjectId: beforeObjectId,
                afterObjectId: afterObjectId,
                beforeContentHash: beforeContentHash,
                afterContentHash: afterContentHash,
                displayName: displayName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String subjectId,
                required String operationId,
                required String managedSkillId,
                Value<String?> sourceLineageId = const Value.absent(),
                Value<String?> beforeObjectId = const Value.absent(),
                Value<String?> afterObjectId = const Value.absent(),
                Value<String?> beforeContentHash = const Value.absent(),
                Value<String?> afterContentHash = const Value.absent(),
                required String displayName,
                Value<int> rowid = const Value.absent(),
              }) => OperationSubjectsCompanion.insert(
                subjectId: subjectId,
                operationId: operationId,
                managedSkillId: managedSkillId,
                sourceLineageId: sourceLineageId,
                beforeObjectId: beforeObjectId,
                afterObjectId: afterObjectId,
                beforeContentHash: beforeContentHash,
                afterContentHash: afterContentHash,
                displayName: displayName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OperationSubjectsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                operationId = false,
                managedSkillId = false,
                sourceLineageId = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (operationId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.operationId,
                                    referencedTable:
                                        $$OperationSubjectsTableReferences
                                            ._operationIdTable(db),
                                    referencedColumn:
                                        $$OperationSubjectsTableReferences
                                            ._operationIdTable(db)
                                            .operationId,
                                  )
                                  as T;
                        }
                        if (managedSkillId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.managedSkillId,
                                    referencedTable:
                                        $$OperationSubjectsTableReferences
                                            ._managedSkillIdTable(db),
                                    referencedColumn:
                                        $$OperationSubjectsTableReferences
                                            ._managedSkillIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }
                        if (sourceLineageId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sourceLineageId,
                                    referencedTable:
                                        $$OperationSubjectsTableReferences
                                            ._sourceLineageIdTable(db),
                                    referencedColumn:
                                        $$OperationSubjectsTableReferences
                                            ._sourceLineageIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [];
                  },
                );
              },
        ),
      );
}

typedef $$OperationSubjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$WorkspaceDatabase,
      $OperationSubjectsTable,
      OperationSubject,
      $$OperationSubjectsTableFilterComposer,
      $$OperationSubjectsTableOrderingComposer,
      $$OperationSubjectsTableAnnotationComposer,
      $$OperationSubjectsTableCreateCompanionBuilder,
      $$OperationSubjectsTableUpdateCompanionBuilder,
      (OperationSubject, $$OperationSubjectsTableReferences),
      OperationSubject,
      PrefetchHooks Function({
        bool operationId,
        bool managedSkillId,
        bool sourceLineageId,
      })
    >;

class $WorkspaceDatabaseManager {
  final _$WorkspaceDatabase _db;
  $WorkspaceDatabaseManager(this._db);
  $$WorkspaceMetadataTableTableManager get workspaceMetadata =>
      $$WorkspaceMetadataTableTableManager(_db, _db.workspaceMetadata);
  $$SourceLineagesTableTableManager get sourceLineages =>
      $$SourceLineagesTableTableManager(_db, _db.sourceLineages);
  $$ManagedSkillsTableTableManager get managedSkills =>
      $$ManagedSkillsTableTableManager(_db, _db.managedSkills);
  $$SkillSourcesTableTableManager get skillSources =>
      $$SkillSourcesTableTableManager(_db, _db.skillSources);
  $$RevisionMetadataTableTableManager get revisionMetadata =>
      $$RevisionMetadataTableTableManager(_db, _db.revisionMetadata);
  $$CurrentRevisionSelectionTableTableManager get currentRevisionSelection =>
      $$CurrentRevisionSelectionTableTableManager(
        _db,
        _db.currentRevisionSelection,
      );
  $$DraftWorkspacesTableTableManager get draftWorkspaces =>
      $$DraftWorkspacesTableTableManager(_db, _db.draftWorkspaces);
  $$UpdateCandidateSessionsTableTableManager get updateCandidateSessions =>
      $$UpdateCandidateSessionsTableTableManager(
        _db,
        _db.updateCandidateSessions,
      );
  $$UpdateCandidateItemsTableTableManager get updateCandidateItems =>
      $$UpdateCandidateItemsTableTableManager(_db, _db.updateCandidateItems);
  $$ProjectRootsTableTableManager get projectRoots =>
      $$ProjectRootsTableTableManager(_db, _db.projectRoots);
  $$ActivationLocationsTableTableManager get activationLocations =>
      $$ActivationLocationsTableTableManager(_db, _db.activationLocations);
  $$ActivationAgentsTableTableManager get activationAgents =>
      $$ActivationAgentsTableTableManager(_db, _db.activationAgents);
  $$SkillUserDataTableTableManager get skillUserData =>
      $$SkillUserDataTableTableManager(_db, _db.skillUserData);
  $$SkillUpdateCheckRecordsTableTableManager get skillUpdateCheckRecords =>
      $$SkillUpdateCheckRecordsTableTableManager(
        _db,
        _db.skillUpdateCheckRecords,
      );
  $$SkillUpdateCheckMetadataTableTableManager get skillUpdateCheckMetadata =>
      $$SkillUpdateCheckMetadataTableTableManager(
        _db,
        _db.skillUpdateCheckMetadata,
      );
  $$PersonalTagsTableTableManager get personalTags =>
      $$PersonalTagsTableTableManager(_db, _db.personalTags);
  $$SkillTagAssignmentsTableTableManager get skillTagAssignments =>
      $$SkillTagAssignmentsTableTableManager(_db, _db.skillTagAssignments);
  $$OperationJournalsTableTableManager get operationJournals =>
      $$OperationJournalsTableTableManager(_db, _db.operationJournals);
  $$OperationJournalStepsTableTableManager get operationJournalSteps =>
      $$OperationJournalStepsTableTableManager(_db, _db.operationJournalSteps);
  $$OperationRecordsTableTableManager get operationRecords =>
      $$OperationRecordsTableTableManager(_db, _db.operationRecords);
  $$OperationSubjectsTableTableManager get operationSubjects =>
      $$OperationSubjectsTableTableManager(_db, _db.operationSubjects);
}
