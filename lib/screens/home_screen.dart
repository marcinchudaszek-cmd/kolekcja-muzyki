import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/database_service.dart';
import '../services/audio_service.dart';
import '../services/history_service.dart';
import '../widgets/album_card.dart';
import '../widgets/mini_player.dart';
import 'album_detail_screen.dart';
import 'add_album_screen.dart';
import 'scan_music_screen.dart';
import 'scanner_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'scan_folder_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  // Trwale kontrolery przewijania: keepScrollOffset przywraca pozycje listy
  // nawet gdy scrollable zostanie przebudowany (PageStorageKey nie wystarczal).
  final ScrollController _gridScrollController = ScrollController();
  final ScrollController _listScrollController = ScrollController();
  bool _isSearching = false;
  bool _isGridView = true; // true = kafelki, false = lista
@override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final audio = Provider.of<AudioService>(context, listen: false);
    final history = Provider.of<HistoryService>(context, listen: false);
    audio.onTrackPlayed = (albumId, trackTitle, duration) {
      history.addRecord(albumId, trackTitle, duration);
    };
  }
  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);
    final audio = Provider.of<AudioService>(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Naglowek
            _buildHeader(context, db),
            
            // Filtry
            _buildFilters(context, db),
            
            // Lista albumów
            Expanded(
              child: db.albums.isEmpty
                  ? _buildEmptyState(context)
                  : _isGridView 
                      ? _buildAlbumGrid(context, db)
                      : _buildAlbumList(context, db),
            ),
            
            // Mini player
            if (audio.currentTrack != null)
              const MiniPlayer(),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: audio.currentTrack != null ? 70 : 0,
        ),
        child: FloatingActionButton(
          onPressed: () => _showAddOptions(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DatabaseService db) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              if (_isSearching) ...[
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: L.of(context).searchAlbums,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isSearching = false;
                            _searchController.clear();
                            db.setSearchQuery('');
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    onChanged: (value) => db.setSearchQuery(value),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: Text(L.of(context).myCollection,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Przyciski
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  tooltip: _isGridView ? L.of(context).viewList : L.of(context).viewGrid,
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _isSearching = true),
                ),
                IconButton(
                  icon: Icon(
                    db.showOnlyFavorites ? Icons.favorite : Icons.favorite_border,
                    color: db.showOnlyFavorites ? Colors.red : null,
                  ),
                  onPressed: () => db.setShowOnlyFavorites(!db.showOnlyFavorites),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      child: ListTile(
                        leading: const Icon(Icons.bar_chart),
                        title: Text(L.of(context).statistics),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()));
                        });
                      },
                    ),
                    PopupMenuItem(
                      child: ListTile(
                        leading: const Icon(Icons.settings),
                        title: Text(L.of(context).settings),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onTap: () {
                        Future.delayed(Duration.zero, () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                        });
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
          
          // Liczniki
          if (!_isSearching)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  _buildCounter(db.totalAlbums.toString(), L.of(context).labelAlbums),
                  const SizedBox(width: 16),
                  _buildCounter(db.totalTracks.toString(), L.of(context).labelTracks),
                  const SizedBox(width: 16),
                  _buildCounter(db.favoriteCount.toString(), L.of(context).labelFavorites),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCounter(String count, String label) {
    return Row(
      children: [
        Text(
          count,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, DatabaseService db) {
    final l = L.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Sortowanie
          _buildFilterChip(
            label: _getSortLabel(l, db.sortBy),
            icon: db.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            onTap: () => _showSortOptions(context, db),
          ),
          const SizedBox(width: 8),

          // Gatunek
          _buildFilterChip(
            label: db.genreFilter == 'all' ? l.filterAll : l.genreName(db.genreFilter),
            icon: Icons.music_note,
            isActive: db.genreFilter != 'all',
            onTap: () => _showGenreFilter(context, db),
          ),
          const SizedBox(width: 8),

          // Format
          _buildFilterChip(
            label: db.formatFilter == 'all' ? l.format : _getFormatLabel(l, db.formatFilter),
            icon: Icons.album,
            isActive: db.formatFilter != 'all',
            onTap: () => _showFormatFilter(context, db),
          ),

          // Lista zyczen
          const SizedBox(width: 8),
          _buildFilterChip(
            label: l.wishlist,
            icon: Icons.card_giftcard,
            isActive: db.showOnlyWishlist,
            onTap: () => db.setShowOnlyWishlist(!db.showOnlyWishlist),
          ),

          // Wyczyść filtry
          if (db.genreFilter != 'all' || db.formatFilter != 'all' || db.showOnlyFavorites || db.showOnlyWishlist) ...[
            const SizedBox(width: 8),
            _buildFilterChip(
              label: l.clearShort,
              icon: Icons.clear,
              onTap: () => db.clearFilters(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[700]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l = L.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_music,
            size: 80,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            l.emptyCollection,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            // Skanowanie pamięci urządzenia działa tylko w aplikacji mobilnej
            kIsWeb ? l.addAlbumsToCollection : l.addOrScan,
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 24),
          if (kIsWeb)
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanFolderScreen()),
              ),
              icon: const Icon(Icons.upload_file),
              label: Text(l.pickFromDisk),
            )
          else
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScanMusicScreen()),
              ),
              icon: const Icon(Icons.folder_open),
              label: Text(l.scanFromPhone),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumGrid(BuildContext context, DatabaseService db) {
    return GridView.builder(
      // Zachowuje pozycje przewijania po powrocie z ekranu albumu.
      controller: _gridScrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: db.albums.length,
      itemBuilder: (context, index) {
        final album = db.albums[index];
        return AlbumCard(
          album: album,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AlbumDetailScreen(albumId: album.id),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumList(BuildContext context, DatabaseService db) {
    return ListView.builder(
      // Zachowuje pozycje przewijania po powrocie z ekranu albumu.
      controller: _listScrollController,
      padding: const EdgeInsets.all(8),
      itemCount: db.albums.length,
      itemBuilder: (context, index) {
        final album = db.albums[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: album.coverUrl != null && album.coverUrl!.isNotEmpty
                    ? Image.network(
                        album.coverUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Theme.of(context).colorScheme.surface,
                          child: Center(child: Text(genreEmoji(album.genre), style: const TextStyle(fontSize: 24))),
                        ),
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(child: Text(genreEmoji(album.genre), style: const TextStyle(fontSize: 24))),
                      ),
              ),
            ),
            title: Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  album.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                Row(
                  children: [
                    if (album.year != null) ...[
                      Text(
                        '${album.year}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      L.of(context).tracksCount(album.tracks.length),
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    if (album.isFavorite) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.favorite, size: 14, color: Colors.red),
                    ],
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Ocena
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(5, (i) => Icon(
                    i < album.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: i < album.rating ? Colors.amber : Colors.grey[600],
                  )),
                ),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlbumDetailScreen(albumId: album.id),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showAddOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L.of(context).addAlbum,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            // Skanowanie pamięci urządzenia niedostępne w przeglądarce —
            // tam zamiast tego jest wybór plików z dysku.
            if (kIsWeb)
              _buildAddOption(
                icon: Icons.upload_file,
                title: L.of(context).pickFromDisk,
                subtitle: L.of(context).pickFromDiskSub,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanFolderScreen()),
                  );
                },
              )
            else
              _buildAddOption(
                icon: Icons.folder_open,
                title: L.of(context).scanFromPhone,
                subtitle: L.of(context).scanFromPhoneSub,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanMusicScreen()),
                  );
                },
              ),
            _buildAddOption(
              icon: Icons.qr_code_scanner,
              title: L.of(context).scanBarcode,
              subtitle: L.of(context).scanBarcodeSub,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScannerScreen()),
                );
              },
            ),
            _buildAddOption(
              icon: Icons.edit,
              title: L.of(context).addManually,
              subtitle: L.of(context).addManuallySub,
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddAlbumScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400])),
      onTap: onTap,
    );
  }

  void _showSortOptions(BuildContext context, DatabaseService db) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.of(context).sortBy, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildSortOption(db, 'artist', L.of(context).sortArtist),
            _buildSortOption(db, 'title', L.of(context).sortTitle),
            _buildSortOption(db, 'year', L.of(context).sortYear),
            _buildSortOption(db, 'rating', L.of(context).sortRating),
            _buildSortOption(db, 'recent', L.of(context).sortRecent),
            const Divider(),
            ListTile(
              leading: Icon(
                db.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              ),
              title: Text(db.sortAscending ? L.of(context).ascending : L.of(context).descending),
              onTap: () {
                db.toggleSortOrder();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(DatabaseService db, String value, String label) {
    return ListTile(
      leading: Radio<String>(
        value: value,
        groupValue: db.sortBy,
        onChanged: (v) {
          db.setSortBy(v!);
          Navigator.pop(context);
        },
      ),
      title: Text(label),
      onTap: () {
        db.setSortBy(value);
        Navigator.pop(context);
      },
    );
  }

  void _showGenreFilter(BuildContext context, DatabaseService db) {
    final genres = ['all', 'rock', 'pop', 'metal', 'jazz', 'classical', 'electronic', 'hip-hop', 'blues', 'other'];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          Text(L.of(context).genre, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...genres.map((g) => ListTile(
            leading: Text(g == 'all' ? '🎵' : genreEmoji(g)),
            title: Text(g == 'all' ? L.of(context).filterAll : L.of(context).genreName(g)),
            trailing: db.genreFilter == g ? const Icon(Icons.check) : null,
            onTap: () {
              db.setGenreFilter(g);
              Navigator.pop(context);
            },
          )),
        ],
      ),
    );
  }

  void _showFormatFilter(BuildContext context, DatabaseService db) {
    final l = L.of(context);
    final formats = [
      ('all', l.filterAll, Icons.album),
      ('cd', 'CD', Icons.album),
      ('vinyl', l.formatVinyl, Icons.album),
      ('digital', l.formatDigital, Icons.cloud),
      ('cassette', l.formatCassette, Icons.radio),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          Text(l.format, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ...formats.map((f) => ListTile(
            leading: Icon(f.$3),
            title: Text(f.$2),
            trailing: db.formatFilter == f.$1 ? const Icon(Icons.check) : null,
            onTap: () {
              db.setFormatFilter(f.$1);
              Navigator.pop(context);
            },
          )),
        ],
      ),
    );
  }

  String _getSortLabel(L l, String sortBy) {
    switch (sortBy) {
      case 'artist': return l.sortArtist;
      case 'title': return l.sortTitle;
      case 'year': return l.sortYear;
      case 'rating': return l.sortRating;
      case 'recent': return l.sortRecentShort;
      default: return l.sort;
    }
  }

  String _getFormatLabel(L l, String format) {
    switch (format) {
      case 'cd': return 'CD';
      case 'vinyl': return l.formatVinyl;
      case 'digital': return l.formatDigital;
      case 'cassette': return l.formatCassette;
      default: return format;
    }
  }
}


















