#!/bin/bash
# Bootstrap: Apache web server behind the HTTPS-only ALB (TLS is terminated on the ALB).
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
  <title>Project 16 - HTTPS with ACM</title>
  <style>
    body { font-family: Arial, sans-serif; text-align: center; margin-top: 60px; }
    .card { display: inline-block; padding: 30px 50px; border-radius: 10px; color: #fff; background: #2e7d32; }
    td { padding: 4px 12px; text-align: left; }
  </style>
</head>
<body>
  <h1>Project 16: Enable HTTPS using ACM</h1>
  <div class="card">
    <h2>&#128274; Secure connection</h2>
    <table>
      <tr><td>Certificate</td><td>${certificate_mode}</td></tr>
      <tr><td>TLS terminated on</td><td>Application Load Balancer (HTTPS :443)</td></tr>
      <tr><td>Plain HTTP</td><td>${http_mode}</td></tr>
      <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
      <tr><td>Availability Zone</td><td>$AZ</td></tr>
    </table>
  </div>
</body>
</html>
EOF

echo "OK" > /var/www/html/health

# Behind the ALB every request arrived over HTTPS, so tell browsers to always use HTTPS
cat > /etc/httpd/conf.d/security-headers.conf <<'EOF'
<IfModule mod_headers.c>
  Header always set Strict-Transport-Security "max-age=31536000"
  Header always set X-Content-Type-Options "nosniff"
</IfModule>
EOF

systemctl enable --now httpd

logger -t project16 "Bootstrap complete: $INSTANCE_ID in $AZ"
