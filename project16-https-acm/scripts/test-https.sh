#!/bin/bash
# Proves HTTPS works through the ALB and plain HTTP is blocked (or only redirected).
# Usage: ./test-https.sh <alb-or-domain-host> [--self-signed]
#   --self-signed  skip certificate trust checks (needed for the imported self-signed cert)
set -uo pipefail

HOST="${1:?Usage: $0 <alb-or-domain-host> [--self-signed]}"
HOST="${HOST#https://}"; HOST="${HOST#http://}"; HOST="${HOST%/}"
INSECURE=""
[ "${2:-}" = "--self-signed" ] && INSECURE="-k"

echo "=== 1. HTTPS request: https://$HOST/ ==="
curl -sS $INSECURE -o /dev/null -m 10 \
  -w "HTTP status : %{http_code}\nRemote      : %{remote_ip}:%{remote_port}\n" \
  "https://$HOST/" || true
curl -sv $INSECURE -o /dev/null -m 10 "https://$HOST/" 2>&1 \
  | grep -E "SSL connection using|subject:|issuer:|expire date:|SSL certificate verify" || true
echo
echo "Security headers:"
curl -sS $INSECURE -I -m 10 "https://$HOST/" | grep -iE "^HTTP/|strict-transport-security" || true

echo
echo "=== 2. Certificate presented by the ALB ==="
echo | openssl s_client -connect "$HOST:443" -servername "$HOST" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null \
  || echo "openssl not available"

echo
echo "=== 3. TLS protocol versions accepted by the ALB ==="
# SECLEVEL=0 lets the local OpenSSL offer TLS 1.1, so a refusal comes from the ALB policy
for PROTO in tls1_1 tls1_2 tls1_3; do
  CIPHER=$(echo | timeout 10 openssl s_client -connect "$HOST:443" -servername "$HOST" \
    -"$PROTO" -cipher 'DEFAULT:@SECLEVEL=0' 2>/dev/null | awk '/Cipher is/ {print $NF}')
  if [ -n "$CIPHER" ] && [ "$CIPHER" != "(NONE)" ]; then
    RESULT="accepted ($CIPHER)"
  else
    RESULT="rejected"
  fi
  printf "%-8s %s\n" "$PROTO" "$RESULT"
done
echo "Expected: tls1_1 rejected, tls1_2 and tls1_3 accepted"

echo
echo "=== 4. Plain HTTP: http://$HOST/ ==="
CODE=$(curl -s -o /dev/null -m 8 -w "%{http_code}" "http://$HOST/")
RC=$?
LOCATION=$(curl -s -o /dev/null -m 8 -w "%{redirect_url}" "http://$HOST/" 2>/dev/null)
if [ $RC -ne 0 ] || [ "$CODE" = "000" ]; then
  echo "PASS - HTTP blocked: connection to port 80 refused/timed out (curl exit $RC)"
elif [ "$CODE" = "301" ] && [[ "$LOCATION" == https://* ]]; then
  echo "PASS - HTTP not served: $CODE redirect to $LOCATION"
else
  echo "FAIL - HTTP returned $CODE"
fi
