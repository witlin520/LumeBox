// LumeBox REX 明文验收样板；演示剧集与演职员是测试数据，不是真实剧集元数据。
// 视频采用 Blender 开放电影公开样片；不需要账号、API Key 或解密服务。
WidgetMetadata = {
  id: "lumebox.rex.workflow.demo", title: "REX 明文样板", version: "1.1.0", requiredVersion: "0.0.1",
  description: "导入、分页、搜索、详情、双线路选集与实播验收。演职员为演示数据。",
  author: "LumeBox", site: "https://www.bigbuckbunny.org/", detailCacheDuration: 60,
  modules: [{id: "films", title: "开放电影样片", functionName: "loadList", params: [
    {name: "page", type: "page"}, {name: "count", type: "count", value: 2}]}],
  search: {title: "搜索样片", functionName: "search", params: [
    {name: "keyword", type: "input"}, {name: "page", type: "page"}]}
};
var demoFilms = [
  {id: "bunny", title: "大雄兔 Big Buck Bunny", file: "BigBuckBunny", description: "Blender 开放动画电影。这里的三集与两条线路用于验证界面，均播放同一部公开样片；封面和角色为占位演示图。"},
  {id: "steel", title: "钢铁之泪 Tears of Steel", file: "Tears of Steel", description: "Blender 开放电影 Tears of Steel。演示条目，用于搜索、详情与播放验证。"}
];
function demoItem(film) {
  var image = "https://picsum.photos/seed/lumebox-rex-" + film.id + "/780/1170";
  return {id: film.id, type: "url", mediaType: "tv", title: film.title,
    link: "lume-demo:" + film.id, posterPath: image, coverUrl: image, backdropPath: image,
    description: film.description, genreTitle: "开放电影 · 演示", releaseDate: film.id === "bunny" ? "2008" : "2012"};
}
async function loadList(params) {
  var page = Math.max(1, Number(params.page) || 1), count = Math.max(1, Number(params.count) || 2);
  return demoFilms.slice((page - 1) * count, page * count).map(demoItem);
}
async function search(params) {
  if (Number(params.page || 1) > 1) return [];
  var word = String(params.keyword || "").trim().toLowerCase();
  if (!word) return [];
  return demoFilms.filter(function(f) { return (f.title + " " + f.id).toLowerCase().indexOf(word) >= 0; }).map(demoItem);
}
async function loadDetail(link) {
  var film = demoFilms.find(function(f) {return "lume-demo:" + f.id === link;});
  if (!film) return null;
  var item = demoItem(film);
  item.detailPoster = item.posterPath;
  item.genreItems = [{id: "open-film", title: "开放电影"}];
  item.peoples = [{id: "demo-character", title: "演示角色", role: "示例头像", avatar: item.coverUrl}];
  item.episodeItems = ["HLS 主线路", "HLS 备用入口"].map(function(line, route) {
    return {id: "route-" + route, title: line, episodeItems: [1,2,3].map(function(ep) {
      return {id: film.id + "-" + route + "-" + ep, type: "url", title: "第" + ep + "集（同片演示）",
        episode: ep, coverUrl: item.coverUrl, videoUrl: (film.id === "bunny" ? "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8" : "https://test-streams.mux.dev/tos_ismc/main.m3u8") + (route ? "?route=backup" : "")};
    })};
  });
  return item;
}
