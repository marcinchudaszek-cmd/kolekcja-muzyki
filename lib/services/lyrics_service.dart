import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsService {
  static Future<String?> fetchLyrics(String artist, String title) async {
    String? lyrics;
    
    // Czysc tytul z dodatkow
    final cleanTitle = _cleanTitle(title);
    final cleanArtist = _cleanArtist(artist);
    
    // 1. lrclib.net
    lyrics = await _fetchFromLrclib(cleanArtist, cleanTitle);
    if (lyrics != null && lyrics.length > 50) return lyrics;
    
    // 2. lyrics.ovh
    lyrics = await _fetchFromLyricsOvh(cleanArtist, cleanTitle);
    if (lyrics != null && lyrics.length > 50) return lyrics;
    
    // 3. Probuj bez czyszczenia
    if (cleanTitle != title || cleanArtist != artist) {
      lyrics = await _fetchFromLrclib(artist, title);
      if (lyrics != null && lyrics.length > 50) return lyrics;
    }
    
    return lyrics;
  }

  static String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'feat\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'ft\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'- remaster.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'remastered.*', caseSensitive: false), '')
        .trim();
  }

  static String _cleanArtist(String artist) {
    return artist
        .replaceAll(RegExp(r'\s*[,&]\s*.*'), '')
        .replaceAll(RegExp(r'\s+feat\..*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+ft\..*', caseSensitive: false), '')
        .trim();
  }

  static Future<List<LyricLine>?> fetchSyncedLyrics(String artist, String title) async {
    try {
      final cleanTitle = _cleanTitle(title);
      final cleanArtist = _cleanArtist(artist);
      
      var result = await _fetchSyncedFromLrclib(cleanArtist, cleanTitle);
      if (result != null && result.isNotEmpty) return result;
      
      if (cleanTitle != title || cleanArtist != artist) {
        result = await _fetchSyncedFromLrclib(artist, title);
        if (result != null && result.isNotEmpty) return result;
      }
    } catch (e) {
      print('Synced lyrics error: $e');
    }
    return null;
  }

  static Future<List<LyricLine>?> _fetchSyncedFromLrclib(String artist, String title) async {
    try {
      final artistEnc = Uri.encodeComponent(artist);
      final titleEnc = Uri.encodeComponent(title);
      
      final url = 'https://lrclib.net/api/get?artist_name=$artistEnc&track_name=$titleEnc';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final syncedLyrics = data['syncedLyrics'];
        
        if (syncedLyrics != null && syncedLyrics.toString().isNotEmpty) {
          return _parseLrc(syncedLyrics);
        }
        
        final plainLyrics = data['plainLyrics'];
        if (plainLyrics != null && plainLyrics.toString().isNotEmpty) {
          return plainLyrics
              .toString()
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .map((line) => LyricLine(time: null, text: line.trim()))
              .toList();
        }
      }
    } catch (e) {
      print('LRCLIB synced error: $e');
    }
    return null;
  }

  static Future<String?> _fetchFromLyricsOvh(String artist, String title) async {
    try {
      final artistEnc = Uri.encodeComponent(artist);
      final titleEnc = Uri.encodeComponent(title);
      
      final url = 'https://api.lyrics.ovh/v1/$artistEnc/$titleEnc';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['lyrics'] != null && data['lyrics'].toString().trim().isNotEmpty) {
          return data['lyrics'].toString().trim();
        }
      }
    } catch (e) {
      print('Lyrics.ovh error: $e');
    }
    return null;
  }

  static Future<String?> _fetchFromLrclib(String artist, String title) async {
    try {
      final artistEnc = Uri.encodeComponent(artist);
      final titleEnc = Uri.encodeComponent(title);
      
      final url = 'https://lrclib.net/api/get?artist_name=$artistEnc&track_name=$titleEnc';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lyrics = data['plainLyrics'] ?? data['syncedLyrics'];
        if (lyrics != null && lyrics.toString().trim().isNotEmpty) {
          return lyrics.toString()
              .replaceAll(RegExp(r'\[\d{2}:\d{2}\.\d{2,3}\]'), '')
              .trim();
        }
      }
    } catch (e) {
      print('LRCLIB error: $e');
    }
    return null;
  }

  static List<LyricLine> _parseLrc(String lrc) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');
    
    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisStr = match.group(3)!;
        final millis = int.parse(millisStr.padRight(3, '0'));
        final text = match.group(4)?.trim() ?? '';
        
        if (text.isNotEmpty) {
          final time = Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
          lines.add(LyricLine(time: time, text: text));
        }
      }
    }
    return lines;
  }
}

class LyricLine {
  final Duration? time;
  final String text;
  LyricLine({required this.time, required this.text});
  bool get isSynced => time != null;
}
