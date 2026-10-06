import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/fair_draw.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';

/// The commit-reveal draw for one circle: replays how the turns fell out of the
/// revealed seed, then rechecks the seed and the order on this phone.
class DrawScreen extends ConsumerWidget {
  const DrawScreen({super.key, required this.circleId});

  final String circleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(circleProvider(circleId));
    return Scaffold(
      appBar: AppBar(title: const Text('Fair draw')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(circleProvider(circleId))),
        data: (c) => _DrawBody(circle: c),
      ),
    );
  }
}

class _DrawBody extends StatelessWidget {
  const _DrawBody({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context) {
    final c = circle;
    final draw = c.draw;
    final check = checkDraw(c);
    final onBlueBody = SovaText.bodySmall.copyWith(color: SovaColors.white.withValues(alpha: 0.85));

    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.lg, SovaSpacing.screenH, SovaSpacing.xl4),
      children: [
        AdirePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(c.name, onBlue: true),
              const SizedBox(height: SovaSpacing.md),
              Text(
                draw?.revealedAt != null ? 'Turns drawn ${longDate(draw!.revealedAt!)}' : 'Sealed, not drawn yet',
                style: SovaText.h2.copyWith(color: SovaColors.white),
              ),
              const SizedBox(height: SovaSpacing.xs),
              Text(
                draw == null
                    ? 'This circle has no recorded draw.'
                    : draw.revealed
                        ? 'The order came from a secret seed whose fingerprint was sealed when the circle was created, '
                            'before anyone joined. Nobody, not even the admin, could choose it.'
                        : 'Sova sealed a fingerprint of a secret seed when the circle was created, before anyone joined. '
                            'When everyone has joined and accepted the rules, the seed is revealed and the turns follow from it.',
                style: onBlueBody,
              ),
            ],
          ),
        ),
        if (draw != null && check != null) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('How the order fell'),
          const SizedBox(height: SovaSpacing.md),
          _DrawAnimation(circle: c, seed: draw.seed!),
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('Checked on this phone'),
          const SizedBox(height: SovaSpacing.md),
          _ChecksCard(check: check, adminCollectsLast: c.adminCollectsLast),
        ],
        if (draw != null) ...[
          const SizedBox(height: SovaSpacing.xl3),
          const Eyebrow('The numbers'),
          const SizedBox(height: SovaSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(SovaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HashLine(label: 'Fingerprint (sealed at creation)', value: draw.commitment),
                  const Divider(height: SovaSpacing.xl2),
                  draw.revealed
                      ? _HashLine(label: 'Seed (revealed at the draw)', value: draw.seed!)
                      : const Text('Seed: kept secret until the draw.', style: SovaText.bodySmall),
                ],
              ),
            ),
          ),
        ],
        // Only circles on the server have a public ledger to check.
        if (draw != null && apiUrl.isNotEmpty) ...[
          const SizedBox(height: SovaSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('$siteUrl/verify/?c=${c.id}'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.verified_user_outlined),
            label: const Text('Check the full record'),
          ),
          const SizedBox(height: SovaSpacing.xs),
          const Text(
            'The public record also shows the fingerprint was sealed before the first member joined.',
            style: SovaText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// Members start A to Z by name. Each one's key, SHA-256(seed:member), settles
/// in turn; then everyone slides into turn order (smallest key first).
class _DrawAnimation extends StatefulWidget {
  const _DrawAnimation({required this.circle, required this.seed});

  final Circle circle;
  final String seed;

  @override
  State<_DrawAnimation> createState() => _DrawAnimationState();
}

class _DrawAnimationState extends State<_DrawAnimation> with SingleTickerProviderStateMixin {
  /// Share of the animation spent revealing keys; the rest moves the cards.
  static const _keysEnd = 0.55;
  static const _moveStart = 0.62;

  late final AnimationController _controller;
  late List<Member> _startOrder;
  late Map<String, int> _turnIndex;
  late Map<String, String> _keys;

  @override
  void initState() {
    super.initState();
    _prepare();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1600 + 420 * _startOrder.length),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "remove animations": show the result straight away.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_DrawAnimation old) {
    super.didUpdateWidget(old);
    if (old.circle != widget.circle || old.seed != widget.seed) _prepare();
  }

  void _prepare() {
    final c = widget.circle;
    _startOrder = [...c.members]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _keys = {for (final m in c.members) m.userId: drawKey(widget.seed, m.userId)};
    _turnIndex = {for (final (i, m) in c.membersByPosition.indexed) m.userId: i};
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _replay() {
    HapticFeedback.selectionClick();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final rowHeight = max(64.0, MediaQuery.textScalerOf(context).scale(18) * 2 + 28);
    final n = _startOrder.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SovaSpacing.md, SovaSpacing.md, SovaSpacing.md, SovaSpacing.xs),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final move = Curves.easeInOutCubic.transform(((t - _moveStart) / (1 - _moveStart)).clamp(0.0, 1.0));
            final stage = t < _keysEnd
                ? 'Members A to Z: working out each one\'s key from the seed'
                : t < 1
                    ? 'Smallest key collects first'
                    : widget.circle.adminCollectsLast
                        ? 'Turn order: smallest key first, admin last as pledged'
                        : 'Turn order: smallest key first';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(stage, style: SovaText.caption)),
                      TextButton.icon(
                        onPressed: _controller.isAnimating ? null : _replay,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text('Replay'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: SovaSpacing.xs),
                SizedBox(
                  height: rowHeight * n,
                  child: Stack(
                    children: [
                      for (final (i, m) in _startOrder.indexed)
                        Positioned(
                          left: 0,
                          right: 0,
                          top: rowHeight * (i + ((_turnIndex[m.userId] ?? i) - i) * move),
                          height: rowHeight,
                          child: _DrawRow(
                            member: m,
                            turn: (_turnIndex[m.userId] ?? i) + 1,
                            keyHex: _keys[m.userId]!,
                            // Keys settle one after another during the first stage.
                            keyProgress: ((t / _keysEnd) * (n + 1) - (i + 1)).clamp(0.0, 1.0),
                            turnOpacity: move,
                            pledgedLast: widget.circle.adminCollectsLast && m.userId == widget.circle.adminId,
                            settled: t >= 1,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DrawRow extends StatelessWidget {
  const _DrawRow({
    required this.member,
    required this.turn,
    required this.keyHex,
    required this.keyProgress,
    required this.turnOpacity,
    required this.pledgedLast,
    required this.settled,
  });

  final Member member;
  final int turn;
  final String keyHex;

  /// 0 while the key is still "rolling", 1 once it shows the real value.
  final double keyProgress;
  final double turnOpacity;
  final bool pledgedLast;
  final bool settled;

  static const _hex = '0123456789abcdef';

  String get _shownKey {
    const shown = 6;
    if (keyProgress >= 1) return '${keyHex.substring(0, shown)}…';
    if (keyProgress <= 0) return '······…';
    // Characters lock in from the left while the rest keep changing.
    final locked = (keyProgress * shown).floor();
    final roll = Random(keyHex.hashCode ^ (keyProgress * 1000).floor());
    return '${keyHex.substring(0, locked)}${List.generate(shown - locked, (_) => _hex[roll.nextInt(16)]).join()}…';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: settled
          ? 'Turn $turn, ${member.name}${pledgedLast ? ', pledged to collect last' : ''}, key ${keyHex.substring(0, 8)}'
          : null,
      excludeSemantics: settled,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: SovaSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.md),
        decoration: BoxDecoration(
          color: SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.md),
          border: Border.all(color: settled && turn == 1 ? SovaColors.electric : SovaColors.border),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Opacity(
                opacity: turnOpacity,
                child: Text('$turn', style: SovaText.h3.copyWith(color: SovaColors.electric)),
              ),
            ),
            MemberAvatar(member, size: 32, highlight: settled && turn == 1),
            const SizedBox(width: SovaSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: SovaText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (pledgedLast)
                    const Text('Admin, pledged to collect last', style: SovaText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: SovaSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: SovaSpacing.xs),
              decoration: BoxDecoration(color: SovaColors.mist, borderRadius: BorderRadius.circular(SovaRadius.sm)),
              child: Text(
                _shownKey,
                style: SovaText.caption.copyWith(
                  color: keyProgress >= 1 ? SovaColors.navy900 : SovaColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecksCard extends StatelessWidget {
  const _ChecksCard({required this.check, required this.adminCollectsLast});

  final DrawCheck check;
  final bool adminCollectsLast;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CheckLine(
              ok: check.seedMatchesCommitment,
              title: check.seedMatchesCommitment
                  ? 'The seed matches the sealed fingerprint'
                  : 'The seed does not match the sealed fingerprint',
              detail: 'SHA-256 of the revealed seed gives the fingerprint published when the circle was created.',
            ),
            const SizedBox(height: SovaSpacing.lg),
            _CheckLine(
              ok: check.orderMatches,
              title: check.orderMatches
                  ? 'Recomputing the order gives the same turns'
                  : 'Recomputing the order gives different turns',
              detail: 'Each member\'s key is SHA-256(seed:member id); the smallest key collects first'
                  '${adminCollectsLast ? ', and the admin collects last as pledged' : ''}.',
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  const _CheckLine({required this.ok, required this.title, required this.detail});

  final bool ok;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Errors stay in the blue/navy palette; the icon carries the meaning.
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            color: ok ? SovaColors.electric : SovaColors.navy900, size: 22),
        const SizedBox(width: SovaSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: SovaText.label),
              const SizedBox(height: 2),
              Text(detail, style: SovaText.caption),
            ],
          ),
        ),
      ],
    );
  }
}

class _HashLine extends StatelessWidget {
  const _HashLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SovaText.caption),
              const SizedBox(height: SovaSpacing.xs),
              SelectableText(
                value,
                style: SovaText.bodySmall.copyWith(
                  color: SovaColors.navy900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy ${label.split(' ').first.toLowerCase()}',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${label.split(' ').first} copied.')));
          },
        ),
      ],
    );
  }
}
