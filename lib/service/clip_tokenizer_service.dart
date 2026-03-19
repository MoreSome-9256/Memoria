import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Pure-Dart implementation of the OpenAI CLIP BPE tokenizer.
///
/// Fully compatible with MobileCLIP2 (both use the standard CLIP BPE vocabulary,
/// vocab size 49408, as confirmed by the HF model card).
///
/// Usage:
/// ```dart
/// final tokenizer = ClipTokenizerService();
/// await tokenizer.warmUp(); // load vocab + merges once
/// final ids = await tokenizer.tokenize('a photo of a cat');
/// // ids is List<int> of length 77: [SOT, ...content..., EOT, 0, 0, ...]
/// ```
class ClipTokenizerService {
  ClipTokenizerService._internal();

  static final ClipTokenizerService _instance =
      ClipTokenizerService._internal();

  factory ClipTokenizerService() => _instance;

  // Token IDs for the CLIP BPE vocabulary.
  static const int sotToken = 49406; // <|startoftext|>
  static const int eotToken = 49407; // <|endoftext|>
  static const int contextLength = 77;

  static const String _vocabAssetPath =
      'assets/clip_tokenizer/tokenizer_vocab.json';
  static const String _mergesAssetPath =
      'assets/clip_tokenizer/tokenizer_merges.txt';

  Map<String, int>? _encoder; // byte-encoded token string → token ID
  Map<String, int>? _bpeRanks; // "unit1 unit2" → merge rank
  Map<int, String>? _byteEncoder; // raw byte value → CLIP unicode char

  // LRU-less cache: for a finite tag set this is fine.
  final Map<String, String> _bpeCache = {};

  bool _initialized = false;

  /// Pre-loads vocabulary and merge rules from assets.
  /// Call this once during app startup to avoid first-use latency.
  Future<void> warmUp() => _ensureLoaded();

  /// Converts [text] into a fixed-length list of [contextLength] (77) token IDs.
  ///
  /// - Position 0: SOT (49406)
  /// - Positions 1..n: content tokens (up to 75)
  /// - Position n+1: EOT (49407)
  /// - Remaining positions: 0 (padding)
  Future<List<int>> tokenize(String text) async {
    await _ensureLoaded();
    return _encodeText(text);
  }

  /// Synchronous variant. Only safe to call after [warmUp] has completed.
  List<int> tokenizeSync(String text) {
    if (!_initialized) {
      throw StateError(
        'ClipTokenizerService 未初始化，请先调用 warmUp()',
      );
    }
    return _encodeText(text);
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _ensureLoaded() async {
    if (_initialized) return;

    _byteEncoder = _buildByteEncoder();

    // Load vocab JSON (~1 MB, one-time cost)
    final vocabJson = await rootBundle.loadString(_vocabAssetPath);
    _encoder =
        (json.decode(vocabJson) as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, v as int),
        );

    // Load BPE merge rules (~48 k lines, one-time cost)
    final mergesText = await rootBundle.loadString(_mergesAssetPath);
    _bpeRanks = {};
    var rank = 0;
    for (final line in mergesText.split('\n')) {
      final t = line.trimRight();
      if (t.isEmpty || t.startsWith('#')) continue;
      _bpeRanks![t] = rank++;
    }

    _initialized = true;
    debugPrint(
      '🔤 ClipTokenizer 就绪  vocab=${_encoder!.length}  merges=${_bpeRanks!.length}',
    );
  }

  // ---------------------------------------------------------------------------
  // Encoding
  // ---------------------------------------------------------------------------

  List<int> _encodeText(String text) {
    final tokens = <int>[];
    final cleaned = _whitespaceClean(_basicClean(text)).toLowerCase();

    for (final match in _tokenPattern.allMatches(cleaned)) {
      final word = match.group(0)!;

      // Map each UTF-8 byte of the word through the CLIP byte encoder.
      final byteStr = _utf8ToByteEncoding(word);

      // Apply BPE and collect token IDs.
      if (byteStr.isNotEmpty) {
        for (final seg in _bpe(byteStr).split(' ')) {
          final id = _encoder![seg];
          if (id != null) tokens.add(id);
        }
      }
    }

    // Build the fixed 77-token sequence.
    final result = List<int>.filled(contextLength, 0); // 0-padding
    result[0] = sotToken;
    final n = math.min(tokens.length, contextLength - 2);
    for (var i = 0; i < n; i++) {
      result[i + 1] = tokens[i];
    }
    result[n + 1] = eotToken;
    return result;
  }

