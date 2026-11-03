import 'dart:convert';

/// Explicit descriptor for remote Spider hosts. The host owns Java/DEX/native
/// execution; the phone uses the same media contract as a local JS Spider.
class RemoteSpider {
  static bool matches(String text) =>
      text.trimLeft().startsWith('{') &&
      RegExp(r'"format"\s*:\s*"lume.remote-spider.v1"').hasMatch(text);
  static String convert(String text) {
    final data = jsonDecode(text) as Map;
    final endpoint = Uri.tryParse('${data['endpoint'] ?? ''}');
    if (endpoint == null ||
        !['http', 'https'].contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.fragment.isNotEmpty) {
      throw const FormatException('远程 Spider 需要有效 http(s) endpoint');
    }
    final transport = '${data['transport'] ?? 't4'}';
    if (!['t4', 'rpc'].contains(transport)) {
      throw const FormatException('远程 Spider transport 应为 t4 或 rpc');
    }
    final meta = Map<String, Object?>.from(data['metadata'] as Map? ?? {});
    return '''
// LumeRuntime: module
${meta.isEmpty ? '' : '// LumeSource: ${jsonEncode(meta)}'}
var endpoint = ${jsonEncode(endpoint.toString())};
var transport = ${jsonEncode(transport)};
async function request(method, args, params) {
  var reply;
  if (transport === 'rpc') {
    reply = await LumeSource.http.post(endpoint, JSON.stringify({method:method,args:args}), {headers:{'Content-Type':'application/json'}});
  } else {
    var query = Object.keys(params).map(k=>encodeURIComponent(k)+'='+encodeURIComponent(params[k])).join('&');
    reply = await LumeSource.http.get(endpoint + (endpoint.indexOf('?')<0?'?':'&') + query);
  }
  if (reply.status < 200 || reply.status >= 300) throw new Error('远程 Spider 返回 HTTP ' + reply.status);
  var value = JSON.parse(reply.body || '{}');
  if (transport === 'rpc' && value.ok === false) throw new Error('远程 Spider 执行失败，请检查服务端日志');
  return transport === 'rpc' && value.ok === true ? value.value : value;
}
module.exports = {
  home: filter=>request('homeContent',[filter],{filter:filter?1:0}),
  homeVod: ()=>request('homeVideoContent',[],{ac:'detail'}),
  category: (tid,pg,filter,extend)=>request('categoryContent',[tid,pg,filter,extend],{ac:'detail',t:tid,pg:pg,filter:filter?1:0,ext:JSON.stringify(extend||{})}),
  search: (key,quick,pg)=>request('searchContent',[key,quick,pg],{wd:key,quick:quick?1:0,pg:pg}),
  detail: ids=>request('detailContent',[ids],{ac:'detail',ids:ids.join(',')}),
  play: (flag,id,vip)=>request('playerContent',[flag,id,vip],{play:id,flag:flag})
};
''';
  }
}
