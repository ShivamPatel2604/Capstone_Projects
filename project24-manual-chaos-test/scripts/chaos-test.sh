#!/bin/bash
# Project 24 - Manual chaos test: inject a failure into httpd on the EC2 instance,
# watch it with the health monitor, restore it and verify recovery. Produces:
#   results/<scenario>/chaos-test-output.txt   full console log + evidence
#   results/<scenario>/monitor.log             1-second health checks (raw data)
#   results/<scenario>/incident-notes.md       incident notes with real timeline/metrics
#
# Usage: ./chaos-test.sh [stop|kill] [outage-seconds]
#   stop (default) : "systemctl stop httpd", keep it down for <outage-seconds> (default 30)
#                    while collecting evidence, then restart manually and verify recovery
#   kill           : SIGKILL httpd (simulated crash), take NO action and verify that
#                    systemd (Restart=on-failure) recovers it automatically
set -euo pipefail

SCENARIO="${1:-stop}"
OUTAGE_SECS="${2:-30}"
case "$SCENARIO" in stop | kill) ;; *)
  echo "Usage: $0 [stop|kill] [outage-seconds]" >&2
  exit 2
  ;;
esac

BASELINE_SECS=10   # healthy checks before the fault
STABILITY_SECS=15  # consecutive healthy time required after recovery
DETECT_TIMEOUT=60  # max wait for the monitor to see the outage
RECOVER_TIMEOUT=120

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TF_DIR="$SCRIPT_DIR/../terraform"
mkdir -p "$SCRIPT_DIR/../results/$SCENARIO"
RESULTS_DIR=$(cd "$SCRIPT_DIR/../results/$SCENARIO" && pwd)
OUTPUT="$RESULTS_DIR/chaos-test-output.txt"
MONITOR_LOG="$RESULTS_DIR/monitor.log"
NOTES="$RESULTS_DIR/incident-notes.md"
: >"$OUTPUT"
: >"$MONITOR_LOG"

tf_out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
INSTANCE_ID=$(tf_out instance_id)
HEALTH_URL=$(tf_out health_url)
APP_URL=$(tf_out app_url)
REGION=$(tf_out aws_region)
SERVICE=$(tf_out service_name)

now_ms() { date -u +%s%3N; }
iso() { [ -n "${1:-}" ] && date -u -d "@$(($1 / 1000)).$(printf '%03d' $(($1 % 1000)))" '+%Y-%m-%dT%H:%M:%S.%3NZ' || echo "n/a"; }
secs() { [ -n "${1:-}" ] && [ -n "${2:-}" ] && awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f s", (b - a) / 1000 }' || echo "n/a"; }
log() { echo "[$(date -u '+%H:%M:%S')] $*" | tee -a "$OUTPUT"; }
section() { printf '\n=== %s ===\n' "$*" | tee -a "$OUTPUT"; }

# Run a shell script as root on the instance through SSM Run Command (no SSH) and print its stdout
ssm_run() {
  local desc="$1" b64 cmd_id status=Pending
  b64=$(printf '%s\n' "$2" | base64 -w0)
  cmd_id=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript --comment "Project 24 chaos test: $desc" \
    --parameters "{\"commands\":[\"echo $b64 | base64 -d | bash\"]}" \
    --query "Command.CommandId" --output text)
  for _ in $(seq 1 90); do
    sleep 1
    status=$(aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
      --query "Status" --output text 2>/dev/null || echo Pending)
    case "$status" in Pending | InProgress | Delayed) ;; *) break ;; esac
  done
  aws ssm get-command-invocation --region "$REGION" --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query "StandardOutputContent" --output text
  if [ "$status" != "Success" ]; then
    echo "SSM command '$desc' ($cmd_id) ended with status $status" >&2
    return 1
  fi
}

