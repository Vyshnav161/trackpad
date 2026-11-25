/// Pairing screen: accepts the 6-digit Pairing_Code shown on the desktop,
/// reports an incorrect code and shows the lockout countdown
/// (Requirements 4.1, 4.2, 4.3, 4.4).
library;

import 'dart:async';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';

import '../transport/transport_manager.dart';

/// Whole seconds left until [lockedUntil] (rounded up), or 0 if not locked.
int lockoutSecondsRemaining(DateTime? lockedUntil, DateTime now) {
  if (lockedUntil == null) return 0;
  final ms = lockedUntil.difference(now).inMilliseconds;
  return ms <= 0 ? 0 : (ms + 999) ~/ 1000;
}

class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.state,
    required this.onSubmit,
    this.onCancel,
    this.now = DateTime.now,
  });

  /// Current connection state; the screen reflects [AwaitingPairing] data
  /// (host, failed attempts, lockout end).
  final ValueListenable<ConnectionState> state;

  /// Submits the code, e.g. `TransportManager.submitPairingCode`.
  final Future<PairingOutcome> Function(String code) onSubmit;

  /// Optional "cancel / back" action.
  final VoidCallback? onCancel;

  /// Clock, injectable for tests.
  final DateTime Function() now;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _ticker;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onState);
    _syncTicker();
  }

  @override
  void didUpdateWidget(PairingScreen old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      old.state.removeListener(_onState);
      widget.state.addListener(_onState);
      _syncTicker();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  AwaitingPairing? get _pairing {
    final s = widget.state.value;
    return s is AwaitingPairing ? s : null;
  }

  int get _remaining =>
      lockoutSecondsRemaining(_pairing?.lockedUntil, widget.now());

  void _onState() {
    if (!mounted) return;
    _syncTicker();
    setState(() {});
  }

  void _syncTicker() {
    if (_remaining > 0) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_remaining == 0) {
          _ticker?.cancel();
          _ticker = null;
        }
        setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  bool get _complete => _controller.text.length == 6;

  Future<void> _submit() async {
    if (_submitting || !_complete || _remaining > 0) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    PairingOutcome? outcome;
    try {
      outcome = await widget.onSubmit(_controller.text);
    } catch (_) {
      outcome = PairingOutcome.failed;
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      switch (outcome!) {
        case PairingOutcome.accepted:
          break;
        case PairingOutcome.incorrect:
          _error =
              'Incorrect code. Check the code on your computer and try '
              'again.';
        case PairingOutcome.lockedOut:
          _error = 'Too many incorrect codes.';
        case PairingOutcome.invalidFormat:
          _error = 'Enter the 6-digit code shown on your computer.';
        case PairingOutcome.failed:
          _error = 'Pairing failed. Please try again.';
      }
      if (outcome == PairingOutcome.incorrect ||
          outcome == PairingOutcome.lockedOut) {
        _controller.clear();
      }
    });
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _pairing;
    final remaining = _remaining;
    final locked = remaining > 0;
    final theme = Theme.of(context);
    final hostName = pairing?.host.name;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair with computer'),
        leading: widget.onCancel == null
            ? null
            : BackButton(onPressed: widget.onCancel),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                hostName == null
                    ? 'Enter the 6-digit pairing code shown on your computer.'
                    : 'Enter the 6-digit pairing code shown on $hostName.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('pairing-code-field'),
                controller: _controller,
                enabled: !locked && !_submitting,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 8,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  counterText: '',
                  hintText: '000000',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              if (locked)
                Text(
                  'Too many incorrect codes. Try again in $remaining '
                  '${remaining == 1 ? 'second' : 'seconds'}.',
                  key: const Key('pairing-lockout'),
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (_error != null ||
                  (pairing != null && pairing.failedAttempts > 0))
                Text(
                  _error ??
                      'Incorrect code. Check the code on your computer and '
                          'try again.',
                  key: const Key('pairing-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('pairing-submit'),
                onPressed: (_complete && !locked && !_submitting)
                    ? _submit
                    : null,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pair'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
