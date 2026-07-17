/// A small, **pure-Dart chess engine**: iterative-deepening alpha-beta search
/// with null-move pruning, principal-variation search (PVS), a quiescence
/// search, MVV-LVA / killer / history move ordering, and a transposition
/// table. No native code and no FFI, so it runs on every Dart/Flutter target.
///
/// Move generation and board state come from the `chess` package.
///
/// ```dart
/// import 'package:crisp_chess_engine/crisp_chess_engine.dart';
///
/// void main() {
///   final result = searchPosition(
///     '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
///     depth: 4,
///   );
///   print(result?.bestMove); // a1a8 (back-rank mate)
/// }
/// ```
///
/// For finer control (custom time budget, per-depth callbacks, or an existing
/// `chess.Chess` board) use [AlphaBetaSearch] directly.
library;

import 'package:chess/chess.dart' as chess;

import 'src/search.dart';

export 'src/search.dart' show AlphaBetaSearch, SearchResult;
export 'src/evaluation.dart' show evaluate, pieceValues;

/// Searches the position given by [fen] to [depth] plies (iterative deepening)
/// and returns the [SearchResult] — including the best move in UCI notation
/// (e.g. `e2e4`) — or `null` if the side to move has no legal moves
/// (checkmate or stalemate).
///
/// Pass [timeBudget] to bound how long the search may run: it returns the best
/// move from the last fully completed depth once the budget is spent. Strongly
/// recommended on interactive/mobile callers — a fixed [depth] of 8+ can take
/// tens of seconds.
SearchResult? searchPosition(String fen, {int depth = 6, Duration? timeBudget}) {
  final game = chess.Chess();
  game.load(fen);
  return AlphaBetaSearch(game).search(depth, timeBudget: timeBudget);
}
