import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/album.dart';
import '../services/database_service.dart';

class EditAlbumScreen extends StatefulWidget {
  final Album album;

  const EditAlbumScreen({super.key, required this.album});

  @override
  State<EditAlbumScreen> createState() => _EditAlbumScreenState();
}

class _EditAlbumScreenState extends State<EditAlbumScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _artistController;
  late TextEditingController _titleController;
  late TextEditingController _yearController;
  late TextEditingController _notesController;
  
  late String _genre;
  late String _format;
  late int _rating;

  @override
  void initState() {
    super.initState();
    _artistController = TextEditingController(text: widget.album.artist);
    _titleController = TextEditingController(text: widget.album.title);
    _yearController = TextEditingController(text: widget.album.year?.toString() ?? '');
    _notesController = TextEditingController(text: widget.album.notes ?? '');
    _genre = widget.album.genre;
    _format = widget.album.format;
    _rating = widget.album.rating;
  }

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    _yearController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.editAlbumTitle),
        actions: [
          TextButton(
            onPressed: _saveAlbum,
            child: Text(l.save),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Artysta
            TextFormField(
              controller: _artistController,
              decoration: InputDecoration(
                labelText: '${l.fieldArtist} *',
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterArtist;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Tytul
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: '${l.albumTitleLabel} *',
                prefixIcon: const Icon(Icons.album),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return l.enterTitle;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Rok
            TextFormField(
              controller: _yearController,
              decoration: InputDecoration(
                labelText: l.releaseYear,
                prefixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            // Gatunek
            Text(
              l.fieldGenre,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'rock', 'pop', 'metal', 'jazz', 'classical', 'electronic', 
                'hip-hop', 'blues', 'other'
              ].map((g) => ChoiceChip(
                label: Text('${genreEmoji(g)} ${genreName(g)}'),
                selected: _genre == g,
                onSelected: (selected) {
                  if (selected) setState(() => _genre = g);
                },
              )).toList(),
            ),
            const SizedBox(height: 24),

            // Format
            Text(
              l.fieldFormat,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ('cd', 'CD'),
                ('vinyl', l.formatVinyl),
                ('digital', l.formatDigital),
                ('cassette', l.formatCassette),
              ].map((f) => ChoiceChip(
                label: Text(f.$2),
                selected: _format == f.$1,
                onSelected: (selected) {
                  if (selected) setState(() => _format = f.$1);
                },
              )).toList(),
            ),
            const SizedBox(height: 24),

            // Ocena
            Text(
              l.rating,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) => IconButton(
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: i < _rating ? Colors.amber : Colors.grey,
                ),
                iconSize: 40,
                onPressed: () => setState(() => _rating = i + 1),
              )),
            ),
            const SizedBox(height: 24),

            // Notatki
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l.notes,
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 32),

            // Przycisk zapisz
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveAlbum,
                icon: const Icon(Icons.save),
                label: Text(l.saveChanges),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveAlbum() {
    if (!_formKey.currentState!.validate()) return;
    final l = L.read(context);

    final db = Provider.of<DatabaseService>(context, listen: false);
    
    widget.album.artist = _artistController.text.trim();
    widget.album.title = _titleController.text.trim();
    widget.album.year = int.tryParse(_yearController.text);
    widget.album.genre = _genre;
    widget.album.format = _format;
    widget.album.rating = _rating;
    widget.album.notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    db.updateAlbum(widget.album);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${l.albumUpdated}'),
        backgroundColor: Colors.green,
      ),
    );
    
    Navigator.pop(context);
  }
}
