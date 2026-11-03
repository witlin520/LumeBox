import '../../shared/widgets/native_glass_controls.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/bangumi/bangumi_client.dart';
import '../../core/bangumi/bangumi_sync.dart';
import '../../core/theme/lume_theme.dart';
import '../../shared/widgets/glass_card.dart';
import 'settings_ui.dart';

/// Bangumi 账号绑定与自动同步开关。
///
/// 令牌只用于 `api.bgm.tv` 的 Bearer 认证；iOS 存系统钥匙串，其它平台落
/// 应用支持目录。配置备份不包含令牌。
class BangumiSettingsPage extends StatefulWidget {
  const BangumiSettingsPage({super.key});

  @override
  State<BangumiSettingsPage> createState() => _BangumiSettingsPageState();
}

class _BangumiSettingsPageState extends State<BangumiSettingsPage> {
  final settings = BangumiSettings.instance;
  final token = TextEditingController();
  bool loading = true, busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await settings.load();
    final value = await settings.token();
    if (!mounted) return;
    token.text = value;
    setState(() => loading = false);
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (busy) return;
    final raw = token.text.trim();
    if (raw.isEmpty) {
      setState(() => message = '请先填写 Access Token');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await settings.setToken(raw);
      final client = BangumiClient(raw);
      try {
        final user = await client.me();
        settings.username = user.displayName;
        settings.userId = user.id;
        await settings.save();
        if (mounted) {
          setState(() => message = '已连接：${user.displayName}');
        }
      } finally {
        client.close();
      }
    } on BangumiException catch (error) {
      if (mounted) setState(() => message = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => message = '连接失败：请检查令牌与网络（$error）');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _signOut() async {
    await settings.signOut();
    if (!mounted) return;
    token.clear();
    setState(() => message = '已退出 Bangumi；本地进度不受影响');
  }

  @override
  Widget build(BuildContext context) => GlassScaffold(
    effectModule: GlassModule.settings,
    title: 'Bangumi 追番同步',
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        GlassCard(
          radius: 14,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                settings.userId > 0 && settings.username.isNotEmpty
                    ? '已连接 ${settings.username}'
                    : '连接 Bangumi 账号',
                style: TextStyle(
                  fontSize: LumeTypography.titleSize,
                  fontWeight: FontWeight.w600,
                  color: LumeTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在 Bangumi 个人设置 → 开放接口创建 Access Token 后粘贴到这里。'
                '绑定视频作品后，播放到第几集会自动写入 Bangumi 的「在看 / 看过」。',
                style: TextStyle(
                  fontSize: LumeTypography.bodySize,
                  height: 1.6,
                  color: LumeTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (loading)
          const Center(child: CircularProgressIndicator())
        else ...<Widget>[
          TextField(
            controller: token,
            enabled: !busy,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Access Token'),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : _connect,
                  child: Text(busy ? '连接中…' : '保存并连接'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: busy ? null : _signOut,
                child: const Text('退出账号'),
              ),
            ],
          ),
        ],
        if (message != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            message!,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: message!.startsWith('已连接')
                  ? LumeTheme.textPrimary
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 8),
        NativeSwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('播放时自动同步进度'),
          subtitle: const Text('按集数写入 Bangumi；失败不会影响播放'),
          value: settings.autoSync,
          onChanged: (value) {
            settings.autoSync = value;
            unawaited(settings.save());
            setState(() {});
          },
        ),
        const SettingsFooterNote(
          '令牌只用于 api.bgm.tv 的认证：iOS 保存在系统钥匙串，'
          '其它平台保存在应用支持目录；不写入配置备份，也不随日志导出。',
          padding: EdgeInsets.fromLTRB(4, 8, 4, 8),
        ),
      ],
    ),
  );
}
