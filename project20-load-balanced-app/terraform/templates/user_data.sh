#!/bin/bash
# Bootstrap: Apache web server that identifies itself, plus a health check endpoint for the ALB.
set -euxo pipefail

dnf install -y httpd

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IMDS="http://169.254.169.254/latest/meta-data"
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/local-ipv4)
SERVER_NAME="${server_name}"

# Different colour per server so the switch is obvious in the browser
if [ "$SERVER_NAME" = "web-1" ]; then COLOR="#1f77b4"; else COLOR="#2ca02c"; fi

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Project 20 - Load Balanced App</title>
  <meta http-equiv="Cache-Control" content="no-store">
  <style>
    body { font-family: Arial, sans-serif; text-align: center; margin-top: 60px; }
    .card { display: inline-block; padding: 30px 50px; border-radius: 10px; color: #fff; background: $COLOR; }
    td { padding: 4px 12px; text-align: left; }
  </style>
</head>
<body>
  <h1>Project 20: Load Balanced App Deployment</h1>
  <div class="card">
    <h2>Served by $SERVER_NAME</h2>
    <table>
      <tr><td>Instance ID</td><td>$INSTANCE_ID</td></tr>
      <tr><td>Availability Zone</td><td>$AZ</td></tr>
      <tr><td>Private IP</td><td>$PRIVATE_IP</td></tr>
    </table>
  </div>
  <p>Refresh the page - the Application Load Balancer alternates between the healthy servers.</p>
</body>
</html>
EOF

# One-line identity for curl loops
echo "$SERVER_NAME $INSTANCE_ID $AZ $PRIVATE_IP" > /var/www/html/whoami.txt

# ALB health check target: returns 200 "OK" while the file exists
echo "OK" > "/var/www/html${health_check_path}"

# Do not let browsers or the ALB cache the pages
cat > /etc/httpd/conf.d/no-cache.conf <<'EOF'
<IfModule mod_headers.c>
  Header set Cache-Control "no-store"
</IfModule>
EOF

systemctl enable --now httpd

logger -t project20 "Bootstrap complete: $SERVER_NAME $INSTANCE_ID in $AZ"
