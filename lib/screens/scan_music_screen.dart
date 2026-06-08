import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:on_audio_query/on_audio_query.dart';
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
    setState(() {
      _isScanning = true;
      _status = 'Skanowanie muzyki...';
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
        _status = 'Znaleziono ${albums.length} albumow';
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _status = 'Blad: $e';
      });
    }
  }

  Future<void> _importSelected() async {
    if (_selectedAlbums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wybierz przynajmniej jeden album')),
      );
      return;
    }

    setState(() {
      _isScanning = true;
      _status = 'Importowanie albumow...';
      _scannedCount = 0;
    });

    final audio = Provider.of<AudioService>(context, listen: false);
    final db = Provider.of<DatabaseService>(context, listen: false);
    
    int imported = 0;
    int skipped = 0;
    final selectedAlbums = _foundAlbums.where((a) => _selectedAlbums.contains(a.id)).toList();

    for (int i = 0; i < selectedAlbums.length; i++) {
      final albumModel = selectedAlbums[i];
      
      setState(() {
        _scannedCount = i + 1;
        _status = 'Importowanie ${i + 1}/${selectedAlbums.length}: ${albumModel.album}';
      });

      try {
        // Konwertuj AlbumModel do naszego Album z pelnymi sciezkami do plikow
        final album = await audio.albumModelToAlbum(albumModel);
        
        // Uzyj funkcji isDuplicate z DatabaseService
        if (!db.isDuplicate(album.artist, album.title)) {
          final added = await db.addAlbum(album);
          if (added) {
            imported++;
          } else {
            skipped++;
          }
        } else {
          skipped++;
        }
      } catch (e) {
        debugPrint('Blad importu albumu: $e');
      }
    }

    setState(() {
      _isScanning = false;
      if (skipped > 0) {
        _status = 'Zaimportowano $imported nowych albumow ($skipped pominieto - duplikaty)';
      } else {
        _status = 'Zaimportowano $imported nowych albumow';
      }
    });

    if (mounted) {
      if (imported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Zaimportowano $imported albumow${skipped > 0 ? ' ($skipped pominieto)' : ''}'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else if (skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Wszystkie wybrane albumy ($skipped) juz istnieja w kolekcji'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Skanuj muzyke'),
        actions: [
          if (_foundAlbums.isNotEmpty && !_isScanning)
            TextButton.icon(
              onPressed: _importSelected,
              icon: const Icon(Icons.download),
              label: Text('Importuj (${_selectedAlbums.length})'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Brak uprawnien
    if (!_hasPermission) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Brak dostepu do plikow',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Aplikacja potrzebuje dostepu do\nplikow muzycznych na urzadzeniu',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _checkPermissions,
              icon: const Icon(Icons.lock_open),
              label: const Text('Udziel dostepu'),
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
            const Text(
              'Nie znaleziono muzyki',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Nie znaleziono albumow w pamieci urzadzenia',
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _scanMusic,
              icon: const Icon(Icons.refresh),
              label: const Text('Skanuj ponownie'),
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
                      ? 'Odznacz wszystkie'
                      : 'Zaznacz wszystkie',
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
                  album.artist ?? 'Nieznany artysta',
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
                label: Text('Importuj ${_selectedAlbums.length} albumow'),
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
