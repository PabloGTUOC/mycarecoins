import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Landing page: dark hero with the phone mockup and family
/// figures, "How it works" steps, the tabbed "See it in action" demo, the
/// fairness section with a sample ledger card, closing CTA and footer.
/// All CTAs lead to the login screen.
class LandingScreen extends StatelessWidget {
  final VoidCallback onSignIn;

  const LandingScreen({super.key, required this.onSignIn});

  List<(String, String, Color, Color)> _steps(AppLocalizations l) => [
        (
          l.landStep1Title,
          l.landStep1Body,
          AppColors.primaryInk,
          AppColors.primarySoft,
        ),
        (
          l.landStep2Title,
          l.landStep2Body,
          AppColors.successInk,
          AppColors.successSoft,
        ),
        (
          l.landStep3Title,
          l.landStep3Body,
          AppColors.warningInk,
          AppColors.warningSoft,
        ),
        (
          l.landStep4Title,
          l.landStep4Body,
          AppColors.dangerInk,
          AppColors.dangerSoft,
        ),
      ];

  List<(String, String, String, String, Color)> _ledgerRows(
          AppLocalizations l) =>
      [
        (l.dayToday, l.landSimMama, l.landSimLedgerRedeemedCoffee, '-30 cc',
            AppColors.danger),
        (l.dayToday, l.landSimPapa, l.landSimLedgerCompletedFeedPet, '+10 cc',
            AppColors.success),
        (l.landSimYesterday, l.landSimMama, l.landSimLedgerCompletedCleanRoom,
            '+20 cc', AppColors.success),
        (l.landSimYesterday, l.landSimSystem, l.landSimLedgerBudget, '+500 cc',
            AppColors.success),
      ];

  @override
  Widget build(BuildContext context) {
    final wide = isWideLayout(context);
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(context, wide),

            // ── How it works ──
            _Section(
              background: AppColors.surface,
              child: Column(
                children: [
                  _Reveal(
                      child: _SectionHead(l.landHowTitle, l.landHowSub)),
                  _StepsGrid(steps: _steps(l)),
                ],
              ),
            ),

            // ── See it in action ──
            _Section(
              background: AppColors.bg,
              child: Column(
                children: [
                  _Reveal(
                      child: _SectionHead(l.landSeeTitle, l.landSeeSub)),
                  const _Reveal(delayMs: 90, child: _DemoSection()),
                ],
              ),
            ),

            // ── Fairness, not guesswork ──
            _Section(
              background: AppColors.surface,
              child: LayoutBuilder(builder: (context, c) {
                final isWide = c.maxWidth > kMobileBreakpoint;
                final text = _Reveal(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.landFairTitle,
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                      const SizedBox(height: 14),
                      Text(l.landFairBody,
                          style: const TextStyle(
                              fontSize: 15,
                              height: 1.65,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 28),
                      for (final (icon, title, body) in [
                        (
                          Icons.trending_up_rounded,
                          l.landFair1Title,
                          l.landFair1Body
                        ),
                        (
                          Icons.verified_user_rounded,
                          l.landFair2Title,
                          l.landFair2Body
                        ),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(icon, size: 20, color: AppColors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(title,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14.5)),
                                    const SizedBox(height: 4),
                                    Text(body,
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
                    ],
                  ),
                );
                final ledger = _Reveal(
                    delayMs: 120, child: _LedgerCard(rows: _ledgerRows(l)));
                return isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: text),
                          const SizedBox(width: 48),
                          Expanded(child: ledger),
                        ],
                      )
                    : Column(
                        children: [text, const SizedBox(height: 32), ledger]);
              }),
            ),

