// services/HeartbeatEndpointPool.js
// 模拟业务心跳的 endpoint 抽样池。
//
// 心跳走在已建好的 TLS channel socket 上（不走 fetch / axios），所以每条 recipe 描述的是
// "原始 HTTP 文本要拼成什么样"——connectionChannel.js 的 buildBusinessHeartbeatRequest 按
// recipe 拼字符串后 socket.write。
//
// 全部 21 条 recipe 来自 patient_4.3.7.apk 反编译 + 实测验证（2026-06-24）：
//   C:\Users\111\Downloads\patient_analysis\API_DOCUMENTATION.md
// 每个接口在 token 为空时均返回 code:0，确认为真正的公开接口。
//
// 通道分两组：
//   mobile-web   (10 个) — Content-Type: application/json, hospitalId Header: 10097, AES 加密
//   yizhu4_gam   (11 个) — Content-Type: application/x-www-form-urlencoded, hospitalId Header: 0, 明文
//
// ⚠️ 本文件随 services/ 一起部署到云端 agent。云端不上传 account/ 目录（DEPLOY.md 明确
// 标记 Web 层专用），所以**禁止从这里 require '../account/...'**——否则 agent 启动直接
// MODULE_NOT_FOUND 崩溃，pm2 看到进程秒挂，健康检查失败。

const HOSPITAL_ID = '10097';

/**
 * Recipe 字段说明：
 *   id              内部稳定 id，UI 勾选与启用配置都用这个
 *   name            UI 展示名
 *   method          'POST'
 *   path            URL 路径
 *   contentType     Content-Type header 值
 *   hospitalIdHdr   header 里 hospitalId 的值（mobile-web 用 '10097'，yizhu4_gam 用 '0'）
 *   bodyTemplate    body 文本，占位符 ${HOSPITAL_ID} 在抽取时替换
 *   encrypted       true 则 body 走 cryptoUtils.encryptData
 */
