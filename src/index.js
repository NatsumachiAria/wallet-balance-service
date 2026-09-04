const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 3000;

// DB connection is optional at boot — /health should not depend on it,
// but /balance/:userId does need it. This mirrors a real service where
// liveness and readiness are different concerns.
let pool;
function getPool() {
  if (!pool) {
    pool = new Pool({
      connectionString: process.env.DATABASE_URL,
      connectionTimeoutMillis: 3000,
    });
  }
  return pool;
}

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'wallet-balance-service', uptime: process.uptime() });
});

// Readiness check — verifies DB connectivity, distinct from liveness.
app.get('/ready', async (req, res) => {
  try {
    await getPool().query('SELECT 1');
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    res.status(503).json({ status: 'not_ready', error: err.message });
  }
});

app.get('/balance/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    const result = await getPool().query(
      'SELECT user_id, available_balance, currency FROM wallet_balances WHERE user_id = $1',
      [userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'user not found' });
    }
    res.status(200).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'internal error', detail: err.message });
  }
});

if (require.main === module) {
  app.listen(PORT, () => {
    console.log(`wallet-balance-service listening on port ${PORT}`);
  });
}

module.exports = app;
