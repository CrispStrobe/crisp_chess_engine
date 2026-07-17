import 'package:chess/chess.dart' as chess;
import 'evaluation.dart';
import 'transposition.dart';

class SearchResult {
  final String bestMove;
  final int score;
  final int depth;
  final int nodesSearched;

  SearchResult({
    required this.bestMove,
    required this.score,
    required this.depth,
    required this.nodesSearched,
  });
}

/// Optimized alpha-beta search with transposition table.
class AlphaBetaSearch {
  final chess.Chess _game;
  bool _stopped = false;
  int _nodes = 0;

  // Time management. When [_deadlineMs] > 0 the search aborts once the clock
  // passes it, so a single (potentially very deep) iteration can bail out
  // mid-tree instead of running to completion.
  final Stopwatch _clock = Stopwatch();
  int _deadlineMs = 0;

  final List<List<String?>> _killers;
  final Map<String, int> _history = {};
  final TranspositionTable _tt = TranspositionTable();

  // Position keys along the current search path, pushed/popped in
  // _makeMove/_unmakeMove. Used for a cheap repetition check that avoids
  // `chess`'s in_threefold_repetition, which rebuilds the FEN for every ply of
  // history on every node (~1ms/node) and dominated search time.
  final List<int> _path = <int>[];

  AlphaBetaSearch(this._game)
      : _killers = List.generate(64, (_) => [null, null]);

  void stop() => _stopped = true;

  /// True once the time budget (if any) has been exhausted.
  bool get _timeUp =>
      _deadlineMs > 0 && _clock.elapsedMilliseconds >= _deadlineMs;

  /// Run iterative deepening up to [maxDepth].
  ///
  /// If [timeBudget] is given the search returns the best move from the last
  /// *fully completed* depth once the budget is spent, rather than blocking
  /// until [maxDepth] is reached. This is what keeps move latency bounded on
  /// slow devices.
  SearchResult? search(
    int maxDepth, {
    void Function(SearchResult)? onDepthComplete,
    Duration? timeBudget,
  }) {
    _stopped = false;
    _nodes = 0;
    _path.clear();
    _deadlineMs = timeBudget?.inMilliseconds ?? 0;
    _clock
      ..reset()
      ..start();
    SearchResult? bestResult;

    for (int depth = 1; depth <= maxDepth; depth++) {
      if (_stopped) break;
      final result = _searchRoot(depth);
      // A time-out aborts mid-iteration and yields a null/partial root result;
      // keep the previous completed depth's move in that case.
      if (result != null && !_stopped) {
        bestResult = result;
        onDepthComplete?.call(result);
      }
      // Don't start a deeper iteration (each is much costlier) once time's up.
      if (_timeUp) break;
    }
    _clock.stop();
    return bestResult;
  }

  SearchResult? _searchRoot(int depth) {
    final moves = _game.generate_moves();
    if (moves.isEmpty) return null;

    final hash = _positionKey();
    final ttEntry = _tt.probe(hash);

    // Pre-compute UCI strings for all moves and build scored list
    final scored = <_ScoredMove>[];
    for (final move in moves) {
      final uci = _moveToUci(move);
      scored.add(
          _ScoredMove(move, uci, _moveScore(move, uci, 0, ttEntry?.bestMove)));
    }
    scored.sort((a, b) => b.score - a.score);

    String? bestMove;
    int bestScore = -999999;
    int alpha = -999999;
    const beta = 999999;

    for (final sm in scored) {
      if (_stopped) return null;

      _makeMove(sm.move);
      _nodes++;
      final score = -_alphaBeta(depth - 1, -beta, -alpha, 1);
      _unmakeMove();

      if (score > bestScore) {
        bestScore = score;
        bestMove = sm.uci;
      }
      if (score > alpha) alpha = score;
    }

    if (bestMove == null) return null;

    _tt.store(
      hash: hash,
      depth: depth,
      score: bestScore,
      flag: TTFlag.exact,
      bestMove: bestMove,
    );

    return SearchResult(
      bestMove: bestMove,
      score: bestScore,
      depth: depth,
      nodesSearched: _nodes,
    );
  }

