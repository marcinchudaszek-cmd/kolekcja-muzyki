import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/album.dart';

class DatabaseService extends ChangeNotifier {
  late Box<Album> _albumsBox;
  List<Album> _albums = [];
  
  // Filtrowanie i sortowanie
  String _searchQuery = '';
  String _genreFilter = 'all';
  String _formatFilter = 'all';
  String _sortBy = 'artist'; // artist, title, year, rating, recent
  bool _sortAscending = true;
  bool _showOnlyFavorites = false;
  bool _showOnlyWishlist = false;

  // Gettery
  List<Album> get albums => _filteredAlbums;
  List<Album> get allAlbums => _albums;
  String get searchQuery => _searchQuery;
  String get genreFilter => _genreFilter;
  String get formatFilter => _formatFilter;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  bool get showOnlyFavorites => _showOnlyFavorites;
  bool get showOnlyWishlist => _showOnlyWishlist;

  // Statystyki
  int get totalAlbums => _albums.length;
  int get totalTracks => _albums.fold(0, (sum, a) => sum + a.tracks.length);
  int get favoriteCount => _albums.where((a) => a.isFavorite).length;
  int get wishlistCount => _albums.where((a) => a.isWishlist).length;
  
  Map<String, int> get genreStats {
    final stats = <String, int>{};
    for (var album in _albums) {
      stats[album.genre] = (stats[album.genre] ?? 0) + 1;
    }
    return stats;
  }

  Map<String, int> get formatStats {
    final stats = <String, int>{};
    for (var album in _albums) {
      stats[album.format] = (stats[album.format] ?? 0) + 1;
    }
    return stats;
  }

  DatabaseService() {
    _init();
  }

  Future<void> _init() async {
    _albumsBox = Hive.box<Album>('albums');
    _loadAlbums();
  }

  void _loadAlbums() {
    _albums = _albumsBox.values.toList();
    notifyListeners();
  }

  // Filtrowane albumy
  List<Album> get _filteredAlbums {
    var filtered = List<Album>.from(_albums);

    // Ulubione
    if (_showOnlyFavorites) {
      filtered = filtered.where((a) => a.isFavorite).toList();
    }

    // Lista zyczen
    if (_showOnlyWishlist) {
      filtered = filtered.where((a) => a.isWishlist).toList();
    }

    // Wyszukiwanie
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((a) =>
        a.artist.toLowerCase().contains(query) ||
        a.title.toLowerCase().contains(query) ||
        a.tracks.any((t) => t.title.toLowerCase().contains(query))
      ).toList();
    }

    // Filtr gatunku
    if (_genreFilter != 'all') {
      filtered = filtered.where((a) => a.genre == _genreFilter).toList();
    }

    // Filtr formatu
    if (_formatFilter != 'all') {
      filtered = filtered.where((a) => a.format == _formatFilter).toList();
    }

