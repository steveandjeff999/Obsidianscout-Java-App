import 'dart:io' show Platform;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

part 'local_db.g.dart';

/// Large cached API responses, collab/checklist documents and drafts, keyed like the
/// SharedPreferences entries they replaced (e.g. `cache_scouting`).
@DataClassName('KvEntry')
class KvEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// One row per scout-history record, so adding or updating one entry doesn't rewrite all of them.
@DataClassName('ScoutHistoryRow')
class ScoutHistoryRows extends Table {
  TextColumn get id => text()();
  IntColumn get createdAt => integer()();
  TextColumn get json => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Submissions saved on this device that haven't reached the server yet.
@DataClassName('OutboxRow')
class OutboxItems extends Table {
  TextColumn get id => text()();

  /// What to send: `match`, `pit`, `qual`, `qual_batch`, `prescout_match`, `prescout_pit`,
  /// `prescout_qual` or `assignment_status`.
  TextColumn get kind => text()();
  TextColumn get eventKey => text().nullable()();
  TextColumn get payload => text()();
  IntColumn get createdAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// Scout-history row to mark `synced` once this item uploads.
  TextColumn get historyId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [KvEntries, ScoutHistoryRows, OutboxItems])
class LocalDb extends _$LocalDb {
  LocalDb(super.e);

  /// Opens `obsidianscout.sqlite` in the app documents directory. drift_flutter runs
  /// SQLite on a background isolate, so queries never block the UI thread.
  ///
  /// On iOS the documents directory is shown in the Files app (exports go there), so the database lives in
  /// Application Support instead, out of the user's reach.
  factory LocalDb.open() => LocalDb(driftDatabase(
        name: 'obsidianscout',
        native: !kIsWeb && Platform.isIOS ? const DriftNativeOptions(databaseDirectory: getApplicationSupportDirectory) : null,
      ));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await m.createIndex(Index('scout_history_created_at', 'CREATE INDEX scout_history_created_at ON scout_history_rows (created_at)'));
          await m.createIndex(Index('outbox_created_at', 'CREATE INDEX outbox_created_at ON outbox_items (created_at)'));
        },
      );
}
