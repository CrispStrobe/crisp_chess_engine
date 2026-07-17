// Alpha-beta search on the bitboard [Position].
//
// Same techniques as the chess-package AlphaBetaSearch (iterative deepening,
// PVS, null-move, quiescence, transposition table, MVV-LVA / killer / history
// ordering, time budget) but operating on bitboards and packed int moves, so
// it runs ~10x faster. NATIVE ONLY (see attacks.dart).

import '../search.dart' show SearchResult;
import 'attacks.dart';
import 'evaluation.dart';
import 'position.dart';

const int _inf = 1 << 30;
const int _mate = 1000000; // mate value; ply is subtracted so shorter mates win
const int _maxPly = 128;

enum _TTFlag { exact, lower, upper }

class _TTEntry {
  int depth;
  int score;
  _TTFlag flag;
  int move;
  _TTEntry(this.depth, this.score, this.flag, this.move);
}

class BitboardSearch {
  final Position pos;

  bool _stopped = false;
  int _nodes = 0;

  final Stopwatch _clock = Stopwatch();
  int _deadlineMs = 0;

  // Move ordering aids.
  final List<List<int>> _killers =
      List.generate(_maxPly, (_) => [0, 0]);
  final List<int> _history = List<int>.filled(64 * 64, 0);

  final Map<int, _TTEntry> _tt = {};
  static const int _ttMaxEntries = 1 << 20;

  // Position hashes along the current search path, for repetition detection.
  final List<int> _path = [];

  BitboardSearch(this.pos);

  void stop() => _stopped = true;

  bool get _timeUp =>
      _deadlineMs > 0 && _clock.elapsedMilliseconds >= _deadlineMs;

  /// Iterative deepening to [maxDepth]. With a [timeBudget] the search returns
  /// the best move from the last fully completed depth once time is spent.
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

