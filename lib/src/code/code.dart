import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:highlight/highlight_core.dart';

import '../folding/foldable_block.dart';
import '../folding/foldable_block_matcher.dart';
import '../folding/parsers/parser_factory.dart';
import '../hidden_ranges/hidden_line_ranges.dart';
import '../hidden_ranges/hidden_line_ranges_builder.dart';
import '../hidden_ranges/hidden_range.dart';
import '../hidden_ranges/hidden_ranges.dart';
import '../hidden_ranges/hidden_ranges_builder.dart';
import '../issues/issue.dart';
import '../named_sections/named_section.dart';
import '../named_sections/parsers/abstract.dart';
import '../service_comment_filter/service_comment_filter.dart';
import '../single_line_comments/parser/single_line_comment_parser.dart';
import '../single_line_comments/parser/single_line_comments.dart';
import '../single_line_comments/single_line_comment.dart';
import 'code_edit_result.dart';
import 'code_line.dart';
import 'code_lines.dart';
import 'code_lines_builder.dart';
import 'string.dart';
import 'text_range.dart';

class Code {
  final String text;
  final List<FoldableBlock> foldableBlocks;
  final Set<FoldableBlock> foldedBlocks;
  final HiddenLineRanges hiddenLineRanges;
  final HiddenRanges hiddenRanges;
  final Result? highlighted;
  final List<Issue> issues;
  final Iterable<SingleLineComment> serviceComments;
  final CodeLines lines;
  final Map<String, NamedSection> namedSections;
  final Result? visibleHighlighted;
  final String visibleText;

  final HiddenRangesBuilder _hiddenRangesBuilder;

  factory Code({
    required String text,
    Result? highlighted,
    Mode? language,
    AbstractNamedSectionParser? namedSectionParser,
    Set<String> readOnlySectionNames = const {},
  }) {
    final sequences = SingleLineComments.byMode[language] ?? [];

    final commentParser = SingleLineCommentParser.parseHighlighted(
      text: text,
      highlighted: highlighted,
      singleLineCommentSequences: sequences,
    );

    final serviceComments = ServiceCommentFilter.filter(
      commentParser.comments,
      namedSectionParser: namedSectionParser,
    );

    final serviceCommentsNodesSet = serviceComments.sources;

    final issues = <Issue>[];
    final List<FoldableBlock> foldableBlocks;

    final lines = CodeLinesBuilder.textToCodeLines(
      text: text,
      readonlyCommentsByLine: commentParser.getIfReadonlyCommentByLine(),
    );

    if (highlighted == null || language == null) {
      foldableBlocks = const [];
    } else {
      final parser = FoldableBlockParserFactory.provideParser(language);

      parser.parse(
        highlighted: highlighted,
        serviceCommentsSources: serviceCommentsNodesSet,
        lines: lines,
      );

      foldableBlocks = parser.blocks;
      issues.addAll(parser.invalidBlocks.map((b) => b.issue));
    }

    final sections = namedSectionParser?.parse(
          singleLineComments: commentParser.comments,
        ) ??
        const [];
    final sectionsMap = {for (final s in sections) s.name: s};

    _applyNamedSectionsToLines(
      lines: lines.lines,
      sections: sectionsMap,
      readOnlySectionNames: readOnlySectionNames,
    );

    final hiddenRangesBuilder = HiddenRangesBuilder.fromMaps(
      {
        int: _commentsToHiddenRanges(serviceComments),
      },
      textLength: text.length,
    );
    final hiddenRanges = hiddenRangesBuilder.ranges;

    final hiddenLineRangesBuilder = HiddenLineRangesBuilder(
      codeLines: lines,
      hiddenRanges: hiddenRanges,
    );

    return Code._(
      text: text,
      foldableBlocks: foldableBlocks,
      foldedBlocks: {},
      hiddenLineRanges: hiddenLineRangesBuilder.hiddenLineRanges,
      hiddenRanges: hiddenRanges,
      hiddenRangesBuilder: hiddenRangesBuilder,
      highlighted: highlighted,
      issues: issues,
      lines: lines,
      namedSections: sectionsMap,
      serviceComments: serviceComments,
      visibleHighlighted: hiddenRanges.cutHighlighted(highlighted),
      visibleText: hiddenRanges.cutString(text),
    );
  }

