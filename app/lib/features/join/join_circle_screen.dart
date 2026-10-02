import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/insights.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../shared/widgets/polish.dart';
import '../../shared/widgets/steps.dart';
import '../circles/circles_screen.dart' show AvatarStack;

class JoinCircleScreen extends ConsumerStatefulWidget {
  const JoinCircleScreen({super.key});

  @override
  ConsumerState<JoinCircleScreen> createState() => _JoinCircleScreenState();
}

class _JoinCircleScreenState extends ConsumerState<JoinCircleScreen> {
  String _code = '';
  Circle? _circle;
  String? _voucherId;
  bool _agreed = false;
  bool _busy = false;
  String? _error;

  Future<void> _find([String? code]) async {
    final c = code ?? _code;
    if (c.length != 6) {
      setState(() => _error = 'Invite codes have 6 letters and numbers.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final found = await ref.read(repositoryProvider).findByInviteCode(c);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _circle = found);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final c = _circle!;
    if (_voucherId == null) {
      setState(() => _error = 'Choose the member who invited you.');
      return;
    }
    if (!_agreed) {
      setState(() => _error = 'Tick the box to accept the group rules.');
      return;
    }
    setState(() => _error = null);
    final repo = ref.read(repositoryProvider);
    final ok = await confirmWithPin(
      context,
      title: 'Join ${c.name}',
      subtitle: 'You accept the rules and agree to pay ${naira(c.contributionAmount)} every ${c.cycle.unit}.',
      onPin: (pin) async {
        await repo.verifyPin(pin);
        await repo.joinCircle(code: c.inviteCode, voucherId: _voucherId!);
      },
    );
    if (!mounted || !ok) return;
    refreshCircle(ref, c.id);
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Welcome to ${c.name}.')));
    context.go('/circle/${c.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = _circle;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a circle'),
        leading: IconButton(
          tooltip: c == null ? 'Close' : 'Back',
          icon: Icon(c == null ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () => c == null
              ? context.pop()
              : setState(() {
                  _circle = null;
                  _error = null;
                }),
        ),
      ),
      body: SafeArea(child: c == null ? _codeStep() : _preview(c)),
    );
  }

  Widget _codeStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl2, SovaSpacing.screenH, SovaSpacing.xl),
      children: [
        const Eyebrow('Invite code'),
        const SizedBox(height: SovaSpacing.md),
        const Text('Enter the code from your circle', style: SovaText.h1),
        const SizedBox(height: SovaSpacing.sm),
        const Text('Ask the member who invited you. It has 6 letters and numbers.', style: SovaText.body),
        const SizedBox(height: SovaSpacing.xl3),
        CodeInput(
          onChanged: (v) => setState(() {
            _code = v;
            _error = null;
          }),
          onCompleted: _find,
        ),
        const SizedBox(height: SovaSpacing.xl),
        if (_error != null) ...[
          NoticeBox(_error!, icon: Icons.error_outline_rounded),
          const SizedBox(height: SovaSpacing.lg),
        ],
        FilledButton(
          onPressed: _busy || _code.length != 6 ? null : _find,
          child: _busy
              ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: SovaColors.white))
              : const Text('Find circle'),
        ),
        const SizedBox(height: SovaSpacing.xl2),
        // TODO: remove once circles come from the server.
        const NoticeBox('Demo mode: try the code T7KP9Q.', icon: Icons.science_outlined),
      ],
    );
  }

  Widget _preview(Circle c) {
    final admin = c.memberById(c.adminId);
    final spots = c.memberCount - c.members.length;
    final taken = c.members.map((m) => m.position).toSet();
    final myTurn = [for (var p = 1; p <= c.memberCount; p++) p].firstWhere((p) => !taken.contains(p), orElse: () => 0);
    final rules = c.rules;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.xl, SovaSpacing.screenH, SovaSpacing.xl),
            children: [
              StaggeredIn(index: 0, child: _StackedCircleCard(circle: c)),
              const SizedBox(height: SovaSpacing.xl2),
              StaggeredIn(
                index: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border.all(color: SovaColors.border),
                    borderRadius: BorderRadius.circular(SovaRadius.xl),
                  ),
                  child: Column(
                    children: [
                      InfoRow('Admin', admin?.name ?? '—'),
                      InfoRow('You pay', '${naira(c.contributionAmount)} ${c.cycle.label.toLowerCase()}', valueStyle: SovaText.moneySmall),
                      InfoRow('You collect', naira(c.payout), valueStyle: SovaText.moneySmall.copyWith(color: SovaColors.electric)),
                      if (myTurn > 0) InfoRow('Your turn', 'Turn $myTurn · ${shortDate(payoutDateFor(c, myTurn))}'),
                      InfoRow('Starts', longDate(c.startDate)),
                      InfoRow('Spots left', '$spots of ${c.memberCount}'),
                    ],
                  ),
                ),
              ),
              if (rules != null) ...[
                const SizedBox(height: SovaSpacing.xl2),
                const SectionHeader('Group rules you accept'),
                const SizedBox(height: SovaSpacing.sm),
                _RuleLine(Icons.timer_outlined,
                    rules.lateFee == 0 ? 'No late fine' : '${naira(rules.lateFee)} fine after ${rules.graceDays} day(s) grace'),
                _RuleLine(Icons.logout_rounded, '${rules.earlyExit.label}: ${rules.earlyExit.description}'),
                if (rules.emergencyPolicy != null) _RuleLine(Icons.medical_services_outlined, rules.emergencyPolicy!),
                _RuleLine(Icons.gavel_rounded, 'Disputes are settled by the record in Sova.'),
              ],
              const SizedBox(height: SovaSpacing.xl2),
              const SectionHeader('Who invited you?'),
              const SizedBox(height: SovaSpacing.xs),
              const Text(
                'They vouch for you. If you collect and then stop paying, it shows on both your records.',
                style: SovaText.bodySmall,
              ),
              const SizedBox(height: SovaSpacing.md),
              for (final m in c.membersByPosition)
                Padding(
                  padding: const EdgeInsets.only(bottom: SovaSpacing.sm),
                  child: Pressable(
                    onTap: () => setState(() {
                      _voucherId = m.userId;
                      _error = null;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(SovaSpacing.md),
                      decoration: BoxDecoration(
                        color: _voucherId == m.userId ? SovaColors.electricTint : SovaColors.white,
                        borderRadius: BorderRadius.circular(SovaRadius.lg),
                        border: Border.all(
                          color: _voucherId == m.userId ? SovaColors.electric : SovaColors.border,
                          width: _voucherId == m.userId ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          MemberAvatar(m, size: 38, highlight: _voucherId == m.userId),
                          const SizedBox(width: SovaSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.name, style: SovaText.label),
                                Text(m.userId == c.adminId ? 'Admin' : 'Member', style: SovaText.caption),
                              ],
                            ),
                          ),
                          Icon(
                            _voucherId == m.userId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: _voucherId == m.userId ? SovaColors.electric : SovaColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: SovaSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreed,
                    activeColor: SovaColors.electric,
                    onChanged: (v) => setState(() {
                      _agreed = v ?? false;
                      _error = null;
                    }),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: SovaSpacing.md),
                      child: Text(
                        'I accept the group rules. Sova records the date I accepted.',
                        style: SovaText.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH),
            child: NoticeBox(_error!, icon: Icons.error_outline_rounded),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(SovaSpacing.screenH, SovaSpacing.md, SovaSpacing.screenH, SovaSpacing.md),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: SovaColors.border))),
          child: FilledButton(onPressed: _join, child: Text('Join ${c.name}', overflow: TextOverflow.ellipsis)),
        ),
      ],
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SovaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: SovaColors.electric),
          const SizedBox(width: SovaSpacing.md),
          Expanded(child: Text(text, style: SovaText.bodySmall.copyWith(color: SovaColors.navy900))),
        ],
      ),
    );
  }
}

