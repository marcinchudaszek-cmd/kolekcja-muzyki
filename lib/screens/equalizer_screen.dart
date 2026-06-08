import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import '../services/audio_service.dart';

class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});

  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool _enabled = false;
  List<AndroidEqualizerBand> _bands = [];
  AndroidEqualizerParameters? _params;

  @override
  void initState() {
    super.initState();
    _initEqualizer();
  }

  Future<void> _initEqualizer() async {
    final audio = Provider.of<AudioService>(context, listen: false);
    final eq = audio.equalizer;
    
    _enabled = eq.enabled;
    _params = await eq.parameters;
    if (_params != null) {
      _bands = _params!.bands;
    }
    setState(() {});
  }

  String _formatFreq(double freq) {
    if (freq >= 1000) {
      return (freq / 1000).toStringAsFixed(1) + 'kHz';
    }
    return freq.toInt().toString() + 'Hz';
  }

  @override
  Widget build(BuildContext context) {
    final audio = Provider.of<AudioService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equalizer'),
        actions: [
          Switch(
            value: _enabled,
            onChanged: (v) {
              audio.equalizer.setEnabled(v);
              setState(() => _enabled = v);
            },
            activeColor: Colors.green,
          ),
        ],
      ),
      body: _bands.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _bands.map((band) {
                        return _buildBandSlider(audio, band);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildPresetButton(audio, 'Flat', [0, 0, 0, 0, 0]),
                      _buildPresetButton(audio, 'Bass', [5, 3, 0, 0, 0]),
                      _buildPresetButton(audio, 'Rock', [4, 2, -1, 2, 4]),
                      _buildPresetButton(audio, 'Pop', [-1, 2, 4, 2, -1]),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildBandSlider(AudioService audio, AndroidEqualizerBand band) {
    final minDb = _params?.minDecibels ?? -15.0;
    final maxDb = _params?.maxDecibels ?? 15.0;
    
    return Column(
      children: [
        Text(
          band.gain.toStringAsFixed(1) + 'dB',
          style: TextStyle(fontSize: 11, color: _enabled ? Colors.white : Colors.grey),
        ),
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                activeTrackColor: _enabled ? Colors.green : Colors.grey,
                inactiveTrackColor: Colors.grey[800],
                thumbColor: _enabled ? Colors.green : Colors.grey,
              ),
              child: Slider(
                value: band.gain,
                min: minDb,
                max: maxDb,
                onChanged: _enabled
                    ? (v) {
                        band.setGain(v);
                        setState(() {});
                      }
                    : null,
              ),
            ),
          ),
        ),
        Text(
          _formatFreq(band.centerFrequency),
          style: TextStyle(fontSize: 10, color: _enabled ? Colors.white70 : Colors.grey),
        ),
      ],
    );
  }

  Widget _buildPresetButton(AudioService audio, String name, List<double> gains) {
    return OutlinedButton(
      onPressed: _enabled && _bands.length >= gains.length
          ? () {
              for (int i = 0; i < gains.length && i < _bands.length; i++) {
                _bands[i].setGain(gains[i]);
              }
              setState(() {});
            }
          : null,
      child: Text(name),
    );
  }
}
