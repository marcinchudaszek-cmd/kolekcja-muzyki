import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Wyszukiwanie i weryfikacja okladek (Deezer, iTunes jako zapas).
///
/// Kazdy kandydat dostaje ocene dopasowania wykonawcy i tytulu. Okladka jest
/// przyjmowana automatycznie tylko przy pewnym dopasowaniu — wczesniej brany
/// byl pierwszy wynik wyszukiwania bez sprawdzenia, stad bledne okladki
/// (inny wykonawca, inny album o podobnej nazwie).
class CoverService {
  static const _timeout = Duration(seconds: 10);

  /// Deezer limituje ~50 zapytan / 5 s. Przy masowym pobieraniu (setki
  /// albumow) bez odstepu API zaczyna zwracac bledy i NIC sie nie pobiera.
  static const _minGap = Duration(milliseconds: 250);
  static DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// iTunes Search API wpuszcza ok. 20 zapytan na minute.
  static const _itunesGap = Duration(seconds: 3);
  static DateTime _lastItunes = DateTime.fromMillisecondsSinceEpoch(0);

  /// Nazwy folderow typu "Mix - Brodka - Granda" daja artyste = "Mix".
  /// To nie jest artysta, tylko marker skladanki — w takim wypadku
  /// prawdziwy artysta siedzi w tytule.
  static const _compilationMarkers = {
    'mix', 'mixy', 'skladanka', 'składanka', 'skladanki', 'składanki',
    'various', 'various artists', 'va', 'rozni', 'różni',
    'rozni wykonawcy', 'różni wykonawcy', 'compilation', 'compilations',
    'hits', 'hity', 'best of', 'the best', 'przeboje', 'nieznany',
    'nieznany artysta', 'unknown', 'unknown artist', '<unknown>',
  };

  static Future<void> _throttle() async {
    final since = DateTime.now().difference(_lastRequest);
    if (since < _minGap) {
      await Future<void>.delayed(_minGap - since);
    }
    _lastRequest = DateTime.now();
  }

