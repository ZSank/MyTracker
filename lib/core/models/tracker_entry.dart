/// Common contract for anything stored in a tracker log.
///
/// Future modules (habits, running, ...) can implement this without changing
/// the vault storage engine.
abstract class TrackerEntry {
  String get id;

  DateTime get timestamp;

  Map<String, dynamic> toJson();
}