  const Code._({
    required this.text,
    required this.foldableBlocks,
    required this.foldedBlocks,
    required this.hiddenLineRanges,
    required this.hiddenRanges,
    required HiddenRangesBuilder hiddenRangesBuilder,
    required this.highlighted,
    required this.issues,
    required this.lines,
    required this.namedSections,
    required this.visibleHighlighted,
    required this.visibleText,
    required this.serviceComments,
  }) : _hiddenRangesBuilder = hiddenRangesBuilder;

  static const empty = Code._(
    text: '',
    foldableBlocks: [],
    foldedBlocks: {},
    hiddenLineRanges: HiddenLineRanges.empty,
    hiddenRanges: HiddenRanges.empty,
    hiddenRangesBuilder: HiddenRangesBuilder.empty,
    highlighted: null,
    issues: [],
    lines: CodeLines.empty,
    namedSections: {},
    visibleHighlighted: null,
    visibleText: '',
    serviceComments: [],
  );

  static void _applyNamedSectionsToLines({
    required List<CodeLine> lines,
    required Map<String, NamedSection> sections,
    required Set<String> readOnlySectionNames,
  }) {
    for (final name in readOnlySectionNames) {
      final section = sections[name];

      if (section == null) {
        continue;
      }

      final lastLineIndex = section.endLine ?? lines.length - 1;

      for (int i = section.startLine; i <= lastLineIndex; i++) {
        lines[i] = lines[i].copyWith(isReadOnly: true);
      }
    }
  }

  static Map<int, HiddenRange> _commentsToHiddenRanges(
    Iterable<SingleLineComment> comments,
  ) {
    return <int, HiddenRange>{
      for (final comment in comments)
        comment.characterIndex: HiddenRange(
          comment.characterIndex,
          comment.characterIndex + comment.outerContent.length,
          firstLine: comment.lineIndex,
          lastLine: comment.lineIndex,
          wholeFirstLine: false,
        ),
    };
  }

  /// Returns whether the current selection has any read-only part.
  bool isReadOnlySelected(TextRange range) {
    if (range.start == -1 && range.end == -1) {
      return false; // Empty selection.
    }

    final startChar = range.normalized.start;
    final endChar = range.normalized.end;

    return isReadOnlyInLineRange(
      TextRange(
        start: lines.characterIndexToLineIndex(startChar),
        end: lines.characterIndexToLineIndex(endChar),
      ),
    );
  }

  /// Returns whether any of the lines of this range is read-only.
  bool isReadOnlyInLineRange(TextRange lineRange) {
    for (int line = lineRange.start; line <= lineRange.end; line++) {
      if (lines.lines[line].isReadOnly) {
        return true;
      }
    }

    return false;
  }

  CodeEditResult getEditResult(TextEditingValue visibleAfter) {
    final visibleRangeAfter = visibleAfter.text.getChangedRange(
      visibleText,
      attributeChangeTo: TextAffinity.upstream,
    );

    if (visibleRangeAfter.start == -1 && visibleRangeAfter.end == -1) {
      return CodeEditResult(
        fullTextAfter: text,
        linesChanged: TextRange.empty,
        charactersChanged: visibleRangeAfter,
      );
    }

    // Recover what exactly was the full old text that was replaced
    // with the new one. For this, inspect the start and end points
    // of the changed part in the old visibleText.
    // If any hidden ranges are collapsed at those points,
    // the trick is to correctly replace them or to correctly preserve them.
    final rangeBefore = TextRange(
      // `end` is responsible for deciding between these two cases when the user
      // entered some text at the point with a hidden range:
      //     text we are adding at the beginning of this line// [START section1]
      //     // [START section1]text we are adding at the beginning of this line
      // We do not want to add that text to the comment and its hidden range.
      // So we must place all hidden ranges collapsed at the end of the diff
      // *after* that diff:
      end: hiddenRanges.recoverPosition(
        visibleText.length - visibleAfter.text.length + visibleRangeAfter.end,
        placeHiddenRanges: TextAffinity.downstream,
      ),

      // If we are inserting (and the old changed part is empty),
      // then using the same `placeHiddenRanges` is straightforward.
      //
      // However, this is also the only option for a non-empty old changed range
      // with a hidden range collapsed at its start. Otherwise we would
      // append to that comment, and the new text will not be visible.
      // Using `TextAffinity.downstream` effectively deletes any such hidden
      // range because it falls into the range of replacement.
      // We may want to reconsider this if we support terminatable hidden range
      // comments like /* ... */ that do not acquire all text to the
      // end of the string.
      start: hiddenRanges.recoverPosition(
        visibleRangeAfter.start,
        placeHiddenRanges: TextAffinity.downstream,
      ),
    );

    final fullTextAfter = rangeBefore.textBefore(text) +
        visibleRangeAfter.textInside(visibleAfter.text) +
        rangeBefore.textAfter(text);

    // The line at [start] has changed for sure.
    // The line at [end - 1] has changed if [end > start].
    // Additionally, the line at [end] has changed if two strings were glued:
    //  - (1) The last old char was '\n' AND
    //  - (2) The char before [start] is not '\n'.
    // We don't need to check (1) because otherwise [end] and [end - 1]
    // are on the same line.
    final lastChar = rangeBefore.end -
        ((rangeBefore.start == 0 || text[rangeBefore.start - 1] == '\n')
            ? 1
            : 0);

    final linesChanged = TextRange(
      start: lines.characterIndexToLineIndex(rangeBefore.start),
      end: lines.characterIndexToLineIndex(max(lastChar, rangeBefore.start)),
    );

    return CodeEditResult(
      fullTextAfter: fullTextAfter,
      linesChanged: linesChanged,
      charactersChanged: visibleRangeAfter,
    );
  }