  static Future<http.Response?> _get(String url, {bool itunes = false}) async {
    if (itunes) {
      final since = DateTime.now().difference(_lastItunes);
      if (since < _itunesGap) await Future<void>.delayed(_itunesGap - since);
      _lastItunes = DateTime.now();
    } else {
      await _throttle();
    }
    try {
      final res = await http.get(Uri.parse(url)).timeout(_timeout);
      if (res.statusCode == 429 || (itunes && res.statusCode == 403)) {
        // Rate limit — odczekaj i sprobuj raz jeszcze.
        await Future<void>.delayed(Duration(seconds: itunes ? 10 : 2));
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

  /// "Nieznany artysta" — z samego tytulu (czesto ogolnego, np. "Moje
  /// piosenki") nie da sie pewnie ustalic okladki.
  static const _unknownMarkers = {
    'nieznany', 'nieznany artysta', 'unknown', 'unknown artist', '<unknown>',
  };

  static bool _isUnknownArtist(String artist) =>
      _unknownMarkers.contains(artist.trim().toLowerCase());

  static bool _isCompilationArtist(String artist) =>
      artist.trim().isEmpty ||
      _compilationMarkers.contains(artist.trim().toLowerCase());

  // ----- Porownywanie nazw -----

  static const _diacritics = <String, String>{
    'ą': 'a', 'ć': 'c', 'ę': 'e', 'ł': 'l', 'ń': 'n', 'ó': 'o',
    'ś': 's', 'ź': 'z', 'ż': 'z',
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'á': 'a', 'é': 'e', 'í': 'i', 'ú': 'u', 'à': 'a', 'è': 'e',
    'ì': 'i', 'ò': 'o', 'ù': 'u', 'â': 'a', 'ê': 'e', 'î': 'i',
    'ô': 'o', 'û': 'u', 'ç': 'c', 'ñ': 'n', 'ø': 'o', 'å': 'a',
  };

  static String _fold(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(_diacritics[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Tytul albumu bez dopiskow wydania, numerow plyt i roku z nazwy folderu.
  static String _cleanAlbumName(String album) {
    return _fold(album)
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'\[.*?\]'), ' ')
        // "1999 - Tytul" / "Tytul - 1999" — rok z nazwy folderu
        .replaceAll(RegExp(r'^\s*(19|20)\d\d\s*[-–_.]\s*'), ' ')
        .replaceAll(RegExp(r'\s*[-–_]\s*(19|20)\d\d\s*$'), ' ')
        .replaceAll(RegExp(r'\b(cd|disc|disk|dysk|plyta)\s*\d+\b'), ' ')
        .replaceAll(RegExp(r'\bvol\.?\s*\d+\b'), ' ')
        .replaceAll(
            RegExp(r'\b(remaster(ed)?|deluxe|edition|expanded|anniversary|'
                r'bonus tracks?|special|limited|reissue|ep|single)\b'),
            ' ')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanArtist(String artist) {
    return _fold(artist)
        .replaceAll(RegExp(r'^the\s+'), '')
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'\b(feat|ft|featuring)\b.*$'), '')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Podobienstwo dwoch oczyszczonych nazw w skali 0..1.
  static double _similarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    // "Granda" vs "Granda Live" — zawieranie na granicy slow.
    if (shorter.length >= 3 &&
        RegExp('(^|\\s)${RegExp.escape(shorter)}(\\s|\$)').hasMatch(longer)) {
      return 0.85;
    }
    final ta = a.split(' ').where((w) => w.isNotEmpty).toSet();
    final tb = b.split(' ').where((w) => w.isNotEmpty).toSet();
    final common = ta.intersection(tb).length;
    return 2 * common / (ta.length + tb.length);
  }

  static _Candidate _score(_Candidate c, String artist, String album,
      int? trackCount) {
    final compilation = _isCompilationArtist(artist);
    final candArtist = _cleanArtist(c.artist);
    c.artistScore = compilation
        ? (_isCompilationArtist(c.artist) || candArtist == 'various artists'
            ? 1.0
            : 0.5)
        : _similarity(_cleanArtist(artist), candArtist);
    c.titleScore = _similarity(_cleanAlbumName(album), _cleanAlbumName(c.album));

    var bonus = 0.0;
    final n = c.trackCount;
    if (trackCount != null && trackCount > 0 && n != null && n > 0) {
      final diff = (n - trackCount).abs();
      if (diff == 0) {
        bonus = 0.1;
      } else if (diff <= 2) {
        bonus = 0.05;
      } else if (diff > max(n, trackCount) / 2) {
        bonus = -0.1;
      }
    }
    // Remis "Granda" vs "Granda (Rework)" — wygrywa identyczny tytul.
    if (_fold(c.album).trim() == _fold(album).trim()) bonus += 0.02;
    c.score = 0.45 * c.artistScore + 0.55 * c.titleScore + bonus;
    return c;
  }

  /// Pewne dopasowanie: zgodny wykonawca I tytul. Dla skladanek (brak
  /// wykonawcy) wymagany prawie identyczny tytul.
  static bool _isConfident(_Candidate c, String artist) {
    if (_isUnknownArtist(artist)) return false;
    if (_isCompilationArtist(artist)) {
      return c.titleScore >= 0.95 && c.artistScore >= 1.0;
    }
    return c.artistScore >= 0.7 && c.titleScore >= 0.6;
  }

  /// Klucz okladki niezalezny od rozmiaru obrazka, zeby porownac URL
  /// zapisany w kolekcji z URL-ami kandydatow.
  static String coverKey(String url) {
    final deezer = RegExp(r'/images/cover/([0-9a-fA-F]+)/').firstMatch(url);
    if (deezer != null) return 'dz:${deezer.group(1)!.toLowerCase()}';
    final apple = RegExp(r'mzstatic\.com/image/thumb/(.+)/[^/]+$').firstMatch(url);
    if (apple != null) return 'it:${apple.group(1)}';
    return url;
  }

  // ----- Kandydaci z API -----

  static String? _deezerCover(Map item) =>
      (item['cover_xl'] ?? item['cover_big'] ?? item['cover_medium'])
          ?.toString();

  static Future<List<_Candidate>> _deezerSearch(String query) async {
    final res = await _get(
        'https://api.deezer.com/search/album?q=${Uri.encodeComponent(query)}&limit=10');
    if (res == null || res.statusCode != 200) return const [];
    try {
      final results = json.decode(res.body)['data'];
      if (results is! List) return const [];
      return [
        for (final item in results)
          if (item is Map && _deezerCover(item) != null)
            _Candidate(
              url: _deezerCover(item)!,
              artist: item['artist']?['name']?.toString() ?? '',
              album: item['title']?.toString() ?? '',
              source: 'Deezer',
              trackCount: (item['nb_tracks'] as num?)?.toInt(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<_Candidate>> _itunesSearch(String query) async {
    final res = await _get(
        'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}'
        '&media=music&entity=album&limit=10&country=PL',
        itunes: true);
    if (res == null || res.statusCode != 200) return const [];
    try {
      final results = json.decode(res.body)['results'];
      if (results is! List) return const [];
      return [
        for (final item in results)
          if (item is Map && item['artworkUrl100'] != null)
            _Candidate(
              url: item['artworkUrl100']
                  .toString()
                  .replaceAll('100x100', '600x600'),
              artist: item['artistName']?.toString() ?? '',
              album: item['collectionName']?.toString() ?? '',
              source: 'iTunes',
              trackCount: (item['trackCount'] as num?)?.toInt(),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Kandydaci posortowani od najlepszego. iTunes odpytywany tylko, gdy
  /// Deezer nie dal pewnego trafienia (lub gdy [alwaysItunes]).
  static Future<List<_Candidate>> _candidates(
    String rawArtist,
    String rawAlbum, {
    int? trackCount,
    bool alwaysItunes = false,
  }) async {
    final n = normalize(rawArtist, rawAlbum);
    final artist = n.artist;
    final album = n.album;
    if (album.isEmpty) return const [];

    final compilation = _isCompilationArtist(artist);
    final cleanAlbum = _cleanAlbumName(album);
    if (cleanAlbum.isEmpty) return const [];

    final found = <String, _Candidate>{};
    void addAll(List<_Candidate> list) {
      for (final c in list) {
        found.putIfAbsent(coverKey(c.url),
            () => _score(c, artist, album, trackCount));
      }
    }

    bool hasConfident() =>
        found.values.any((c) => _isConfident(c, artist));

    if (!compilation) {
      // Wyszukiwanie zaawansowane Deezera: pola wykonawcy i albumu osobno.
      addAll(await _deezerSearch('artist:"$artist" album:"$cleanAlbum"'));
      if (!hasConfident()) {
        addAll(await _deezerSearch('${_cleanArtist(artist)} $cleanAlbum'));
      }
    } else {
      addAll(await _deezerSearch(cleanAlbum));
    }

    if (alwaysItunes || !hasConfident()) {
      addAll(await _itunesSearch(
          compilation ? cleanAlbum : '${_cleanArtist(artist)} $cleanAlbum'));
    }

    final list = found.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return list;
  }

  // ----- API publiczne -----

  /// Okladka tylko przy pewnym dopasowaniu; null, gdy nic pewnego.
  /// [trackCount] (liczba utworow w albumie) pomaga odroznic wydania.
  static Future<String?> fetchCover(String artist, String album,
      {int? trackCount}) async {
    try {
      final cands = await _candidates(artist, album, trackCount: trackCount);
      final artistN = normalize(artist, album).artist;
      for (final c in cands) {
        if (_isConfident(c, artistN)) return c.url;
      }
    } catch (e) {
      debugPrint('fetchCover error: $e');
    }
    return null;
  }

  /// Sprawdza zapisana okladke albumu i — jesli trzeba — proponuje inna.
  static Future<CoverCheck> checkCover(
    String artist,
    String album, {
    String? currentUrl,
    int? trackCount,
  }) async {
    final cands = await _candidates(artist, album, trackCount: trackCount);
    final artistN = normalize(artist, album).artist;
    final confident = cands.where((c) => _isConfident(c, artistN)).toList();
    final hasCurrent = currentUrl != null && currentUrl.isNotEmpty;

    if (hasCurrent) {
      final key = coverKey(currentUrl);
      // Obecna okladka jest wsrod dobrze pasujacych kandydatow — w porzadku
      // (prog nizszy niz "pewny", zeby nie podmieniac np. wersji deluxe).
      final matchesCurrent = cands.any((c) =>
          coverKey(c.url) == key && c.titleScore >= 0.5 && c.artistScore >= 0.6);
      if (matchesCurrent) return const CoverCheck(CoverVerdict.ok);
    }

    if (confident.isNotEmpty) {
      final best = confident.first;
      return CoverCheck(
        hasCurrent ? CoverVerdict.replace : CoverVerdict.add,
        newUrl: best.url,
        matchArtist: best.artist,
        matchAlbum: best.album,
        source: best.source,
      );
    }
    return CoverCheck(
        hasCurrent ? CoverVerdict.unconfirmed : CoverVerdict.notFound);
  }

  /// Propozycje do recznego wyboru — najlepiej pasujace na poczatku, potem
  /// reszta dyskografii wykonawcy.
  static Future<List<CoverSuggestion>> fetchSuggestions(
      String rawArtist, String rawAlbum, {int? trackCount}) async {
    final suggestions = <CoverSuggestion>[];
    final n = normalize(rawArtist, rawAlbum);
    final artist = n.artist;
    if (artist.isEmpty && n.album.isEmpty) return suggestions;

    try {
      final cands = await _candidates(rawArtist, rawAlbum,
          trackCount: trackCount, alwaysItunes: true);
      final seen = <String>{};
      for (final c in cands.take(10)) {
        if (!seen.add(coverKey(c.url))) continue;
        suggestions.add(CoverSuggestion(
          url: c.url,
          artist: c.artist,
          album: c.album,
          source: c.source,
          match: c.score.clamp(0.0, 1.0),
        ));
      }

      // Dyskografia wykonawcy — gdy szukany album ma inna nazwe w serwisie.
      if (!_isCompilationArtist(artist) && suggestions.length < 16) {
        final artistId = await _findArtistId(artist);
        if (artistId != null) {
          for (final item in await _getArtistAlbums(artistId)) {
            if (suggestions.length >= 16) break;
            final url = _deezerCover(item);
            if (url == null || !seen.add(coverKey(url))) continue;
            suggestions.add(CoverSuggestion(
              url: url,
              artist: item['artist']?['name']?.toString() ?? artist,
              album: item['title']?.toString() ?? '',
              source: 'Deezer',
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('fetchSuggestions error: $e');
    }
    return suggestions;
  }

  static Future<int?> _findArtistId(String artist) async {
    try {
      final response = await _get(
          'https://api.deezer.com/search/artist?q=${Uri.encodeComponent(artist)}&limit=5');
      if (response == null || response.statusCode != 200) return null;
      final results = json.decode(response.body)['data'];
      if (results is! List || results.isEmpty) return null;
      final wanted = _cleanArtist(artist);
      for (final item in results) {
        if (_similarity(wanted, _cleanArtist(item['name']?.toString() ?? '')) >=
            0.85) {
          final id = item['id'];
          return id is int ? id : int.tryParse(id.toString());
        }
      }
      // Brak zgodnego wykonawcy — lepiej nic niz cudza dyskografia.
      return null;
    } catch (e) {
      debugPrint('_findArtistId error: $e');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> _getArtistAlbums(int artistId) async {
    try {
      final response =
          await _get('https://api.deezer.com/artist/$artistId/albums?limit=50');
      if (response == null || response.statusCode != 200) return const [];
      final results = json.decode(response.body)['data'];
      if (results is! List) return const [];
      return [
        for (final item in results)
          if (item is Map<String, dynamic>) item,
      ];
    } catch (e) {
      debugPrint('_getArtistAlbums error: $e');
      return const [];
    }
  }

  // ----- Okladki wybrane recznie -----

  static const _prefsManual = 'cover_manual_album_ids';

  /// Okladki wybrane recznie (propozycja, wklejony URL) — przeglad okladek
  /// ich nie rusza.
  static Future<void> markManual(String albumId, bool manual) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(_prefsManual) ?? []).toSet();
      manual ? ids.add(albumId) : ids.remove(albumId);
      await prefs.setStringList(_prefsManual, ids.toList());
    } catch (e) {
      debugPrint('markManual error: $e');
    }
  }

  static Future<Set<String>> manualIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsManual) ?? []).toSet();
    } catch (_) {
      return {};
    }
  }
}

class _Candidate {
  _Candidate({
    required this.url,
    required this.artist,
    required this.album,
    required this.source,
    this.trackCount,
  });

  final String url;
  final String artist;
  final String album;
  final String source;
  final int? trackCount;
  double artistScore = 0;
  double titleScore = 0;
  double score = 0;
}

enum CoverVerdict {
  /// Obecna okladka pasuje.
  ok,

  /// Obecna okladka nie pasuje, jest pewna lepsza.
  replace,

  /// Brak okladki, znaleziono pewna.
  add,

  /// Jest okladka, ale nie udalo sie jej potwierdzic ani znalezc lepszej.
  unconfirmed,

  /// Brak okladki i nic pewnego nie znaleziono.
  notFound,
}

class CoverCheck {
  const CoverCheck(
    this.verdict, {
    this.newUrl,
    this.matchArtist,
    this.matchAlbum,
    this.source,
  });

  final CoverVerdict verdict;
  final String? newUrl;
  final String? matchArtist;
  final String? matchAlbum;
  final String? source;
}

class CoverSuggestion {
  final String url;
  final String artist;
  final String album;
  final String source;

  /// Ocena dopasowania 0..1 (null dla pozycji z dyskografii).
  final double? match;

  CoverSuggestion({
    required this.url,
    required this.artist,
    required this.album,
    required this.source,
    this.match,
  });
}
