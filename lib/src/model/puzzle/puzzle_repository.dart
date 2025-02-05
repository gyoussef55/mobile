import 'dart:convert';

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/auth/auth_client.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/perf.dart';
import 'package:lichess_mobile/src/utils/json.dart';
import 'package:logging/logging.dart';
import 'package:result_extensions/result_extensions.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'puzzle.dart';
import 'puzzle_angle.dart';
import 'puzzle_difficulty.dart';
import 'puzzle_opening.dart';
import 'puzzle_streak.dart';
import 'puzzle_theme.dart';
import 'storm.dart';

part 'puzzle_repository.freezed.dart';
part 'puzzle_repository.g.dart';

@Riverpod(keepAlive: true)
PuzzleRepository puzzleRepository(PuzzleRepositoryRef ref) {
  final apiClient = ref.watch(authClientProvider);
  return PuzzleRepository(Logger('PuzzleRepository'), apiClient: apiClient);
}

/// Repository that interacts with lichess.org puzzle API
class PuzzleRepository {
  const PuzzleRepository(
    Logger log, {
    required this.apiClient,
  }) : _log = log;

  final AuthClient apiClient;
  final Logger _log;

  FutureResult<PuzzleBatchResponse> selectBatch({
    required int nb,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
    PuzzleDifficulty difficulty = PuzzleDifficulty.normal,
  }) {
    return apiClient
        .get(
          Uri.parse(
            '$kLichessHost/api/puzzle/batch/${angle.key}?nb=$nb&difficulty=${difficulty.name}',
          ),
          retryOnError: false,
        )
        .flatMap(_decodeBatchResponse);
  }

  FutureResult<PuzzleBatchResponse> solveBatch({
    required int nb,
    required IList<PuzzleSolution> solved,
    PuzzleAngle angle = const PuzzleTheme(PuzzleThemeKey.mix),
    PuzzleDifficulty difficulty = PuzzleDifficulty.normal,
  }) {
    return apiClient
        .post(
          Uri.parse(
            '$kLichessHost/api/puzzle/batch/${angle.key}?nb=$nb&difficulty=${difficulty.name}',
          ),
          headers: {'Content-type': 'application/json'},
          body: jsonEncode({
            'solutions': solved
                .map(
                  (e) => {
                    'id': e.id.value,
                    'win': e.win,
                    'rated': e.rated,
                  },
                )
                .toList(),
          }),
          retryOnError: false,
        )
        .flatMap(_decodeBatchResponse);
  }

  FutureResult<Puzzle> fetch(PuzzleId id) {
    return apiClient.get(Uri.parse('$kLichessHost/api/puzzle/$id')).flatMap(
          (response) => readJsonObjectFromResponse(
            response,
            mapper: _puzzleFromJson,
            logger: _log,
          ),
        );
  }

  FutureResult<PuzzleStreakResponse> streak() {
    return apiClient
        .get(Uri.parse('$kLichessHost/api/streak'))
        .flatMap((response) {
      return readJsonObjectFromResponse(
        response,
        mapper: (Map<String, dynamic> json) {
          return PuzzleStreakResponse(
            puzzle: _puzzleFromPick(pick(json).required()),
            streak: IList(
              pick(json['streak']).asStringOrThrow().split(' ').map(
                    (e) => PuzzleId(e),
                  ),
            ),
          );
        },
        logger: _log,
      );
    });
  }

  FutureResult<void> postStreakRun(int run) {
    return apiClient.post(
      Uri.parse('$kLichessHost/api/streak/$run'),
    );
  }

  FutureResult<PuzzleStormResponse> storm() {
    return apiClient.get(Uri.parse('$kLichessHost/api/storm')).flatMap(
      (response) {
        return readJsonObjectFromResponse(
          response,
          mapper: (Map<String, dynamic> json) {
            return PuzzleStormResponse(
              puzzles: IList(
                pick(json['puzzles']).asListOrThrow(_litePuzzleFromPick),
              ),
              highscore: pick(json['high']).letOrNull(_stormHighScoreFromPick),
              key: pick(json['key']).asStringOrNull(),
            );
          },
        );
      },
    );
  }

