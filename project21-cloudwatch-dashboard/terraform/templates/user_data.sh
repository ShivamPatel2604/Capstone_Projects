#!/bin/bash
# Bootstrap: Apache web app + CloudWatch agent publishing memory/disk/CPU metrics.
set -euxo pipefail

dnf install -y httpd amazon-cloudwatch-agent stress-ng

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
IMDS="http://169.254.169.254/latest/meta-data"
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" $IMDS/placement/availability-zone)
SERVER_NAME="${server_name}"

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Project 21 - CloudWatch Monitoring Dashboard</title></head>
<body style="font-family: Arial, sans-serif; text-align: center; margin-top: 60px;">
  <h1>Project 21: CloudWatch Monitoring Dashboard</h1>
  <h2>Served by $SERVER_NAME</h2>
  <p>Instance $INSTANCE_ID in $AZ</p>
  <p>Requests, latency, CPU, memory and disk for this app are graphed on the CloudWatch dashboard.</p>
</body>
</html>
EOF

echo "$SERVER_NAME $INSTANCE_ID $AZ" > /var/www/html/whoami.txt
echo "OK" > /var/www/html/health

# Slow endpoint (~0.3-0.8 s) so the latency graph has something to show under load
mkdir -p /var/www/cgi-bin
cat > /var/www/cgi-bin/slow <<'EOF'
#!/bin/bash
sleep 0.$((RANDOM % 6 + 3))
echo "Content-Type: text/plain"
echo
echo "slow response from $(hostname)"
EOF
chmod 755 /var/www/cgi-bin/slow

systemctl enable --now httpd

# CloudWatch agent: metrics aggregated by InstanceId so the dashboard can graph them per server
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem": {
        "measurement": ["mem_used_percent"]
      },
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["/"],
        "drop_device": true
      },
      "cpu": {
        "measurement": ["cpu_usage_iowait"],
        "totalcpu": true
      },
      "netstat": {
        "measurement": ["tcp_established"]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

logger -t project21 "Bootstrap complete: $SERVER_NAME $INSTANCE_ID in $AZ"