  Code foldedAt(int line) {
    final block = _getFoldableBlockByStartLine(line);
    if (block == null || foldedBlocks.contains(block)) {
      return this;
    }

    final hiddenRange = foldableBlockToHiddenRange(block);
    final newHiddenRangesBuilder = _hiddenRangesBuilder.copyWithRange(
      block,
      hiddenRange,
    );

    return _copyWithFolding(
      foldedBlocks: {...foldedBlocks, block},
      hiddenRangesBuilder: newHiddenRangesBuilder,
    );
  }

  Code unfoldedAt(int line) {
    final block = _getFoldableBlockByStartLine(line);
    if (block == null || !foldedBlocks.contains(block)) {
      return this;
    }

    return _copyWithFolding(
      foldedBlocks: {...foldedBlocks}..remove(block),
      hiddenRangesBuilder: _hiddenRangesBuilder.copyWithoutRange(block),
    );
  }

  FoldableBlock? _getFoldableBlockByStartLine(int line) {
    return foldableBlocks.firstWhereOrNull(
      (block) => block.firstLine == line,
    );
  }

  HiddenRange foldableBlockToHiddenRange(FoldableBlock block) {
    final firstLine = lines.lines[block.firstLine + 1]; //Keep 1st line visible.
    final lastLine = lines.lines[block.lastLine];

    return HiddenRange(
      firstLine.textRange.start - 1, // Includes '\n' before.
      lastLine.textRange.end - 1, // Excludes '\n' after.
      firstLine: block.firstLine,
      lastLine: block.lastLine,
      wholeFirstLine: false, // Some characters of the first line are visible.
    );
  }

  /// Folds this code at the same blocks as the [oldCode] is.
  Code foldedAs(Code oldCode) {
    final matcher = FoldableBlockMatcher(
      oldBlocks: oldCode.foldableBlocks,
      oldLines: oldCode.lines.lines,
      newBlocks: foldableBlocks,
      newLines: lines.lines,
      oldFoldedBlocks: oldCode.foldedBlocks,
    );

    final newHiddenRangesBuilder = _hiddenRangesBuilder.copyMergingSourceMap({
      FoldableBlock: {
        for (final block in matcher.newFoldedBlocks)
          block: foldableBlockToHiddenRange(block),
      },
    });

    return _copyWithFolding(
      foldedBlocks: matcher.newFoldedBlocks,
      hiddenRangesBuilder: newHiddenRangesBuilder,
    );
  }

  Code _copyWithFolding({
    required Set<FoldableBlock> foldedBlocks,
    required HiddenRangesBuilder hiddenRangesBuilder,
  }) {
    final hiddenRanges = hiddenRangesBuilder.ranges;

    final hiddenLineRangesBuilder = HiddenLineRangesBuilder(
      codeLines: lines,
      hiddenRanges: hiddenRanges,
    );

    return Code._(
      text: text,
      foldableBlocks: foldableBlocks,
      foldedBlocks: foldedBlocks,
      hiddenLineRanges: hiddenLineRangesBuilder.hiddenLineRanges,
      hiddenRanges: hiddenRanges,
      hiddenRangesBuilder: hiddenRangesBuilder,
      highlighted: highlighted,
      issues: issues,
      lines: lines,
      namedSections: namedSections,
      visibleHighlighted: hiddenRanges.cutHighlighted(highlighted),
      visibleText: hiddenRanges.cutString(text),
      serviceComments: serviceComments,
    );
  }
}
