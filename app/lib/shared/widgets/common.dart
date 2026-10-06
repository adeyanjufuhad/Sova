import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/theme.dart';
import '../../data/models.dart';
import 'adire_painter.dart';

class SovaLogo extends StatelessWidget {
  const SovaLogo({super.key, this.size = 32, this.onBlue = false, this.wordmark = true});

  final double size;
  final bool onBlue;
  final bool wordmark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          onBlue ? 'assets/brand/sova-mark-light.png' : 'assets/brand/sova-mark-navy.png',
          width: size,
          height: size,
          semanticLabel: wordmark ? null : 'Sova',
        ),
        if (wordmark) ...[
          const SizedBox(width: SovaSpacing.sm),
          Text(
            'sova',
            style: SovaText.h2.copyWith(
              fontSize: size * 0.7,
              color: onBlue ? SovaColors.white : SovaColors.navy900,
            ),
          ),
        ],
      ],
    );
  }
}

/// Small uppercase label with a square marker, like the website's eyebrows.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.onBlue = false});

  final String text;
  final bool onBlue;

  @override
  Widget build(BuildContext context) {
    final color = onBlue ? SovaColors.sky : SovaColors.electric;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, color: color),
        const SizedBox(width: SovaSpacing.sm),
        // Flexible so a long label wraps instead of overflowing on small phones.
        Flexible(child: Text(text.toUpperCase(), style: SovaText.eyebrow.copyWith(color: color))),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.compact = false});

  final ContributionStatus status;

  /// Shorter wording for tight rows ("Awaiting" instead of "Awaiting confirmation").
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (status) {
      ContributionStatus.fullyConfirmed => (SovaColors.electric, SovaColors.white, Icons.done_all_rounded),
      ContributionStatus.payerConfirmed => (SovaColors.electricTint, SovaColors.electric, Icons.schedule_rounded),
      ContributionStatus.pending => (SovaColors.mist, SovaColors.textSecondary, Icons.radio_button_unchecked_rounded),
      ContributionStatus.disputed => (SovaColors.navy900, SovaColors.white, Icons.gavel_rounded),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.sm, vertical: SovaSpacing.xs),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SovaRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: SovaSpacing.xs),
          Text(
            compact && status == ContributionStatus.payerConfirmed ? 'Awaiting' : status.label,
            style: SovaText.caption.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.member, {super.key, this.size = 40, this.highlight = false});

  final Member member;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? SovaColors.electric : SovaColors.electricTint,
        shape: BoxShape.circle,
      ),
      child: Text(
        member.initial,
        style: SovaText.label.copyWith(color: highlight ? SovaColors.white : SovaColors.electric),
      ),
    );
  }
}

/// Label on the left, value on the right; used in receipts and summaries.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueStyle});

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SovaSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: SovaText.bodySmall)),
          const SizedBox(width: SovaSpacing.lg),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: valueStyle ?? SovaText.label),
          ),
        ],
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.5, color: SovaColors.electric));
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SovaSpacing.xl3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 40, color: SovaColors.electric),
            const SizedBox(height: SovaSpacing.lg),
            Text(message, textAlign: TextAlign.center, style: SovaText.body),
            if (onRetry != null) ...[
              const SizedBox(height: SovaSpacing.lg),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bordered message used for inline errors (blue-and-white, no red).
class NoticeBox extends StatelessWidget {
  const NoticeBox(this.message, {super.key, this.icon = Icons.info_outline_rounded});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SovaSpacing.md),
      decoration: BoxDecoration(
        color: SovaColors.electricTint,
        borderRadius: BorderRadius.circular(SovaRadius.md),
        border: Border.all(color: SovaColors.electric.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: SovaColors.electric),
          const SizedBox(width: SovaSpacing.sm),
          Expanded(child: Text(message, style: SovaText.bodySmall.copyWith(color: SovaColors.navy900))),
        ],
      ),
    );
  }
}

/// Goes back if there is a screen underneath; otherwise (opened from a link,
/// a reload, or after `context.go`) goes to [fallback].
void leaveScreen(BuildContext context, {String fallback = '/circles'}) =>
    context.canPop() ? context.pop() : context.go(fallback);

/// App bar back button that always shows, even when nothing is underneath.
class SovaBackButton extends StatelessWidget {
  const SovaBackButton({super.key, this.fallback = '/circles'});

  final String fallback;

  @override
  Widget build(BuildContext context) => BackButton(onPressed: () => leaveScreen(context, fallback: fallback));
}

/// A designed empty list: an adire tile with an icon, what's missing, what to
/// do about it, and up to two actions. Used instead of a bare notice when a
/// whole screen or section has nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: SovaSpacing.xl, vertical: SovaSpacing.xl3),
      decoration: BoxDecoration(
        color: SovaColors.white,
        borderRadius: BorderRadius.circular(SovaRadius.xl),
        border: Border.all(color: SovaColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(SovaRadius.lg),
            child: SizedBox.square(
              dimension: 64,
              child: ColoredBox(
                color: SovaColors.electric,
                child: CustomPaint(
                  painter: AdirePainter(color: SovaColors.white.withValues(alpha: 0.18), tile: 48),
                  child: Icon(icon, color: SovaColors.white, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(height: SovaSpacing.lg),
          Text(title, style: SovaText.h3, textAlign: TextAlign.center),
          const SizedBox(height: SovaSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(message, style: SovaText.bodySmall, textAlign: TextAlign.center),
          ),
          if (action != null) ...[
            const SizedBox(height: SovaSpacing.xl),
            SizedBox(width: double.infinity, child: action),
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: SovaSpacing.sm),
            SizedBox(width: double.infinity, child: secondaryAction),
          ],
        ],
      ),
    );
  }
}
