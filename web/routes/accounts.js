'use strict';

const { Router } = require('express');
const { getDb, ok, err, now } = require('./_helper');
const { autoAssignOps } = require('./proxies');

const router = Router();

// GET /api/accounts  ?enabled=1
router.get('/', (req, res) => {
  try {
    const db = getDb();
    let sql = `SELECT a.*,
      COALESCE(ad.uuid, ad.device_id) AS device_uuid,
      (SELECT COUNT(*) FROM tasks t WHERE t.account_id = a.id) AS task_count,
      (SELECT COUNT(*) FROM proxies p WHERE p.account_id = a.id AND p.enabled = 1) AS proxy_count,
      (SELECT r.request_time FROM account_request_logs r WHERE r.account_id = a.id ORDER BY r.id DESC LIMIT 1) AS last_request_time,
      CASE WHEN op.id IS NULL THEN NULL WHEN op.proxy_type = 'direct' THEN '本机直连' ELSE op.host || ':' || op.port END AS ops_proxy_label
      FROM accounts a
      LEFT JOIN proxies op ON op.id = a.ops_proxy_id
      LEFT JOIN account_devices ad ON ad.account_id = a.id`;
    const params = [];
    if (req.query.enabled !== undefined) {
      sql += ' WHERE a.enabled = ?';
      params.push(req.query.enabled === '1' ? 1 : 0);
    }
    sql += ' ORDER BY a.id ASC';
    ok(res, db.prepare(sql).all(...params));
  } catch (e) {
    err(res, e.message, 500);
  }
});

// GET /api/accounts/:id/request-logs
router.get('/:id/request-logs', (req, res) => {
  try {
    const db = getDb();
    if (!db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id)) return err(res, '账号不存在', 404);
    const limit = Math.min(parseInt(req.query.limit) || 200, 500);
    const rows = db.prepare(
      'SELECT * FROM account_request_logs WHERE account_id = ? ORDER BY id DESC LIMIT ?'
    ).all(req.params.id, limit);
    ok(res, rows);
  } catch (e) {
    err(res, e.message, 500);
  }
});

// GET /api/accounts/:id/patients
router.get('/:id/patients', (req, res) => {
  try {
    const db = getDb();
    const account = db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id);
    if (!account) return err(res, '账号不存在', 404);

    const rows = db.prepare('SELECT * FROM account_patients WHERE account_id = ? ORDER BY id').all(req.params.id);
    const patients = rows.map(r => {
      const patientId = String(Math.round(Number(r.patient_id)));
      const idCard = r.id_card || '';
      let gender = '', age = null;
      if (idCard.length >= 18) {
        gender = parseInt(idCard[16]) % 2 === 1 ? '男' : '女';
        age = new Date().getFullYear() - parseInt(idCard.substring(6, 10));
      }
      return { id: patientId, name: r.name || '', gender, age };
    }).filter(p => p.name);
    ok(res, patients);
  } catch (e) {
    err(res, e.message, 500);
  }
});

// PUT /api/accounts/:id
router.put('/:id', (req, res) => {
  try {
    const db = getDb();
    if (!db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id)) return err(res, '账号不存在', 404);
    const b = req.body;
    db.prepare(`UPDATE accounts SET
      enabled          = COALESCE(@enabled, enabled),
      account_type     = COALESCE(@account_type, account_type),
      account_platform = COALESCE(@account_platform, account_platform),
      proxy_max_count  = COALESCE(@proxy_max_count, proxy_max_count),
      updated_at       = @updated_at
      WHERE id = @id`).run({
      id:               req.params.id,
      enabled:          b.enabled != null ? (b.enabled ? 1 : 0) : null,
      account_type:     b.account_type ?? null,
      account_platform: b.account_platform ?? null,
      proxy_max_count:  b.proxy_max_count ?? null,
      updated_at:       now(),
    });
    // 方案 C：代理改为任务级归属，账号级 proxy_max_count 不再触发代理分配。
    ok(res, db.prepare('SELECT * FROM accounts WHERE id = ?').get(req.params.id));
  } catch (e) {
    err(res, e.message, 500);
  }
});

