import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';

/// Four dots plus a large numeric keypad. Big keys suit low-literacy users
/// and work without the system keyboard.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.onCompleted, this.length = 4, this.busy = false});

  final ValueChanged<String> onCompleted;
  final int length;
  final bool busy;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  /// Clears the dots, e.g. after a wrong PIN.
  void clear() => setState(() => _pin = '');

  void _tap(String digit) {
    if (widget.busy || _pin.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += digit);
    if (_pin.length == widget.length) widget.onCompleted(_pin);
  }

  void _backspace() {
    if (widget.busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: '${_pin.length} of ${widget.length} digits entered',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? SovaColors.electric : SovaColors.white,
                    border: Border.all(color: i < _pin.length ? SovaColors.electric : SovaColors.borderStrong, width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        SizedBox(
          height: 24,
          child: widget.busy
              ? const SizedBox.square(
                  dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: SovaColors.electric))
              : null,
        ),
        const SizedBox(height: SovaSpacing.lg),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _Key(label: d, onTap: () => _tap(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88, height: 72),
            _Key(label: '0', onTap: () => _tap('0')),
            _Key(icon: Icons.backspace_outlined, semanticLabel: 'Delete', onTap: _backspace),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({this.label, this.icon, this.semanticLabel, required this.onTap});

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(SovaSpacing.xs),
      child: Material(
        color: label != null ? SovaColors.mist : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 64,
            child: Center(
              child: label != null
                  ? Text(label!, style: SovaText.h1)
                  : Icon(icon, color: SovaColors.navy900, semanticLabel: semanticLabel),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that asks for the PIN and runs [onPin]. Returns true when
/// [onPin] succeeds; shows its error message and lets the user retry otherwise.
Future<bool> confirmWithPin(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<void> Function(String pin) onPin,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true, // above the tab bar
    isScrollControlled: true,
    backgroundColor: SovaColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
    builder: (_) => _PinSheet(title: title, subtitle: subtitle, onPin: onPin),
  );
  return result ?? false;
}

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.title, required this.subtitle, required this.onPin});

  final String title;
  final String subtitle;
  final Future<void> Function(String pin) onPin;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final _padKey = GlobalKey<PinPadState>();
  bool _busy = false;
  String? _error;

  Future<void> _submit(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onPin(pin);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _padKey.currentState?.clear();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: SovaColors.borderStrong, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: SovaSpacing.xl2),
            const Icon(Icons.lock_outline_rounded, color: SovaColors.electric, size: 28),
            const SizedBox(height: SovaSpacing.md),
            Text(widget.title, style: SovaText.h2, textAlign: TextAlign.center),
            const SizedBox(height: SovaSpacing.xs),
            Text(widget.subtitle, style: SovaText.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: SovaSpacing.xl2),
            PinPad(key: _padKey, busy: _busy, onCompleted: _submit),
            if (_error != null) ...[
              const SizedBox(height: SovaSpacing.md),
              Text(_error!, style: SovaText.label.copyWith(color: SovaColors.electric), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
