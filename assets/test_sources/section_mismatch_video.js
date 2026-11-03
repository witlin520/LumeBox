// LumeSource: {"id":"test-section-video","name":"板块隔离测试","version":"1.0.0","category":"video"}
var LumeSource = {
  id: 'test-section-video', name: '板块隔离测试', version: '1.0.0', category: 'video',
  async categories() { return [{id: 'all', title: '全部'}]; },
  async list() { return {items: [], hasMore: false}; },
  async detail() { return null; },
  async chapters() { return []; },
  async content() { return {kind: 'video', url: 'https://example.invalid/video.mp4'}; }
};
