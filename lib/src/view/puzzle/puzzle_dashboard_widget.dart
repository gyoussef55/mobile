import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/common/errors.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_providers.dart';
import 'package:lichess_mobile/src/model/puzzle/puzzle_theme.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/string.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/shimmer.dart';
import 'package:lichess_mobile/src/widgets/stat_card.dart';

class PuzzleDashboardWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puzzleDashboard = ref.watch(puzzleDashboardProvider);

    return puzzleDashboard.when(
      data: (data) {
        final chartData =
            data.themes.take(9).sortedBy((e) => e.theme.name).toList();
        return ListSection(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.puzzlePuzzleDashboard),
              Text(
                context.l10n.nbDays(30),
                style: TextStyle(
                  fontSize: 14,
                  color: textShade(context, Styles.subtitleOpacity),
                ),
              ),
            ],
          ),
          // hack to make the divider take full length or row
          cupertinoAdditionalDividerMargin: -14,
          children: [
            StatCardRow([
              StatCard(
                context.l10n.performance,
                value: data.global.performance.toString(),
              ),
              StatCard(
                context.l10n
                    .puzzleNbPlayed(data.global.nb)
                    .replaceAll(RegExp(r'\d+'), '')
                    .trim()
                    .capitalize(),
                value: data.global.nb.toString().localizeNumbers(),
              ),
              StatCard(
                context.l10n.puzzleSolved.capitalize(),
                value:
                    '${((data.global.firstWins / data.global.nb) * 100).round()}%',
              ),
            ]),
            if (chartData.length >= 3)
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: AspectRatio(
                  aspectRatio: 1.2,
                  child: PuzzleChart(chartData),
                ),
              ),
          ],
        );
      },
      error: (e, s) {
        debugPrint(
          'SEVERE: [PuzzleDashboardWidget] could not load puzzle dashboard; $e\n$s',
        );
        return Padding(
          padding: Styles.bodySectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.puzzlePuzzleDashboard,
                style: Styles.sectionTitle,
              ),
              if (e is NotFoundException)
                Text(context.l10n.puzzleNoPuzzlesToShow)
              else
                const Text('Could not load dashboard.'),
            ],
          ),
        );
      },
      loading: () {
        final loaderHeight = MediaQuery.sizeOf(context).width;
        return Shimmer(
          child: ShimmerLoading(
            isLoading: true,
            child: Padding(
              padding: Styles.bodySectionBottomPadding,
              child: Column(
                children: [
                  // ignore: avoid-wrapping-in-padding
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Container(
                      width: double.infinity,
                      height: 25,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                    ),
                  ),
                  // ignore: avoid-wrapping-in-padding
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0),
                    child: Container(
                      width: double.infinity,
                      height: loaderHeight,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PuzzleChart extends StatelessWidget {
  const PuzzleChart(this.puzzleData);

  final List<PuzzleDashboardData> puzzleData;

  @override
  Widget build(BuildContext context) {
    final radarColor =
        Theme.of(context).colorScheme.onBackground.withOpacity(0.5);
    final chartColor = Theme.of(context).colorScheme.tertiary;
    return RadarChart(
      RadarChartData(
        radarBorderData: BorderSide(width: 0.5, color: radarColor),
        gridBorderData: BorderSide(width: 0.5, color: radarColor),
        tickBorderData: BorderSide(width: 0.5, color: radarColor),
        radarShape: RadarShape.polygon,
        dataSets: [
          RadarDataSet(
            fillColor: Theme.of(context).platform == TargetPlatform.iOS
                ? null
                : chartColor.withOpacity(0.2),
            borderColor: Theme.of(context).platform == TargetPlatform.iOS
                ? null
                : chartColor,
            dataEntries: puzzleData
                .map((theme) => RadarEntry(value: theme.performance.toDouble()))
                .toList(),
          ),
        ],
        getTitle: (index, angle) => RadarChartTitle(
          text: puzzleThemeL10n(context, puzzleData[index].theme).name,
        ),
        titleTextStyle: const TextStyle(fontSize: 10),
        titlePositionPercentageOffset: 0.09,
        tickCount: 3,
        ticksTextStyle: const TextStyle(fontSize: 8),
      ),
    );
  }
}