            // ── CTA ──
            Container(
              color: AppColors.ink,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
              child: _Reveal(
                child: Column(
                  children: [
                    Text(l.landCtaTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: Colors.white)),
                    const SizedBox(height: 12),
                    Text(l.landCtaSub,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, color: Color(0xBFFFFFFF))),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: onSignIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.ink,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill)),
                      ),
                      child: Text(l.landCreateFamily,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            ),

            // ── Footer ──
            Container(
              color: AppColors.surface,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Row(
                    children: [
                      const Text('CareCoins',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l.landCopyright,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textSecondary)),
                      ),
                      TextButton(
                          onPressed: onSignIn, child: Text(l.landLogIn)),
                      TextButton(
                          onPressed: onSignIn, child: Text(l.landRegister)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context, bool wide) {
    final l = AppLocalizations.of(context);
    final heroText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Entrance(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x24FFFFFF)),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(l.landForFamilies,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xBFFFFFFF))),
          ),
        ),
        const SizedBox(height: 24),
        _Entrance(
          delayMs: 80,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${l.landHeroLine1}\n'),
              TextSpan(
                  text: l.landHeroLine2,
                  style: const TextStyle(color: Color(0xFF93C5FD))),
            ]),
            style: TextStyle(
                fontSize: wide ? 56 : 34,
                fontWeight: FontWeight.w800,
                height: 1.08,
                letterSpacing: -1.5,
                color: Colors.white),
          ),
        ),
        const SizedBox(height: 24),
        _Entrance(
          delayMs: 160,
          child: SizedBox(
            width: 560,
            child: Text(
              l.landHeroSubtitle,
              style: const TextStyle(
                  fontSize: 16, height: 1.65, color: Color(0xBFFFFFFF)),
            ),
          ),
        ),
        const SizedBox(height: 36),
        _Entrance(
          delayMs: 240,
          child: Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: onSignIn,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 26, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
                child: Text(l.landGetStarted,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              OutlinedButton(
                onPressed: onSignIn,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x38FFFFFF)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 26, vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill)),
                ),
                child: Text(l.signInPlain,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
        ),
      ],
    );

    // The illustration column: phone mockup with the family figures below,
    // mirroring .hero-visual. Decorative, so hidden from screen readers.
    final heroVisual = _Entrance(
      delayMs: 320,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _PhoneMockup(),
            SizedBox(height: 20),
            _FamilyFigures(),
          ],
        ),
      ),
    );

    return Container(
      color: AppColors.ink,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: wide ? 72 : 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // The CareCoins coin mark (same asset as the launcher/PWA
                  // icons); its rounded corners are baked into the image.
                  Image.asset('assets/icon/icon-512.png',
                      width: 30,
                      height: 30,
                      cacheWidth:
                          (30 * MediaQuery.devicePixelRatioOf(context))
                              .round()),
                  const SizedBox(width: 8),
                  const Text('CareCoins',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Colors.white)),
                  const Spacer(),
                  TextButton(
                    onPressed: onSignIn,
                    child: Text(l.signInPlain,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              SizedBox(height: wide ? 72 : 48),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: heroText),
                    const SizedBox(width: 64),
                    heroVisual,
                  ],
                )
              else ...[
                heroText,
                const SizedBox(height: 48),
                Center(child: heroVisual),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Motion ───────────────────────────────────────────────────────────

/// One-time page-load entrance (fade + rise) used by the hero. Skipped
/// entirely when the platform asks for reduced motion.
class _Entrance extends StatefulWidget {
  final Widget child;
  final int delayMs;

  const _Entrance({required this.child, this.delayMs = 0});

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> {
  bool _shown = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (MediaQuery.of(context).disableAnimations) {
      _shown = true;
      return;
    }
    Future.delayed(Duration(milliseconds: 60 + widget.delayMs), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutQuart,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutQuart,
        child: widget.child,
      ),
    );
  }
}

/// Scroll-triggered reveal: content is fully laid out from the start (no
/// blank sections if the listener never fires) and fades in the first
/// time it enters the viewport. Reduced motion renders instantly.
class _Reveal extends StatefulWidget {
  final Widget child;
  final int delayMs;

  const _Reveal({required this.child, this.delayMs = 0});

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> {
  bool _shown = false;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shown = true;
      return;
    }
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _position)) {
      _position?.removeListener(_check);
      _position = pos?..addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted || _shown) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * 0.93) {
      _position?.removeListener(_check);
      if (widget.delayMs == 0) {
        setState(() => _shown = true);
      } else {
        Future.delayed(Duration(milliseconds: widget.delayMs), () {
          if (mounted) setState(() => _shown = true);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeOutQuart,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.05),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutQuart,
        child: widget.child,
      ),
    );
  }
}

// ── Hero visual ──────────────────────────────────────────────────────