    SearchResult? best;
    for (var depth = 1; depth <= maxDepth; depth++) {
      if (_stopped) break;
      final result = _searchRoot(depth);
      if (result != null && !_stopped) {
        best = result;
        onDepthComplete?.call(result);
        // A forced mate is found — no point searching deeper.
        if (result.score.abs() >= _mate - _maxPly) break;
      }
      if (_timeUp) break;
    }
    _clock.stop();
    return best;
  }

  SearchResult? _searchRoot(int depth) {
    final hash = pos.hash();
    final ttMove = _tt[hash]?.move ?? 0;

    final moves = <int>[];
    pos.generatePseudoLegal(moves);
    _orderMoves(moves, ttMove, 0);

    var bestMove = 0;
    var bestScore = -_inf;
    var alpha = -_inf;
    const beta = _inf;
    var legal = 0;

    for (final m in moves) {
      pos.makeMove(m);
      if (!pos.moverKingSafe) {
        pos.unmakeMove();
        continue;
      }
      legal++;
      _path.add(pos.hash());
      final score = -_alphaBeta(depth - 1, -beta, -alpha, 1);
      _path.removeLast();
      pos.unmakeMove();

      if (_stopped) return null;
      if (score > bestScore) {
        bestScore = score;
        bestMove = m;
      }
      if (score > alpha) alpha = score;
    }

    if (legal == 0) return null; // mate or stalemate at the root
    _ttStore(hash, depth, bestScore, _TTFlag.exact, bestMove);
    return SearchResult(
      bestMove: pos.moveToUci(bestMove),
      score: bestScore,
      depth: depth,
      nodesSearched: _nodes,
    );
  }

  int _alphaBeta(int depth, int alpha, int beta, int ply) {
    if (_stopped) return 0;
    if (_deadlineMs > 0 && (_nodes & 1023) == 0 && _timeUp) {
      _stopped = true;
      return 0;
    }

    // Draws: 50-move rule and repetition on the current line.
    if (pos.halfmove >= 100 || _isRepetition()) return 0;

    if (depth <= 0) return _quiescence(alpha, beta, ply);

    final inCheck = pos.inCheck;
    final hash = pos.hash();

    // Transposition table.
    final entry = _tt[hash];
    if (entry != null && entry.depth >= depth) {
      switch (entry.flag) {
        case _TTFlag.exact:
          return entry.score;
        case _TTFlag.lower:
          if (entry.score >= beta) return entry.score;
        case _TTFlag.upper:
          if (entry.score <= alpha) return entry.score;
      }
    }

    // Null-move pruning. Skip near leaves, in check, and when we have only
    // pawns+king (zugzwang risk).
    if (!inCheck && depth >= 3 && ply > 0 && _hasNonPawnMaterial()) {
      pos.makeNullMove();
      _path.add(pos.hash());
      final nullScore = -_alphaBeta(depth - 1 - 2, -beta, -beta + 1, ply + 1);
      _path.removeLast();
      pos.unmakeNullMove();
      if (nullScore >= beta) return beta;
    }

    final ttMove = entry?.move ?? 0;
    final moves = <int>[];
    pos.generatePseudoLegal(moves);
    _orderMoves(moves, ttMove, ply);

    var bestMove = 0;
    var bestScore = -_inf;
    final origAlpha = alpha;
    var legal = 0;
    var moveIndex = 0;

    for (final m in moves) {
      pos.makeMove(m);
      if (!pos.moverKingSafe) {
        pos.unmakeMove();
        continue;
      }
      legal++;
      _nodes++;
      _path.add(pos.hash());

      final givesCheck = pos.inCheck;
      final quiet = !moveIsCapture(m) && !moveIsPromotion(m);
      int score;
      if (moveIndex == 0) {
        score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
      } else {
        // Late-move reduction for quiet, non-checking moves.
        var reduction = 0;
        if (moveIndex >= 4 && depth >= 3 && quiet && !givesCheck && !inCheck) {
          reduction = 1;
        }
        score = -_alphaBeta(depth - 1 - reduction, -alpha - 1, -alpha, ply + 1);
        if (score > alpha && score < beta) {
          score = -_alphaBeta(depth - 1, -beta, -alpha, ply + 1);
        }
      }

      _path.removeLast();
      pos.unmakeMove();
      moveIndex++;

      if (_stopped) return 0;

      if (score > bestScore) {
        bestScore = score;
        bestMove = m;
      }
      if (score > alpha) alpha = score;
      if (alpha >= beta) {
        // Beta cutoff — record killers/history for quiet moves.
        if (quiet) {
          final k = _killers[ply];
          if (k[0] != m) {
            k[1] = k[0];
            k[0] = m;
          }
          _history[(moveFrom(m) << 6) | moveTo(m)] += depth * depth;
        }
        _ttStore(hash, depth, bestScore, _TTFlag.lower, m);
        return bestScore;
      }
    }

    if (legal == 0) {
      // No legal move: checkmate (prefer shorter mates) or stalemate.
      return inCheck ? -_mate + ply : 0;
    }

    final flag = bestScore <= origAlpha ? _TTFlag.upper : _TTFlag.exact;
    _ttStore(hash, depth, bestScore, flag, bestMove);
    return bestScore;
  }

  int _quiescence(int alpha, int beta, int ply) {
    if (_stopped) return 0;
    if (_deadlineMs > 0 && (_nodes & 1023) == 0 && _timeUp) {
      _stopped = true;
      return 0;
    }

    final standPat = evaluatePosition(pos);
    if (standPat >= beta) return beta;
    if (standPat > alpha) alpha = standPat;
    if (ply >= _maxPly - 1) return standPat;

    final moves = <int>[];
    pos.generateCaptures(moves);
    _orderCaptures(moves);

    for (final m in moves) {
      pos.makeMove(m);
      if (!pos.moverKingSafe) {
        pos.unmakeMove();
        continue;
      }
      _nodes++;
      final score = -_quiescence(-beta, -alpha, ply + 1);
      pos.unmakeMove();
      if (_stopped) return 0;
      if (score >= beta) return beta;
      if (score > alpha) alpha = score;
    }
    return alpha;
  }

  bool _isRepetition() {
    if (_path.length < 5) return false;
    final key = _path.last;
    for (var i = _path.length - 3; i >= 0; i -= 2) {
      if (_path[i] == key) return true;
    }
    return false;
  }

  bool _hasNonPawnMaterial() {
    final us = pos.turn;
    return (pos.pieces[us][knight] |
            pos.pieces[us][bishop] |
            pos.pieces[us][rook] |
            pos.pieces[us][queen]) !=
        0;
  }

  // ---- Move ordering --------------------------------------------------------

  static const int _mvvLva = 1 << 20; // capture base score

  void _orderMoves(List<int> moves, int ttMove, int ply) {
    final k0 = _killers[ply][0], k1 = _killers[ply][1];
    moves.sort((a, b) => _moveScore(b, ttMove, k0, k1) -
        _moveScore(a, ttMove, k0, k1));
  }

  int _moveScore(int m, int ttMove, int k0, int k1) {
    if (m == ttMove) return 1 << 28;
    if (moveIsCapture(m)) {
      final victim = moveIsEnPassant(m) ? pawn : pos.mailbox[moveTo(m)];
      final attacker = pos.mailbox[moveFrom(m)];
      return _mvvLva + pieceValue[victim] * 16 - pieceValue[attacker];
    }
    if (moveIsPromotion(m)) return _mvvLva + pieceValue[movePromoType(m)];
    if (m == k0) return _mvvLva - 1;
    if (m == k1) return _mvvLva - 2;
    return _history[(moveFrom(m) << 6) | moveTo(m)];
  }

  void _orderCaptures(List<int> moves) {
    moves.sort((a, b) => _captureScore(b) - _captureScore(a));
  }

  int _captureScore(int m) {
    if (moveIsPromotion(m)) return pieceValue[movePromoType(m)] * 16;
    final victim = moveIsEnPassant(m) ? pawn : pos.mailbox[moveTo(m)];
    final attacker = pos.mailbox[moveFrom(m)];
    return pieceValue[victim] * 16 - pieceValue[attacker];
  }

  void _ttStore(int hash, int depth, int score, _TTFlag flag, int move) {
    final existing = _tt[hash];
    if (existing == null || depth >= existing.depth) {
      if (_tt.length >= _ttMaxEntries && existing == null) {
        _tt.remove(_tt.keys.first);
      }
      _tt[hash] = _TTEntry(depth, score, flag, move);
    }
  }
}