  FutureResult<StormNewHigh?> postStormRun(StormRunStats stats) {
    final Map<String, String> body = {
      'puzzles': stats.history.length.toString(),
      'score': stats.score.toString(),
      'moves': stats.moves.toString(),
      'errors': stats.errors.toString(),
      'combo': stats.comboBest.toString(),
      'time': stats.time.inSeconds.toString(),
      'highest': stats.highest.toString(),
      'notAnExploit':
          "Yes, we know that you can send whatever score you like. That's why there's no leaderboards and no competition.",
    };

    return apiClient
        .post(
      Uri.parse('$kLichessHost/storm'),
      body: body,
    )
        .flatMap((response) {
      return readJsonObjectFromResponse(
        response,
        mapper: (Map<String, dynamic> json) {
          return pick(json['newHigh']).letOrNull(
            (p) => StormNewHigh(
              key: p('key').asStormNewHighTypeOrThrow(),
              prev: p('prev').asIntOrThrow(),
            ),
          );
        },
      );
    });
  }

  FutureResult<Puzzle> daily() {
    return apiClient.get(Uri.parse('$kLichessHost/api/puzzle/daily')).flatMap(
          (response) => readJsonObjectFromResponse(
            response,
            mapper: _puzzleFromJson,
            logger: _log,
          ).map(
            (puzzle) => puzzle.copyWith(
              isDailyPuzzle: true,
            ),
          ),
        );
  }

  FutureResult<PuzzleDashboard> puzzleDashboard() {
    return apiClient
        .get(Uri.parse('$kLichessHost/api/puzzle/dashboard/30'))
        .flatMap((response) {
      return readJsonObjectFromResponse(
        response,
        mapper: _puzzleDashboardFromJson,
        logger: _log,
      );
    });
  }

  FutureResult<IList<PuzzleHistoryEntry>> puzzleActivity(
    int max, {
    DateTime? before,
  }) {
    final beforeQuery =
        before != null ? '&before=${before.millisecondsSinceEpoch}' : '';
    return apiClient
        .get(
          Uri.parse('$kLichessHost/api/puzzle/activity?max=$max$beforeQuery'),
        )
        .flatMap(
          (response) => readNdJsonListFromResponse(
            response,
            mapper: _puzzleActivityFromJson,
            logger: _log,
          ),
        );
  }

  FutureResult<StormDashboard> stormDashboard(UserId userId) {
    return apiClient
        .get(Uri.parse('$kLichessHost/api/storm/dashboard/${userId.value}'))
        .flatMap(
          (response) => readJsonObjectFromResponse(
            response,
            mapper: _stormDashboardFromJson,
            logger: _log,
          ),
        );
  }

  FutureResult<IMap<PuzzleThemeKey, PuzzleThemeData>> puzzleThemes() {
    return apiClient.get(
      Uri.parse('$kLichessHost/training/themes'),
      headers: {'Accept': 'application/json'},
    ).flatMap(
      (response) => readJsonObjectFromResponse(
        response,
        mapper: _puzzleThemeFromJson,
        logger: _log,
      ),
    );
  }

  FutureResult<IList<PuzzleOpeningFamily>> puzzleOpenings() {
    return apiClient.get(
      Uri.parse('$kLichessHost/training/openings'),
      headers: {'Accept': 'application/json'},
    ).flatMap(
      (response) => readJsonObjectFromResponse(
        response,
        mapper: _puzzleOpeningFromJson,
        logger: _log,
      ),
    );
  }

  Result<PuzzleBatchResponse> _decodeBatchResponse(http.Response response) {
    return readJsonObjectFromResponse(
      response,
      mapper: (Map<String, dynamic> json) {
        final puzzles = json['puzzles'];
        if (puzzles is! List<dynamic>) {
          throw const FormatException('puzzles: expected a list');
        }
        return PuzzleBatchResponse(
          puzzles: IList(
            puzzles.map((e) {
              if (e is! Map<String, dynamic>) {
                throw const FormatException('Expected an object');
              }
              return _puzzleFromJson(e);
            }),
          ),
          glicko: pick(json['glicko']).letOrNull(_puzzleGlickoFromPick),
          rounds: pick(json['rounds']).letOrNull(
            (p0) => IList(
              p0.asListOrNull(
                (p1) => _puzzleRoundFromPick(p1),
              ),
            ),
          ),
        );
      },
      logger: _log,
    );
  }
}

@freezed
class PuzzleBatchResponse with _$PuzzleBatchResponse {
  const factory PuzzleBatchResponse({
    required IList<Puzzle> puzzles,
    PuzzleGlicko? glicko,
    IList<PuzzleRound>? rounds,
  }) = _PuzzleBatchResponse;
}

