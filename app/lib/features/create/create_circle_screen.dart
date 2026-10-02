import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/adire_painter.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/pin_pad.dart';
import '../../shared/widgets/polish.dart';
import '../../shared/widgets/steps.dart';

/// Formats an invite code as two groups of three: T7K–P9Q.
String groupedCode(String code) => code.length == 6 ? '${code.substring(0, 3)}–${code.substring(3)}' : code;

DateTime _lastPayout(CycleType cycle, DateTime start, int members) {
  final steps = members - 1;
  return switch (cycle) {
    CycleType.daily => start.add(Duration(days: steps)),
    CycleType.weekly => start.add(Duration(days: 7 * steps)),
    CycleType.monthly => DateTime(start.year, start.month + steps, start.day),
  };
}

class CreateCircleScreen extends ConsumerStatefulWidget {
  const CreateCircleScreen({super.key});

  @override
  ConsumerState<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends ConsumerState<CreateCircleScreen> {
  static const _steps = ['Basics', 'Schedule', 'Rules', 'Review'];

  int _step = 0;
  final _name = TextEditingController();
  final _amount = TextEditingController(text: '10000');
  final _emergency = TextEditingController();
  int _members = 6;
  CycleType _cycle = CycleType.weekly;
  late DateTime _start = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 7));
  bool _adminFirst = false;
  int _lateFee = 500;
  int _graceDays = 1;
  EarlyExitPolicy _earlyExit = EarlyExitPolicy.findReplacement;
  bool _agreed = false;
  String? _error;
  Circle? _created;

  int get _amountValue => int.tryParse(_amount.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _emergency.dispose();
    super.dispose();
  }

  NewCircle get _draft => NewCircle(
    name: _name.text.trim(),
    contributionAmount: _amountValue,
    memberCount: _members,
    cycle: _cycle,
    startDate: _start,
    adminCollectsFirst: _adminFirst,
    lateFee: _lateFee,
    graceDays: _graceDays,
    earlyExit: _earlyExit,
    emergencyPolicy: _emergency.text,
  );

  String? _validate() {
    if (_step == 0) {
      if (_name.text.trim().length < 2) return 'Give your circle a name your members will recognise.';
      if (_amountValue < 100) return 'The contribution must be at least ₦100.';
    }
    if (_step == 3 && !_agreed) return 'Tick the box to confirm you agree to these rules.';
    return null;
  }

  Future<void> _next() async {
    final problem = _validate();
    setState(() => _error = problem);
    if (problem != null) return;
    FocusScope.of(context).unfocus();
    if (_step < _steps.length - 1) {
      setState(() => _step++);
      return;
    }
    final repo = ref.read(repositoryProvider);
    Circle? created;
    final ok = await confirmWithPin(
      context,
      title: 'Create ${_draft.name}',
      subtitle: 'You are the admin and you accept these rules.',
      onPin: (pin) async {
        await repo.verifyPin(pin);
        created = await repo.createCircle(_draft);
      },
    );
    if (!mounted || !ok || created == null) return;
    ref.invalidate(circlesProvider);
    HapticFeedback.mediumImpact();
    setState(() => _created = created);
  }

  void _back() {
    if (_step == 0) {
      context.pop();
    } else {
      setState(() {
        _error = null;
        _step--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_created != null) return _Created(circle: _created!);

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Start a circle'),
          leading: IconButton(
            tooltip: _step == 0 ? 'Close' : 'Back',
            icon: Icon(_step == 0 ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed: _back,
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SovaSpacing.screenH,
                  SovaSpacing.lg,
                  SovaSpacing.screenH,
                  SovaSpacing.sm,
                ),
                child: StepIndicator(labels: _steps, current: _step),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        SovaSpacing.screenH,
                        SovaSpacing.lg,
                        SovaSpacing.screenH,
                        SovaSpacing.xl,
                      ),
                      children: switch (_step) {
                        0 => _basics(),
                        1 => _schedule(),
                        2 => _rules(),
                        _ => _review(),
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.screenH),
                  child: NoticeBox(_error!, icon: Icons.error_outline_rounded),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  SovaSpacing.screenH,
                  SovaSpacing.md,
                  SovaSpacing.screenH,
                  SovaSpacing.md,
                ),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: SovaColors.border)),
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: OutlinedButton(onPressed: _back, child: const Text('Back')),
                      ),
                      const SizedBox(width: SovaSpacing.md),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _next,
                        child: Text(_step == _steps.length - 1 ? 'Create circle' : 'Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 1 -------------------------------------------------------------------
  List<Widget> _basics() => [
    const Text('Name your circle and set the amount', style: SovaText.h2),
    const SizedBox(height: SovaSpacing.xl2),
    TextField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      maxLength: 60,
      decoration: const InputDecoration(labelText: 'Circle name', hintText: 'e.g. Office Esusu', counterText: ''),
    ),
    const SizedBox(height: SovaSpacing.lg),
    TextField(
      controller: _amount,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
      style: SovaText.moneyMedium,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Each member pays',
        prefixText: '₦ ',
        prefixStyle: SovaText.moneyMedium,
        helperText: 'per ${_cycle.unit}',
      ),
    ),
    const SizedBox(height: SovaSpacing.md),
    Wrap(
      spacing: SovaSpacing.sm,
      runSpacing: SovaSpacing.sm,
      children: [
        for (final v in const [2000, 5000, 10000, 20000, 50000])
          Pressable(
            onTap: () => setState(() => _amount.text = '$v'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.md, vertical: SovaSpacing.sm),
              decoration: BoxDecoration(
                color: _amountValue == v ? SovaColors.electric : SovaColors.mist,
                borderRadius: BorderRadius.circular(SovaRadius.full),
              ),
              child: Text(
                naira(v),
                style: SovaText.label.copyWith(
                  fontSize: 13,
                  color: _amountValue == v ? SovaColors.white : SovaColors.navy900,
                ),
              ),
            ),
          ),
      ],
    ),
    const SizedBox(height: SovaSpacing.xl2),
    const Text('How many members, including you?', style: SovaText.label),
    const SizedBox(height: SovaSpacing.md),
    Container(
      padding: const EdgeInsets.all(SovaSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: SovaColors.borderStrong),
        borderRadius: BorderRadius.circular(SovaRadius.lg),
      ),
      child: Row(
        children: [
          _RoundStep(
            icon: Icons.remove_rounded,
            label: 'Fewer members',
            onTap: _members > 2 ? () => setState(() => _members--) : null,
          ),
          Expanded(
            child: Column(
              children: [
                Text('$_members', style: SovaText.h1),
                Text('members · $_members turns', style: SovaText.caption),
              ],
            ),
          ),
          _RoundStep(
            icon: Icons.add_rounded,
            label: 'More members',
            onTap: _members < 30 ? () => setState(() => _members++) : null,
          ),
        ],
      ),
    ),
  ];

  // Step 2 -------------------------------------------------------------------
  List<Widget> _schedule() {
    final end = _lastPayout(_cycle, _start, _members);
    return [
      const Text('When do members pay?', style: SovaText.h2),
      const SizedBox(height: SovaSpacing.xl),
      for (final c in CycleType.values) ...[
        _ChoiceCard(
          selected: _cycle == c,
          title: c.label,
          subtitle: switch (c) {
            CycleType.daily => 'Best for market traders with daily sales',
            CycleType.weekly => 'The most popular: steady without daily pressure',
            CycleType.monthly => 'Best for salary earners',
          },
          onTap: () => setState(() => _cycle = c),
        ),
        const SizedBox(height: SovaSpacing.sm),
      ],
      const SizedBox(height: SovaSpacing.lg),
      const Text('First payment date', style: SovaText.label),
      const SizedBox(height: SovaSpacing.sm),
      Pressable(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: _start,
            firstDate: DateUtils.dateOnly(DateTime.now()),
            lastDate: DateTime.now().add(const Duration(days: 180)),
          );
          if (picked != null) setState(() => _start = picked);
        },
        child: Container(
          padding: const EdgeInsets.all(SovaSpacing.lg),
          decoration: BoxDecoration(
            border: Border.all(color: SovaColors.borderStrong),
            borderRadius: BorderRadius.circular(SovaRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_outlined, color: SovaColors.electric),
              const SizedBox(width: SovaSpacing.md),
              Expanded(child: Text(longDate(_start), style: SovaText.label)),
              Text('Change', style: SovaText.label.copyWith(color: SovaColors.electric)),
            ],
          ),
        ),
      ),
      const SizedBox(height: SovaSpacing.xl),
      const Text('When do you collect?', style: SovaText.label),
      const SizedBox(height: SovaSpacing.sm),
      _ChoiceCard(
        selected: !_adminFirst,
        title: 'Last (recommended)',
        subtitle: 'Shows good faith: you collect after everyone else.',
        onTap: () => setState(() => _adminFirst = false),
      ),
      const SizedBox(height: SovaSpacing.sm),
      _ChoiceCard(
        selected: _adminFirst,
        title: 'First',
        subtitle: 'Other members join in the order they accept.',
        onTap: () => setState(() => _adminFirst = true),
      ),
      const SizedBox(height: SovaSpacing.xl),
      Container(
        padding: const EdgeInsets.all(SovaSpacing.lg),
        decoration: BoxDecoration(color: SovaColors.mist, borderRadius: BorderRadius.circular(SovaRadius.lg)),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Each member pays '),
              TextSpan(
                text: naira(_amountValue),
                style: const TextStyle(fontWeight: FontWeight.w700, color: SovaColors.navy900),
              ),
              TextSpan(text: ' every ${_cycle.unit} and collects '),
              TextSpan(
                text: naira(_draft.payout),
                style: const TextStyle(fontWeight: FontWeight.w700, color: SovaColors.navy900),
              ),
              TextSpan(text: ' once. The last payout is around ${longDate(end)}.'),
            ],
          ),
          style: SovaText.bodySmall.copyWith(color: SovaColors.textSecondary),
        ),
      ),
    ];
  }

  // Step 3 -------------------------------------------------------------------
  List<Widget> _rules() => [
    const Text('Agree the rules up front', style: SovaText.h2),
    const SizedBox(height: SovaSpacing.xs),
    const Text(
      'Every member accepts these when they join. Clear rules prevent fights later.',
      style: SovaText.bodySmall,
    ),
    const SizedBox(height: SovaSpacing.xl),
    const Text('Fine for paying late', style: SovaText.label),
    const SizedBox(height: SovaSpacing.sm),
    SegmentedChips<int>(
      options: const {0: 'No fine', 500: '₦500', 1000: '₦1,000', 2000: '₦2,000'},
      selected: _lateFee,
      onChanged: (v) => setState(() => _lateFee = v),
    ),
    const SizedBox(height: SovaSpacing.xl),
    const Text('Grace period before a payment is late', style: SovaText.label),
    const SizedBox(height: SovaSpacing.sm),
    SegmentedChips<int>(
      options: const {0: 'None', 1: '1 day', 2: '2 days', 3: '3 days'},
      selected: _graceDays,
      onChanged: (v) => setState(() => _graceDays = v),
    ),
    const SizedBox(height: SovaSpacing.xl),
    const Text('If someone must leave early', style: SovaText.label),
    const SizedBox(height: SovaSpacing.sm),
    for (final p in EarlyExitPolicy.values) ...[
      _ChoiceCard(
        selected: _earlyExit == p,
        title: p.label,
        subtitle: p.description,
        onTap: () => setState(() => _earlyExit = p),
      ),
      const SizedBox(height: SovaSpacing.sm),
    ],
    const SizedBox(height: SovaSpacing.lg),
    TextField(
      controller: _emergency,
      maxLines: 3,
      maxLength: 300,
      decoration: const InputDecoration(
        labelText: 'Emergencies (optional)',
        hintText: 'e.g. If a member falls ill, the group can move their turn earlier.',
        alignLabelWithHint: true,
      ),
    ),
  ];

  // Step 4 -------------------------------------------------------------------
  List<Widget> _review() {
    final d = _draft;
    return [
      const Text('Check everything', style: SovaText.h2),
      const SizedBox(height: SovaSpacing.lg),
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: SovaColors.border),
          borderRadius: BorderRadius.circular(SovaRadius.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            AdirePanel(
              radius: 0,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.name, style: SovaText.h3.copyWith(color: SovaColors.white)),
                        const SizedBox(height: SovaSpacing.xs),
                        Text(
                          'Each payout',
                          style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.8)),
                        ),
                        Text(naira(d.payout), style: SovaText.moneyMedium.copyWith(color: SovaColors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
              child: Column(
                children: [
                  InfoRow(
                    'Contribution',
                    '${naira(d.contributionAmount)} ${d.cycle.label.toLowerCase()}',
                    valueStyle: SovaText.moneySmall,
                  ),
                  InfoRow('Members', '${d.memberCount}'),
                  InfoRow('First payment', longDate(d.startDate)),
                  InfoRow('Your turn', d.adminCollectsFirst ? 'First' : 'Last (turn ${d.memberCount})'),
                  InfoRow('Late fine', d.lateFee == 0 ? 'None' : '${naira(d.lateFee)} after ${d.graceDays} day(s)'),
                  InfoRow('Leaving early', d.earlyExit.label),
                  if (_emergency.text.trim().isNotEmpty) InfoRow('Emergencies', _emergency.text.trim()),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: SovaSpacing.lg),
      Pressable(
        onTap: () => setState(() {
          _agreed = !_agreed;
          _error = null;
        }),
        child: Row(
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
            const SizedBox(width: SovaSpacing.xs),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: SovaSpacing.md),
                child: Text(
                  'I agree to these rules as admin. Sova records the date I accepted, and every member accepts them when they join.',
                  style: SovaText.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: SovaSpacing.md),
      const NoticeBox(
        'Sova never holds the money. Members pay each other directly; Sova keeps the record.',
        icon: Icons.account_balance_outlined,
      ),
    ];
  }
}

class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: onTap == null ? SovaColors.mist : SovaColors.electricTint,
          borderRadius: BorderRadius.circular(SovaRadius.md),
        ),
        child: Icon(icon, color: onTap == null ? SovaColors.textMuted : SovaColors.electric),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.selected, required this.title, required this.subtitle, required this.onTap});

  final bool selected;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(SovaSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? SovaColors.electricTint : SovaColors.white,
          borderRadius: BorderRadius.circular(SovaRadius.lg),
          border: Border.all(color: selected ? SovaColors.electric : SovaColors.borderStrong, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: SovaText.label),
                  const SizedBox(height: 2),
                  Text(subtitle, style: SovaText.caption),
                ],
              ),
            ),
            const SizedBox(width: SovaSpacing.md),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? SovaColors.electric : SovaColors.textMuted,
              semanticLabel: selected ? 'Selected' : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown after creating: the invite code to share.
