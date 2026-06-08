import 'package:hive/hive.dart';

part 'listening_history.g.dart';

@HiveType(typeId: 2)
class ListeningRecord extends HiveObject {
  @HiveField(0)
  String albumId;

  @HiveField(1)
  String trackTitle;

  @HiveField(2)
  DateTime playedAt;

  @HiveField(3)
  int durationSeconds; // ile sekund sluchano

  ListeningRecord({
    required this.albumId,
    required this.trackTitle,
    required this.playedAt,
    required this.durationSeconds,
  });
}

