/// Kept only to recognize and remove the retired built-in service catalog.
class DanmakuPresets {
  static const retiredUrls = <String>[
    "https://dm.999.team/87654321",
    "https://danmu.qianting168.com/456765847636987622146901",
    "https://dm.ljiaovm.com/luosen",
    "https://danmu.longemby.com/lilyemby",
    "https://justdanmu.irisnb.com/iris-danmu",
    "https://dandan.wenjian.de/wenjian",
    "https://danmu.cynn.top/cynnsq",
    "https://dmfl.us.ci/87654321",
    "https://danmu.0000996.xyz/",
    "https://dm.taotu.ink/87654321",
    "https://logvardm.278612356.xyz/steven",
    "https://logvar.hhht.cc.cd/87654321",
    "https://dm.66608880.xyz/87654321",
    "https://danmu.iyo.us.ci/theft-dastardly-prognosis-hula-agenda2-dropkick",
  ];

  static bool retired(Map<String, String> source) =>
      (source['id'] ?? '').startsWith('preset-') ||
      (RegExp(r'^弹(?:[1-9]|1[0-4])$').hasMatch(source['name'] ?? '') &&
          retiredUrls.contains(source['url']));
}
