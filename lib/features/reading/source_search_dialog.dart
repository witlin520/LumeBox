import '../../shared/widgets/network_owned_state.dart';
import '../../core/net/network_cancellation.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/reading/reading_library.dart';
import '../../core/source/source.dart';
import 'section_toolbar.dart';

class SourceSearchDialog extends StatefulWidget {
  const SourceSearchDialog({
    super.key,
    required this.source,
    required this.library,
    required this.initialQuery,
    this.title,
    this.candidateTitles = const [],
  });
  final DataSource? source;
  final ReadingLibrary library;
  final String initialQuery;
  final String? title;
  final List<String> candidateTitles;
  @override
  State<SourceSearchDialog> createState() => _SourceSearchDialogState();
}

class _SourceSearchDialogState extends State<SourceSearchDialog>
    with NetworkOwnedState<SourceSearchDialog> {
  late final input = TextEditingController(text: widget.initialQuery);
  late final history = SearchHistoryStore(
    widget.library.section,
    widget.library,
  );
  List<String> suggestions = [];
  Timer? timer;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    suggestions = SearchSuggestions(
      source: widget.source,
      history: history.load(),
      candidates: widget.candidateTitles,
    ).localForKeyword(input.text);
    if (input.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) changed(input.text);
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    revision++;
    input.dispose();
    super.dispose();
  }

  void changed(String value) {
    timer?.cancel();
    networkRequests.cancelAll();
    final token = ++revision;
    final query = value.trim();
    setState(
      () => suggestions = SearchSuggestions(
        source: widget.source,
        history: history.load(),
        candidates: widget.candidateTitles,
      ).localForKeyword(query),
    );
    if (query.isEmpty || widget.source is! SuggestCapable) return;
    timer = Timer(const Duration(milliseconds: 300), () async {
      List<String> found;
      try {
        found = await networkRequests.run(
          'suggestions',
          () => SearchSuggestions(
            source: widget.source,
            history: history.load(),
            candidates: widget.candidateTitles,
          ).forKeyword(query),
        );
      } on NetworkCancelled {
        return;
      }
      if (!mounted || token != revision || input.text.trim() != query) return;
      setState(() => suggestions = found);
    });
  }

  void submit(String value) {
    final query = value.trim();
    if (query.isNotEmpty) history.remember(query);
    Navigator.pop(context, query);
  }

  TextSpan highlighted(String title) {
    final query = input.text.trim();
    if (query.isEmpty) return TextSpan(text: title);
    final matches = RegExp(
      RegExp.escape(query),
      caseSensitive: false,
    ).allMatches(title);
    final spans = <TextSpan>[];
    var offset = 0;
    for (final match in matches) {
      spans.add(TextSpan(text: title.substring(offset, match.start)));
      spans.add(
        TextSpan(
          text: title.substring(match.start, match.end),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      offset = match.end;
    }
    spans.add(TextSpan(text: title.substring(offset)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title ?? '搜索 · ${widget.source?.name ?? '当前站点'}'),
    content: TextFieldTapRegion(
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: input,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: changed,
              onSubmitted: submit,
              onTapOutside: (_) {
                timer?.cancel();
                networkRequests.cancelAll();
                revision++;
                setState(() => suggestions = []);
                FocusScope.of(context).unfocus();
              },
            ),
            if (input.text.trim().isEmpty && suggestions.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    history.clear();
                    setState(() => suggestions = []);
                  },
                  child: const Text('清空全部历史'),
                ),
              ),
            if (suggestions.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final title in suggestions)
                      ListTile(
                        dense: true,
                        title: Text.rich(highlighted(title)),
                        onTap: () => submit(title),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => submit(''), child: const Text('清空')),
      FilledButton(
        onPressed: () => submit(input.text),
        child: const Text('搜索'),
      ),
    ],
  );
}
