import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/listening_history.dart';
import '../models/album.dart';

class HistoryService extends ChangeNotifier {
  late Box<ListeningRecord> _historyBox;
  List<ListeningRecord> _history = [];

  List<ListeningRecord> get history => _history;

  HistoryService() {
    _init();
  }

  Future<void> _init() async {
    _historyBox = Hive.box<ListeningRecord>('listening_history');
    _loadHistory();
  }

  void _loadHistory() {
    _history = _historyBox.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt));
    notifyListeners();
  }

  // Dodaj nowy wpis do historii
  Future<void> addRecord(String albumId, String trackTitle, int durationSeconds) async {
    final record = ListeningRecord(
      albumId: albumId,
      trackTitle: trackTitle,
      playedAt: DateTime.now(),
      durationSeconds: durationSeconds,
    );
    await _historyBox.add(record);
    _loadHistory();
  }

  // Statystyki - najczesciej sluchane albumy
  Map<String, int> getTopAlbums(List<Album> allAlbums, {int limit = 10}) {
    final albumCounts = <String, int>{};
    
    for (var record in _history) {
      albumCounts[record.albumId] = (albumCounts[record.albumId] ?? 0) + 1;
    }
    
    final sorted = albumCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Map.fromEntries(sorted.take(limit));
  }

  // Statystyki - najczesciej sluchane utwory
  Map<String, int> getTopTracks({int limit = 10}) {
    final trackCounts = <String, int>{};
    
    for (var record in _history) {
      trackCounts[record.trackTitle] = (trackCounts[record.trackTitle] ?? 0) + 1;
    }
    
    final sorted = trackCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Map.fromEntries(sorted.take(limit));
  }

  // Laczny czas sluchania
  Duration getTotalListeningTime() {
    final totalSeconds = _history.fold<int>(0, (sum, r) => sum + r.durationSeconds);
    return Duration(seconds: totalSeconds);
  }

  // Sluchane dzisiaj
  List<ListeningRecord> getTodayHistory() {
    final today = DateTime.now();
    return _history.where((r) => 
      r.playedAt.year == today.year &&
      r.playedAt.month == today.month &&
      r.playedAt.day == today.day
    ).toList();
  }

  // Sluchane w tym tygodniu
  List<ListeningRecord> getWeekHistory() {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _history.where((r) => r.playedAt.isAfter(weekAgo)).toList();
  }

  // Wyczysc historie
  Future<void> clearHistory() async {
    await _historyBox.clear();
    _loadHistory();
  }

  // Liczba odsluchan dla albumu
  int getAlbumPlayCount(String albumId) {
    return _history.where((r) => r.albumId == albumId).length;
  }

  // Ostatnio sluchane albumy (unikalne)
  List<String> getRecentAlbumIds({int limit = 10}) {
    final seen = <String>{};
    final result = <String>[];
    
    for (var record in _history) {
      if (!seen.contains(record.albumId)) {
        seen.add(record.albumId);
        result.add(record.albumId);
        if (result.length >= limit) break;
      }
    }
    
    return result;
  }
}
