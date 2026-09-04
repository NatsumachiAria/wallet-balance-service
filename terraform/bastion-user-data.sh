#!/bin/bash
set -eux

# Amazon Linux 2023 ships the SSM agent already, so nothing is installed
# here to enable access. These packages exist only to work on the database.
dnf install -y git jq

# Package names track what the distribution carries; try newest first.
dnf install -y postgresql17 || dnf install -y postgresql16 || dnf install -y postgresql15

# Helper that opens psql using the connection string held in Secrets
# Manager. The password is never typed and never lands in shell history.
cat > /usr/local/bin/db-connect <<'SCRIPT'
#!/bin/bash
set -euo pipefail
URL=$(aws secretsmanager get-secret-value \
  --secret-id "${secret_arn}" \
  --region "${region}" \
  --query SecretString --output text)
exec psql "$URL" "$@"
SCRIPT
chmod +x /usr/local/bin/db-connect

cat > /etc/motd <<'MOTD'

  Maintenance host — private subnet, no inbound rules, no key pair.

    db-connect                       open psql against the app database
    db-connect -f schema.sql         apply a file
    curl http://<alb-dns>/health     test through the load balancer

MOTD
