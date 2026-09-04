CREATE TABLE IF NOT EXISTS wallet_balances (
    user_id VARCHAR(64) PRIMARY KEY,
    available_balance NUMERIC(12, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'THB'
);

INSERT INTO wallet_balances (user_id, available_balance, currency) VALUES
    ('user-001', 4250.00, 'THB'),
    ('user-002', 1875.50, 'THB'),
    ('user-003', 0.00, 'THB')
ON CONFLICT (user_id) DO NOTHING;