@freezed
class PuzzleStreakResponse with _$PuzzleStreakResponse {
  const factory PuzzleStreakResponse({
    required Puzzle puzzle,
    required Streak streak,
  }) = _PuzzleStreakResponse;
}

@freezed
class PuzzleStormResponse with _$PuzzleStormResponse {
  const factory PuzzleStormResponse({
    required IList<LitePuzzle> puzzles,
    required String? key,
    required PuzzleStormHighScore? highscore,
  }) = _PuzzleStormResponse;
}

// --

PuzzleHistoryEntry _puzzleActivityFromJson(Map<String, dynamic> json) =>
    _historyPuzzleFromPick(pick(json).required());

Puzzle _puzzleFromJson(Map<String, dynamic> json) =>
    _puzzleFromPick(pick(json).required());

PuzzleDashboard _puzzleDashboardFromJson(Map<String, dynamic> json) =>
    _puzzleDashboardFromPick(pick(json).required());

IMap<PuzzleThemeKey, PuzzleThemeData> _puzzleThemeFromJson(
  Map<String, dynamic> json,
) =>
    _puzzleThemeFromPick(pick(json).required());

IList<PuzzleOpeningFamily> _puzzleOpeningFromJson(Map<String, dynamic> json) =>
    _puzzleOpeningFromPick(pick(json).required());

Puzzle _puzzleFromPick(RequiredPick pick) {
  return Puzzle(
    puzzle: pick('puzzle').letOrThrow(_puzzleDatafromPick),
    game: pick('game').letOrThrow(_puzzleGameFromPick),
  );
}

StormDashboard _stormDashboardFromJson(Map<String, dynamic> json) =>
    _stormDashboardFromPick(pick(json).required());

StormDashboard _stormDashboardFromPick(RequiredPick pick) {
  final dateFormat = DateFormat('yyyy/M/d');
  return StormDashboard(
    highScore: PuzzleStormHighScore(
      day: pick('high', 'day').asIntOrThrow(),
      allTime: pick('high', 'allTime').asIntOrThrow(),
      month: pick('high', 'month').asIntOrThrow(),
      week: pick('high', 'week').asIntOrThrow(),
    ),
    dayHighscores: pick('days')
        .asListOrThrow((p0) => _stormDayFromPick(p0, dateFormat))
        .toIList(),
  );
}

StormDayScore _stormDayFromPick(RequiredPick pick, DateFormat format) =>
    StormDayScore(
      runs: pick('runs').asIntOrThrow(),
      score: pick('score').asIntOrThrow(),
      time: pick('time').asIntOrThrow(),
      highest: pick('highest').asIntOrThrow(),
      day: format.parse(pick('_id').asStringOrThrow()),
    );

LitePuzzle _litePuzzleFromPick(RequiredPick pick) {
  return LitePuzzle(
    id: pick('id').asPuzzleIdOrThrow(),
    fen: pick('fen').asStringOrThrow(),
    solution: pick('line').asStringOrThrow().split(' ').toIList(),
    rating: pick('rating').asIntOrThrow(),
  );
}

PuzzleStormHighScore _stormHighScoreFromPick(RequiredPick pick) {
  return PuzzleStormHighScore(
    allTime: pick('allTime').asIntOrThrow(),
    day: pick('day').asIntOrThrow(),
    month: pick('month').asIntOrThrow(),
    week: pick('week').asIntOrThrow(),
  );
}

PuzzleData _puzzleDatafromPick(RequiredPick pick) {
  return PuzzleData(
    id: pick('id').asPuzzleIdOrThrow(),
    rating: pick('rating').asIntOrThrow(),
    plays: pick('plays').asIntOrThrow(),
    initialPly: pick('initialPly').asIntOrThrow(),
    solution: pick('solution').asListOrThrow((p0) => p0.asStringOrThrow()).lock,
    themes:
        pick('themes').asListOrThrow((p0) => p0.asStringOrThrow()).toSet().lock,
  );
}

PuzzleGlicko _puzzleGlickoFromPick(RequiredPick pick) {
  return PuzzleGlicko(
    rating: pick('rating').asDoubleOrThrow(),
    deviation: pick('deviation').asDoubleOrThrow(),
    provisional: pick('provisional').asBoolOrNull(),
  );
}

PuzzleRound _puzzleRoundFromPick(RequiredPick pick) {
  return PuzzleRound(
    id: pick('id').asPuzzleIdOrThrow(),
    ratingDiff: pick('ratingDiff').asIntOrThrow(),
    win: pick('win').asBoolOrThrow(),
  );
}

