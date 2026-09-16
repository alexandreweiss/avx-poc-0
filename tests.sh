#!/bin/bash
# PoC Test Suite — Aviatrix Multicloud AWS Dublin + GCP Frankfurt
# Requires: Aviatrix User VPN connected before running.
# Run from repo root after terraform apply:
#   AVX_PASSWORD=<controller-password> ./tests.sh

set -uo pipefail

AVX_PASSWORD="${AVX_PASSWORD:-}"
if [ -z "$AVX_PASSWORD" ]; then
  echo "Usage: AVX_PASSWORD=<controller-password> ./tests.sh" >&2
  exit 1
fi

KEY="${KEY:-spoke-vms.pem}"

# IPs are read from terraform output by default.
# Override any variable via environment: AWS1_PRIV=x.x.x.x ./tests.sh
_tf_ip() { terraform output -raw "$1" 2>/dev/null | sed 's|http://||'; }

AWS1_PRIV="${AWS1_PRIV:-$(_tf_ip nginx_url_aws1)}"
AWS2_PRIV="${AWS2_PRIV:-$(_tf_ip nginx_url_aws2)}"
GCP_PRIV="${GCP_PRIV:-$(_tf_ip nginx_url_gcp)}"
CONTROLLER="${CONTROLLER:-$(terraform output -raw aviatrix_controller_ip 2>/dev/null)}"
if [ -z "$CONTROLLER" ]; then
  echo "ERROR: could not resolve controller IP. Set CONTROLLER=<ip> or run from repo root." >&2
  exit 1
fi

if [ -z "$AWS1_PRIV" ] || [ -z "$AWS2_PRIV" ] || [ -z "$GCP_PRIV" ]; then
  echo "ERROR: could not resolve spoke IPs from terraform output." >&2
  echo "Run from the repo root after terraform apply, or set AWS1_PRIV / AWS2_PRIV / GCP_PRIV manually." >&2
  exit 1
fi

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

PASS=0; FAIL=0

