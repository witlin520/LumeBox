import 'dart:async';

import 'package:flutter/material.dart';

import '../util/lume_log.dart';

class StartupTask {
  const StartupTask(this.name, this.run, {this.required = false});
  final String name;
  final Future<void> Function() run;
  final bool required;
}

class StartupIssue {
  const StartupIssue(this.name, this.required);
  final String name;
  final bool required;
}

Future<List<StartupIssue>> initializeAppTasks(
  List<StartupTask> tasks, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final issues = <StartupIssue>[];
  await Future.wait(
    tasks.map((task) async {
      try {
        await Future.sync(task.run).timeout(timeout);
      } catch (error, stack) {
        issues.add(StartupIssue(task.name, task.required));
        LumeLog.error(StateError('启动加载失败：${task.name}：$error'), stack);
      }
    }),
  );
  return issues;
}

/// No application routes are exposed until privacy initialization succeeds.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.initialize,
    required this.child,
    this.onReady,
  });
  final Future<List<StartupIssue>> Function() initialize;
  final Widget child;
  final VoidCallback? onReady;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  List<StartupIssue>? issues;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    setState(() => issues = null);
    List<StartupIssue> result;
    try {
      result = await widget.initialize();
    } catch (error, stack) {
      LumeLog.error(error, stack);
      result = [const StartupIssue('启动初始化', true)];
    }
    if (!mounted) return;
    setState(() => issues = result);
    if (result.isEmpty) enter();
  }

  void enter() {
    setState(() => ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ready) return widget.child;
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'LumeBox',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  if (issues == null) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('正在加载本机设置…'),
                  ] else ...[
                    const Text('部分启动项目未能加载'),
                    const SizedBox(height: 12),
                    for (final issue in issues!) Text(issue.name),
                    const SizedBox(height: 20),
                    FilledButton(onPressed: load, child: const Text('重新加载')),
                    if (!issues!.any((i) => i.required))
                      TextButton(onPressed: enter, child: const Text('继续使用')),
                    if (issues!.any((i) => i.required))
                      const Text('隐私保护尚未就绪，重新加载成功后才能进入。'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
