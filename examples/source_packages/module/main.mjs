import {title} from './helper.mjs';
export default {
  categories() { return [{id:'demo', title}]; },
  list() { return {items:[{id:'one', title}], hasMore:false}; },
  detail({id}) { return {id, title}; },
  chapters() { return []; },
  content() { throw new Error('这是模块加载示例，没有真实影片'); }
};
