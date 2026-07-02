import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/album.dart';
import '../services/database_service.dart';
import '../l10n/app_localizations.dart';
import '../services/cover_service.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  MobileScannerController? _controller;
  bool _isScanning = true;
  bool _isSearching = false;
  String? _scannedCode;
  Map<String, dynamic>? _foundRelease;
  String? _error;
  final _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L.of(context).scanBarcode),
      ),
      body: Column(
        children: [
          // Skaner lub wynik
          Expanded(
            flex: 2,
            child: _isScanning ? _buildScanner() : _buildResult(),
          ),
          
          // Reczne wpisywanie
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L.of(context).orEnterCode),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualController,
                        decoration: const InputDecoration(
                          hintText: 'np. 0602547202888',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isSearching ? null : () {
                        if (_manualController.text.length >= 8) {
                          _searchBarcode(_manualController.text);
                        }
                      },
                      child: Text(L.of(context).search),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null && barcode.rawValue!.length >= 8) {
                _searchBarcode(barcode.rawValue!);
                break;
              }
            }
          },
        ),
        
        // Ramka skanowania
        Center(
          child: Container(
            width: 280,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 3,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        
        // Wskazowka
        Positioned(
          bottom: 20,
          left: 0,
          right: 0,
          child: Text(
            L.of(context).aimCamera,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              backgroundColor: Colors.black54,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(L.of(context).searchingMusicBrainz),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _resetScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: Text(L.of(context).scanAgain),
              ),
            ],
          ),
        ),
      );
    }

    if (_foundRelease != null) {
      final artist = _foundRelease!['artist'] ?? L.of(context).unknownArtist;
      final title = _foundRelease!['title'] ?? L.of(context).untitled;
      final year = _foundRelease!['year'] ?? '';
      final tracks = _foundRelease!['tracks'] as List? ?? [];

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info o albumie
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(L.of(context).albumFound, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (year.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('📅 $year', style: TextStyle(color: Colors.grey[400])),
                  ],
                ],
              ),
            ),
            
            // Lista utworow
            if (tracks.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                L.of(context).trackListCount(tracks.length),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tracks.length,
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return ListTile(
                      dense: true,
                      leading: Text(
                        '${index + 1}.',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      title: Text(track['title'] ?? '', style: const TextStyle(fontSize: 14)),
                    );
                  },
                ),
              ),
            ],
            
            // Przyciski
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetScanner,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(L.of(context).scanAnother),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _addAlbum(context),
                    icon: const Icon(Icons.add),
                    label: Text(L.of(context).add),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Center(child: Text(L.of(context).scanBarcodePrompt));
  }

  Future<void> _searchBarcode(String barcode) async {
    final l = L.read(context);
    setState(() {
      _isScanning = false;
      _isSearching = true;
      _scannedCode = barcode;
      _error = null;
      _foundRelease = null;
    });
    
    _controller?.stop();

    try {
      // Szukaj w MusicBrainz
      final searchResponse = await http.get(
        Uri.parse('https://musicbrainz.org/ws/2/release/?query=barcode:$barcode&fmt=json'),
        headers: {'User-Agent': 'KolekcjaMuzyki/1.0'},
      );

      if (searchResponse.statusCode != 200) {
        throw Exception(l.connectionError);
      }

      final searchData = json.decode(searchResponse.body);
      final releases = searchData['releases'] as List?;

      if (releases == null || releases.isEmpty) {
        throw Exception(l.noAlbumForCode(barcode));
      }

      final release = releases[0];
      final releaseId = release['id'];

      // Pobierz szczegoly z utworami
      final detailsResponse = await http.get(
        Uri.parse('https://musicbrainz.org/ws/2/release/$releaseId?inc=recordings+artist-credits&fmt=json'),
        headers: {'User-Agent': 'KolekcjaMuzyki/1.0'},
      );

      if (detailsResponse.statusCode != 200) {
        throw Exception(l.errorFetchingDetails);
      }

      final details = json.decode(detailsResponse.body);
      
      // Wyciagnij artyste
      String artist = 'Nieznany';
      final artistCredit = details['artist-credit'] as List?;
      if (artistCredit != null && artistCredit.isNotEmpty) {
        artist = artistCredit[0]['name'] ?? artistCredit[0]['artist']?['name'] ?? 'Nieznany';
      }

      // Wyciagnij utwory
      List<Map<String, dynamic>> tracks = [];
      final media = details['media'] as List?;
      if (media != null) {
        for (var medium in media) {
          final mediumTracks = medium['tracks'] as List?;
          if (mediumTracks != null) {
            for (var track in mediumTracks) {
              tracks.add({
                'title': track['title'],
                'duration': track['length'],
              });
            }
          }
        }
      }

      setState(() {
        _isSearching = false;
        _foundRelease = {
          'artist': artist,
          'title': details['title'],
          'year': details['date']?.toString().substring(0, 4),
          'tracks': tracks,
        };
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  void _resetScanner() {
    setState(() {
      _isScanning = true;
      _isSearching = false;
      _scannedCode = null;
      _foundRelease = null;
      _error = null;
    });
    _controller?.start();
  }

  void _addAlbum(BuildContext context) async {
    if (_foundRelease == null) return;
    final l = L.read(context);

    final db = Provider.of<DatabaseService>(context, listen: false);
    final artist = _foundRelease!['artist'] ?? l.unknownArtist;
    final title = _foundRelease!['title'] ?? l.untitled;
    
    // Sprawdz duplikaty
    if (db.isDuplicate(artist, title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.albumExistsNamed(title)),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Pokaz ladowanie
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l.downloadingCover),
              ],
            ),
          ),
        ),
      ),
    );

    // Pobierz okladke
    String? coverUrl;
    try {
      coverUrl = await CoverService.fetchCover(artist, title);
    } catch (e) {
      print('Blad pobierania okladki: $e');
    }

    if (!mounted) return;
    Navigator.pop(context); // Zamknij dialog ladowania

    final tracks = (_foundRelease!['tracks'] as List).map((t) => Track(
      title: t['title'] ?? '',
      durationSeconds: t['duration'] != null ? (t['duration'] / 1000).round() : null,
    )).toList();

    final album = Album(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      artist: artist,
      title: title,
      year: int.tryParse(_foundRelease!['year'] ?? ''),
      genre: 'other',
      format: 'cd',
      rating: 3,
      tracks: tracks,
      notes: l.codeLabel(_scannedCode ?? ''),
      coverUrl: coverUrl,
    );

    final added = await db.addAlbum(album);

    if (added) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.addedAlbum(album.title, coverUrl != null)),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.albumExists),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}