PuzzleGame _puzzleGameFromPick(RequiredPick pick) {
  return PuzzleGame(
    id: pick('id').asGameIdOrThrow(),
    perf: pick('perf', 'key').asPerfOrThrow(),
    rated: pick('rated').asBoolOrThrow(),
    white: pick('players').letOrThrow(
      (it) => it
          .asListOrThrow(_puzzlePlayerFromPick)
          .firstWhere((p) => p.side == Side.white),
    ),
    black: pick('players').letOrThrow(
      (it) => it
          .asListOrThrow(_puzzlePlayerFromPick)
          .firstWhere((p) => p.side == Side.black),
    ),
    pgn: pick('pgn').asStringOrThrow(),
  );
}

PuzzleGamePlayer _puzzlePlayerFromPick(RequiredPick pick) {
  return PuzzleGamePlayer(
    name: pick('name').asStringOrThrow(),
    side: pick('color').asSideOrThrow(),
    title: pick('title').asStringOrNull(),
  );
}

PuzzleHistoryEntry _historyPuzzleFromPick(RequiredPick pick) {
  return PuzzleHistoryEntry(
    win: pick('win').asBoolOrThrow(),
    date: pick('date').asDateTimeFromMillisecondsOrThrow(),
    rating: pick('puzzle', 'rating').asIntOrThrow(),
    id: pick('puzzle', 'id').asPuzzleIdOrThrow(),
    fen: pick('puzzle', 'fen').asStringOrThrow(),
    lastMove: pick('puzzle', 'lastMove').asUciMoveOrThrow(),
  );
}

PuzzleDashboard _puzzleDashboardFromPick(RequiredPick pick) => PuzzleDashboard(
      global: PuzzleDashboardData(
        nb: pick('global')('nb').asIntOrThrow(),
        firstWins: pick('global')('firstWins').asIntOrThrow(),
        replayWins: pick('global')('replayWins').asIntOrThrow(),
        performance: pick('global')('performance').asIntOrThrow(),
        theme: PuzzleThemeKey.mix,
      ),
      themes: pick('themes')
          .asMapOrThrow<String, Map<String, dynamic>>()
          .keys
          .map(
            (key) => _puzzleDashboardDataFromPick(
              pick('themes')(key)('results').required(),
              key,
            ),
          )
          .toIList(),
    );

PuzzleDashboardData _puzzleDashboardDataFromPick(
  RequiredPick results,
  String themeKey,
) =>
    PuzzleDashboardData(
      nb: results('nb').asIntOrThrow(),
      firstWins: results('firstWins').asIntOrThrow(),
      replayWins: results('replayWins').asIntOrThrow(),
      performance: results('performance').asIntOrThrow(),
      theme: puzzleThemeNameMap.get(themeKey) ?? PuzzleThemeKey.mix,
    );

IMap<PuzzleThemeKey, PuzzleThemeData> _puzzleThemeFromPick(RequiredPick pick) {
  final themeMap = puzzleThemeNameMap;
  final Map<PuzzleThemeKey, PuzzleThemeData> result = {};
  pick('themes').asMapOrThrow<String, dynamic>().keys.forEach((name) {
    pick('themes', name)
        .asListOrThrow((listPick) {
          return PuzzleThemeData(
            count: listPick('count').asIntOrThrow(),
            desc: listPick('desc').asStringOrThrow(),
            key: themeMap[listPick('key').asStringOrThrow()] ??
                PuzzleThemeKey.unsupported,
            name: listPick('name').asStringOrThrow(),
          );
        })
        .whereNot((e) => e.key == PuzzleThemeKey.unsupported)
        .forEach((e) {
          result[e.key] = e;
        });
  });

  return result.lock;
}

IList<PuzzleOpeningFamily> _puzzleOpeningFromPick(RequiredPick pick) {
  return pick('openings').asListOrThrow((openingPick) {
    final familyPick = openingPick('family');
    final openings = openingPick('openings').asListOrNull(
      (openPick) => PuzzleOpeningData(
        key: openPick('key').asStringOrThrow(),
        name: openPick('name').asStringOrThrow(),
        count: openPick('count').asIntOrThrow(),
      ),
    );

    return PuzzleOpeningFamily(
      key: familyPick('key').asStringOrThrow(),
      name: familyPick('name').asStringOrThrow(),
      count: familyPick('count').asIntOrThrow(),
      openings: openings != null ? openings.toIList() : IList(const []),
    );
  }).toIList();
}
