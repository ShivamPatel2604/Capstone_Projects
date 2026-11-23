# Incident Notes: Web service outage - httpd stopped (manual chaos test)

| Field | Value |
| --- | --- |
| Incident date | 2026-11-23 |
| Type | Planned chaos test (game day), scenario `stop` |
| Severity | SEV-3 (test environment, no real users) |
| Service | `httpd` on EC2 `i-021a02f768db01b76` (ap-south-1) |
| Health check | `http://13.233.196.155/health`, 1 check/s from the Linux VM |
| Result | **PASS** - service recovered and stayed healthy |

## Summary
Fault injected at 2026-11-23T15:15:45.402Z: httpd stopped with 'systemctl stop httpd'. The health monitor detected the outage after 0.3 s and the service was serving traffic again at 2026-11-23T15:16:18.255Z, 32.9 s after the fault. During the 15s verification window that followed, 0 health checks failed.

## Impact
- 32 of 63 health checks failed (32 x HTTP 000); availability during the test window: 49.2%.
- Observed downtime: 32.6 s. Every request in that window would have failed (single instance, no load balancer).
- No data loss: the site content is static and unchanged.

## Timeline (UTC)
| Time | Event |
| --- | --- |
| 2026-11-23T15:15:34.433Z | Health monitor started, service healthy (baseline) |
| 2026-11-23T15:15:45.402Z | **Fault injected**: httpd stopped with 'systemctl stop httpd' |
| 2026-11-23T15:15:45.698Z | **Detected**: first failed health check (HTTP 000) |
| 2026-11-23T15:16:17.477Z | **Restart issued**: `systemctl start httpd` via SSM after collecting evidence |
| 2026-11-23T15:16:18.255Z | **Recovered**: first successful health check |
| 2026-11-23T15:16:35.056Z | Stability window passed (17 UP / 0 DOWN), incident closed |

## Metrics
| Metric | Value |
| --- | --- |
| Time to detect (MTTD) | 0.3 s |
| Time to recover (MTTR, fault -> healthy) | 32.9 s |
| Observed downtime (first failed -> first good check) | 32.6 s |
| Restart command -> healthy | 0.8 s |
| Failed / total health checks | 32 / 63 |

## Detection
The outage was detected by the synthetic monitor (`scripts/monitor.sh`) polling `/health` every second. HTTP `000` means the TCP connection was refused because nothing was listening on port 80.

## Root cause
httpd was stopped cleanly with `systemctl stop httpd` as a deliberate fault injection. A clean stop is not a failure to systemd, so the `Restart=on-failure` policy correctly did **not** restart it: the service stayed down until a responder restored it.

## Resolution and recovery verification
Manual restart through SSM Run Command (no SSH): `systemctl start httpd`.

Recovery was verified by:
1. The monitor returning to HTTP 200 and staying UP for 15s (17 UP / 0 DOWN checks).
2. `systemctl is-active httpd` = `active` on the instance and local `/health` returning 200.
3. The application page loading from the VM with the "Service is UP" banner: yes.

## Evidence
Monitor log around the outage (`<time> <epoch-ms> <http-code> <latency> <state>`):
```
2026-11-23T15:15:43.652Z 1795446943652 200 0.012238 UP
2026-11-23T15:15:44.675Z 1795446944675 200 0.011587 UP
2026-11-23T15:15:45.698Z 1795446945698 000 0.006333 DOWN
2026-11-23T15:15:46.714Z 1795446946714 000 0.006637 DOWN
2026-11-23T15:15:47.732Z 1795446947732 000 0.007315 DOWN
... 28 more DOWN checks ...
2026-11-23T15:16:17.235Z 1795446977235 000 0.006647 DOWN
2026-11-23T15:16:18.255Z 1795446978255 200 0.013006 UP
2026-11-23T15:16:19.279Z 1795446979279 200 0.013188 UP
2026-11-23T15:16:20.303Z 1795446980303 200 0.010802 UP
```

Instance state during the outage (SSM):
```
$ systemctl status httpd
○ httpd.service - The Apache HTTP Server
     Loaded: loaded (/usr/lib/systemd/system/httpd.service; enabled; preset: disabled)
    Drop-In: /etc/systemd/system/httpd.service.d
             └─10-restart.conf
     Active: inactive (dead) since Mon 2026-11-23 15:15:46 UTC; 2s ago
   Duration: 4min 11.068s
       Docs: man:httpd.service(8)
    Process: 4777 ExecStart=/usr/sbin/httpd $OPTIONS -DFOREGROUND (code=exited, status=0/SUCCESS)

$ journalctl -u httpd (last 10 min)
Nov 23 15:11:34 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Starting httpd.service - The Apache HTTP Server...
Nov 23 15:11:34 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Started httpd.service - The Apache HTTP Server.
Nov 23 15:11:34 ip-10-24-1-238.ap-south-1.compute.internal httpd[4777]: Server configured, listening on: port 80
Nov 23 15:15:45 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Stopping httpd.service - The Apache HTTP Server...
Nov 23 15:15:46 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: httpd.service: Deactivated successfully.
Nov 23 15:15:46 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Stopped httpd.service - The Apache HTTP Server.

$ ss -ltn sport = :80
nothing is listening on port 80
```

Service state after recovery (SSM):
```
is-active : active
MainPID=26791
NRestarts=0
ActiveEnterTimestamp=Mon 2026-11-23 15:16:17 UTC
local health: HTTP 200

Nov 23 15:15:45 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Stopping httpd.service - The Apache HTTP Server...
Nov 23 15:15:46 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: httpd.service: Deactivated successfully.
Nov 23 15:15:46 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Stopped httpd.service - The Apache HTTP Server.
Nov 23 15:16:17 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Starting httpd.service - The Apache HTTP Server...
Nov 23 15:16:17 ip-10-24-1-238.ap-south-1.compute.internal systemd[1]: Started httpd.service - The Apache HTTP Server.
Nov 23 15:16:17 ip-10-24-1-238.ap-south-1.compute.internal httpd[26791]: Server configured, listening on: port 80
```

Full console log: `chaos-test-output.txt`; raw checks: `monitor.log`.

## What went well
- The synthetic monitor flagged the outage within 0.3 s of the fault.
- SSM Run Command gave root access for diagnosis and restart without SSH keys or an open port 22.
- httpd was serving again 0.8 s after the restart command; no data or config was lost.

## What could be improved
- Recovery depended entirely on a human: most of the downtime was response time, not restart time.
- Detection relied on someone watching the monitor - there was no alarm or page.
- A single instance is a single point of failure: every failed check was a user-facing error.

## Action items
| # | Action | Status |
| --- | --- | --- |
| 1 | Add a CloudWatch alarm (Route 53 health check or CloudWatch Synthetics) with SNS notification on /health | Open |
| 2 | Put the service behind an ALB with 2+ instances in an Auto Scaling group (see Project 20) | Open |
| 3 | Turn the manual restart into a runbook / SSM Automation document so recovery is one click | Open |
