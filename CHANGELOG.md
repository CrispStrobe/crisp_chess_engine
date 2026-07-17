# Changelog

## 0.4.0

Search efficiency for the bitboard engine: ~32% fewer nodes to reach a given
depth, so it searches meaningfully deeper within the same time budget (which is
what matters on slower devices). No change to the public API.

### Added

- Aspiration windows: each iterative-deepening iteration searches a narrow band
  around the previous score, widening only on a fail. Reaches greater depth in a
  fixed time budget.
- Static Exchange Evaluation (`Position.see`) and SEE-based pruning of losing
  captures in quiescence — the largest node reduction, and it keeps quiescence
  from exploding on bad capture sequences. SEE is covered by unit tests.

## 0.3.0

Adds a native bitboard engine — 20-60x the nodes/sec of the original
chess-package search at equal depth (e.g. a depth-8 midgame search dropped from
~37s to ~0.8s).

### Added

- `package:crisp_chess_engine/bitboard.dart` — a self-contained bitboard core:
  `Position` (board state, make/unmake, move generation, FEN), `perft`,
  `evaluatePosition`, and `BitboardSearch` (alpha-beta + PVS + null-move +
  quiescence + transposition table + MVV-LVA/killer/history ordering + a time
  budget). Move generation is verified by perft against the six standard
  reference positions (startpos, Kiwipete, positions 3-6).

  **Native (Dart VM / AOT) only.** Bitboards are 64-bit and rely on 64-bit
  integer literals and operations, which dart2js cannot represent. Do not import
  this library from code that compiles to JavaScript — use the existing
  `AlphaBetaSearch` (which runs on `package:chess`) on web.

The original `AlphaBetaSearch` API is unchanged.

## 0.2.0

Correctness and performance release. Anyone on 0.1.0 should upgrade: the search
could return a move for the **wrong side**.

### Fixed

- **Search returned illegal moves.** Null-move pruning was implemented by
  writing a modified FEN with `Chess.load()`, which calls `clear()` and wipes
  the undo history — so every ancestor's `undo()` silently stopped restoring the
  board. Compounding it, `evaluate()` called `in_draw` /
  `in_threefold_repetition`, which unwind and replay the entire move history and
  thereby restore `turn` behind the search's back, undoing the null move's turn
  swap. From the opening position at depth >= 6 the engine answered `b8c6` — a
  Black move — for White. Null move is now an O(1) in-place turn/en-passant
  swap, and `evaluate()` no longer inspects draw state.
- **Weak moves.** With the board corrupted mid-search the engine preferred
  self-weakening moves such as `f2f3` and `a2a3` from the opening. It now plays
  normal moves (`e2e4`, `g1f3`, `b1c3`).
- **Transposition table collisions.** The position key was the hash of the FEN's
  piece-placement + side-to-move prefix, ignoring castling rights and the
  en-passant square, so genuinely different positions shared an entry. The key
  now covers both.

### Added

- `AlphaBetaSearch.search(..., timeBudget:)` and
  `searchPosition(..., timeBudget:)` — iterative deepening now returns the best
  move from the last completed depth once the budget is spent, aborting
  mid-iteration if needed. Strongly recommended for interactive callers: a fixed
  depth of 8+ can take tens of seconds.

### Changed

- ~5x faster (about 3k -> 15k+ nodes/sec). `evaluate()` was rebuilding the FEN
  for every ply of history on *every call* (two full history unwinds), and the
  position key rebuilt the FEN on every node.
- **Breaking (behavioural):** `evaluate()` is now a static evaluation. It still
  reports checkmate, but no longer returns 0 for draws/stalemate — the search
  owns terminal and repetition detection (it now uses a cheap position-key path
  check instead of `in_threefold_repetition`).

## 0.1.0

- Initial release: a pure-Dart chess engine (alpha-beta with null-move pruning,
  PVS, quiescence, MVV-LVA / killer / history ordering, and a transposition
  table), extracted from the CrispChess app. `searchPosition(fen, depth:)`
  convenience plus the lower-level `AlphaBetaSearch`.
