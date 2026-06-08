import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/album.dart';
import '../services/database_service.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<DatabaseService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statystyki'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Glowne liczniki
          Row(
            children: [
              Expanded(child: _buildStatCard(context, Icons.album, db.totalAlbums.toString(), 'Albumow')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, Icons.music_note, db.totalTracks.toString(), 'Utworow')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildStatCard(context, Icons.favorite, db.favoriteCount.toString(), 'Ulubionych')),
              const SizedBox(width: 12),
              Expanded(child: _buildStatCard(context, Icons.card_giftcard, db.wishlistCount.toString(), 'Lista zyczen')),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Gatunki
          _buildSectionTitle(context, 'Gatunki'),
          const SizedBox(height: 12),
          _buildGenreChart(context, db),
          
          const SizedBox(height: 24),
          
          // Formaty
          _buildSectionTitle(context, 'Formaty'),
          const SizedBox(height: 12),
          _buildFormatChart(context, db),
          
          const SizedBox(height: 24),
          
          // Top artysci
          _buildSectionTitle(context, 'Top artysci'),
          const SizedBox(height: 12),
          _buildTopArtists(context, db),
          
          const SizedBox(height: 24),
          
          // Lata
          _buildSectionTitle(context, 'Albumy wedlug lat'),
          const SizedBox(height: 12),
          _buildYearChart(context, db),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildGenreChart(BuildContext context, DatabaseService db) {
    final stats = db.genreStats;
    if (stats.isEmpty) {
      return const Text('Brak danych');
    }
    
    final total = stats.values.fold(0, (a, b) => a + b);
    final sorted = stats.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: sorted.take(8).map((entry) {
          final percent = (entry.value / total * 100).toStringAsFixed(0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Text(genreEmoji(entry.key), style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(genreName(entry.key)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: entry.value / total,
                        backgroundColor: Colors.grey[800],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${entry.value} ($percent%)',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFormatChart(BuildContext context, DatabaseService db) {
    final stats = db.formatStats;
    if (stats.isEmpty) {
      return const Text('Brak danych');
    }
    
    final formatLabels = {
      'cd': (Icons.album, 'CD'),
      'vinyl': (Icons.album_outlined, 'Winyl'),
      'digital': (Icons.cloud, 'Cyfrowy'),
      'cassette': (Icons.radio, 'Kaseta'),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats.entries.map((entry) {
          final label = formatLabels[entry.key] ?? (Icons.help, entry.key);
          return Column(
            children: [
              Icon(label.$1, size: 32, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 8),
              Text(
                '${entry.value}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Text(
                label.$2,
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTopArtists(BuildContext context, DatabaseService db) {
    final artistCounts = <String, int>{};
    for (var album in db.allAlbums) {
      artistCounts[album.artist] = (artistCounts[album.artist] ?? 0) + 1;
    }
    
    if (artistCounts.isEmpty) {
      return const Text('Brak danych');
    }
    
    final sorted = artistCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: sorted.take(5).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final artist = entry.value;
          return ListTile(
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: index == 0
                    ? Colors.amber
                    : index == 1
                        ? Colors.grey[400]
                        : index == 2
                            ? Colors.orange[300]
                            : Colors.grey[700],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
            title: Text(artist.key),
            trailing: Text(
              '${artist.value} alb.',
              style: TextStyle(color: Colors.grey[400]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildYearChart(BuildContext context, DatabaseService db) {
    final yearCounts = <int, int>{};
    for (var album in db.allAlbums) {
      if (album.year != null) {
        final decade = (album.year! ~/ 10) * 10;
        yearCounts[decade] = (yearCounts[decade] ?? 0) + 1;
      }
    }
    
    if (yearCounts.isEmpty) {
      return const Text('Brak danych o latach');
    }
    
    final sorted = yearCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final maxCount = sorted.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: sorted.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text("${entry.key}'s"),
                ),
                Expanded(
                  child: LinearProgressIndicator(
                    value: entry.value / maxCount,
                    backgroundColor: Colors.grey[800],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                    minHeight: 20,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${entry.value}',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