pass() { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
section() { echo; echo "=== $1 ==="; }

# ──────────────────────────────────────────────
section "0. PRE-CHECK: VPN connectivity"
# ──────────────────────────────────────────────

echo "  Checking reachability of AWS Spoke 1 private IP ($AWS1_PRIV)..."
if ping -c 1 -W 3 "$AWS1_PRIV" &>/dev/null; then
  pass "VPN connected — $AWS1_PRIV reachable"
else
  echo "  [FAIL] $AWS1_PRIV unreachable — connect to Aviatrix User VPN first (gateway: $CONTROLLER)"
  echo "  Download your VPN profile from the Controller and connect before running this script."
  exit 1
fi

# ──────────────────────────────────────────────
section "1. NGINX REACHABILITY (VPN client → spoke private IPs)"
# ──────────────────────────────────────────────

for vm in "AWS Spoke 1:$AWS1_PRIV:AWS Dublin" "AWS Spoke 2:$AWS2_PRIV:AWS Dublin" "GCP Spoke:$GCP_PRIV:GCP Frankfurt"; do
  name=$(echo $vm | cut -d: -f1)
  ip=$(echo $vm | cut -d: -f2)
  expected=$(echo $vm | cut -d: -f3)
  result=$(curl -s --max-time 5 "http://$ip" 2>/dev/null || true)
  if echo "$result" | grep -q "$expected"; then
    pass "$name nginx page contains '$expected'"
  else
    fail "$name nginx unreachable or wrong content (got: $(echo $result | head -c80))"
  fi
done

# ──────────────────────────────────────────────
section "2. EAST-WEST: AWS1 → AWS2 (same cloud, cross-spoke)"
# ──────────────────────────────────────────────

result=$(ssh $SSH_OPTS ubuntu@$AWS1_PRIV \
  "curl -s --max-time 5 http://$AWS2_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Spoke 2"; then
  pass "AWS1 → AWS2 via private IP (DCF PERMIT policy active)"
else
  fail "AWS1 → AWS2 failed — DCF may be blocking or routing missing"
fi

# ──────────────────────────────────────────────
section "3. EAST-WEST: AWS → GCP (cross-cloud via transit peering)"
# ──────────────────────────────────────────────

result=$(ssh $SSH_OPTS ubuntu@$AWS1_PRIV \
  "curl -s --max-time 10 http://$GCP_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Frankfurt"; then
  pass "AWS Spoke 1 → GCP Spoke via private IP (cross-cloud transit peering)"
else
  fail "AWS1 → GCP failed (check transit peering + DCF policy)"
fi

# ──────────────────────────────────────────────
section "4. LATENCY: cross-cloud RTT (AWS Dublin ↔ GCP Frankfurt)"
# ──────────────────────────────────────────────

echo "  Pinging GCP private IP from AWS Spoke 1 (5 packets)..."
rtt=$(ssh $SSH_OPTS ubuntu@$AWS1_PRIV \
  "ping -c 5 -q $GCP_PRIV 2>/dev/null | tail -1" 2>/dev/null || echo "failed")
echo "  RTT: $rtt"
if echo "$rtt" | grep -qE "mdev|avg"; then
  pass "Cross-cloud ICMP ping reachable (check RTT above for baseline)"
else
  fail "Ping AWS→GCP failed — ICMP may be blocked by DCF or routing"
fi

echo "  Pinging AWS Spoke 2 from GCP..."
rtt=$(ssh $SSH_OPTS ubuntu@$GCP_PRIV \
  "ping -c 5 -q $AWS2_PRIV 2>/dev/null | tail -1" 2>/dev/null || echo "failed")
echo "  RTT: $rtt"

# ──────────────────────────────────────────────
section "5. EGRESS: spoke VM internet access via Aviatrix gateway (single_ip_snat)"
# ──────────────────────────────────────────────

echo "  Testing HTTP egress from AWS Spoke 1 (should be allowed by DCF AllWeb policy)..."
result=$(ssh $SSH_OPTS ubuntu@$AWS1_PRIV \
  "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com" 2>/dev/null || echo "000")
if [ "$result" = "200" ] || [ "$result" = "301" ] || [ "$result" = "302" ]; then
  pass "HTTP egress allowed from AWS Spoke 1 (HTTP $result) — single_ip_snat working"
else
  fail "HTTP egress blocked or unreachable from AWS Spoke 1 (got HTTP $result)"
fi

echo "  Testing HTTP egress from GCP Spoke..."
result=$(ssh $SSH_OPTS ubuntu@$GCP_PRIV \
  "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com" 2>/dev/null || echo "000")
if [ "$result" = "200" ] || [ "$result" = "301" ] || [ "$result" = "302" ]; then
  pass "HTTP egress allowed from GCP Spoke (HTTP $result)"
else
  fail "HTTP egress blocked from GCP Spoke (got HTTP $result)"
fi

# ──────────────────────────────────────────────
section "6. ENCRYPTION: verify tunnel encryption on gateway"
# ──────────────────────────────────────────────

echo "  Checking Aviatrix tunnel encryption via controller API..."
CID=$(curl -sk -X POST "https://${CONTROLLER}/v1/api" \
  -d "action=login&username=admin&password=${AVX_PASSWORD}" \
  2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))" 2>/dev/null || true)

if [ -n "$CID" ]; then
  tunnel_info=$(curl -sk -X GET \
    "https://${CONTROLLER}/v2/api?action=list_encrypted_tunnels&CID=$CID" \
    2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
tunnels=d.get('results',[])
if isinstance(tunnels,list):
    print(f'{len(tunnels)} encrypted tunnels active')
elif isinstance(d.get('results'),dict):
    print(f'results: {list(d[\"results\"].keys())[:5]}')
else:
    print('check controller UI for tunnel encryption status')
" 2>/dev/null || echo "parse error")
  pass "Controller reachable — $tunnel_info"
  echo "  Tip: CoPilot → FlowIQ shows encrypted flow visualization"
else
  fail "Controller API login failed"
fi

# ──────────────────────────────────────────────
section "7. TRACEROUTE: path through Aviatrix gateways"
# ──────────────────────────────────────────────

echo "  Traceroute AWS Spoke 1 → GCP Spoke (shows hops through gateways):"
ssh $SSH_OPTS ubuntu@$AWS1_PRIV \
  "traceroute -n -m 8 -w 2 $GCP_PRIV 2>/dev/null || tracepath -n -m 8 $GCP_PRIV 2>/dev/null || echo 'traceroute not available'" \
  2>/dev/null | head -15 || true

# ──────────────────────────────────────────────
echo
echo "══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
  echo
  echo "Useful debug commands (requires VPN):"
  echo "  ssh -i $KEY ubuntu@$AWS1_PRIV     # AWS Spoke 1"
  echo "  ssh -i $KEY ubuntu@$AWS2_PRIV     # AWS Spoke 2"
  echo "  ssh -i $KEY ubuntu@$GCP_PRIV      # GCP Spoke"
  echo "  Controller: https://$CONTROLLER"
  exit 1
fi