/// The phone frame from .phone-frame: a miniature of the Daily view with
/// timeline cards, the NOW divider, a free-time gap and the bottom tabs.
/// Purely illustrative; the tiny type keeps it at a phone's scale.
// Note: Type inside _PhoneMockup is illustrative and intentionally below the 12 pt floor.
class _PhoneMockup extends StatelessWidget {
  const _PhoneMockup();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: 210,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: const Color(0x0FFFFFFF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x8C000000), blurRadius: 80, offset: Offset(0, 40)),
          BoxShadow(
              color: Color(0x4D000000), blurRadius: 32, offset: Offset(0, 16)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Notch
          Container(
            width: 48,
            height: 5,
            margin: const EdgeInsets.only(top: 4, bottom: 8),
            decoration: BoxDecoration(
                color: const Color(0xFF1E2D40),
                borderRadius: BorderRadius.circular(AppRadii.pill)),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Container(
              height: 372,
              color: AppColors.bg,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(14, 8, 14, 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('9:41',
                            style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                        Text('●●●',
                            style: TextStyle(
                                fontSize: 8.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: AppColors.border))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l.landSimDate,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.warningSoft,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill)),
                          child: const Text('🪙 460cc',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.warningInk)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 7, 14, 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                            child: const LinearProgressIndicator(
                              value: 0.4,
                              minHeight: 4,
                              backgroundColor: AppColors.border,
                              valueColor:
                                  AlwaysStoppedAnimation(AppColors.success),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(l.landSimTasksDone('2/5'),
                            style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        _PsRow('8:00', l.landSimTaskSchoolRun,
                            '30m · 🪙 15cc ✓', AppColors.primary),
                        const _PsNow(),
                        _PsRow('14:00', l.landSimTaskWalkDog, '30m · 🪙 10cc',
                            AppColors.success),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(l.landSimHourFree,
                              style: const TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary)),
                        ),
                        _PsRow('18:00', l.landSimTaskDinnerPrep, '45m · 🪙 20cc',
                            AppColors.warning),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
                    decoration: const BoxDecoration(
                      color: Color(0xEBFFFFFF),
                      border:
                          Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _PsNavItem('📅', l.dayToday, active: true),
                        _PsNavItem('🏠', l.landSimNavHub),
                        _PsNavItem('🏆', l.tabRewards),
                        _PsNavItem('📊', l.tabStats),
                        _PsNavItem('👤', l.tabMe),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PsRow extends StatelessWidget {
  final String time;
  final String title;
  final String meta;
  final Color color;

  const _PsRow(this.time, this.title, this.meta, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 10, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(time,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 7.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 1),
                  Text(meta,
                      style: const TextStyle(
                          fontSize: 8, color: Color(0xD1FFFFFF))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PsNow extends StatelessWidget {
  const _PsNow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 1, 10, 1),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.danger, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(AppLocalizations.of(context).landSimNow,
                style: const TextStyle(
                    fontSize: 6.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger)),
          ),
          const Expanded(child: Divider(color: AppColors.danger, height: 1)),
        ],
      ),
    );
  }
}

class _PsNavItem extends StatelessWidget {
  final String emoji;
  final String label;
  final bool active;

  const _PsNavItem(this.emoji, this.label, {this.active = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
            opacity: active ? 1 : 0.35,
            child: Text(emoji, style: const TextStyle(fontSize: 13))),
        Text(label,
            style: TextStyle(
                fontSize: 6.5,
                fontWeight: FontWeight.w700,
                color:
                    active ? AppColors.primary : AppColors.textSecondary)),
      ],
    );
  }
}

/// The four family figures, drawn on a 200×72 coordinate space with the
/// semantic accent palette.
class _FamilyFigures extends StatelessWidget {
  const _FamilyFigures();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(
        size: Size(150, 54), painter: _FamilyFiguresPainter());
  }
}

class _FamilyFiguresPainter extends CustomPainter {
  const _FamilyFiguresPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200; // scale from the 200×72 viewBox
    void figure(Color color, double cx, double cy, double r, Rect body,
        double rx) {
      final paint = Paint()..color = color;
      canvas.drawCircle(Offset(cx * s, cy * s), r * s, paint);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(body.left * s, body.top * s, body.width * s,
                  body.height * s),
              Radius.circular(rx * s)),
          paint);
    }

    figure(AppColors.primary, 34, 16, 12, const Rect.fromLTWH(22, 31, 24, 30), 7);
    figure(AppColors.success, 74, 19, 11, const Rect.fromLTWH(63, 33, 22, 27), 7);
    figure(AppColors.warning, 110, 26, 9, const Rect.fromLTWH(101, 38, 18, 22), 6);
    figure(AppColors.danger, 143, 31, 7, const Rect.fromLTWH(136, 41, 14, 17), 5);

    canvas.drawLine(
        Offset(12 * s, 62 * s),
        Offset(170 * s, 62 * s),
        Paint()
          ..color = const Color(0x2EFFFFFF)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _FamilyFiguresPainter oldDelegate) => false;
}

