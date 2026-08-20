import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CoverService {
  static const _timeout = Duration(seconds: 10);

  /// Deezer limituje ~50 zapytan / 5 s. Przy masowym pobieraniu (setki
  /// albumow) bez odstepu API zaczyna zwracac bledy i NIC sie nie pobiera.
  static const _minGap = Duration(milliseconds: 250);
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// Nazwy folderow typu "Mix - Brodka - Granda" daja artyste = "Mix".
  /// To nie jest artysta, tylko marker skladanki — w takim wypadku
  /// prawdziwy artysta siedzi w tytule.
  static const _compilationMarkers = {
    'mix', 'mixy', 'skladanka', 'składanka', 'skladanki', 'składanki',
    'various', 'various artists', 'va', 'rozni', 'różni',
    'rozni wykonawcy', 'różni wykonawcy', 'compilation', 'compilations',
    'hits', 'hity', 'best of', 'the best', 'przeboje', 'nieznany',
    'nieznany artysta', 'unknown', 'unknown artist',
  };

  static Future<void> _throttle() async {
    final since = DateTime.now().difference(_lastRequest);
    if (since < _minGap) {
      await Future<void>.delayed(_minGap - since);
    }
    _lastRequest = DateTime.now();
  }

  static Future<http.Response?> _get(String url) async {
    await _throttle();
    try {
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode == 429) {
        // Rate limit — odczekaj i sprobuj raz jeszcze.
        await Future<void>.delayed(const Duration(seconds: 2));
        await _throttle();
        return await http.get(Uri.parse(url)).timeout(_timeout);
      }
      return res;
    } catch (e) {
      debugPrint('CoverService request error: $e');
      return null;
    }
  }

  /// Normalizuje pare (artysta, album). Gdy artysta to marker skladanki,
  /// a tytul ma format "Artysta - Album", rozbija tytul na wlasciwe czesci.
  static ({String artist, String album}) normalize(String artist, String album) {
    var a = artist.trim();
    var b = album.trim();

    if (_compilationMarkers.contains(a.toLowerCase()) && b.contains(' - ')) {
      final parts = b.split(' - ');
      a = parts[0].trim();
      b = parts.sublist(1).join(' - ').trim();
    }
    return (artist: a, album: b);
  }

  static Future<String?> fetchCover(String artist, String album) async {
    final n = normalize(artist, album);
    final a = n.artist;
    final b = n.album;
    if (a.isEmpty && b.isEmpty) return null;

    try {
      // 1. Bezposrednie szukanie albumu (najskuteczniejsze dla dowolnych nazw).
      final direct = await _searchAlbum(a, b);
      if (direct != null) return direct;

      // 2. Przez artyste — dopasuj album z jego dyskografii.
      if (a.isNotEmpty) {
        final artistId = await _findArtistId(a);
        if (artistId != null) {
          final albums = await _getArtistAlbums(artistId);
          final cover = _findMatchingCover(albums, b);
          if (cover != null) return cover;
        }
      }

      // 3. iTunes jako backup.
      return await _fetchFromItunes(a, b);
    } catch (e) {
      debugPrint('fetchCover error: $e');
      return null;
    }
  }

  /// Deezer /search/album — szuka po nazwie albumu (i artyscie jesli znany).
  static Future<String?> _searchAlbum(String artist, String album) async {
    final queries = <String>[
      if (artist.isNotEmpty && album.isNotEmpty) '$artist $album',
      if (album.isNotEmpty) album,
    ];

    for (final q in queries) {
      final clean = _cleanAlbumName(q);
      if (clean.isEmpty) continue;
      final res =
          await _get('https://api.deezer.com/search/album?q=${Uri.encodeComponent(clean)}&limit=5');
      if (res == null || res.statusCode != 200) continue;

      try {
        final data = json.decode(res.body);
        final results = data['data'];
        if (results is List && results.isNotEmpty) {
          final first = results[0];
          final cover =
              first['cover_xl'] ?? first['cover_big'] ?? first['cover_medium'];
          if (cover != null) return cover.toString();
        }
      } catch (_) {
        // niepoprawny JSON — probuj dalej
      }
    }
    return null;
  }

  /// Propozycje z Deezer /search/album — kluczowe dla skladanek, gdzie
  /// dyskografia artysty nie zawiera szukanego wydawnictwa.
  static Future<void> _addAlbumSearchSuggestions(
      List<CoverSuggestion> suggestions, String artist, String album) async {
    final q = _cleanAlbumName(
        [if (artist.isNotEmpty) artist, if (album.isNotEmpty) album].join(' '));
    if (q.isEmpty) return;

    final res = await _get(
        'https://api.deezer.com/search/album?q=${Uri.encodeComponent(q)}&limit=6');
    if (res == null || res.statusCode != 200) return;

    try {
      final data = json.decode(res.body);
      final results = data['data'];
      if (results is! List) return;

      final existing = suggestions.map((s) => s.url).toSet();
      for (final item in results) {
        if (suggestions.length >= 6) break;
        final cover =
            item['cover_xl'] ?? item['cover_big'] ?? item['cover_medium'];
        if (cover == null) continue;
        final url = cover.toString();
        if (existing.contains(url)) continue;
        existing.add(url);
        suggestions.add(CoverSuggestion(
          url: url,
          artist: item['artist']?['name']?.toString() ?? artist,
          album: item['title']?.toString() ?? album,
          source: 'Deezer',
        ));
      }
    } catch (_) {
      // niepoprawny JSON — pomin
    }
  }

  static Future<List<CoverSuggestion>> fetchSuggestions(
      String rawArtist, String rawAlbum) async {
    final suggestions = <CoverSuggestion>[];

    final n = normalize(rawArtist, rawAlbum);
    final artist = n.artist;
    final album = n.album;
    if (artist.isEmpty && album.isEmpty) return suggestions;

    try {
      // Propozycje z bezposredniego szukania albumu (dziala tez dla skladanek).
      await _addAlbumSearchSuggestions(suggestions, artist, album);

      // Znajdz artyste
      final artistId = artist.isEmpty ? null : await _findArtistId(artist);
      
      if (artistId != null) {
        // Pobierz albumy artysty
        final albums = await _getArtistAlbums(artistId);
        
        // Dodaj albumy jako propozycje
        for (var albumData in albums) {
          if (suggestions.length >= 8) break;
          
          final coverUrl = albumData['cover_xl'] ?? albumData['cover_big'] ?? albumData['cover_medium'];
          final albumTitle = albumData['title'];
          final albumArtist = albumData['artist']?['name'] ?? artist;
          
          if (coverUrl != null && albumTitle != null) {
            suggestions.add(CoverSuggestion(
              url: coverUrl.toString(),
              artist: albumArtist.toString(),
              album: albumTitle.toString(),
              source: 'Deezer',
            ));
          }
        }
      }
      
      // Dodaj tez z iTunes
      await _addItunesSuggestions(suggestions, artist, album);
      
    } catch (e) {
      debugPrint('fetchSuggestions error: $e');
    }
    
    return suggestions;
  }

  static Future<int?> _findArtistId(String artist) async {
    try {
      final query = Uri.encodeComponent(artist);
      final response =
          await _get('https://api.deezer.com/search/artist?q=$query&limit=5');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['data'];
        
        if (results != null && results is List && results.isNotEmpty) {
          // Szukaj dokladnego dopasowania
          for (var item in results) {
            final name = item['name']?.toString().toLowerCase() ?? '';
            if (name == artist.toLowerCase() || name.contains(artist.toLowerCase()) || artist.toLowerCase().contains(name)) {
              final id = item['id'];
              if (id != null) return id is int ? id : int.tryParse(id.toString());
            }
          }
          // Fallback - pierwszy wynik
          final id = results[0]['id'];
          if (id != null) return id is int ? id : int.tryParse(id.toString());
        }
      }
    } catch (e) {
      debugPrint('_findArtistId error: $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _getArtistAlbums(int artistId) async {
    final albums = <Map<String, dynamic>>[];
    
    try {
      final response =
          await _get('https://api.deezer.com/artist/$artistId/albums?limit=50');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['data'];
        
        if (results != null && results is List) {
          for (var item in results) {
            if (item is Map<String, dynamic>) {
              albums.add(item);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_getArtistAlbums error: $e');
    }
    
    return albums;
  }

  static String? _findMatchingCover(List<Map<String, dynamic>> albums, String searchAlbum) {
    if (albums.isEmpty) return null;
    
    final cleanSearch = _cleanAlbumName(searchAlbum);
    
    // Szukaj dopasowania
    for (var album in albums) {
      final title = album['title']?.toString() ?? '';
      final cleanTitle = _cleanAlbumName(title);
      
      // Dokladne dopasowanie lub zawiera sie
      if (cleanTitle == cleanSearch || cleanTitle.contains(cleanSearch) || cleanSearch.contains(cleanTitle)) {
        final cover = album['cover_xl'] ?? album['cover_big'] ?? album['cover_medium'];
        if (cover != null) return cover.toString();
      }
    }
    
    // Szukaj po slowach kluczowych
    final searchWords = cleanSearch.split(' ').where((w) => w.length > 2).toSet();
    
    for (var album in albums) {
      final title = album['title']?.toString() ?? '';
      final cleanTitle = _cleanAlbumName(title);
      final titleWords = cleanTitle.split(' ').where((w) => w.length > 2).toSet();
      
      final common = searchWords.intersection(titleWords);
      if (common.isNotEmpty) {
        final cover = album['cover_xl'] ?? album['cover_big'] ?? album['cover_medium'];
        if (cover != null) return cover.toString();
      }
    }
    
    return null;
  }

  static String _cleanAlbumName(String album) {
    return album
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'cd\s*\d+'), '')
        .replaceAll(RegExp(r'disc\s*\d+'), '')
        .replaceAll(RegExp(r'vol\.?\s*\d+'), '')
        .replaceAll(RegExp(r'remaster'), '')
        .replaceAll(RegExp(r'deluxe'), '')
        .replaceAll(RegExp(r'edition'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<String?> _fetchFromItunes(String artist, String album) async {
    try {
      final query = Uri.encodeComponent('$artist $album'.trim());
      final response = await _get(
          'https://itunes.apple.com/search?term=$query&media=music&entity=album&limit=5');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (results != null && results is List && results.isNotEmpty) {
          for (var item in results) {
            final resultArtist = item['artistName']?.toString().toLowerCase() ?? '';
            if (resultArtist.contains(artist.toLowerCase()) || artist.toLowerCase().contains(resultArtist)) {
              final artwork = item['artworkUrl100']?.toString();
              if (artwork != null) {
                return artwork.replaceAll('100x100', '600x600');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_fetchFromItunes error: $e');
    }
    return null;
  }

  static Future<void> _addItunesSuggestions(List<CoverSuggestion> suggestions, String artist, String album) async {
    try {
      final query = Uri.encodeComponent('$artist $album'.trim());
      final response = await _get(
          'https://itunes.apple.com/search?term=$query&media=music&entity=album&limit=5');

      if (response != null && response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (results != null && results is List) {
          final existingUrls = suggestions.map((s) => s.url).toSet();
          
          for (var item in results) {
            if (suggestions.length >= 10) break;
            
            final resultArtist = item['artistName']?.toString() ?? '';
            if (!resultArtist.toLowerCase().contains(artist.toLowerCase()) && 
                !artist.toLowerCase().contains(resultArtist.toLowerCase())) {
              continue;
            }
            
            final artwork = item['artworkUrl100']?.toString();
            final albumName = item['collectionName']?.toString() ?? '';
            
            if (artwork != null) {
              final coverUrl = artwork.replaceAll('100x100', '600x600');
              if (!existingUrls.contains(coverUrl)) {
                existingUrls.add(coverUrl);
                suggestions.add(CoverSuggestion(
                  url: coverUrl,
                  artist: resultArtist,
                  album: albumName,
                  source: 'iTunes',
                ));
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('_addItunesSuggestions error: $e');
    }
  }
}

class CoverSuggestion {
  final String url;
  final String artist;
  final String album;
  final String source;

  CoverSuggestion({
    required this.url,
    required this.artist,
    required this.album,
    required this.source,
  });
}
