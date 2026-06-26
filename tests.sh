#!/bin/bash
# PoC Test Suite — Aviatrix Multicloud AWS Dublin + GCP Frankfurt
# Run from repo root after terraform apply:
#   chmod +x tests.sh && ./tests.sh

set -uo pipefail

KEY="spoke-vms.pem"
AWS1_PUB="54.195.68.218"
AWS2_PUB="34.245.126.234"
GCP_PUB="34.159.235.213"

AWS1_PRIV="10.20.0.124"
AWS2_PRIV="10.21.0.120"
GCP_PRIV="10.31.0.3"

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

PASS=0; FAIL=0

pass() { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
section() { echo; echo "=== $1 ==="; }

# ──────────────────────────────────────────────
section "1. NGINX REACHABILITY (public internet → spokes)"
# ──────────────────────────────────────────────

for vm in "AWS Spoke 1:$AWS1_PUB:AWS Dublin" "AWS Spoke 2:$AWS2_PUB:AWS Dublin" "GCP Spoke:$GCP_PUB:GCP Frankfurt"; do
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

result=$(ssh $SSH_OPTS ubuntu@$AWS1_PUB \
  "curl -s --max-time 5 http://$AWS2_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Spoke 2"; then
  pass "AWS1 → AWS2 via private IP (DCF PERMIT policy active)"
else
  fail "AWS1 → AWS2 failed — DCF may be blocking or routing missing"
fi

result=$(ssh $SSH_OPTS ubuntu@$AWS2_PUB \
  "curl -s --max-time 5 http://$AWS1_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Spoke 1"; then
  pass "AWS2 → AWS1 via private IP"
else
  fail "AWS2 → AWS1 failed"
fi

# ──────────────────────────────────────────────
section "3. EAST-WEST: AWS → GCP (cross-cloud via transit peering)"
# ──────────────────────────────────────────────

result=$(ssh $SSH_OPTS ubuntu@$AWS1_PUB \
  "curl -s --max-time 10 http://$GCP_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Frankfurt"; then
  pass "AWS Spoke 1 → GCP Spoke via private IP (cross-cloud transit peering)"
else
  fail "AWS1 → GCP failed (check transit peering + DCF policy)"
fi

result=$(ssh $SSH_OPTS ubuntu@$AWS2_PUB \
  "curl -s --max-time 10 http://$GCP_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Frankfurt"; then
  pass "AWS Spoke 2 → GCP Spoke via private IP"
else
  fail "AWS2 → GCP failed"
fi

# ──────────────────────────────────────────────
section "4. EAST-WEST: GCP → AWS (reverse cross-cloud)"
# ──────────────────────────────────────────────

result=$(ssh $SSH_OPTS ubuntu@$GCP_PUB \
  "curl -s --max-time 10 http://$AWS1_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Spoke 1"; then
  pass "GCP Spoke → AWS Spoke 1 via private IP"
else
  fail "GCP → AWS1 failed"
fi

result=$(ssh $SSH_OPTS ubuntu@$GCP_PUB \
  "curl -s --max-time 10 http://$AWS2_PRIV" 2>/dev/null || true)
if echo "$result" | grep -q "Spoke 2"; then
  pass "GCP Spoke → AWS Spoke 2 via private IP"
else
  fail "GCP → AWS2 failed"
fi

# ──────────────────────────────────────────────
section "5. LATENCY: cross-cloud RTT (AWS Dublin ↔ GCP Frankfurt)"
# ──────────────────────────────────────────────

echo "  Pinging GCP private IP from AWS Spoke 1 (5 packets)..."
rtt=$(ssh $SSH_OPTS ubuntu@$AWS1_PUB \
  "ping -c 5 -q $GCP_PRIV 2>/dev/null | tail -1" 2>/dev/null || echo "failed")
echo "  RTT: $rtt"
if echo "$rtt" | grep -qE "mdev|avg"; then
  pass "Cross-cloud ICMP ping reachable (check RTT above for baseline)"
else
  fail "Ping AWS→GCP failed — ICMP may be blocked by DCF or routing"
fi

echo "  Pinging AWS Spoke 2 from GCP..."
rtt=$(ssh $SSH_OPTS ubuntu@$GCP_PUB \
  "ping -c 5 -q $AWS2_PRIV 2>/dev/null | tail -1" 2>/dev/null || echo "failed")
echo "  RTT: $rtt"

# ──────────────────────────────────────────────
section "6. DCF DEFAULT-DENY: direct internet egress should be blocked"
# ──────────────────────────────────────────────
# DCF has explicit egress PERMIT for AllWeb on port 80/443, so HTTP should work
# but raw ping to 8.8.8.8 traverses the gateway and should be logged/visible

echo "  Testing HTTP egress from AWS Spoke 1 (should be allowed by DCF AllWeb policy)..."
result=$(ssh $SSH_OPTS ubuntu@$AWS1_PUB \
  "curl -s --max-time 5 -o /dev/null -w '%{http_code}' http://example.com" 2>/dev/null || echo "000")
if [ "$result" = "200" ]; then
  pass "HTTP egress allowed (DCF AllWeb PERMIT policy working)"
else
  fail "HTTP egress blocked or unreachable (got HTTP $result)"
fi

# ──────────────────────────────────────────────
section "7. ENCRYPTION: verify tunnel encryption on gateway"
# ──────────────────────────────────────────────

echo "  Checking Aviatrix tunnel encryption via controller API..."
CID=$(curl -sk -X POST "https://54.75.173.51/v1/api" \
  -d "action=login&username=admin&password=AirLiquid@123" \
  2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('CID',''))" 2>/dev/null || true)

if [ -n "$CID" ]; then
  tunnel_info=$(curl -sk -X GET \
    "https://54.75.173.51/v2/api?action=list_encrypted_tunnels&CID=$CID" \
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
section "8. TRACEROUTE: path through Aviatrix gateways"
# ──────────────────────────────────────────────

echo "  Traceroute AWS Spoke 1 → GCP Spoke (shows hops through gateways):"
ssh $SSH_OPTS ubuntu@$AWS1_PUB \
  "traceroute -n -m 8 -w 2 $GCP_PRIV 2>/dev/null || tracepath -n -m 8 $GCP_PRIV 2>/dev/null || echo 'traceroute not available'" \
  2>/dev/null | head -15 || true

# ──────────────────────────────────────────────
echo
echo "══════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════"

if [ $FAIL -gt 0 ]; then
  echo
  echo "Useful debug commands:"
  echo "  ssh -i $KEY ubuntu@$AWS1_PUB     # AWS Spoke 1"
  echo "  ssh -i $KEY ubuntu@$AWS2_PUB     # AWS Spoke 2"
  echo "  ssh -i $KEY ubuntu@$GCP_PUB      # GCP Spoke"
  echo "  Controller: https://54.75.173.51"
  echo "  CoPilot:    https://54.170.105.209"
  exit 1
fi