# Print the epoch-ms of the first monitor check in state $1 at/after epoch-ms $2 (waits up to $3 s)
wait_for_state() {
  local deadline=$(($(date +%s) + $3)) ms
  while [ "$(date +%s)" -lt "$deadline" ]; do
    ms=$(awk -v s="$1" -v t="$2" '$2 >= t && $5 == s { print $2; exit }' "$MONITOR_LOG")
    if [ -n "$ms" ]; then
      echo "$ms"
      return 0
    fi
    sleep 1
  done
  return 1
}

MON_PID=""
FAULT_ACTIVE=0
cleanup() {
  [ -n "$MON_PID" ] && kill "$MON_PID" 2>/dev/null || true
  if [ "$FAULT_ACTIVE" = 1 ]; then
    echo >&2
    echo "WARNING: the test stopped while $SERVICE may still be down. Restore it with:" >&2
    echo "  aws ssm send-command --region $REGION --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript --parameters 'commands=[\"systemctl start $SERVICE\"]'" >&2
  fi
}
trap cleanup EXIT

section "Project 24 manual chaos test - scenario: $SCENARIO"
log "Instance : $INSTANCE_ID ($REGION)"
log "Service  : $SERVICE"
log "Health   : $HEALTH_URL"
log "Results  : $RESULTS_DIR"

# ---------------------------------------------------------------------------
section "1. Pre-flight checks"
PING=""
for _ in $(seq 1 30); do
  PING=$(aws ssm describe-instance-information --region "$REGION" \
    --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --query "InstanceInformationList[0].PingStatus" --output text)
  [ "$PING" = "Online" ] && break
  sleep 10
done
log "SSM status: $PING"
[ "$PING" = "Online" ] || { log "ABORT: instance is not Online in SSM"; exit 1; }

CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$HEALTH_URL" || true)
log "Health check from this VM: HTTP $CODE"
[ "$CODE" = "200" ] || { log "ABORT: service is not healthy before the test - nothing to break"; exit 1; }

# ---------------------------------------------------------------------------
section "2. Steady state (baseline)"
ssm_run "baseline" "
echo \"is-active : \$(systemctl is-active $SERVICE)\"
systemctl show $SERVICE -p MainPID -p NRestarts -p Restart -p ActiveEnterTimestamp
curl -s -o /dev/null -w 'local health: HTTP %{http_code}\n' http://localhost/health
" | tee -a "$OUTPUT"

"$SCRIPT_DIR/monitor.sh" "$HEALTH_URL" "$MONITOR_LOG" 1 2> >(tee -a "$OUTPUT" >&2) &
MON_PID=$!
MONITOR_START_MS=$(now_ms)
log "Health monitor started (pid $MON_PID, 1 check/s) - collecting ${BASELINE_SECS}s of baseline"
sleep "$BASELINE_SECS"
log "Baseline: $(grep -c ' UP$' "$MONITOR_LOG" || true) UP / $(grep -c ' DOWN$' "$MONITOR_LOG" || true) DOWN"

