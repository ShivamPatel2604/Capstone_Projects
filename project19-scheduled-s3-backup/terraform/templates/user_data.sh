#!/bin/bash
# Bootstrap: web server (log source), cron daemon and the S3 log backup script.
# The cron job that runs the script is created afterwards via SSM Run Command.
set -euxo pipefail

dnf install -y httpd rsyslog cronie

# rsyslog writes /var/log/messages, /var/log/secure and /var/log/cron
systemctl enable --now rsyslog
systemctl enable --now crond

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head><title>Project 19 - Scheduled S3 Backup</title></head>
<body>
  <h1>Project 19: Scheduled S3 Backup</h1>
  <p>Instance: $INSTANCE_ID</p>
  <p>Apache and system logs on this server are archived and uploaded to Amazon S3 by a cron job.</p>
</body>
</html>
EOF

systemctl enable --now httpd

# ---------------------------------------------------------------------------
# Backup script: tar + gzip the logs and upload them to S3
# ---------------------------------------------------------------------------
cat > /usr/local/bin/s3-log-backup.sh <<'SCRIPT'
#!/bin/bash
# Archives server logs and uploads them to S3.
# Key layout: s3://<bucket>/<prefix>/<instance-id>/YYYY/MM/DD/logs-<instance-id>-<timestamp>.tar.gz
set -euo pipefail

BUCKET="${bucket_name}"
PREFIX="${backup_prefix}"
REGION="${aws_region}"
LOG_PATHS="var/log/httpd var/log/messages var/log/secure var/log/cron"

# Skip this run if the previous one is still in progress
exec 9>/var/run/s3-log-backup.lock
flock -n 9 || { echo "$(date -u +%FT%TZ) previous backup still running, skipping"; exit 0; }

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
DATE_PATH=$(date -u +%Y/%m/%d)
ARCHIVE="/tmp/logs-$INSTANCE_ID-$TIMESTAMP.tar.gz"
KEY="$PREFIX/$INSTANCE_ID/$DATE_PATH/$(basename "$ARCHIVE")"
trap 'rm -f "$ARCHIVE"' EXIT

SOURCES=""
for p in $LOG_PATHS; do
  if [ -e "/$p" ]; then SOURCES="$SOURCES $p"; fi
done

# Exit code 1 only means a log file changed while it was being read
tar -czf "$ARCHIVE" -C / --warning=no-file-changed $SOURCES || [ $? -eq 1 ]

SIZE=$(stat -c %s "$ARCHIVE")
SHA256=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)

aws s3 cp "$ARCHIVE" "s3://$BUCKET/$KEY" --region "$REGION" --only-show-errors \
  --metadata "sha256=$SHA256,source-host=$(hostname)"

echo "$(date -u +%FT%TZ) uploaded s3://$BUCKET/$KEY ($SIZE bytes, sha256=$SHA256)"
SCRIPT

chmod 755 /usr/local/bin/s3-log-backup.sh
touch /var/log/s3-backup.log

logger -t project19 "Bootstrap complete on $INSTANCE_ID - backup script installed, cron job not yet created"
