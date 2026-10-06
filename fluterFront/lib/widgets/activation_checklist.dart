import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// One step of the activation checklist.
class ChecklistStep {
  final String label;
  final bool done;

  /// Deep link to where the step happens; ignored once [done].
  final VoidCallback onGo;

  const ChecklistStep(
      {required this.label, required this.done, required this.onGo});
}

/// "Get your family going" — the dashboard activation checklist
/// (docs/onboarding-help-plan.md Phase 3). Walks a new family through the
/// full economy loop once. Steps auto-check from real data, each pending
/// row deep-links to where it happens, and the card can be dismissed.
/// The parent hides it entirely once every step is done.
class ActivationChecklist extends StatelessWidget {
  final List<ChecklistStep> steps;
  final VoidCallback onDismiss;

  const ActivationChecklist(
      {super.key, required this.steps, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final done = steps.where((s) => s.done).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 28),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.primary),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: const [
          BoxShadow(
              color: Color(0x142563EB),
              blurRadius: 24,
              offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.checklistCardTitle,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              PillBadge(
                  text: '$done/${steps.length}',
                  color: AppColors.primaryInk,
                  background: AppColors.primarySoft,
                  fontSize: 11),
              IconButton(
                onPressed: onDismiss,
                tooltip: l.dismissChecklist,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textSecondary),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 12),
            child: Text(l.checklistCardSubtitle,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
          for (final step in steps)
            Tappable(
              onTap: step.done ? null : step.onGo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: step.done
                            ? AppColors.success
                            : Colors.transparent,
                        border: step.done
                            ? null
                            : Border.all(
                                color: AppColors.inputBorder, width: 2),
                        shape: BoxShape.circle,
                      ),
                      child: step.done
                          ? const Icon(Icons.check_rounded,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(step.label,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: step.done
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            decoration: step.done
                                ? TextDecoration.lineThrough
                                : null,
                          )),
                    ),
                    if (!step.done)
                      const Icon(Icons.chevron_right_rounded,
                          size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
