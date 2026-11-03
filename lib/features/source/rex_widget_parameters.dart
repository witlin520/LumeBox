import 'package:flutter/material.dart';

import '../../core/js/rex_widget_host.dart';
import '../../core/reading/reading_library.dart';
import '../../core/session/section.dart';
import '../../shared/widgets/glass_card.dart';

class RexWidgetParametersEditor extends StatefulWidget {
  const RexWidgetParametersEditor({
    super.key,
    required this.section,
    required this.sourceId,
  });
  final Section section;
  final String sourceId;
  @override
  State<RexWidgetParametersEditor> createState() => RexWidgetParametersState();
}

class RexWidgetParametersState extends State<RexWidgetParametersEditor> {
  List<Map<String, Object?>> _definitions = [];
  final _controllers = <String, TextEditingController>{};
  final _values = <String, Object?>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Object? _default(Map<String, Object?> definition) {
    if (definition.containsKey('value')) return definition['value'];
    final options = definition['enumOptions'];
    return options is List && options.isNotEmpty && options.first is Map
        ? options.first['value']
        : '';
  }

  Future<void> _load() async {
    try {
      await ReadingLibrary.open(widget.section);
      if (!mounted) return;
      _definitions =
          RexWidgetSettings.definitions(widget.section, widget.sourceId)
              .where((d) => d['name'] is String && d['type'] != 'constant')
              .take(64)
              .toList();
      final saved = RexWidgetSettings.parameters(
        widget.section,
        widget.sourceId,
      );
      for (final definition in _definitions) {
        final name = definition['name'] as String;
        final value = saved.containsKey(name)
            ? saved[name]
            : _default(definition);
        _values[name] = value;
        _controllers[name] = TextEditingController(text: '${value ?? ''}');
      }
      setState(() {});
    } on Object catch (error) {
      if (mounted) setState(() => _error = 'Widget 参数读取失败：$error');
    }
  }

  Future<void> save() async {
    if (_definitions.isEmpty) return;
    for (final d in _definitions) {
      final name = d['name'] as String;
      if (d['type'] != 'enumeration') _values[name] = _controllers[name]!.text;
    }
    await RexWidgetSettings.saveParameters(
      widget.section,
      widget.sourceId,
      _values,
    );
  }

  void reset() {
    setState(() {
      for (final d in _definitions) {
        final name = d['name'] as String;
        _values[name] = _default(d);
        _controllers[name]!.text = '${_values[name] ?? ''}';
      }
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_definitions.isEmpty && _error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Widget 参数'),
            const SizedBox(height: 8),
            for (final definition in _definitions) _field(definition),
            if (_error != null) Text(_error!),
          ],
        ),
      ),
    );
  }

  Widget _field(Map<String, Object?> definition) {
    final name = definition['name'] as String;
    final title = '${definition['title'] ?? name}';
    final options = definition['enumOptions'];
    if (definition['type'] == 'enumeration' && options is List) {
      final values = <String, Map>{
        for (final o in options.whereType<Map>()) '${o['value']}': o,
      };
      final selected = '${_values[name]}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: ValueKey('$name:$selected'),
          initialValue: values.containsKey(selected) ? selected : null,
          decoration: InputDecoration(labelText: title),
          isExpanded: true,
          items: [
            for (final entry in values.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text('${entry.value['title'] ?? entry.key}'),
              ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _values[name] = values[v]!['value']);
          },
        ),
      );
    }
    final private = RegExp(
      r'password|secret|token|cookie|key',
      caseSensitive: false,
    ).hasMatch(name);
    final multiline =
        !private &&
        (_controllers[name]!.text.contains('\n') ||
            RegExp('data|config|sites', caseSensitive: false).hasMatch(name));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[name],
        decoration: InputDecoration(labelText: title),
        obscureText: private,
        autocorrect: !private,
        enableSuggestions: !private,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
      ),
    );
  }
}