  int _alphaBeta(int depth, int alpha, int beta, int ply) {
    if (_stopped) return 0;
    // Periodic time check so a deep iteration can abort mid-tree. Checked every
    // 256 nodes (~17ms at current speeds) to keep budget overshoot small.
    if (_deadlineMs > 0 && (_nodes & 255) == 0 && _timeUp) {
      _stopped = true;
      return 0;
    }

    // Generate moves ONCE — use result to detect checkmate/stalemate
    final moves = _game.generate_moves();

    if (moves.isEmpty) {
      // No moves = checkmate or stalemate
      return _game.in_check ? (-99999 + ply) : 0;
    }

    if (_game.half_moves >= 100 || _isRepetition()) return 0;

    if (depth <= 0) return _quiescence(alpha, beta, ply);

    // Reverse futility pruning: if static eval is far above beta,
    // prune — the position is so good no move can make it worse.
    if (depth <= 3 && !_game.in_check && ply > 0) {
      final staticEval = evaluate(_game);
      final margin = 120 * depth; // centipawns margin per depth
      if (staticEval - margin >= beta) {
        return staticEval; // Prune
      }
    }

    // Null move pruning: skip our turn and search at reduced depth.
    // If the score still exceeds beta, the position is so good we can prune.
    // Don't use in check, at low depth, or near endgame (zugzwang risk).
    if (depth >= 3 && !_game.in_check && ply > 0) {
      // In-place null move: hand the turn to the opponent without touching the
      // board or the undo history. The previous implementation used
      // `_game.load()`, which calls `clear()` and wipes the history stack —
      // corrupting every ancestor's pending `undo()` and producing nonsense
      // moves. Saving/restoring turn + en-passant is O(1) and correct.
      final savedTurn = _game.turn;
      final savedEp = _game.ep_square;
      _game.turn = savedTurn == chess.Color.WHITE
          ? chess.Color.BLACK
          : chess.Color.WHITE;
      _game.ep_square = chess.Chess.EMPTY;

      final nullScore = -_alphaBeta(depth - 1 - 2, -beta, -beta + 1, ply + 1);

      _game.turn = savedTurn;
      _game.ep_square = savedEp;

      if (nullScore >= beta) {
        return beta; // Null move cutoff
      }
    }

    // TT lookup
    final hash = _positionKey();
    final ttEntry = _tt.probe(hash);
    if (ttEntry != null && ttEntry.depth >= depth) {
      switch (ttEntry.flag) {
        case TTFlag.exact:
          return ttEntry.score;
        case TTFlag.lowerBound:
          if (ttEntry.score >= beta) return ttEntry.score;
          if (ttEntry.score > alpha) alpha = ttEntry.score;
        case TTFlag.upperBound:
          if (ttEntry.score <= alpha) return ttEntry.score;
          if (ttEntry.score < beta) beta = ttEntry.score;
      }
    }

    // Pre-compute UCI strings and scores for move ordering
    final scored = <_ScoredMove>[];
    for (final move in moves) {
      final uci = _moveToUci(move);
      scored.add(_ScoredMove(
          move, uci, _moveScore(move, uci, ply, ttEntry?.bestMove)));
    }
    scored.sort((a, b) => b.score - a.score);

    String? bestMove;
    int bestScore = -999999;
    final origAlpha = alpha;
    int moveIndex = 0;

    for (final sm in scored) {
      if (_stopped) return 0;

      // Check if capture before making the move
      final isCapture = _game.get(sm.move.toAlgebraic) != null;
      _makeMove(sm.move);
      _nodes++;

      int score;
      if (moveIndex == 0) {
        // First move (expected best): search with full window
        score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
      } else {
        // PVS: search with zero-width window first
        // Combined with Late Move Reductions for later quiet moves
        if (moveIndex >= 4 && depth >= 3 && !_game.in_check && !isCapture) {
          score = -_alphaBeta(depth - 2, -alpha - 1, -alpha, ply + 1);
        } else {
          score = -_alphaBeta(depth - 1, -alpha - 1, -alpha, ply + 1);
        }
        // Re-search with full window if it fails high
        if (score > alpha && score < beta) {
          score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
        }
      }
      _unmakeMove();
      moveIndex++;

      if (score > bestScore) {
        bestScore = score;
        bestMove = sm.uci;
      }

      if (score >= beta) {
        if (ply < _killers.length) {
          _killers[ply][1] = _killers[ply][0];
          _killers[ply][0] = sm.uci;
        }
        _history[sm.uci] = (_history[sm.uci] ?? 0) + depth * depth;
        _tt.store(
            hash: hash,
            depth: depth,
            score: score,
            flag: TTFlag.lowerBound,
            bestMove: sm.uci);
        return beta;
      }
      if (score > alpha) alpha = score;
    }

    final flag = bestScore <= origAlpha ? TTFlag.upperBound : TTFlag.exact;
    _tt.store(
        hash: hash,
        depth: depth,
        score: bestScore,
        flag: flag,
        bestMove: bestMove);

    return alpha;
  }

