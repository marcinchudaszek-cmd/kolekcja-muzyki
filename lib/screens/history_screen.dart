import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/history_service.dart';
import '../services/database_service.dart';
import '../models/album.dart';
import 'album_detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Historia sluchania'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Ostatnie'),
              Tab(text: 'Top Albumy'),
              Tab(text: 'Top Utwory'),
            ],
          ),
          actions: [
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: const ListTile(
                    leading: Icon(Icons.delete_forever, color: Colors.red),
                    title: Text('Wyczysc historie'),
                  ),
                  onTap: () => _confirmClear(context),
                ),
              ],
            ),
          ],
        ),
        body: Consumer2<HistoryService, DatabaseService>(
          builder: (context, history, db, child) {
            return TabBarView(
              children: [
                _buildRecentTab(context, history, db),
                _buildTopAlbumsTab(context, history, db),
                _buildTopTracksTab(context, history),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecentTab(BuildContext context, HistoryService history, DatabaseService db) {
    final recentIds = history.getRecentAlbumIds(limit: 20);
    
    if (recentIds.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Brak historii sluchania', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text('Odtworz muzyke, a pojawi sie tutaj!', 
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: recentIds.length,
      itemBuilder: (context, index) {
        final albumId = recentIds[index];
        Album? album;
        try {
          album = db.getAlbum(albumId);
        } catch (e) {
          return const SizedBox.shrink();
        }
        
        if (album == null) return const SizedBox.shrink();
        
        final playCount = history.getAlbumPlayCount(albumId);
        
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 50,
                height: 50,
                child: album.coverUrl != null && album.coverUrl!.isNotEmpty
                    ? Image.network(album.coverUrl!, fit: BoxFit.cover)
                    : Container(
                        color: Theme.of(context).colorScheme.surface,
                        child: Center(child: Text(genreEmoji(album.genre))),
                      ),
              ),
            ),
            title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(album.artist, style: TextStyle(color: Colors.grey[400])),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$playCount', style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                )),
                Text('odsluchan', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlbumDetailScreen(albumId: albumId)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopAlbumsTab(BuildContext context, HistoryService history, DatabaseService db) {
    final topAlbums = history.getTopAlbums(db.allAlbums, limit: 20);
    
    if (topAlbums.isEmpty) {
      return const Center(
        child: Text('Brak danych', style: TextStyle(color: Colors.grey)),
      );
    }

    final entries = topAlbums.entries.toList();
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        Album? album;
        try {
          album = db.getAlbum(entry.key);
        } catch (e) {
          return const SizedBox.shrink();
        }
        
        if (album == null) return const SizedBox.shrink();
        
        return Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: index < 3 
                    ? [Colors.amber, Colors.grey[400], Colors.brown[300]][index]
                    : Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: index < 3 ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
            title: Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(album.artist, style: TextStyle(color: Colors.grey[400])),
            trailing: Text(
              '${entry.value}x',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AlbumDetailScreen(albumId: entry.key)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopTracksTab(BuildContext context, HistoryService history) {
    final topTracks = history.getTopTracks(limit: 30);
    
    if (topTracks.isEmpty) {
      return const Center(
        child: Text('Brak danych', style: TextStyle(color: Colors.grey)),
      );
    }

    final entries = topTracks.entries.toList();
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        
        return Card(
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: index < 3 
                    ? [Colors.amber, Colors.grey[400], Colors.brown[300]][index]
                    : Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: index < 3 ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
            title: Text(entry.key, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(
              '${entry.value}x',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmClear(BuildContext context) {
    Future.delayed(Duration.zero, () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Wyczyscic historie?'),
          content: const Text('Ta operacja usunie cala historie sluchania.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () {
                Provider.of<HistoryService>(context, listen: false).clearHistory();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Historia wyczyszczona')),
                );
              },
              child: const Text('Wyczysc', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    });
  }
}


