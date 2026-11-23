#!/bin/bash
# Log source setup only. The CloudWatch agent is installed later via SSM Run Command.
set -euxo pipefail

dnf install -y httpd rsyslog

# rsyslog writes /var/log/messages and /var/log/secure (AL2023 uses journald only by default)
systemctl enable --now rsyslog

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Project 17 - Log Forwarding</title></head>
<body>
  <h1>Project 17: Log Forwarding to CloudWatch</h1>
  <p>Instance: $INSTANCE_ID</p>
  <p>Every request to this page is written to the Apache access log and shipped to CloudWatch Logs.</p>
</body>
</html>
EOF

systemctl enable --now httpd
logger -t project17 "Web server bootstrap complete on $INSTANCE_ID"