/// The circle shown as a stack of cards (after 21st.dev's "Wallet Card"):
/// flat layers behind, member avatars, and amounts that respect hide-amounts.
class _StackedCircleCard extends ConsumerWidget {
  const _StackedCircleCard({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = circle;
    return SizedBox(
      height: 214,
      child: Stack(
        children: [
          // Two flat layers peeking out underneath.
          Positioned(
            left: 28,
            right: 28,
            bottom: 0,
            height: 40,
            child: Container(decoration: BoxDecoration(color: SovaColors.sky, borderRadius: BorderRadius.circular(SovaRadius.xl2))),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 10,
            height: 40,
            child: Container(
              decoration: BoxDecoration(color: SovaColors.electric, borderRadius: BorderRadius.circular(SovaRadius.xl2)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SovaRadius.xl2),
              child: ColoredBox(
                color: SovaColors.navy900,
                child: CustomPaint(
                  painter: AdirePainter(color: SovaColors.white.withValues(alpha: 0.06), tile: 90),
                  child: Padding(
                    padding: const EdgeInsets.all(SovaSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(c.name,
                                  style: SovaText.h3.copyWith(color: SovaColors.white), overflow: TextOverflow.ellipsis),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: 2),
                              decoration: BoxDecoration(
                                color: SovaColors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(SovaRadius.full),
                              ),
                              child: Text(c.cycle.label,
                                  style: SovaText.caption.copyWith(color: SovaColors.white, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text('Each payout', style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.7))),
                        Money(c.payout, style: SovaText.moneyLarge.copyWith(color: SovaColors.white, fontSize: 30)),
                        const SizedBox(height: SovaSpacing.md),
                        Row(
                          children: [
                            AvatarStack(members: c.membersByPosition, size: 28),
                            const SizedBox(width: SovaSpacing.sm),
                            Expanded(
                              child: Text(
                                '${c.members.length} of ${c.memberCount} joined',
                                style: SovaText.caption.copyWith(color: SovaColors.sky, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