  /// Maps every rune of [word] to its CLIP byte-encoding unicode equivalent.
  String _utf8ToByteEncoding(String word) {
    final buf = StringBuffer();
    for (final rune in word.runes) {
      for (final byte in utf8.encode(String.fromCharCode(rune))) {
        buf.write(_byteEncoder![byte]!);
      }
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // BPE algorithm (mirrors OpenAI simple_tokenizer.py)
  // ---------------------------------------------------------------------------

  String _bpe(String token) {
    if (_bpeCache.containsKey(token)) return _bpeCache[token]!;

    final len = token.length;
    if (len == 0) return token;

    // Initial word: individual chars with </w> appended to the last one.
    var word = List<String>.generate(len, (i) {
      return i == len - 1 ? '${token[i]}</w>' : token[i];
    });

    if (word.length == 1) {
      _bpeCache[token] = word[0];
      return word[0];
    }

    while (word.length > 1) {
      // Find the adjacent pair with the smallest BPE rank.
      int? bestRank;
      String? bestFirst;
      String? bestSecond;

      for (var i = 0; i < word.length - 1; i++) {
        final rank = _bpeRanks!['${word[i]} ${word[i + 1]}'];
        if (rank != null && (bestRank == null || rank < bestRank)) {
          bestRank = rank;
          bestFirst = word[i];
          bestSecond = word[i + 1];
        }
      }

      if (bestFirst == null) break; // No more mergeable pairs.

      // Merge ALL occurrences of (bestFirst, bestSecond) in one pass.
      final merged = bestFirst + bestSecond!;
      final newWord = <String>[];
      var i = 0;
      while (i < word.length) {
        if (i < word.length - 1 &&
            word[i] == bestFirst &&
            word[i + 1] == bestSecond) {
          newWord.add(merged);
          i += 2;
        } else {
          newWord.add(word[i]);
          i++;
        }
      }
      word = newWord;
    }

    final result = word.join(' ');
    _bpeCache[token] = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Regex that mirrors the CLIP simple_tokenizer pattern.
  /// Handles ASCII/Latin/CJK text — sufficient for English and Chinese tags.
  static final RegExp _tokenPattern = RegExp(
    // Special tokens first, then English contractions, then word runs.
    r"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d"
    r"|[a-zA-Z\u00C0-\u024F\u4E00-\u9FFF\uF900-\uFAFF]+"
    r'|[0-9]'
    r'|[^\s]+',
    caseSensitive: false,
  );

  static String _basicClean(String text) {
    return text
        .replaceAll('\u00a0', ' ') // non-breaking space
        .replaceAll('\u200b', '') // zero-width space
        .replaceAll('\ufeff', ''); // BOM
  }

  static String _whitespaceClean(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Replicates Python's `bytes_to_unicode()` from simple_tokenizer.py.
  ///
  /// Maps every byte value (0-255) to a unique BMP unicode character.
  /// Printable ASCII (33-126) and Latin-1 supplement (161-172, 174-255) are
  /// self-mapping (byte value == code point). The remaining 68 bytes are
  /// mapped to code points 256..323.
  static Map<int, String> _buildByteEncoder() {
    // "Nice" byte ranges that map to themselves.
    final bs = <int>[];
    for (var i = 33; i <= 126; i++) {
      bs.add(i); // '!' .. '~'
    }
    for (var i = 161; i <= 172; i++) {
      bs.add(i); // '¡' .. '¬'
    }
    for (var i = 174; i <= 255; i++) {
      bs.add(i); // '®' .. 'ÿ'
    }

    // Code-point counterparts start as a copy, then extend for non-nice bytes.
    final cs = List<int>.from(bs);
    var n = 0;
    for (var b = 0; b < 256; b++) {
      if (!bs.contains(b)) {
        bs.add(b);
        cs.add(256 + n);
        n++;
      }
    }

    final result = <int, String>{};
    for (var i = 0; i < bs.length; i++) {
      result[bs[i]] = String.fromCharCode(cs[i]);
    }
    return result;
  }
}