// DELETE /api/accounts/:id
router.delete('/:id', (req, res) => {
  try {
    const db = getDb();
    if (!db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id)) return err(res, '账号不存在', 404);

    // 方案 C：删除该账号下的任务 → task_proxies 经 CASCADE 清理，任务代理自动回到全局空闲池
    db.prepare('DELETE FROM tasks WHERE account_id = ?').run(req.params.id);
    // 删除账号（子表通过 ON DELETE CASCADE 自动清理）
    db.prepare('DELETE FROM accounts WHERE id = ?').run(req.params.id);

    ok(res, { deleted: true });
  } catch (e) {
    err(res, e.message, 500);
  }
});

// PATCH /api/accounts/:id/enabled
router.patch('/:id/enabled', (req, res) => {
  try {
    const db = getDb();
    if (!db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id)) return err(res, '账号不存在', 404);
    const enabled = req.body.enabled ? 1 : 0;
    db.prepare('UPDATE accounts SET enabled = ?, updated_at = ? WHERE id = ?').run(enabled, now(), req.params.id);
    if (!enabled) {
      // 禁用账号时清除其操作代理（任务代理改为任务级，不再随账号释放）
      db.prepare('UPDATE accounts SET ops_proxy_id = NULL, updated_at = ? WHERE id = ?').run(now(), req.params.id);
    } else {
      const account = db.prepare('SELECT * FROM accounts WHERE id = ?').get(req.params.id);
      autoAssignOps(db, account);
    }
    ok(res, db.prepare(`
      SELECT a.*,
        COALESCE(ad.uuid, ad.device_id) AS device_uuid,
        (SELECT COUNT(*) FROM tasks t WHERE t.account_id = a.id) AS task_count,
        (SELECT COUNT(*) FROM proxies p WHERE p.account_id = a.id AND p.enabled = 1) AS proxy_count,
        CASE WHEN op.id IS NULL THEN NULL WHEN op.proxy_type = 'direct' THEN '本机直连' ELSE op.host || ':' || op.port END AS ops_proxy_label
      FROM accounts a
      LEFT JOIN proxies op ON op.id = a.ops_proxy_id
      LEFT JOIN account_devices ad ON ad.account_id = a.id
      WHERE a.id = ?`).get(req.params.id));
  } catch (e) {
    err(res, e.message, 500);
  }
});

// PATCH /api/accounts/:id/ops-proxy  body: { proxyId: number|null }
router.patch('/:id/ops-proxy', (req, res) => {
  try {
    const db = getDb();
    if (!db.prepare('SELECT id FROM accounts WHERE id = ?').get(req.params.id)) return err(res, '账号不存在', 404);
    const { proxyId } = req.body;
    if (proxyId != null) {
      const proxy = db.prepare('SELECT id, proxy_type, port, real_ip FROM proxies WHERE id = ? AND ops_enabled = 1').get(proxyId);
      if (!proxy) return err(res, '代理不存在或未开启操作模式', 404);
      if (proxy.proxy_type === 'ssh' && !proxy.port) {
        return err(res, `该 SSH 代理（${proxy.real_ip || '?'}）为"仅云端"代理，无本地端口，不能作账号操作代理`, 400);
      }
    }
    db.prepare('UPDATE accounts SET ops_proxy_id = ?, updated_at = ? WHERE id = ?').run(proxyId ?? null, now(), req.params.id);
    ok(res, db.prepare(`
      SELECT a.*,
        COALESCE(ad.uuid, ad.device_id) AS device_uuid,
        (SELECT COUNT(*) FROM tasks t WHERE t.account_id = a.id) AS task_count,
        (SELECT COUNT(*) FROM proxies p WHERE p.account_id = a.id AND p.enabled = 1) AS proxy_count,
        CASE WHEN op.id IS NULL THEN NULL WHEN op.proxy_type = 'direct' THEN '本机直连' ELSE op.host || ':' || op.port END AS ops_proxy_label
      FROM accounts a
      LEFT JOIN proxies op ON op.id = a.ops_proxy_id
      LEFT JOIN account_devices ad ON ad.account_id = a.id
      WHERE a.id = ?`).get(req.params.id));
  } catch (e) { err(res, e.message, 500); }
});

module.exports = router;
