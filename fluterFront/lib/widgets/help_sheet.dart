import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/tour_service.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// "How CareCoins works" — the always-available help surface from
/// docs/onboarding-help-plan.md (Phase 1). Bottom sheet on phones, centered
/// dialog on wide layouts. Copy mirrors the landing page's four steps so the
/// story users saw before signing up is the one the app tells inside.
Future<void> showHelpSheet(BuildContext context) {
  if (isWideLayout(context)) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: const _HelpContent(),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
        child: const _HelpContent(),
      ),
    ),
  );
}

// ── Widgets ──────────────────────────────────────────────────────────

class _HelpContent extends StatelessWidget {
  const _HelpContent();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final steps = [
      (l.landStep1Title, l.landStep1Body, AppColors.primaryInk, AppColors.primarySoft),
      (l.landStep2Title, l.landStep2Body, AppColors.successInk, AppColors.successSoft),
      (l.landStep3Title, l.landStep3Body, AppColors.warningInk, AppColors.warningSoft),
      (l.landStep4Title, l.landStep4Body, AppColors.dangerInk, AppColors.dangerSoft),
    ];
    final glossary = [
      (l.glossCoinTerm, l.glossCoinDef),
      (l.glossBudgetTerm, l.glossBudgetDef),
      (l.glossTemplateTerm, l.glossTemplateDef),
      (l.glossValidationTerm, l.glossValidationDef),
      (l.glossBountyTerm, l.glossBountyDef),
      (l.glossSelfTerm, l.glossSelfDef),
      (l.glossCoverageTerm, l.glossCoverageDef),
      (l.glossObjectTerm, l.glossObjectDef),
      (l.glossLedgerTerm, l.glossLedgerDef),
    ];
    final faq = [
      (l.faqCoinsQ, l.faqCoinsA),
      (l.faqApprovalQ, l.faqApprovalA),
      (l.faqCompletedQ, l.faqCompletedA),
      (l.faqRepeatQ, l.faqRepeatA),
      (l.faqBountyQ, l.faqBountyA),
      (l.faqRewardsQ, l.faqRewardsA),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(l.helpTitle,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: l.closeHelp,
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            children: [
              Text(l.helpIntro,
                style: const TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              for (final (i, step) in steps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: step.$4, shape: BoxShape.circle),
                        child: Text('${i + 1}',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: step.$3)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(step.$1,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 3),
                            Text(step.$2,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    height: 1.55,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              _HelpSectionTitle(l.helpGlossary),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    for (final (i, entry) in glossary.indexed) ...[
                      if (i > 0)
                        const Divider(color: AppColors.border, height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 118,
                              child: Text(entry.$1,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(entry.$2,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.5,
                                      color: AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              _HelpSectionTitle(l.helpCommonQuestions),
              for (final (q, a) in faq)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Theme(
                    // Strip the ExpansionTile's default divider lines.
                    data: Theme.of(context)
                        .copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      childrenPadding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      title: Text(q,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      iconColor: AppColors.textSecondary,
                      collapsedIconColor: AppColors.textSecondary,
                      expandedCrossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(a,
                            style: const TextStyle(
                                fontSize: 13,
                                height: 1.55,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              // Phase 2: forget the tab tours; screens listening to
              // TourService re-run their coach marks, starting with the
              // tab that's currently visible.
              VButton(
                type: VButtonType.outline,
                block: true,
                onPressed: () {
                  TourService.I.resetTabTours();
                  Navigator.pop(context);
                },
                child: Text(l.helpReplayTour),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HelpSectionTitle extends StatelessWidget {
  final String text;

  const _HelpSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 12),
      child: Text(text,
          style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3)),
    );
  }
}
