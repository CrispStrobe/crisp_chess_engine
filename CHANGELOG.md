# Changelog

## 0.1.0

- Initial release: a pure-Dart chess engine (alpha-beta with null-move pruning,
  PVS, quiescence, MVV-LVA / killer / history ordering, and a transposition
  table), extracted from the CrispChess app. `searchPosition(fen, depth:)`
  convenience plus the lower-level `AlphaBetaSearch`.
