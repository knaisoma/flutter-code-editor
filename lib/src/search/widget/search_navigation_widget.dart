import 'package:flutter/material.dart';

import '../search_navigation_controller.dart';

const _iconSize = 20.0;

class SearchNavigationWidget extends StatelessWidget {
  final FocusNode patternFocusNode;
  final FocusNode codeFieldFocusNode;
  final SearchNavigationController searchNavigationController;

  const SearchNavigationWidget({
    super.key,
    required this.patternFocusNode,
    required this.codeFieldFocusNode,
    required this.searchNavigationController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: searchNavigationController,
      builder: (context, child) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                hoverColor: Colors.transparent,
                onTap: () {
                  patternFocusNode.unfocus();
                  codeFieldFocusNode.requestFocus();
                  searchNavigationController.movePrevious();
                },
                child: const Icon(
                  Icons.arrow_upward,
                  size: _iconSize,
                ),
              ),
              InkWell(
                hoverColor: Colors.transparent,
                onTap: () {
                  patternFocusNode.unfocus();
                  codeFieldFocusNode.requestFocus();
                  searchNavigationController.moveNext();
                },
                child: const Icon(
                  Icons.arrow_downward,
                  size: _iconSize,
                ),
              ),
            ],
          ),
          Text(
            '${searchNavigationController.value.currentMatchIndex + 1} '
            '/ '
            '${searchNavigationController.value.totalMatchesCount}',
          ),
        ],
      ),
    );
  }
}