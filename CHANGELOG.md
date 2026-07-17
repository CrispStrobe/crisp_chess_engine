# Changelog

## 0.8.0

Brings the chess-package `AlphaBetaSearch` (the web / non-native path) up to par
with the bitboard engine on endgames and repetitions.

### Added

- `AlphaBetaSearch(..., repetitionHistory: [...])` — seeds repetition detection
  with the game's prior positions, same as the bitboard engine. Without it the
  web search could draw a won game (or shuffle a won ending) by repetition.
- `AlphaBetaSearch.positionKeyOf(game)` — the search's position key, exposed so
  callers can build the `repetitionHistory` list from a game's prior positions.
- Endgame mop-up in the chess-package `evaluate()` (mirrors the bitboard term):
  in a bare-king ending with mating material, drives the lone king to a corner
  and the strong king in. Fires only when a king is bare, so contested
  positions are unaffected.

Together these let the web search convert K+R vs K / K+Q vs K at shallow depth
instead of shuffling. Both additions are backward compatible.

## 0.7.0

Repetition awareness across the actual game, not just the search tree.

### Added

- `BitboardSearch(..., repetitionHistory: [...])` seeds repetition detection
  with the game's prior position keys (in order, the current position last).
  Without it the search evaluates each position in a vacuum and can *walk into a
  repetition* — drawing a won game, or shuffling a won ending forever at shallow
  depth. With the game history, a repeat scores as a draw, so the engine avoids
  it when winning (and seeks it when losing).
- `Position.hash()` is the key to collect for that list.

Effect: at depth 6 (beyond the mate horizon) K+R vs K — including a central lone
king — now converts instead of shuffling to the 50-move rule. Purely additive:
callers that pass no history behave exactly as before.

## 0.6.0

Endgame mop-up evaluation, so the engine converts won bare-king endings instead
of shuffling.

### Added

- A mop-up term: when one side has only its king and the other has mating
  material (a rook or queen), the evaluation drives the lone king toward a
  corner and brings the strong king in — a monotonic gradient toward the mate.

  Material + PST alone gives no gradient in these endings, so a shallow search
  never converts them. With mop-up, K+Q vs K is mated at depth 6 and K+R vs K at
  depth 8, both of which the material+PST baseline shuffles indefinitely.

The term only fires when a king is truly bare, so it has no effect on contested
middlegames (verified: the tactical node counts are unchanged).

## 0.5.0

Positional evaluation terms for the bitboard engine, verified stronger by
self-play. Cost-free (no measurable nodes/sec impact) with no tactical
regression.

### Added

- Evaluation now includes the **bishop pair** bonus and **pawn structure**
  (doubled, isolated and passed pawns) on top of material + piece-square tables.
  In deterministic fixed-depth self-play from 18 openings (both colours) the new
  evaluation scores ~54-62% against the material+PST baseline.
- `evaluateMaterialPst` — the material+PST-only evaluation, exposed as a
  lightweight alternative and the A/B baseline (`test/selfplay.dart`).
- `BitboardSearch` takes an optional `evaluator` so alternative evaluations can
  be dropped in (used by the self-play harness).
- `Position.see` is public (already used internally for quiescence pruning).

A mobility term was tried and **dropped**: it was ~40% slower and its per-node
value cancelled against the shallower search that cost caused, so it was a wash
in time-budgeted play.

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
