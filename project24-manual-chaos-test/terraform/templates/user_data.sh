#!/bin/bash
# Bootstrap: Apache web server (the service under test) with a /health endpoint
# and a systemd drop-in so that crashes are auto-restarted.
set -euxo pipefail

dnf install -y httpd

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IMDS="http://169.254.169.254/latest/meta-data"
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/placement/availability-zone)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Project 24 - Manual Chaos Test</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; margin-top: 60px; }
    .card { display: inline-block; padding: 30px 50px; border-radius: 10px; color: #fff; background: #2ca02c; }
  </style>
</head>
<body>
  <h1>Project 24: Manual Chaos Test</h1>
  <div class="card">
    <h2>Service is UP</h2>
    <p>${project_name} - $INSTANCE_ID ($AZ)</p>
  </div>
  <p>If you can read this page, httpd has recovered.</p>
</body>
</html>
EOF

# Health endpoint for the monitor: 200 "OK" while httpd is serving
echo "OK" > /var/www/html/health

cat > /etc/httpd/conf.d/no-cache.conf <<'EOF'
<IfModule mod_headers.c>
  Header set Cache-Control "no-store"
</IfModule>
EOF

# Self-healing for crashes only: Restart=on-failure restarts httpd if it dies
# unexpectedly (e.g. SIGKILL), but NOT after an intentional "systemctl stop".
mkdir -p /etc/systemd/system/httpd.service.d
cat > /etc/systemd/system/httpd.service.d/10-restart.conf <<'EOF'
[Unit]
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Restart=on-failure
RestartSec=${restart_delay_secs}
EOF
systemctl daemon-reload

systemctl enable --now httpd

logger -t project24 "Bootstrap complete: httpd up on $INSTANCE_ID in $AZ"
