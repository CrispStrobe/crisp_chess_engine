import 'package:chess/chess.dart' as chess;
import 'package:crisp_chess_engine/crisp_chess_engine.dart';
import 'package:test/test.dart';

const _startpos = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

Set<String> _legalMoves(chess.Chess g) => g
    .generate_moves()
    .map((m) => '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}')
    .toSet();

void main() {
  test('finds a back-rank mate in one (Ra8#)', () {
    final r = searchPosition('6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1', depth: 3);
    expect(r, isNotNull);
    expect(r!.bestMove, 'a1a8');
  });

  test('reports a mate score when a forced mate exists', () {
    // White queen + king box the black king in the corner; several mates in
    // one exist, so assert the (large) mate score rather than a specific move.
    final r = searchPosition('k7/8/1K6/8/8/8/8/1Q6 w - - 0 1', depth: 3);
    expect(r, isNotNull);
    expect(r!.score, greaterThan(90000));
  });

  test('returns a legal move from the opening position', () {
    final r = searchPosition(
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      depth: 3,
    );
    expect(r, isNotNull);
    // UCI: from-square + to-square, e.g. e2e4.
    expect(r!.bestMove, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    expect(r.depth, 3);
    expect(r.nodesSearched, greaterThan(0));
  });

  test('captures a hanging queen', () {
    // White to move; a free black queen on d5 is taken by the pawn on e4.
    final r = searchPosition('4k3/8/8/3q4/4P3/8/8/4K3 w - - 0 1', depth: 4);
    expect(r, isNotNull);
    expect(r!.bestMove, 'e4d5');
  });

  group('regression', () {
    // Null-move pruning used to be implemented with `_game.load()`, which calls
    // clear() and wipes the undo history, and evaluate() called `in_draw` /
    // `in_threefold_repetition`, which unwind and replay the whole history and
    // so restored `turn` behind the search's back. Both silently corrupted the
    // board mid-search: at depth >= 6 the engine returned moves for the *wrong
    // side* (e.g. b8c6 as White from the opening position).
    test('root move is always legal for the side to move', () {
      for (var depth = 1; depth <= 8; depth++) {
        final legal = _legalMoves(chess.Chess()..load(_startpos));
        final r = searchPosition(_startpos, depth: depth);
        expect(r, isNotNull, reason: 'depth $depth returned no result');
        expect(legal, contains(r!.bestMove),
            reason: 'depth $depth returned ${r.bestMove}, '
                'which is not legal for White');
      }
    });

    test('search leaves the caller\'s board untouched', () {
      final game = chess.Chess()..load(_startpos);
      AlphaBetaSearch(game).search(6);
      expect(game.fen, _startpos);
      expect(game.turn, chess.Color.WHITE);
    });

    test('picks a sane opening move rather than a self-weakening one', () {
      // The corrupted search used to answer f2f3 / a2a3 here.
      final r = searchPosition(_startpos, depth: 6);
      expect(r, isNotNull);
      expect(r!.bestMove, isNot(anyOf('f2f3', 'g2g4', 'a2a3', 'h2h4')));
    });
  });

  group('time budget', () {
    test('returns within the budget instead of running to depth', () {
      // Depth 64 would never finish; the budget must bound it.
      final sw = Stopwatch()..start();
      final r = searchPosition(
        'r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/2NBPN2/PPP2PPP/R1BQ1RK1 w - - 0 8',
        depth: 64,
        timeBudget: const Duration(milliseconds: 500),
      );
      sw.stop();
      expect(r, isNotNull);
      // Generous ceiling — asserting it terminates promptly, not exact timing.
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('a budgeted search still returns a legal move', () {
      final legal = _legalMoves(chess.Chess()..load(_startpos));
      final r = searchPosition(_startpos,
          depth: 64, timeBudget: const Duration(milliseconds: 300));
      expect(r, isNotNull);
      expect(legal, contains(r!.bestMove));
    });
  });
}