// ── How it works ─────────────────────────────────────────────────────

/// The steps grid with the connecting hairline behind the number circles
/// on wide layouts; stacked on phones.
class _StepsGrid extends StatelessWidget {
  final List<(String, String, Color, Color)> steps;

  const _StepsGrid({required this.steps});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final fourAcross = c.maxWidth > kMobileBreakpoint;
      Widget step(int i) {
        final data = steps[i];
        return _Reveal(
          delayMs: i * 90,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(color: data.$4, shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: data.$3)),
              ),
              const SizedBox(height: 14),
              Text(data.$1,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(data.$2,
                  style: const TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary)),
            ],
          ),
        );
      }

      if (!fourAcross) {
        return Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                  padding: const EdgeInsets.only(bottom: 28), child: step(i)),
          ],
        );
      }
      return Stack(
        children: [
          Positioned(
            top: 20,
            left: 56,
            right: 56,
            child: Container(height: 1, color: AppColors.border),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 32),
                Expanded(child: step(i)),
              ],
            ],
          ),
        ],
      );
    });
  }
}

// ── See it in action ─────────────────────────────────────────────────

class _DemoSection extends StatefulWidget {
  const _DemoSection();

  @override
  State<_DemoSection> createState() => _DemoSectionState();
}

class _DemoSectionState extends State<_DemoSection> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _demoTab(0, Icons.verified_user_rounded, l.landDemoTabDashboard),
                const SizedBox(width: 6),
                _demoTab(1, Icons.shopping_bag_rounded, l.landDemoTabRewards),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 380),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x0D0E1726),
                    blurRadius: 24,
                    offset: Offset(0, 4)),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeOutQuart,
              child: _tab == 0
                  ? const _DashboardSim(key: ValueKey('dash'))
                  : const _MarketplaceSim(key: ValueKey('market')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _demoTab(int i, IconData icon, String label) {
    final on = _tab == i;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        hoverColor: on ? Colors.transparent : AppColors.primarySoft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: on ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: on ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? Colors.white : AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Family Hub" demo tab: member cards, KPI minis and the activity feed,
/// built from the app's own component vocabulary.
class _DashboardSim extends StatelessWidget {
  const _DashboardSim({super.key});

  List<(String, String, String, Color, Color)> _members(AppLocalizations l) => [
        ('👩🏽', l.landSimMama, '120', AppColors.primaryInk, AppColors.primarySoft),
        ('👨🏽', l.landSimPapa, '340', AppColors.successInk, AppColors.successSoft),
        ('👶🏽', 'Leo', '80', AppColors.warningInk, AppColors.warningSoft),
        ('👧🏽', 'Sofia', '160', AppColors.dangerInk, AppColors.dangerSoft),
      ];

  List<(String, Color, Color, String, String, String, String, Color)> _feed(
          AppLocalizations l) =>
      [
        ('✓', AppColors.primaryInk, AppColors.primarySoft,
            l.landSimFeedCompleted(l.landSimMama),
            l.landSimSubjectCleanRoom, l.landSimTime2Min, '+20 cc',
            AppColors.success),
        ('✓', AppColors.primaryInk, AppColors.primarySoft,
            l.landSimFeedCompleted(l.landSimPapa),
            l.landSimSubjectFeedPet, l.landSimTime1Hour, '+10 cc',
            AppColors.success),
        ('🛍️', AppColors.dangerInk, AppColors.dangerSoft,
            l.landSimFeedRedeemed(l.landSimMama),
            l.landSimSubjectCoffee, l.landSimTime3Hours, '-30 cc',
            AppColors.danger),
      ];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.landSimActiveMembers,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (emoji, name, coins, accent, soft) in _members(l))
              Container(
                width: 96,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(
                  color: soft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Column(
                  children: [
                    Text(emoji, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(name,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    Text('● $coins cc',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: accent)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SimKpi(l.landSimKpiBalance, '460', 'cc', l.landSimKpiBalanceSub,
                AppColors.primary, null),
            _SimKpi(l.landSimKpiTasks, '2/5', null, l.landSimKpiTasksSub,
                AppColors.success, 0.4),
            _SimKpi(l.landSimKpiBounties, '1', null, l.landSimKpiBountiesSub,
                AppColors.warning, null),
            _SimKpi(l.landSimKpiActivity, '3', null, l.landSimKpiActivitySub,
                AppColors.textPrimary, null),
          ],
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.landSimRecentActivity,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        for (final (icon, fg, bg, verb, subject, time, amt, amtColor)
            in _feed(l))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Text(icon,
                      style: TextStyle(fontSize: 12, color: fg)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: verb),
                          TextSpan(
                              text: subject,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800)),
                        ]),
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                      Row(
                        children: [
                          Text(time,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          const Spacer(),
                          Text(amt,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: amtColor)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final isWide = c.maxWidth > 640;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.landSimFamilyHub,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(l.landSimGreeting(l.landSimMama),
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: right),
              ],
            )
          else ...[
            left,
            const SizedBox(height: 20),
            right,
          ],
        ],
      );
    });
  }
}

