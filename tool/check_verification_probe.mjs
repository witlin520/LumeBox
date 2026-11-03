import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync('assets/js/verification_probe.js','utf8');
const node = (selectors, props={}) => ({ selectors:selectors.split('|'), id:'',className:'',visible:true,
  getClientRects(){ return this.visible ? [{}] : [] }, ...props });
function inspect({text='',title='',nodes=[],status=200,confirmed=false,elapsed=6000,selectors=[],local}={}) {
  const storage = {length:0};
  const context = vm.createContext({
    document:{title,body:{innerText:text},readyState:'complete',querySelectorAll(selector){
      return nodes.filter(n => n.selectors.includes(selector) || selector.split(',').some(s=>n.selectors.includes(s.trim())));
    }},location:{href:'https://business.example/list',origin:'https://business.example'},
    getComputedStyle:n=>({visibility:n.visible?'visible':'hidden'}),localStorage:local||storage,sessionStorage:storage,
  });
  return vm.runInContext(source,context)(selectors,status,confirmed,elapsed);
}
const fixtures = [
  ['cloudflare',{text:'Just a moment',nodes:[node('iframe',{src:'https://challenges.cloudflare.com/turnstile'})]}],
  ['geetest',{nodes:[node('[id],[class]',{className:'geetest_wrap'}),node('[role="slider"]')]}],
  ['recaptchaV2',{text:"I'm not a robot",nodes:[node('iframe',{src:'https://google.com/recaptcha/api2/anchor'})]}],
  ['recaptchaV3',{nodes:[node('script[src]',{src:'https://google.com/recaptcha/api.js?render=SITEKEY'})]}],
  ['hcaptcha',{nodes:[node('iframe',{src:'https://hcaptcha.com/1'})]}],
  ['tencent',{nodes:[node('iframe',{src:'https://captcha.gtimg.com/1'})]}],
  ['aliyunCaptcha',{nodes:[node('[id],[class]',{className:'aliyun-captcha'})]}],
  ['yidun',{nodes:[node('[id],[class]',{className:'yidun-captcha'})]}],
  ['imageCaptcha',{text:'请输入图中文字',nodes:[node('img[src*="captcha"]'),node('input:not([type="hidden"])')]}],
  ['unknown',{text:'安全验证，点击完成验证',nodes:[node('button')]}],
  ['unknown',{text:'访问验证',nodes:[node('cap-widget[data-cap-api-endpoint]')]}],
  ['unknown',{nodes:[node('cap-widget[data-cap-api-endpoint]')]}],
  ['unknown',{status:419}],['unknown',{status:428}],['unknown',{status:520}],
  ['arkose',{text:'Just a moment',nodes:[node('iframe',{src:'https://arkoselabs.com/1'})]}],
  ['datadome',{text:'DataDome bot protection'}],['blocked',{text:'Access denied'}],
  ['aliyunWaf',{text:'acw_sc__v2 x5sec'}],
  ['tencentWaf',{text:'腾讯云 WAF',nodes:[node('button')]}],
  ['baiduJiasule',{text:'__jsl_clearance_s __jsluid_s'}],
  ['riverse',{text:'FSSBBIl1UgzbN7N' }],
  ['domesticCaptcha',{text:'smidV2 td_cookie',nodes:[node('[role="slider"]')]}],
];
for (const [kind,fixture] of fixtures) assert.equal(inspect(fixture).kind,kind,kind);
for (const text of ['登录后继续，验证码','公告：请稍候','没有找到相关内容','请稍候','加载中','']) {
  assert.equal(inspect({text}).kind,'none',`false positive: ${text}`);
}
assert.equal(inspect({text:'安全验证，点击完成验证',nodes:[node('button'),node('[data-business-content]')]}).kind,'none');
assert.equal(inspect({text:'登录',confirmed:true}).kind,'unknown');
assert.equal(inspect({text:'verification failed, try again, Verified'}).success,false);
assert.equal(inspect({text:'验证成功'}).success,true);
assert.equal(inspect({nodes:[node('[name="g-recaptcha-response"]',{value:'proof'})]}).token,true);
assert.equal(inspect({text:'article',selectors:['.business'],nodes:[node('.business')]}).business,true);
assert.equal(inspect({text:'安全验证，正在计算 javascript proof of work',status:419}).heavy,true);
assert.equal(inspect(fixtures.find(([k])=>k==='recaptchaV3')[1]).heavy,true);
assert.equal(inspect(fixtures.find(([k])=>k==='riverse')[1]).heavy,true);
assert.equal(inspect({text:'FSSBBIl1UgzbN7N',nodes:[node('button')]}).heavy,false);
assert.equal(inspect({nodes:[node('script[src]',{src:'https://google.com/recaptcha/api.js?render=SITEKEY'}),node('[data-business-content]')]}).challenge,false);
const values = new Map(Array.from({length:140},(_,i)=>['key-'+i,'value-'+i]));
values.set('proof','x'.repeat(9000));
const full = inspect({local:{length:values.size,key:i=>[...values.keys()][i],getItem:key=>values.get(key)}});
assert.equal(Object.keys(full.localStorage).length,141);
assert.equal(full.localStorage.proof.length,9000);
console.log(`PASS: ${fixtures.length} provider/status fixtures, false positives, tokens, retry and non-interactive risk`);
