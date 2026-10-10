import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carecoins_flutter/widgets/ui.dart';

Widget _wrap(Widget child, {TextScaler? textScaler}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: textScaler != null ? mq.copyWith(textScaler: textScaler) : mq,
          child: Scaffold(
            body: SingleChildScrollView(child: child),
          ),
        );
      },
    ),
  );
}

void main() {
  group('P5-6: Card headers on phones', () {
    const titleText = 'Coins earned per month';
    const subtitleText = 'All time';

    testWidgets('Phone (390x844): chip is below subtitle, title is on one line',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // In Flutter test, the default Ahem font is monospace with 1:1 square glyphs
      // (24px wide per char), so 22 chars takes 528px. A text scale of 0.6 mimics
      // real Latin proportional font metrics (e.g. Roboto/Plus Jakarta Sans) where
      // the title fits in 342 px on one line, but wraps if the chip is beside it.
      await tester.pumpWidget(
        _wrap(
          VCard(
            title: titleText,
            subtitle: subtitleText,
            action: FilterChip(
              label: const Text('By caregiver'),
              selected: false,
              onSelected: (_) {},
            ),
            child: const SizedBox(height: 100),
          ),
          textScaler: const TextScaler.linear(0.6),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text(titleText);
      final subtitleFinder = find.text(subtitleText);
      final chipFinder = find.byType(FilterChip);

      // Title is one line (height < 40)
      final titleSize = tester.getSize(titleFinder);
      expect(titleSize.height, lessThan(40.0));

      // Chip's top edge is below the subtitle's bottom edge
      final subtitleBottom = tester.getBottomLeft(subtitleFinder).dy;
      final chipTop = tester.getTopLeft(chipFinder).dy;
      expect(chipTop, greaterThanOrEqualTo(subtitleBottom));
    });

    testWidgets('Wide (1280x800): chip centre dy is within title vertical bounds',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrap(
          VCard(
            title: titleText,
            subtitle: subtitleText,
            action: FilterChip(
              label: const Text('By caregiver'),
              selected: false,
              onSelected: (_) {},
            ),
            child: const SizedBox(height: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleFinder = find.text(titleText);
      final chipFinder = find.byType(FilterChip);

      final titleTop = tester.getTopLeft(titleFinder).dy;
      final titleBottom = tester.getBottomLeft(titleFinder).dy;
      final chipCenterY = tester.getCenter(chipFinder).dy;

      // Chip's centre dy is within the title's vertical bounds (same row)
      expect(chipCenterY, greaterThanOrEqualTo(titleTop));
      expect(chipCenterY, lessThanOrEqualTo(titleBottom));
    });

    testWidgets('No action: layout unchanged, no Align added by VCard',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrap(
          const VCard(
            title: titleText,
            subtitle: subtitleText,
            child: SizedBox(key: Key('content_box'), height: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No Align widget inside VCard
      expect(
        find.descendant(of: find.byType(VCard), matching: find.byType(Align)),
        findsNothing,
      );

      // Title and subtitle are present
      expect(find.text(titleText), findsOneWidget);
      expect(find.text(subtitleText), findsOneWidget);
    });

    testWidgets('Card with action and no title: action row goes first with top padding 24',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        _wrap(
          VCard(
            action: FilterChip(
              label: const Text('By caregiver'),
              selected: false,
              onSelected: (_) {},
            ),
            child: const SizedBox(height: 100),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final chipFinder = find.byType(FilterChip);
      expect(chipFinder, findsOneWidget);

      final cardTop = tester.getTopLeft(find.byType(Card)).dy;
      final chipTop = tester.getTopLeft(chipFinder).dy;
      // Top padding 24 from card top
      expect(chipTop - cardTop, greaterThanOrEqualTo(24.0));
    });
  });
}
