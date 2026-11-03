import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/widgets/lume_icon.dart';
import 'dandanplay_client.dart';
import 'danmaku_models.dart';

class DanmakuMatchSelection {
  const DanmakuMatchSelection(this.episode, this.track);
  final DandanplayEpisode episode;
  final DanmakuTrack track;
}

/// Search, select the work, then confirm its episode without stacking drawers.
/// The caller owns the client and persists only a non-empty loaded selection.
class DanmakuMatchSheet extends StatefulWidget {
  const DanmakuMatchSheet({
    super.key,
    required this.client,
    required this.title,
    required this.episode,
    this.serviceLabel,
    this.onChangeService,
  });
  final DandanplayClient client;
  final String title;
  final int episode;
  final String? serviceLabel;
  final VoidCallback? onChangeService;
  @override
  State<DanmakuMatchSheet> createState() => _DanmakuMatchSheetState();
}

class _DanmakuMatchSheetState extends State<DanmakuMatchSheet> {
  late final _title = TextEditingController(
    text: DandanplayClient.searchTitle(widget.title),
  );
  late final _number = TextEditingController(text: '${widget.episode}');
  List<DandanplayEpisode> _items = [];
  String? _workKey, _error;
  DandanplayEpisode? _selected;
  bool _loading = false, _loadingTrack = false, _showOthers = false;
  int _generation = 0;
  String _queryTitle = '';
  int? _queryEpisode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  @override
  void dispose() {
    _generation++;
    _title.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final title = _title.text.trim();
    final number = int.tryParse(_number.text.trim());
    if (title.isEmpty || number == null || number < 1) {
      setState(() => _error = '请填写片名和正确的集数');
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _items = [];
      _workKey = null;
      _selected = null;
      _showOthers = false;
      _queryTitle = title;
      _queryEpisode = number;
    });
    try {
      final items = await widget.client.search(title, episode: number);
      if (!mounted || generation != _generation) return;
      setState(() => _items = items);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = DandanplayClient.describeError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  int _relevance(DandanplayEpisode item) {
    final title = DandanplayClient.normalizedTitle(item.title);
    final query = DandanplayClient.normalizedTitle(_queryTitle);
    if (title == query) return 0;
    final shortest = title.length < query.length ? title.length : query.length;
    final longest = title.length > query.length ? title.length : query.length;
    return shortest >= 3 &&
            shortest / longest >= .75 &&
            (title.contains(query) || query.contains(title))
        ? 1
        : 2;
  }

  Map<String, List<DandanplayEpisode>> get _works {
    final works = <String, List<DandanplayEpisode>>{};
    for (final item in _items) {
      works.putIfAbsent(item.workKey, () => []).add(item);
    }
    return works;
  }

  List<DandanplayEpisode> _episodes(String key) {
    final items = _items.where((item) => item.workKey == key).toList();
    items.sort(
      (a, b) =>
          (a.number ?? DandanplayClient.parsedEpisodeNumber(a.episode) ?? 99999)
              .compareTo(
                b.number ??
                    DandanplayClient.parsedEpisodeNumber(b.episode) ??
                    99999,
              ),
    );
    final seen = <String>{};
    return items.where((item) => seen.add(item.id)).toList();
  }

  void _chooseWork(String key) {
    final episodes = _episodes(key);
    final current = episodes
        .where(
          (item) =>
              (item.number ??
                  DandanplayClient.parsedEpisodeNumber(item.episode)) ==
              _queryEpisode,
        )
        .toList();
    // TMDB 映射条目经常只有 episodeId、没有弹幕，不能当作默认选中项；
    // 同集还有原生来源时优先原生。
    final preferred = current
        .where((item) => item.source.toLowerCase() != 'tmdb')
        .toList();
    setState(() {
      _workKey = key;
      _error = null;
      _selected = preferred.length == 1 && !preferred.single.supplementary
          ? preferred.single
          : null;
    });
  }

  Future<void> _allEpisodes() async {
    final key = _workKey;
    if (key == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.client.search(_queryTitle);
      if (!mounted || generation != _generation) return;
      final episodes = items.where((item) => item.workKey == key).toList();
      setState(() {
        if (episodes.isEmpty) {
          _error = '此服务没有返回这部作品的其他集数';
        } else {
          _items = episodes;
        }
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = DandanplayClient.describeError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _load() async {
    final selected = _selected;
    if (selected == null) return;
    var episode = selected;
    final generation = ++_generation;
    setState(() {
      _loadingTrack = true;
      _error = null;
    });
    try {
      var track = DanmakuTrack.parse([]);
      Object? failure;
      // 选中的条目可能是 TMDB 映射或某个没有弹幕的来源；同作品同集还有
      // 其他非 TMDB 候选时自动换一个，避免用户再搜一次。
      for (final candidate in [
        selected,
        ...DandanplayClient.alternatives(_items, selected),
      ]) {
        if (!mounted || generation != _generation) return;
        DanmakuTrack retry;
        try {
          retry = await widget.client.comments(candidate.id);
        } catch (error) {
          failure = error;
          continue;
        }
        if (!mounted || generation != _generation) return;
        if (retry.isEmpty) continue;
        episode = candidate;
        track = retry;
        break;
      }
      if (track.isEmpty) {
        setState(
          () => _error = failure != null
              ? DandanplayClient.describeError(failure)
              : episode.source.toLowerCase() == 'tmdb'
              ? '官方 TMDB 条目只有作品信息，该集暂无弹幕。请更换为兼容弹幕服务后重新搜索。'
              : '这部作品的该集返回 0 条弹幕（已尝试同集的其他来源），尚未保存关联。请换一集或更换服务。',
        );
        return;
      }
      Navigator.pop(context, DanmakuMatchSelection(episode, track));
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = DandanplayClient.describeError(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingTrack = false);
      }
    }
  }

  Widget? _episodeNote(DandanplayEpisode item) {
    final notes = <String>[
      if (item.source.toLowerCase() == 'tmdb') 'TMDB 映射，可能没有弹幕',
      if (item.supplementary) '附加内容／合集，请核对后手动选择',
      if (!item.supplementary &&
          (item.number ?? DandanplayClient.parsedEpisodeNumber(item.episode)) ==
              _queryEpisode)
        '当前集数',
    ];
    return notes.isEmpty ? null : Text(notes.join(' · '));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildContent);

  Widget _buildContent(BuildContext context, BoxConstraints constraints) {
    final compact = constraints.maxHeight < 280;
    final works = _works.entries.toList()
      ..sort(
        (a, b) =>
            _relevance(a.value.first).compareTo(_relevance(b.value.first)),
      );
    final hasExact = works.any((work) => _relevance(work.value.first) == 0);
    final visible = works
        .where(
          (work) =>
              _showOthers || _relevance(work.value.first) <= (hasExact ? 0 : 1),
        )
        .toList();
    final currentWork = _workKey == null ? null : _episodes(_workKey!);
    final content = Column(
      children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                if (_workKey != null)
                  IconButton(
                    tooltip: '返回作品列表',
                    onPressed: _loadingTrack
                        ? null
                        : () => setState(() {
                            _workKey = null;
                            _selected = null;
                            _error = null;
                          }),
                    icon: const LumeIcon(
                      Icons.arrow_back,
                      slot: 'danmaku.match.back',
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _workKey == null ? '1 · 选择作品' : '2 · 确认集数',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '返回弹幕设置',
                  onPressed: () => Navigator.pop(context),
                  icon: const LumeIcon(
                    Icons.close,
                    slot: 'danmaku.match.close',
                  ),
                ),
              ],
            ),
          ),
        Padding(
          // Preserve the editors and their input connection when the keyboard
          // removes the preceding header in the compact landscape layout.
          key: const ValueKey('danmaku-match-search-fields'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              if (!compact)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '正在播放：${widget.title} · 第${widget.episode}集',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('danmaku-match-editors'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('danmaku-match-title'),
                      controller: _title,
                      enabled: !_loadingTrack,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        labelText: '片名',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      key: const ValueKey('danmaku-match-episode'),
                      controller: _number,
                      enabled: !_loadingTrack,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        labelText: '集数',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '搜索',
                    onPressed: _loading || _loadingTrack ? null : _search,
                    icon: const LumeIcon(
                      Icons.search,
                      slot: 'danmaku.match.search',
                    ),
                  ),
                ],
              ),
              if (!compact && widget.serviceLabel != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.serviceLabel!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (!compact && _error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('danmaku-match-error'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_loading || _loadingTrack) const LinearProgressIndicator(),
        Expanded(
          child: _loading
              ? const Center(child: Text('正在查找作品与集数…'))
              : currentWork != null
              ? ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (currentWork.isNotEmpty)
                      ListTile(
                        title: Text(currentWork.first.workTitle),
                        subtitle: Text(currentWork.first.details),
                      ),
                    for (final item in currentWork)
                      ListTile(
                        key: ValueKey('danmaku-episode-${item.id}'),
                        selected: _selected?.id == item.id,
                        leading: Icon(
                          _selected?.id == item.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(item.episode),
                        subtitle: _episodeNote(item),
                        onTap: _loadingTrack
                            ? null
                            : () => setState(() => _selected = item),
                      ),
                    TextButton(
                      onPressed: _loadingTrack ? null : _allEpisodes,
                      child: const Text('查看这部作品的全部集数'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _items.isEmpty
                              ? '本服务未找到“$_queryTitle”第${_queryEpisode ?? widget.episode}集的弹幕。可修改片名、集数或更换服务。'
                              : '本服务返回的作品与片名不一致，已收起其他结果。',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    for (final work in visible)
                      ListTile(
                        key: ValueKey('danmaku-work-${work.key}'),
                        title: Text(work.value.first.workTitle),
                        subtitle: Text(
                          [
                            work.value.first.details,
                            _relevance(work.value.first) == 0
                                ? '片名一致'
                                : '近似片名，请核对',
                          ].where((s) => s.isNotEmpty).join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _loadingTrack
                            ? null
                            : () => _chooseWork(work.key),
                      ),
                    if (!_showOthers && works.length > visible.length)
                      TextButton(
                        onPressed: () => setState(() => _showOthers = true),
                        child: Text(
                          '展开其他 ${works.length - visible.length} 个近似结果',
                        ),
                      ),
                  ],
                ),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_workKey != null)
                  FilledButton(
                    onPressed: _selected == null || _loading || _loadingTrack
                        ? null
                        : _load,
                    child: Text(_loadingTrack ? '正在加载弹幕…' : '加载所选集弹幕'),
                  ),
                if (!compact && widget.onChangeService != null)
                  TextButton(
                    onPressed: _loadingTrack ? null : widget.onChangeService,
                    child: const Text('更换服务 / 自定义 danmu 地址'),
                  ),
              ],
            ),
          ),
      ],
    );
    return content;
  }
}
