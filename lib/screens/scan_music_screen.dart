import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';

class ScanMusicScreen extends StatefulWidget {
  const ScanMusicScreen({super.key});

  @override
  State<ScanMusicScreen> createState() => _ScanMusicScreenState();
}

class _ScanMusicScreenState extends State<ScanMusicScreen> {
  bool _isScanning = false;
  bool _hasPermission = false;
  String _status = '';
  List<AlbumModel> _foundAlbums = [];
  Set<int> _selectedAlbums = {};
  int _scannedCount = 0;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final audio = Provider.of<AudioService>(context, listen: false);
    final hasPermission = await audio.checkPermissions();
    setState(() {
      _hasPermission = hasPermission;
    });
    
    if (hasPermission) {
      _scanMusic();
    }
  }

  Future<void> _scanMusic() async {
    final l = L.read(context);
    setState(() {
      _isScanning = true;
      _status = l.scanningMusic;
      _foundAlbums = [];
      _scannedCount = 0;
    });

    try {
      final audio = Provider.of<AudioService>(context, listen: false);

      // Skanuj albumy
      final albums = await audio.scanAlbums();

      setState(() {
        _totalCount = albums.length;
        _foundAlbums = albums;
        _selectedAlbums = Set.from(albums.map((a) => a.id));
        _isScanning = false;
        _status = l.foundAlbums(albums.length);
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = l.errorGeneric(e);
      });
    }
  }

  Future<void> _importSelected() async {
    final l = L.read(context);
    if (_selectedAlbums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.selectAtLeastOne)),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _status = l.importingAlbums;
      _scannedCount = 0;
    });

    final audio = Provider.of<AudioService>(context, listen: false);
    final db = Provider.of<DatabaseService>(context, listen: false);
    
    int addedTracks = 0;
    int newAlbums = 0;
    int skippedTracks = 0;
    final selectedAlbums = _foundAlbums.where((a) => _selectedAlbums.contains(a.id)).toList();

    // Zbior sciezek juz w kolekcji — budowany raz na caly import.
    final existingPaths = db.allTrackPaths;

    for (int i = 0; i < selectedAlbums.length; i++) {
      final albumModel = selectedAlbums[i];

      setState(() {
        _scannedCount = i + 1;
        _status = l.importingProgress(i + 1, selectedAlbums.length, albumModel.album);
      });

      try {
        // Konwertuj AlbumModel do naszego Album z pelnymi sciezkami do plikow
        final album = await audio.albumModelToAlbum(albumModel);

        // Odsiej utwory, ktorych pliki juz sa w kolekcji (gdziekolwiek).
        final fresh = <Track>[];
        for (final t in album.tracks) {
          final key = t.filePath?.toLowerCase().replaceAll('\\', '/').trim();
          if (key == null || key.isEmpty) continue;
          if (existingPaths.contains(key)) {
            skippedTracks++;
            continue;
          }
          existingPaths.add(key);
          fresh.add(t);
        }
        if (fresh.isEmpty) continue;

        final existingAlbum = db.findAlbumByName(album.artist, album.title);
        if (existingAlbum != null) {
          // Album juz jest — dopisz tylko nowe utwory.
          addedTracks += await db.addTracksToAlbum(existingAlbum, fresh);
        } else {
          album.tracks = fresh;
          await db.addAlbum(album);
          newAlbums++;
          addedTracks += fresh.length;
        }
      } catch (e) {
        debugPrint('Blad importu albumu: $e');
      }
    }

    final summary = addedTracks > 0
        ? l.importSummary(addedTracks, newAlbums, skippedTracks)
        : l.nothingNew;

    setState(() {
      _isScanning = false;
      _status = summary;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summary),
          backgroundColor: addedTracks > 0 ? Colors.green : Colors.orange,
        ),
      );
      if (addedTracks > 0) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.scanMusicTitle),
        actions: [
          if (_foundAlbums.isNotEmpty && !_isScanning)
            TextButton.icon(
              onPressed: _importSelected,
              icon: const Icon(Icons.download),
              label: Text(l.importCount(_selectedAlbums.length)),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final l = L.of(context);
    // Brak uprawnien
    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noAccessTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              l.noAccessDesc,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkPermissions,
              icon: const Icon(Icons.lock_open),
              label: Text(l.grantAccess),
            ),
          ],
        ),
      );
    }

    // Skanowanie
    if (_isScanning) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              _status,
              style: const TextStyle(fontSize: 16),
            ),
            if (_totalCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '$_scannedCount / $_totalCount',
                style: TextStyle(color: Colors.grey[400]),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: LinearProgressIndicator(
                  value: _totalCount > 0 ? _scannedCount / _totalCount : null,
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Brak albumow
    if (_foundAlbums.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.music_off, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              l.noMusicTitle,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              l.noMusicDesc,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanMusic,
              icon: const Icon(Icons.refresh),
              label: Text(l.scanAgain),
            ),
          ],
        ),
      );
    }

    // Lista albumow
    return Column(
      children: [
        // Status i przyciski
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedAlbums.length == _foundAlbums.length) {
                      _selectedAlbums.clear();
                    } else {
                      _selectedAlbums = Set.from(_foundAlbums.map((a) => a.id));
                    }
                  });
                },
                child: Text(
                  _selectedAlbums.length == _foundAlbums.length
                      ? l.deselectAll
                      : l.selectAll,
                ),
              ),
            ],
          ),
        ),
        
        // Lista
        Expanded(
          child: ListView.builder(
            itemCount: _foundAlbums.length,
            itemBuilder: (context, index) {
              final album = _foundAlbums[index];
              final isSelected = _selectedAlbums.contains(album.id);
              
              return ListTile(
                leading: QueryArtworkWidget(
                  id: album.id,
                  type: ArtworkType.ALBUM,
                  nullArtworkWidget: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.album, color: Colors.grey),
                  ),
                  artworkBorder: BorderRadius.circular(8),
                  artworkWidth: 50,
                  artworkHeight: 50,
                ),
                title: Text(
                  album.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  album.artist ?? l.unknownArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: Checkbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedAlbums.add(album.id);
                      } else {
                        _selectedAlbums.remove(album.id);
                      }
                    });
                  },
                ),
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedAlbums.remove(album.id);
                    } else {
                      _selectedAlbums.add(album.id);
                    }
                  });
                },
              );
            },
          ),
        ),
        
        // Przycisk importu
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _selectedAlbums.isNotEmpty ? _importSelected : null,
                icon: const Icon(Icons.download),
                label: Text(l.importAlbumsCount(_selectedAlbums.length)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
