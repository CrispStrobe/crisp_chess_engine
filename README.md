# crisp_chess_engine

A small, **pure-Dart chess engine** — no native code, no FFI, so it runs on
every Dart/Flutter target including the web.

Search: iterative-deepening **alpha-beta** with **null-move pruning**,
**principal-variation search (PVS)**, a **quiescence** search, MVV-LVA / killer /
history move ordering, and a **transposition table**. Board state and move
generation come from the [`chess`](https://pub.dev/packages/chess) package.

## Install

```yaml
dependencies:
  crisp_chess_engine: ^0.1.0
```

## Usage

```dart
import 'package:crisp_chess_engine/crisp_chess_engine.dart';

void main() {
  final result = searchPosition(
    '6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1',
    depth: 4,
  );
  print(result?.bestMove); // a1a8  (back-rank mate, Ra8#)
  print(result?.score);    // large positive mate score
}
```

`searchPosition` returns a `SearchResult` (`bestMove` in UCI, `score` in
centipawns from the side-to-move's perspective, `depth`, `nodesSearched`), or
`null` if the side to move has no legal moves (checkmate or stalemate).

For finer control — an existing `chess.Chess` board, per-depth callbacks, or
stopping the search — use [`AlphaBetaSearch`] directly:

```dart
import 'package:chess/chess.dart';
import 'package:crisp_chess_engine/crisp_chess_engine.dart';

final game = Chess()..load(fen);
final search = AlphaBetaSearch(game);
final result = search.search(8, onDepthComplete: (r) => print('d${r.depth}: ${r.bestMove}'));
```

## License

MIT. Extracted from the CrispChess app's built-in engine.
