import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/audio_service.dart';

class AudioSettingsScreen extends StatelessWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L.of(context).audioSettings),
      ),
      body: Consumer<AudioService>(
        builder: (context, audio, child) {
          final l = L.of(context);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader(context, l.crossfadeSection),
              
              SwitchListTile(
                title: Text(l.enableCrossfade),
                subtitle: Text(l.crossfadeDesc),
                value: audio.crossfadeEnabled,
                onChanged: (value) => audio.setCrossfade(value),
              ),
              
              if (audio.crossfadeEnabled) ...[
                ListTile(
                  title: Text(l.crossfadeDuration),
                  subtitle: Text(l.secondsCount(audio.crossfadeDuration)),
                  trailing: SizedBox(
                    width: 150,
                    child: Slider(
                      value: audio.crossfadeDuration.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '${audio.crossfadeDuration}s',
                      onChanged: (value) => audio.setCrossfadeDuration(value.toInt()),
                    ),
                  ),
                ),
              ],
              
              const Divider(height: 32),
              
              _buildSectionHeader(context, 'Equalizer'),
              
              ListTile(
                leading: const Icon(Icons.equalizer),
                title: Text(l.openSystemEq),
                subtitle: Text(l.eqDesc),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openSystemEqualizer(context),
              ),
              
              const Divider(height: 32),
              
              _buildSectionHeader(context, l.sectionAbout),
              
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    l.crossfadeInfo + l.eqInfo,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  void _openSystemEqualizer(BuildContext context) async {
    final l = L.read(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Equalizer'),
        content: Text(l.eqInstructions),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.ok),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final url = Uri.parse('https://play.google.com/store/search?q=equalizer&c=apps');
              await launchUrl(url, mode: LaunchMode.externalApplication);
            },
            child: Text(l.playStore),
          ),
        ],
      ),
    );
  }
}