class _SimKpi extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String subtitle;
  final Color accent;
  final double? progress;

  const _SimKpi(this.label, this.value, this.unit, this.subtitle, this.accent,
      this.progress);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: accent)),
              if (unit != null) ...[
                const SizedBox(width: 4),
                Text(unit!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.success),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Activities & Rewards" demo tab: task templates and the rewards store.
class _MarketplaceSim extends StatelessWidget {
  const _MarketplaceSim({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final templates = _simCard(l, l.landSimTaskTemplates, [
      ('📚', AppColors.primary, l.landSimTemplHomework,
          l.landSimTemplHomeworkSub, '+15 cc'),
      ('🌱', AppColors.success, l.landSimTemplWalkDog, l.landSimTemplWalkDogSub,
          '+10 cc'),
    ]);
    final rewards = _simCard(l, l.landSimRewardsStore, [
      ('🎮', AppColors.warning, l.landSimRewardGames, l.landSimRewardGamesSub,
          l.landSimRedeem),
      ('🍦', AppColors.danger, l.landSimRewardIceCream,
          l.landSimRewardIceCreamSub, l.landSimRedeem),
    ]);

    return LayoutBuilder(builder: (context, c) {
      final isWide = c.maxWidth > 640;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.landDemoRewardsTitle,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🪙 ', style: TextStyle(fontSize: 12)),
                    const Text('460',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    Text('  ${l.landSimFamilyPool}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isWide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: templates),
                const SizedBox(width: 16),
                Expanded(child: rewards),
              ],
            )
          else ...[
            templates,
            const SizedBox(height: 16),
            rewards,
          ],
        ],
      );
    });
  }

  Widget _simCard(AppLocalizations l, String title,
      List<(String, Color, String, String, String)> items) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (emoji, color, name, sub, badge) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(AppRadii.sm)),
                    child:
                        Text(emoji, style: const TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700)),
                        Text(sub,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  badge == l.landSimRedeem
                      ? PillBadge(
                          text: badge,
                          fontSize: 12,
                          color: Colors.white,
                          background: AppColors.primary)
                      : PillBadge(
                          text: badge,
                          fontSize: 12,
                          color: AppColors.successInk,
                          background: AppColors.successSoft),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared section chrome ────────────────────────────────────────────

class _Section extends StatelessWidget {
  final Color background;
  final Widget child;

  const _Section({required this.background, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
      child: Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080), child: child),
      ),
    );
  }
}

class _SectionHead extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHead(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 44),
      child: Column(
        children: [
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 16, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// The "Recent transactions" sample card from the fairness section.
class _LedgerCard extends StatelessWidget {
  final List<(String, String, String, String, Color)> rows;

  const _LedgerCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 30, offset: Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.landSimRecentTransactions,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
              PillBadge(
                  text: l.landSimVerified,
                  color: AppColors.successInk,
                  background: AppColors.successSoft,
                  fontSize: 12),
            ],
          ),
          const SizedBox(height: 14),
          for (final (date, name, desc, amount, color) in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: Text(date,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800)),
                        Text(desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(amount,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: color)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