  int _quiescence(int alpha, int beta, int ply) {
    if (_stopped) return 0;

    final standPat = evaluate(_game);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;

    // Delta pruning: if even winning a queen can't raise alpha, skip
    if (standPat + 900 < alpha) return alpha;

    // Generate all moves and filter for captures
    final moves = _game.generate_moves();
    final captures = <_ScoredCapture>[];
    for (final m in moves) {
      final victim = _game.get(m.toAlgebraic);
      if (victim != null) {
        // MVV-LVA scoring: value victim high, attacker low
        final victimVal = pieceValues[victim.type] ?? 0;
        final attacker = _game.get(m.fromAlgebraic);
        final attackerVal = pieceValues[attacker?.type] ?? 0;
        final score = victimVal * 10 - attackerVal; // MVV-LVA
        captures.add(_ScoredCapture(m, score));
      }
    }

    // Sort by MVV-LVA score (highest first)
    captures.sort((a, b) => b.score - a.score);

    for (final cap in captures) {
      if (_stopped) return 0;

      // SEE-like pruning: skip captures where victim is worth less than attacker
      // and we're already close to alpha (likely losing exchange)
      if (cap.score < 0 &&
          standPat + (pieceValues[_game.get(cap.move.toAlgebraic)?.type] ?? 0) <
              alpha) {
        continue;
      }

      _makeMove(cap.move);
      _nodes++;
      final score = -_quiescence(-beta, -alpha, ply + 1);
      _unmakeMove();

      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }

    return alpha;
  }

  /// Fast position key folded directly from the board array.
  ///
  /// Avoids rebuilding the FEN string (which `_game.fen` does every call by
  /// scanning the board *and* allocating), and — unlike the old FEN-prefix
  /// hash — includes castling rights and the en-passant square, so distinct
  /// positions no longer collide in the transposition table. FNV-1a mixing.
  int _positionKey() {
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    final board = _game.board;
    for (var i = chess.Chess.SQUARES_A8; i <= chess.Chess.SQUARES_H1; i++) {
      if ((i & 0x88) != 0) continue; // skip off-board 0x88 squares
      final piece = board[i];
      if (piece != null) {
        h = (h ^ (i * 13 + piece.type.shift * 2 + piece.color.index + 1)) *
            prime;
      }
    }
    h = (h ^ (_game.turn == chess.Color.WHITE ? 1 : 2)) * prime;
    h = (h ^ _game.castling[chess.Color.WHITE]) * prime;
    h = (h ^ _game.castling[chess.Color.BLACK]) * prime;
    h = (h ^ ((_game.ep_square ?? chess.Chess.EMPTY) + 2)) * prime;
    return h;
  }

  /// Make a move using a reusable map to reduce GC pressure.
  static final Map<String, String?> _moveMap = {
    'from': '',
    'to': '',
    'promotion': null
  };

  void _makeMove(chess.Move move) {
    _moveMap['from'] = move.fromAlgebraic;
    _moveMap['to'] = move.toAlgebraic;
    _moveMap['promotion'] = move.promotion?.name;
    final ok = _game.move(_moveMap);
    // Invariant: every move we make came from generate_moves() on the current
    // position, so it must be accepted. A rejection means board state and the
    // move list have desynced (e.g. something restored `turn` behind our back)
    // and would silently corrupt the search via a mismatched undo().
    assert(ok,
        'move() rejected ${move.fromAlgebraic}${move.toAlgebraic} turn=${_game.turn}');
    _path.add(_positionKey());
  }

  void _unmakeMove() {
    _path.removeLast();
    _game.undo();
  }

  /// Cheap repetition check: has the current position (top of [_path]) already
  /// occurred earlier on this search line? Position keys include side-to-move,
  /// castling rights and the en-passant square, so only truly identical
  /// positions match. O(path length) integer compares — no FEN rebuilding.
  bool _isRepetition() {
    if (_path.length < 5) return false;
    final key = _path.last;
    // Same position recurs every 2 plies at the earliest; step back by two.
    for (var i = _path.length - 3; i >= 0; i -= 2) {
      if (_path[i] == key) return true;
    }
    return false;
  }

  String _moveToUci(chess.Move move) {
    return '${move.fromAlgebraic}${move.toAlgebraic}${move.promotion?.name ?? ''}';
  }

  int _moveScore(chess.Move move, String uci, int ply, String? ttBestMove) {
    if (ttBestMove != null && uci == ttBestMove) return 20000;

    final victim = _game.get(move.toAlgebraic);
    if (victim != null) {
      final attacker = _game.get(move.fromAlgebraic);
      return 10000 +
          (pieceValues[victim.type] ?? 0) -
          ((pieceValues[attacker?.type] ?? 0) ~/ 10);
    }

    if (move.promotion != null) return 9000;

    if (ply < _killers.length) {
      if (_killers[ply][0] == uci) return 8000;
      if (_killers[ply][1] == uci) return 7000;
    }

    return _history[uci] ?? 0;
  }
}

/// Move with pre-computed UCI string and ordering score.
class _ScoredMove {
  final chess.Move move;
  final String uci;
  final int score;
  _ScoredMove(this.move, this.uci, this.score);
}

/// Capture move with MVV-LVA score for quiescence ordering.
class _ScoredCapture {
  final chess.Move move;
  final int score;
  _ScoredCapture(this.move, this.score);
}
