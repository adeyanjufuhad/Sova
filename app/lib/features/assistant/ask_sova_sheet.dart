import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/polish.dart';

/// Opens "Ask Sova": a short explanation of a circle or a dispute, or an
/// answer to a question about how Sova works, in English or Pidgin.
Future<void> showAskSova(BuildContext context, {required AssistantTopic topic, String? circleId, String? disputeId}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true, // above the tab bar
      isScrollControlled: true,
      backgroundColor: SovaColors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(SovaRadius.xl2))),
      builder: (_) => AskSovaSheet(topic: topic, circleId: circleId, disputeId: disputeId),
    );

/// Questions people ask most, offered as one-tap chips.
const askSovaSuggestions = [
  'Who holds the money?',
  'How is the payout order decided?',
  'What happens if someone doesn\'t pay?',
  'What is the Sova Score?',
];

class AskSovaSheet extends ConsumerStatefulWidget {
  const AskSovaSheet({super.key, required this.topic, this.circleId, this.disputeId});

  final AssistantTopic topic;
  final String? circleId;
  final String? disputeId;

  @override
  ConsumerState<AskSovaSheet> createState() => _AskSovaSheetState();
}

class _AskSovaSheetState extends ConsumerState<AskSovaSheet> {
  final _question = TextEditingController();
  AssistantLanguage _language = AssistantLanguage.english;
  AssistantAnswer? _answer;
  String? _error;
  bool _busy = false;

  /// Questions are typed first; circles and disputes are explained straight away.
  bool get _asking => widget.topic == AssistantTopic.question;

  @override
  void initState() {
    super.initState();
    if (!_asking) _ask();
  }

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final question = _question.text.trim();
    if (_asking && question.length < 3) {
      setState(() => _error = 'Type a question first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final answer = await ref
          .read(repositoryProvider)
          .askSova(
            topic: widget.topic,
            circleId: widget.circleId,
            disputeId: widget.disputeId,
            question: _asking ? question : null,
            language: _language,
          );
      if (mounted) setState(() => _answer = answer);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setLanguage(AssistantLanguage language) {
    if (language == _language) return;
    setState(() => _language = language);
    if (!_asking || _answer != null) _ask();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = switch (widget.topic) {
      AssistantTopic.circle => 'This circle in plain words, from its record.',
      AssistantTopic.dispute => 'What this dispute is about and how it gets decided.',
      AssistantTopic.question => 'Ask anything about how Sova works.',
    };
    final source = widget.topic == AssistantTopic.question ? 'how Sova works' : 'this circle\'s record';

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          SovaSpacing.screenH,
          SovaSpacing.lg,
          SovaSpacing.screenH,
          SovaSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: SovaColors.borderStrong, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: SovaSpacing.xl),
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: SovaColors.electric, size: 24),
                  const SizedBox(width: SovaSpacing.sm),
                  const Expanded(child: Text('Ask Sova', style: SovaText.h2)),
                  SegmentedChips<AssistantLanguage>(
                    options: {for (final l in AssistantLanguage.values) l: l.label},
                    selected: _language,
                    onChanged: _busy ? (_) {} : _setLanguage,
                  ),
                ],
              ),
              const SizedBox(height: SovaSpacing.xs),
              Text(subtitle, style: SovaText.bodySmall),
              const SizedBox(height: SovaSpacing.lg),
              if (_asking) ...[
                TextField(
                  controller: _question,
                  maxLength: 300,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _busy ? null : _ask(),
                  decoration: const InputDecoration(hintText: 'Type your question', counterText: ''),
                ),
                const SizedBox(height: SovaSpacing.sm),
                Wrap(
                  spacing: SovaSpacing.sm,
                  runSpacing: SovaSpacing.sm,
                  children: [
                    for (final s in askSovaSuggestions)
                      ActionChip(
                        label: Text(s, style: SovaText.caption.copyWith(color: SovaColors.navy900)),
                        backgroundColor: SovaColors.mist,
                        side: const BorderSide(color: SovaColors.border),
                        onPressed: _busy
                            ? null
                            : () {
                                _question.text = s;
                                _ask();
                              },
                      ),
                  ],
                ),
                const SizedBox(height: SovaSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: _busy ? null : _ask, child: const Text('Ask')),
                ),
                const SizedBox(height: SovaSpacing.lg),
              ],
              if (_busy)
                const _Thinking()
              else if (_error != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NoticeBox(_error!),
                    if (!_asking) ...[
                      const SizedBox(height: SovaSpacing.sm),
                      OutlinedButton(onPressed: _ask, child: const Text('Try again')),
                    ],
                  ],
                )
              else if (_answer != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(SovaSpacing.lg),
                    decoration: BoxDecoration(
                      color: SovaColors.mist,
                      borderRadius: BorderRadius.circular(SovaRadius.lg),
                      border: Border.all(color: SovaColors.border),
                    ),
                    child: SelectableText(_answer!.text, style: SovaText.body),
                  ),
                ),
                const SizedBox(height: SovaSpacing.sm),
                Text(
                  // The offline demo fills in a template; only the live app asks a model.
                  _answer!.model == 'demo'
                      ? 'Offline demo: a fixed answer filled in from $source. The live app writes it with AI.'
                      : 'Written by AI from $source. It can make mistakes: the circle screen is the record. '
                            'Sova never holds or moves money.',
                  style: SovaText.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ask Sova is writing an answer',
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: 14),
          SizedBox(height: SovaSpacing.sm),
          Skeleton(height: 14),
          SizedBox(height: SovaSpacing.sm),
          Skeleton(height: 14, width: 180),
        ],
      ),
    );
  }
}