# ---------------------------------------------------------------------------
section "3. Inject failure"
SENT_MS=$(now_ms)
FAULT_ACTIVE=1
if [ "$SCENARIO" = "stop" ]; then
  FAULT_DESC="httpd stopped with 'systemctl stop httpd'"
  INJECT_OUT=$(ssm_run "stop service" "
echo \"ACTION_MS=\$(date -u +%s%3N)\"
systemctl stop $SERVICE
echo \"is-active : \$(systemctl is-active $SERVICE)\"
systemctl show $SERVICE -p ActiveState -p SubState -p Result
")
else
  FAULT_DESC="httpd killed with SIGKILL (simulated crash)"
  INJECT_OUT=$(ssm_run "kill service" "
echo \"MainPID before : \$(systemctl show -p MainPID --value $SERVICE)\"
echo \"ACTION_MS=\$(date -u +%s%3N)\"
systemctl kill -s SIGKILL $SERVICE
sleep 1
echo \"is-active : \$(systemctl is-active $SERVICE)\"
systemctl show $SERVICE -p ActiveState -p SubState -p Result
")
fi
echo "$INJECT_OUT" | tee -a "$OUTPUT"
INJECT_MS=$(sed -n 's/^ACTION_MS=//p' <<<"$INJECT_OUT" | head -n 1)
log "Fault injected at $(iso "$INJECT_MS") (instance clock): $FAULT_DESC"

# ---------------------------------------------------------------------------
section "4. Detect"
if DETECT_MS=$(wait_for_state DOWN "$SENT_MS" "$DETECT_TIMEOUT"); then
  DETECT_CODE=$(awk -v t="$DETECT_MS" '$2 == t { print $3; exit }' "$MONITOR_LOG")
  log "Monitor detected the outage at $(iso "$DETECT_MS") (HTTP $DETECT_CODE) - time to detect $(secs "$INJECT_MS" "$DETECT_MS")"
else
  DETECT_MS=""
  DETECT_CODE=""
  log "Monitor did not observe any failed check within ${DETECT_TIMEOUT}s"
fi

# ---------------------------------------------------------------------------
RESTART_MS=""
EVIDENCE=""
if [ "$SCENARIO" = "stop" ]; then
  section "5. Investigate and restore (manual)"
  log "Responder collecting evidence from the instance via SSM"
  EVIDENCE=$(ssm_run "collect evidence" "
echo '\$ systemctl status $SERVICE'
systemctl status $SERVICE --no-pager -l | head -n 8
echo
echo '\$ journalctl -u $SERVICE (last 10 min)'
journalctl -u $SERVICE --since '-10 min' --no-pager | tail -n 8
echo
echo '\$ ss -ltn sport = :80'
ss -ltn 'sport = :80' | tail -n +2 | grep . || echo 'nothing is listening on port 80'
" || true)
  echo "$EVIDENCE" | tee -a "$OUTPUT"

  WAITED=$((($(now_ms) - ${DETECT_MS:-$SENT_MS}) / 1000))
  if [ "$WAITED" -lt "$OUTAGE_SECS" ]; then
    log "Holding the outage for another $((OUTAGE_SECS - WAITED))s (outage target ${OUTAGE_SECS}s)"
    sleep $((OUTAGE_SECS - WAITED))
  fi

  log "Restarting $SERVICE"
  RESTART_OUT=$(ssm_run "restart service" "
echo \"ACTION_MS=\$(date -u +%s%3N)\"
systemctl start $SERVICE
echo \"is-active : \$(systemctl is-active $SERVICE)\"
curl -s -o /dev/null -w 'local health: HTTP %{http_code}\n' http://localhost/health
")
  echo "$RESTART_OUT" | tee -a "$OUTPUT"
  RESTART_MS=$(sed -n 's/^ACTION_MS=//p' <<<"$RESTART_OUT" | head -n 1)
  log "Manual restart issued at $(iso "$RESTART_MS")"
else
  section "5. Restore (automatic - no human action)"
  log "Waiting for systemd Restart=on-failure to bring $SERVICE back"
fi

# ---------------------------------------------------------------------------
section "6. Verify recovery"
RECOVER_MS=""
if [ -n "$DETECT_MS" ]; then
  if RECOVER_MS=$(wait_for_state UP "$DETECT_MS" "$RECOVER_TIMEOUT"); then
    FAULT_ACTIVE=0
    log "First successful health check at $(iso "$RECOVER_MS") - outage observed for $(secs "$DETECT_MS" "$RECOVER_MS")"
  else
    RECOVER_MS=""
    log "Service did NOT recover within ${RECOVER_TIMEOUT}s"
  fi
else
  FAULT_ACTIVE=0
fi

log "Stability window: ${STABILITY_SECS}s of continuous health checks"
sleep "$STABILITY_SECS"
STABLE_MS=$(now_ms)
REF_MS="${RECOVER_MS:-$SENT_MS}"
POST_UP=$(awk -v t="$REF_MS" '$2 >= t && $5 == "UP"' "$MONITOR_LOG" | wc -l)
POST_DOWN=$(awk -v t="$REF_MS" '$2 > t && $5 == "DOWN"' "$MONITOR_LOG" | wc -l)
log "After recovery: $POST_UP UP / $POST_DOWN DOWN checks"

POST_STATE=$(ssm_run "post-recovery check" "
echo \"is-active : \$(systemctl is-active $SERVICE)\"
systemctl show $SERVICE -p MainPID -p NRestarts -p ActiveEnterTimestamp
curl -s -o /dev/null -w 'local health: HTTP %{http_code}\n' http://localhost/health
echo
journalctl -u $SERVICE --since '-10 min' --no-pager | tail -n 6
" || true)
echo "$POST_STATE" | tee -a "$OUTPUT"

if curl -s --max-time 5 "$APP_URL" | grep -q "Service is UP"; then PAGE_OK=yes; else PAGE_OK=no; fi
log "App page served from this VM: $PAGE_OK"

kill "$MON_PID" 2>/dev/null || true
MON_PID=""

# ---------------------------------------------------------------------------
section "7. Results"
TOTAL=$(wc -l <"$MONITOR_LOG")
UP=$(grep -c ' UP$' "$MONITOR_LOG" || true)
DOWN=$(grep -c ' DOWN$' "$MONITOR_LOG" || true)
AVAIL=$(awk -v u="$UP" -v t="$TOTAL" 'BEGIN { printf "%.1f%%", t ? 100 * u / t : 0 }')
DOWN_CODES=$(awk '$5 == "DOWN" { print $3 }' "$MONITOR_LOG" | sort | uniq -c | awk '{ printf "%s%s x HTTP %s", sep, $1, $2; sep = ", " }')
[ -n "$DOWN_CODES" ] || DOWN_CODES="none"

if grep -q '^is-active : active' <<<"$POST_STATE" && [ "$PAGE_OK" = yes ] && [ "$POST_DOWN" -eq 0 ] &&
  { [ -z "$DETECT_MS" ] || [ -n "$RECOVER_MS" ]; }; then
  RESULT=PASS
else
  RESULT=FAIL
fi

{
  printf '%-34s %s\n' "Scenario" "$SCENARIO ($FAULT_DESC)"
  printf '%-34s %s\n' "Fault injected" "$(iso "$INJECT_MS")"
  printf '%-34s %s\n' "Outage detected" "$(iso "$DETECT_MS")"
  printf '%-34s %s\n' "Restart issued" "$([ -n "$RESTART_MS" ] && iso "$RESTART_MS" || echo "n/a (automatic)")"
  printf '%-34s %s\n' "Service recovered" "$(iso "$RECOVER_MS")"
  printf '%-34s %s\n' "Time to detect (MTTD)" "$(secs "$INJECT_MS" "$DETECT_MS")"
  printf '%-34s %s\n' "Time to recover (MTTR, from fault)" "$(secs "$INJECT_MS" "$RECOVER_MS")"
  printf '%-34s %s\n' "Observed downtime (monitor)" "$(secs "$DETECT_MS" "$RECOVER_MS")"
  printf '%-34s %s\n' "Restart -> healthy" "$(secs "$RESTART_MS" "$RECOVER_MS")"
  printf '%-34s %s\n' "Health checks" "$TOTAL total, $UP UP, $DOWN DOWN ($DOWN_CODES)"
  printf '%-34s %s\n' "Availability during test" "$AVAIL"
  printf '%-34s %s\n' "RESULT" "$RESULT"
} | tee -a "$OUTPUT"

# ---------------------------------------------------------------------------
# Monitor excerpt around the outage, long DOWN runs collapsed
EXCERPT_FROM=$((${DETECT_MS:-$SENT_MS} - 3000))
EXCERPT_TO=$((${RECOVER_MS:-$STABLE_MS} + 3000))
EXCERPT=$(awk -v a="$EXCERPT_FROM" -v b="$EXCERPT_TO" '
  $2 < a || $2 > b { next }
  $5 == "DOWN" { if (++d <= 3) print; else { held = $0; skipped++ }; next }
  { if (skipped > 1) print "... " skipped - 1 " more DOWN checks ..."; if (skipped) print held; d = 0; skipped = 0; print }
  END { if (skipped > 1) print "... " skipped - 1 " more DOWN checks ..."; if (skipped) print held }
' "$MONITOR_LOG")

BT='`'
if [ "$SCENARIO" = "stop" ]; then
  TITLE="Web service outage - httpd stopped (manual chaos test)"
  ROOT_CAUSE="httpd was stopped cleanly with ${BT}systemctl stop httpd${BT} as a deliberate fault injection. A clean stop is not a failure to systemd, so the ${BT}Restart=on-failure${BT} policy correctly did **not** restart it: the service stayed down until a responder restored it."
  RESOLUTION="Manual restart through SSM Run Command (no SSH): ${BT}systemctl start httpd${BT}."
  WENT_WELL="- The synthetic monitor flagged the outage within $(secs "$INJECT_MS" "$DETECT_MS") of the fault.
- SSM Run Command gave root access for diagnosis and restart without SSH keys or an open port 22.
- httpd was serving again $(secs "$RESTART_MS" "$RECOVER_MS") after the restart command; no data or config was lost."
  IMPROVE="- Recovery depended entirely on a human: most of the downtime was response time, not restart time.
- Detection relied on someone watching the monitor - there was no alarm or page.
- A single instance is a single point of failure: every failed check was a user-facing error."
  ACTIONS="| 1 | Add a CloudWatch alarm (Route 53 health check or CloudWatch Synthetics) with SNS notification on /health | Open |
| 2 | Put the service behind an ALB with 2+ instances in an Auto Scaling group (see Project 20) | Open |
| 3 | Turn the manual restart into a runbook / SSM Automation document so recovery is one click | Open |"
else
  TITLE="Web service crash - httpd killed (manual chaos test)"
  ROOT_CAUSE="All httpd processes were killed with SIGKILL (${BT}systemctl kill -s SIGKILL httpd${BT}) to simulate a crash such as an OOM kill. systemd recorded an unclean exit (${BT}Result=signal${BT}) and, as configured by ${BT}Restart=on-failure${BT} / ${BT}RestartSec${BT}, restarted the service automatically."
  RESOLUTION="Automatic: systemd restarted httpd. No human action was taken."
  WENT_WELL="- Self-healing worked: systemd restarted httpd with no human involvement.
- Recovery time was bounded by ${BT}RestartSec${BT} rather than by response time.
- The synthetic monitor captured the short outage, giving evidence that the auto-restart works."
  IMPROVE="- There was still a user-visible outage of $(secs "$DETECT_MS" "$RECOVER_MS"), roughly ${BT}RestartSec${BT} plus start-up time.
- Nobody was notified of the crash; repeated crashes could go unnoticed until ${BT}StartLimitBurst${BT} is hit and systemd gives up.
- A single instance is a single point of failure."
  ACTIONS="| 1 | Alarm on restarts (journal / CloudWatch agent) so crashes are investigated, not just healed | Open |
| 2 | Run 2+ instances behind an ALB so one crash does not cause downtime (see Project 20) | Open |
| 3 | Tune ${BT}RestartSec${BT} and keep ${BT}StartLimitBurst${BT} to avoid restart loops | Open |"
fi

cat >"$NOTES" <<EOF
# Incident Notes: ${TITLE}

| Field | Value |
| --- | --- |
| Incident date | $(date -u -d "@$((${INJECT_MS:-$SENT_MS} / 1000))" '+%Y-%m-%d') |
| Type | Planned chaos test (game day), scenario ${BT}${SCENARIO}${BT} |
| Severity | SEV-3 (test environment, no real users) |
| Service | ${BT}${SERVICE}${BT} on EC2 ${BT}${INSTANCE_ID}${BT} (${REGION}) |
| Health check | ${BT}${HEALTH_URL}${BT}, 1 check/s from the Linux VM |
| Result | **${RESULT}** - $([ "$RESULT" = PASS ] && echo "service recovered and stayed healthy" || echo "recovery not verified, see chaos-test-output.txt") |

## Summary
${FAULT_DESC^} at $(iso "$INJECT_MS"). The health monitor detected the outage after $(secs "$INJECT_MS" "$DETECT_MS") and the service was serving traffic again at $(iso "$RECOVER_MS"), $(secs "$INJECT_MS" "$RECOVER_MS") after the fault. During the ${STABILITY_SECS}s verification window that followed, ${POST_DOWN} health checks failed.

## Impact
- ${DOWN} of ${TOTAL} health checks failed (${DOWN_CODES}); availability during the test window: ${AVAIL}.
- Observed downtime: $(secs "$DETECT_MS" "$RECOVER_MS"). Every request in that window would have failed (single instance, no load balancer).
- No data loss: the site content is static and unchanged.

## Timeline (UTC)
| Time | Event |
| --- | --- |
| $(iso "$MONITOR_START_MS") | Health monitor started, service healthy (baseline) |
| $(iso "$INJECT_MS") | **Fault injected**: ${FAULT_DESC} |
| $(iso "$DETECT_MS") | **Detected**: first failed health check (HTTP ${DETECT_CODE:-n/a}) |
$( [ "$SCENARIO" = stop ] && echo "| $(iso "$RESTART_MS") | **Restart issued**: ${BT}systemctl start httpd${BT} via SSM after collecting evidence |" || echo "| - | No human action - waiting for systemd auto-restart |" )
| $(iso "$RECOVER_MS") | **Recovered**: first successful health check |
| $(iso "$STABLE_MS") | Stability window passed (${POST_UP} UP / ${POST_DOWN} DOWN), incident closed |

## Metrics
| Metric | Value |
| --- | --- |
| Time to detect (MTTD) | $(secs "$INJECT_MS" "$DETECT_MS") |
| Time to recover (MTTR, fault -> healthy) | $(secs "$INJECT_MS" "$RECOVER_MS") |
| Observed downtime (first failed -> first good check) | $(secs "$DETECT_MS" "$RECOVER_MS") |
| Restart command -> healthy | $(secs "$RESTART_MS" "$RECOVER_MS") |
| Failed / total health checks | ${DOWN} / ${TOTAL} |

## Detection
The outage was detected by the synthetic monitor (${BT}scripts/monitor.sh${BT}) polling ${BT}/health${BT} every second. HTTP ${BT}000${BT} means the TCP connection was refused because nothing was listening on port 80.

## Root cause
${ROOT_CAUSE}

## Resolution and recovery verification
${RESOLUTION}

Recovery was verified by:
1. The monitor returning to HTTP 200 and staying UP for ${STABILITY_SECS}s (${POST_UP} UP / ${POST_DOWN} DOWN checks).
2. ${BT}systemctl is-active httpd${BT} = ${BT}$(sed -n 's/^is-active : //p' <<<"$POST_STATE" | head -n 1)${BT} on the instance and local ${BT}/health${BT} returning 200.
3. The application page loading from the VM with the "Service is UP" banner: ${PAGE_OK}.

## Evidence
Monitor log around the outage (${BT}<time> <epoch-ms> <http-code> <latency> <state>${BT}):
${BT}${BT}${BT}
${EXCERPT}
${BT}${BT}${BT}
$( [ -n "$EVIDENCE" ] && printf '\nInstance state during the outage (SSM):\n%s\n%s\n%s\n' "${BT}${BT}${BT}" "$EVIDENCE" "${BT}${BT}${BT}" || true )

Service state after recovery (SSM):
${BT}${BT}${BT}
${POST_STATE}
${BT}${BT}${BT}

Full console log: ${BT}chaos-test-output.txt${BT}; raw checks: ${BT}monitor.log${BT}.

## What went well
${WENT_WELL}

## What could be improved
${IMPROVE}

## Action items
| # | Action | Status |
| --- | --- | --- |
${ACTIONS}
EOF

echo | tee -a "$OUTPUT"
log "Incident notes written to $NOTES"
log "Console log saved to   $OUTPUT"
[ "$RESULT" = PASS ]