const RECIPES = [
  // ══════════════════════════════════════════════════════════════
  // mobile-web 通道（10 个）— JSON body, AES 加密
  // ══════════════════════════════════════════════════════════════

  {
    id: 'get_encrypt_type',
    name: '获取加密类型',
    method: 'POST',
    path: '/mobile-web/gam.sys.cid.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: '{}',
    encrypted: false,   // 唯一不加密的 mobile-web 接口
  },
  {
    id: 'system_config',
    name: '系统配置',
    method: 'POST',
    path: '/mobile-web/gam.sys.systemConfig.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"configKey":"WebApplyTimeConfig","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'hosp_info',
    name: '医院信息',
    method: 'POST',
    path: '/mobile-web/more.hospital.note.info.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"type":"HOSPITAL_INFO","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'service_phone',
    name: '医院服务电话',
    method: 'POST',
    path: '/mobile-web/more.hospital.note.info.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"type":"PHONE_NUMBER","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'guide_dept_list',
    name: '导诊科室列表',
    method: 'POST',
    path: '/mobile-web/guiding.depts.info.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"regType":"RESERVATION","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'guide_dept_doc_list',
    name: '导诊科室医生列表',
    method: 'POST',
    path: '/mobile-web/guiding.dept.doctors.info.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"deptId":"124325","regType":"RESERVATION","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'guide_dept_detail',
    name: '导诊科室详情',
    method: 'POST',
    path: '/mobile-web/guiding.dept.detail.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"deptId":"124325","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'famous_doc_list',
    name: '名医列表',
    method: 'POST',
    path: '/mobile-web/guiding.famous.doctors.info.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"unit":"8","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'dept_list_by_type',
    name: '按类型获取科室',
    method: 'POST',
    path: '/mobile-web/gam/guiding.type.depts.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"type":"IMPORTMANT","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },
  {
    id: 'source_doctor_detail',
    name: '号源医生详情',
    method: 'POST',
    path: '/mobile-web/source.doctor.detail.hsr',
    contentType: 'application/json',
    hospitalIdHdr: HOSPITAL_ID,
    bodyTemplate: `{"doctorCode":"101011","hospitalId":"${HOSPITAL_ID}"}`,
    encrypted: true,
  },

  // ══════════════════════════════════════════════════════════════
  // yizhu4_gam 通道（11 个）— form-urlencoded body, 明文（不加密）
  // ══════════════════════════════════════════════════════════════

  {
    id: 'hosp_protocol',
    name: '医院协议（预约须知）',
    method: 'POST',
    path: '/yizhu4_gam/output.protocol.getOne.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `type=YYXY&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'notice',
    name: '联系客服 / 药品快递须知',
    method: 'POST',
    path: '/yizhu4_gam/output.protocol.getOne.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `type=LXKF&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'banners',
    name: '轮播 Banner',
    method: 'POST',
    path: '/yizhu4_gam/carousel.getByHospitalId.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `groupName=%E8%87%AA%E5%8A%A9%E6%9C%8D%E5%8A%A1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'hosp_news',
    name: '医院新闻',
    method: 'POST',
    path: '/yizhu4_gam/hospitalFreshNews.getNewsBySelectCondition.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `word=&current=1&pageSize=10&state=1&isOnHot=1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'hosp_notice',
    name: '医院公告',
    method: 'POST',
    path: '/yizhu4_gam/hospitalAnnounced.getNewsBySelectCondition.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `word=&current=1&pageSize=10&state=1&isOnHot=1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'medical_guide',
    name: '就医指南',
    method: 'POST',
    path: '/yizhu4_gam/medicalGuide.getNewsBySelectCondition.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `word=&current=1&pageSize=10&state=1&isOnHot=1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'health_news',
    name: '健康资讯',
    method: 'POST',
    path: '/yizhu4_gam/healthInformation.getNewsBySelectCondition.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `word=&current=1&pageSize=10&state=1&isOnHot=1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'health_classification',
    name: '健康资讯分类',
    method: 'POST',
    path: '/yizhu4_gam/healthInformation.findClassificationList.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `state=1&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'scrolling_news',
    name: '滚动消息',
    method: 'POST',
    path: '/yizhu4_gam/scrollingNews.viewScrollingNews.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `type=2&hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'common_faq_types',
    name: '常见问题分类',
    method: 'POST',
    path: '/yizhu4_gam/output.BasicCommonQuestion.classfiList.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `hospitalId=${HOSPITAL_ID}`,
    encrypted: false,
  },
  {
    id: 'common_faqs',
    name: '常见问题列表',
    method: 'POST',
    path: '/yizhu4_gam/output.BasicCommonQuestion.list.hsr',
    contentType: 'application/x-www-form-urlencoded;charset=utf-8',
    hospitalIdHdr: '0',
    bodyTemplate: `hospitalId=${HOSPITAL_ID}&classificationId=1`,
    encrypted: false,
  },
];

const RECIPE_BY_ID = new Map(RECIPES.map(r => [r.id, r]));
const ALL_IDS = RECIPES.map(r => r.id);

/**
 * 从启用集合中随机抽 1 条 recipe；启用集合为空或全部未命中时退回全集。
 * @param {string[]|null|undefined} enabledIds  启用的 recipe id 列表（空数组 / 未配置 = 全启用）
 * @returns {object}  recipe 对象
 */
function pickRandomRecipe(enabledIds) {
  let candidates;
  if (!Array.isArray(enabledIds) || enabledIds.length === 0) {
    candidates = RECIPES;
  } else {
    candidates = enabledIds.map(id => RECIPE_BY_ID.get(id)).filter(Boolean);
    if (candidates.length === 0) candidates = RECIPES;
  }
  return candidates[Math.floor(Math.random() * candidates.length)];
}

/** 从 [min, max] 均匀抽一个 int 毫秒数。max < min 时退回 min。 */
function pickInterval(min, max) {
  const lo = Math.max(0, parseInt(min, 10) || 0);
  const hi = Math.max(lo, parseInt(max, 10) || lo);
  if (hi === lo) return lo;
  return lo + Math.floor(Math.random() * (hi - lo + 1));
}

module.exports = {
  RECIPES,
  ALL_IDS,
  pickRandomRecipe,
  pickInterval,
};
