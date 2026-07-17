/// Native-only bitboard chess core: board representation, move generation,
/// make/unmake, FEN, and perft.
///
/// **Do not import this from code that compiles to JavaScript.** Bitboards are
/// 64-bit and rely on 64-bit integer literals and operations, which are not
/// representable under dart2js (web ints are doubles). Native (Dart VM / AOT)
/// only. The web build must reach the engine through the [package] search that
/// runs on `package:chess`, never this library.
library;

export 'src/bitboard/attacks.dart';
export 'src/bitboard/evaluation.dart';
export 'src/bitboard/position.dart';
export 'src/bitboard/search.dart';
export 'src/search.dart' show SearchResult;
