import 'dart:convert';
import 'package:http/http.dart' as http;

class CoverService {
  static const _timeout = Duration(seconds: 10);

  static Future<String?> fetchCover(String artist, String album) async {
    if (artist.isEmpty) return null;
    
    try {
      // 1. Znajdz artyste
      final artistId = await _findArtistId(artist);
      
      if (artistId != null) {
        // 2. Pobierz albumy artysty
        final albums = await _getArtistAlbums(artistId);
        
        // 3. Znajdz pasujacy album
        final cover = _findMatchingCover(albums, album);
        if (cover != null) return cover;
        
        // 4. Fallback - pierwszy album artysty
        if (albums.isNotEmpty) {
          final firstAlbum = albums[0];
          final cover = firstAlbum['cover_xl'] ?? firstAlbum['cover_big'] ?? firstAlbum['cover_medium'];
          if (cover != null) return cover.toString();
        }
      }
      
      // 5. iTunes jako backup
      return await _fetchFromItunes(artist, album);
    } catch (e) {
      print('fetchCover error: $e');
      return null;
    }
  }

  static Future<List<CoverSuggestion>> fetchSuggestions(String artist, String album) async {
    final suggestions = <CoverSuggestion>[];
    
    if (artist.isEmpty) return suggestions;
    
    try {
      // Znajdz artyste
      final artistId = await _findArtistId(artist);
      
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
      print('fetchSuggestions error: $e');
    }
    
    return suggestions;
  }

  static Future<int?> _findArtistId(String artist) async {
    try {
      final query = Uri.encodeComponent(artist);
      final response = await http.get(
        Uri.parse('https://api.deezer.com/search/artist?q=$query&limit=5'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
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
      print('_findArtistId error: $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _getArtistAlbums(int artistId) async {
    final albums = <Map<String, dynamic>>[];
    
    try {
      final response = await http.get(
        Uri.parse('https://api.deezer.com/artist/$artistId/albums?limit=50'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
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
      print('_getArtistAlbums error: $e');
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
      final query = Uri.encodeComponent('$artist $album');
      final response = await http.get(
        Uri.parse('https://itunes.apple.com/search?term=$query&media=music&entity=album&limit=5'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
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
      print('_fetchFromItunes error: $e');
    }
    return null;
  }

  static Future<void> _addItunesSuggestions(List<CoverSuggestion> suggestions, String artist, String album) async {
    try {
      final query = Uri.encodeComponent('$artist $album');
      final response = await http.get(
        Uri.parse('https://itunes.apple.com/search?term=$query&media=music&entity=album&limit=5'),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
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
      print('_addItunesSuggestions error: $e');
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
