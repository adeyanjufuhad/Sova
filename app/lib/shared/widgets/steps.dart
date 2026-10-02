import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/theme.dart';

/// Numbered step indicator (after 21st.dev's "Configuration Stepper"):
/// filled circle for the current step, a tick for finished ones, joined by
/// a line that fills in as you progress.
class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.labels, required this.current});

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of ${labels.length}: ${labels[current]}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _line(i > 0, i <= current)),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < current
                                ? SovaColors.electric
                                : i == current
                                    ? SovaColors.navy900
                                    : SovaColors.mist,
                          ),
                          child: i < current
                              ? const Icon(Icons.check_rounded, size: 16, color: SovaColors.white)
                              : Text(
                                  '${i + 1}',
                                  style: SovaText.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: i == current ? SovaColors.white : SovaColors.textMuted,
                                  ),
                                ),
                        ),
                        Expanded(child: _line(i < labels.length - 1, i < current)),
                      ],
                    ),
                    const SizedBox(height: SovaSpacing.xs),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SovaText.caption.copyWith(
                        fontSize: 11,
                        fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                        color: i <= current ? SovaColors.navy900 : SovaColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _line(bool visible, bool done) => Container(
        height: 2,
        color: !visible ? Colors.transparent : (done ? SovaColors.electric : SovaColors.border),
      );
}

/// Six-character invite code in two groups of three (after 21st.dev's
/// "Input OTP Alphanumeric"). One hidden field drives the boxes, so paste works.
class CodeInput extends StatefulWidget {
  const CodeInput({super.key, required this.onChanged, this.onCompleted, this.length = 6});

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final int length;

  @override
  State<CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends State<CodeInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _group(String code, int from, int count) {
    return Expanded(
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.lg),
          border: Border.all(color: SovaColors.borderStrong),
        ),
        child: Row(
          children: [
            for (var i = from; i < from + count; i++) ...[
              if (i > from) const VerticalDivider(width: 1, thickness: 1, color: SovaColors.border),
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: i == code.length && _focus.hasFocus
                        ? const Border(bottom: BorderSide(color: SovaColors.electric, width: 2.5))
                        : null,
                  ),
                  child: Text(i < code.length ? code[i] : '', style: SovaText.h1.copyWith(letterSpacing: 0)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _controller.text;
    final half = widget.length ~/ 2;
    return GestureDetector(
      onTap: () => _focus.requestFocus(),
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            alwaysIncludeSemantics: true,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(widget.length),
                TextInputFormatter.withFunction((_, v) => v.copyWith(text: v.text.toUpperCase())),
              ],
              decoration: const InputDecoration(labelText: 'Invite code'),
              onChanged: (v) {
                setState(() {});
                widget.onChanged(v);
                if (v.length == widget.length) widget.onCompleted?.call(v);
              },
            ),
          ),
          Row(
            children: [
              _group(code, 0, half),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.md),
                child: Container(width: 14, height: 2.5, color: SovaColors.navy900),
              ),
              _group(code, half, widget.length - half),
            ],
          ),
        ],
      ),
    );
  }
}
