(function (selectors, status, confirmed, elapsed, responseHeaders) {
  'use strict';
  const visible = element => !!element && !!(element.getClientRects().length) &&
    getComputedStyle(element).visibility !== 'hidden';
  const any = selector => { try { return Array.from(document.querySelectorAll(selector)).some(visible); } catch (_) { return false; } };
  const text = (document.title + '\n' + (document.body?.innerText || '')).slice(0, 24000);
  const retry = /验证失败|请重试|try again|please retry|verification failed|incorrect captcha/i.test(text);
  const success = !retry && /验证成功|you are verified|verification (?:successful|complete)|\bverified\b/i.test(text);
  const frames = Array.from(document.querySelectorAll('iframe')).map(f => f.src || '');
  const sources = frames.concat(Array.from(document.querySelectorAll('script[src]')).map(s => s.src)).join('\n');
  const markers = Array.from(document.querySelectorAll('[id],[class]')).slice(0, 3000)
    .map(e => String(e.id || '') + ' ' + String(e.className || '')).join(' ').toLowerCase();
  const evidence = text + '\n' + sources + '\n' + markers + '\n' +
    (document.documentElement?.outerHTML || '').slice(0, 64000) + '\n' + JSON.stringify(responseHeaders || {});
  let kind = 'none', heavy = false;
  if (/arkoselabs\.com|funcaptcha\.com|arkose-iframe|fc-iframe-wrap/i.test(evidence)) { kind = 'arkose'; heavy = true; }
  else if (/datadome\.co|datadome bot protection/i.test(evidence)) { kind = 'datadome'; heavy = true; }
  else if (/akamai|your request is blocked|access denied|无法访问|拒绝访问/i.test(text)) { kind = 'blocked'; heavy = true; }
  else if (/just a moment|checking your browser|ray id|cf-turnstile|cf-challenge|cf-chl-|challenges\.cloudflare\.com|attention required.*cloudflare/i.test(evidence)) kind = 'cloudflare';
  else if (/geetest|gt_slider|geetest_wrap|极验验证/i.test(evidence)) kind = 'geetest';
  else if (/recaptcha|g-recaptcha|i.m not a robot/i.test(evidence)) {
    kind = /recaptcha\/api\.js\?[^\s]*render=(?!explicit)[\w-]+/i.test(sources) && !any('iframe,[class*="recaptcha"]') ? 'recaptchaV3' : 'recaptchaV2';
  }
  else if (/hcaptcha\.com|h-captcha|hcaptcha-box|hcaptcha/i.test(evidence)) kind = 'hcaptcha';
  else if (/captcha\.gtimg\.com|ssl\.captcha\.qq\.com|tc-captcha|tc-slider|腾讯防水墙/i.test(evidence)) kind = 'tencent';
  else if (/captcha\.aliyuncs\.com|aliyun-captcha|botguard/i.test(evidence)) kind = 'aliyunCaptcha';
  else if (/dun\.163\.com|yidun-captcha|ntc-captcha|网易易盾/i.test(evidence)) kind = 'yidun';
  else if (any('img[src*="captcha"],img[class*="captcha"],img[id*="captcha"]') && any('input:not([type="hidden"])') && /验证码|图中文字|captcha/i.test(text)) kind = 'imageCaptcha';
  else if (/acw_sc__v2|x5sec|aliyuncaptcha|_____tmd_____|aliyun_waf/i.test(evidence)) kind = 'aliyunWaf';
  else if (/腾讯云\s*WAF|waf\.qq\.com/i.test(evidence)) kind = 'tencentWaf';
  else if (/__jsl_clearance_s|__jsluid_s|yunjiasu|加速乐|\bjsl\b/i.test(evidence)) kind = 'baiduJiasule';
  else if (/FSSBBIl1UgzbN7N|riverse|瑞数/i.test(evidence)) kind = 'riverse';
  else if (/\bdx-|smidV2|td_cookie|顶象|数美|同盾/i.test(evidence)) kind = 'domesticCaptcha';
  // CAP renders its button inside a shadow root; the document has no button/input.
  const cap = document.querySelectorAll('cap-widget[data-cap-api-endpoint]').length > 0;
  const interactive = cap || any('button,input:not([type="hidden"]),[role="button"],[role="slider"],canvas,[class*="slider"]') ||
    Array.from(document.querySelectorAll('iframe')).some(frame => {
      const rect = frame.getBoundingClientRect ? frame.getBoundingClientRect() : {width:320,height:180};
      return visible(frame) && rect.width >= 20 && rect.height >= 20;
    });
  const generic = /访问验证|安全验证|请稍候|请稍等|点击完成验证|完成验证|拖动滑块|滑动验证|please complete the security check/i.test(text);
  const container = cap || any('[class*="captcha"],[id*="captcha"],[class*="challenge"],[id*="challenge"],[class*="verify"],[id*="verify"],[role="slider"]');
  const excluded = /登录|登錄|sign in|log in|暂无|没有找到|无结果|no results|公告|announcement/i.test(text);
  const wanted = Array.isArray(selectors) ? selectors.filter(s => typeof s === 'string' && s.trim()) : [];
  const business = wanted.length ? wanted.some(any) : !excluded && any(
    'article,video,audio,.video-list,.book-list,.manga-list,.detail-content,.detail-container,.list-container,.search-results,form[role="search"],input[type="search"],[data-business-content]') ||
    (!wanted.length && !excluded && !generic &&
      Array.from(document.querySelectorAll('a[href]')).filter(visible).length >= 3 && text.trim().length > 80);
  const abnormal = [419,428,520].includes(Number(status));
  if (kind === 'riverse' && !interactive && !business) heavy = true;
  const stalled = Number(elapsed) >= 5000 && (text.trim().length < 40 || /loading|加载中/i.test(text));
  if (kind === 'none' && (!excluded || confirmed) && (confirmed ||
      (!business && ((generic && (interactive || container || abnormal)) ||
      (container && interactive) || (abnormal && (generic || stalled || text.trim().length < 40)))))) kind = 'unknown';
  if (!heavy && !business && kind !== 'none' && !interactive &&
      (kind === 'recaptchaV3' || (kind === 'unknown' && abnormal && Number(elapsed) >= 3000) || /javascript.*(?:calculat|计算)|正在计算|proof.of.work/i.test(evidence))) heavy = true;
  const token = ['cf-turnstile-response','g-recaptcha-response','h-captcha-response']
    .some(name => Array.from(document.querySelectorAll('[name="' + name + '"]')).some(e => String(e.value || '').trim()));
  const storage = area => { const result = Object.create(null); try {
    for (let i = 0; i < area.length; i++) { const key = area.key(i); if (key !== null) result[key] = area.getItem(key); }
  } catch (_) {} return result; };
  let local = {}, session = {};
  try { local = storage(localStorage); session = storage(sessionStorage); } catch (_) {}
  const blocking = container || frames.some(src => /challenges\.cloudflare\.com|recaptcha|hcaptcha|geetest|captcha\.gtimg\.com|ssl\.captcha\.qq\.com|captcha\.aliyuncs\.com|dun\.163\.com/i.test(src)) ||
    /just a moment|checking your browser|访问验证|安全验证|拖动滑块|请输入图中文字/i.test(text);
  const verificationFrames = frames.filter(src => /challenges\.cloudflare\.com|recaptcha|hcaptcha|geetest|captcha\.gtimg\.com|ssl\.captcha\.qq\.com|captcha\.aliyuncs\.com|dun\.163\.com/i.test(src));
  const challenge = heavy || (kind !== 'none' && (!business || blocking || confirmed));
  return {kind,heavy,challenge,business,interactive,blocking,retry,success,token,frames,verificationFrames,url:location.href,origin:location.origin,
    ready:document.readyState === 'complete',localStorage:local,sessionStorage:session};
})