class _Created extends StatelessWidget {
  const _Created({required this.circle});

  final Circle circle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SovaSpacing.screenH),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(color: SovaColors.electric, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: SovaColors.white, size: 38),
              ),
              const SizedBox(height: SovaSpacing.xl),
              Text('${circle.name} is ready', style: SovaText.h1, textAlign: TextAlign.center),
              const SizedBox(height: SovaSpacing.sm),
              const Text(
                'Send this code to the people you trust. Whoever invites a new member vouches for them.',
                style: SovaText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SovaSpacing.xl2),
              AdirePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Invite code',
                      textAlign: TextAlign.center,
                      style: SovaText.caption.copyWith(color: SovaColors.white.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: SovaSpacing.xs),
                    Text(
                      groupedCode(circle.inviteCode),
                      textAlign: TextAlign.center,
                      style: SovaText.display.copyWith(color: SovaColors.white, letterSpacing: 4),
                    ),
                    const SizedBox(height: SovaSpacing.md),
                    Center(
                      child: Pressable(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: 'Join my Sova circle "${circle.name}" with code ${circle.inviteCode}.'),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite message copied. Paste it in WhatsApp or SMS.')),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.lg, vertical: SovaSpacing.sm),
                          decoration: BoxDecoration(
                            color: SovaColors.white,
                            borderRadius: BorderRadius.circular(SovaRadius.full),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.copy_rounded, size: 16, color: SovaColors.navy900),
                              const SizedBox(width: SovaSpacing.sm),
                              Text('Copy invite message', style: SovaText.label.copyWith(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(onPressed: () => context.go('/circle/${circle.id}'), child: const Text('Go to circle')),
              const SizedBox(height: SovaSpacing.sm),
              TextButton(onPressed: () => context.go('/circles'), child: const Text('Back to my circles')),
            ],
          ),
        ),
      ),
    );
  }
}
