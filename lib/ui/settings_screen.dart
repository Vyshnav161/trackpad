import 'package:flutter/material.dart';

import '../storage/settings_store.dart';

/// Settings for Sensitivity, natural scrolling and tap-to-click
/// (Requirements 12.1, 12.2, 12.4). Values are persisted by [SettingsStore].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});

  final SettingsStore store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _sensitivity;
  late bool _naturalScrolling;
  late bool _tapToClick;
  final TextEditingController _sensitivityText = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.store.settings;
    _sensitivity = s.sensitivity;
    _naturalScrolling = s.naturalScrolling;
    _tapToClick = s.tapToClick;
    _sensitivityText.text = _format(_sensitivity);
  }

  @override
  void dispose() {
    _sensitivityText.dispose();
    super.dispose();
  }

  String _format(double v) => v.toStringAsFixed(2);

  Future<void> _commitSensitivity(double value) async {
    final accepted = await widget.store.setSensitivity(value);
    if (!mounted) return;
    setState(() {
      if (accepted) {
        _sensitivity = value;
        _error = null;
      }
    });
  }

  Future<void> _submitText(String raw) async {
    final value = double.tryParse(raw.trim());
    if (value == null || !SettingsStore.isValidSensitivity(value)) {
      // Reject and retain the previous Sensitivity (Requirement 12.4).
      setState(() {
        _error =
            'Enter a value from '
            '${SettingsStore.minSensitivity} to ${SettingsStore.maxSensitivity}';
        _sensitivityText.text = _format(_sensitivity);
      });
      return;
    }
    await _commitSensitivity(value);
    if (mounted) _sensitivityText.text = _format(_sensitivity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Sensitivity', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _sensitivity.clamp(
              SettingsStore.minSensitivity,
              SettingsStore.maxSensitivity,
            ),
            min: SettingsStore.minSensitivity,
            max: SettingsStore.maxSensitivity,
            divisions: 90,
            label: _format(_sensitivity),
            onChanged: (v) => setState(() {
              _sensitivity = v;
              _sensitivityText.text = _format(v);
              _error = null;
            }),
            onChangeEnd: _commitSensitivity,
          ),
          TextField(
            controller: _sensitivityText,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  'Sensitivity '
                  '(${SettingsStore.minSensitivity}–${SettingsStore.maxSensitivity})',
              errorText: _error,
            ),
            onSubmitted: _submitText,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Natural scrolling'),
            value: _naturalScrolling,
            onChanged: (v) async {
              setState(() => _naturalScrolling = v);
              await widget.store.setNaturalScrolling(v);
            },
          ),
          SwitchListTile(
            title: const Text('Tap to click'),
            value: _tapToClick,
            onChanged: (v) async {
              setState(() => _tapToClick = v);
              await widget.store.setTapToClick(v);
            },
          ),
        ],
      ),
    );
  }
}