    // Sortowanie
    filtered.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'artist':
          result = a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
          break;
        case 'title':
          result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'year':
          result = (a.year ?? 0).compareTo(b.year ?? 0);
          break;
        case 'rating':
          result = a.rating.compareTo(b.rating);
          break;
        case 'recent':
          result = a.createdAt.compareTo(b.createdAt);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });

    return filtered;
  }

  // Dodaj album
  Future<bool> addAlbum(Album album) async {
    // Sprawdz duplikaty
    if (isDuplicate(album.artist, album.title)) {
      return false; // Album juz istnieje
    }
    await _albumsBox.put(album.id, album);
    _loadAlbums();
    return true;
  }

  // Dodaj wiele albumow (zwraca liczbe dodanych)
  Future<int> addAlbums(List<Album> albums) async {
    int added = 0;
    for (var album in albums) {
      if (!isDuplicate(album.artist, album.title)) {
        await _albumsBox.put(album.id, album);
        added++;
      }
    }
    _loadAlbums();
    return added;
  }

  // Sprawdz czy album juz istnieje
  bool isDuplicate(String artist, String title) {
    final artistLower = artist.toLowerCase().trim();
    final titleLower = title.toLowerCase().trim();
    
    return _albums.any((a) => 
      a.artist.toLowerCase().trim() == artistLower &&
      a.title.toLowerCase().trim() == titleLower
    );
  }

  // Znajdz podobne albumy (do ostrzezenia)
  List<Album> findSimilar(String artist, String title) {
    final artistLower = artist.toLowerCase().trim();
    final titleLower = title.toLowerCase().trim();
    
    return _albums.where((a) {
      final aArtist = a.artist.toLowerCase().trim();
      final aTitle = a.title.toLowerCase().trim();
      
      // Dokladne dopasowanie
      if (aArtist == artistLower && aTitle == titleLower) return true;
      
      // Czesciowe dopasowanie
      if (aArtist.contains(artistLower) || artistLower.contains(aArtist)) {
        if (aTitle.contains(titleLower) || titleLower.contains(aTitle)) {
          return true;
        }
      }
      
      return false;
    }).toList();
  }

  // Aktualizuj album
  Future<void> updateAlbum(Album album) async {
    await _albumsBox.put(album.id, album);
    _loadAlbums();
  }

  // Usun album
  Future<void> deleteAlbum(String id) async {
    await _albumsBox.delete(id);
    _loadAlbums();
  }

  // Pobierz album po ID
  Album? getAlbum(String id) {
    return _albums.firstWhere((a) => a.id == id, orElse: () => throw Exception('Album not found'));
  }

  // Toggle ulubione
  Future<void> toggleFavorite(String id) async {
    final album = getAlbum(id);
    if (album != null) {
      album.isFavorite = !album.isFavorite;
      await updateAlbum(album);
    }
  }

  // Toggle lista zyczen
  Future<void> toggleWishlist(String id) async {
    final album = getAlbum(id);
    if (album != null) {
      album.isWishlist = !album.isWishlist;
      await updateAlbum(album);
    }
  }

  // Ustaw ocene
  Future<void> setRating(String id, int rating) async {
    final album = getAlbum(id);
    if (album != null) {
      album.rating = rating.clamp(1, 5);
      await updateAlbum(album);
    }
  }

  // Aktualizuj okladke
  Future<void> updateCover(String id, String coverUrl) async {
    final album = getAlbum(id);
    if (album != null) {
      album.coverUrl = coverUrl;
      await updateAlbum(album);
    }
  }

  // Losowy album
  Album? getRandomAlbum() {
    if (_albums.isEmpty) return null;
    final index = DateTime.now().millisecondsSinceEpoch % _albums.length;
    return _albums[index];
  }

  // Settery filtrow
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setGenreFilter(String genre) {
    _genreFilter = genre;
    notifyListeners();
  }

  void setFormatFilter(String format) {
    _formatFilter = format;
    notifyListeners();
  }

  void setSortBy(String sort) {
    _sortBy = sort;
    notifyListeners();
  }

  void toggleSortOrder() {
    _sortAscending = !_sortAscending;
    notifyListeners();
  }

  void setShowOnlyFavorites(bool value) {
    _showOnlyFavorites = value;
    _showOnlyWishlist = false;
    notifyListeners();
  }

  void setShowOnlyWishlist(bool value) {
    _showOnlyWishlist = value;
    _showOnlyFavorites = false;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _genreFilter = 'all';
    _formatFilter = 'all';
    _showOnlyFavorites = false;
    _showOnlyWishlist = false;
    notifyListeners();
  }

  // Import/Export
  List<Map<String, dynamic>> exportToJson() {
    return _albums.map((a) => {
      'id': a.id,
      'artist': a.artist,
      'title': a.title,
      'year': a.year,
      'genre': a.genre,
      'format': a.format,
      'rating': a.rating,
      'coverUrl': a.coverUrl,
      'notes': a.notes,
      'isFavorite': a.isFavorite,
      'isWishlist': a.isWishlist,
      'tracks': a.tracks.map((t) => {
        'title': t.title,
        'filePath': t.filePath,
        'durationSeconds': t.durationSeconds,
        'trackNumber': t.trackNumber,
      }).toList(),
    }).toList();
  }

  Future<int> importFromJson(List<dynamic> data) async {
    int imported = 0;
    for (var item in data) {
      try {
        final tracks = (item['tracks'] as List?)?.map((t) => Track(
          title: t['title'] ?? '',
          filePath: t['filePath'],
          durationSeconds: t['durationSeconds'],
          trackNumber: t['trackNumber'] ?? 0,
        )).toList() ?? [];

        final album = Album(
          id: item['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          artist: item['artist'] ?? 'Nieznany',
          title: item['title'] ?? 'Bez tytulu',
          year: item['year'],
          genre: item['genre'] ?? 'other',
          format: item['format'] ?? 'digital',
          rating: item['rating'] ?? 3,
          coverUrl: item['coverUrl'],
          notes: item['notes'],
          isFavorite: item['isFavorite'] ?? false,
          isWishlist: item['isWishlist'] ?? false,
          tracks: tracks,
        );
        
        await addAlbum(album);
        imported++;
      } catch (e) {
        debugPrint('Blad importu: $e');
      }
    }
    return imported;
  }
}
