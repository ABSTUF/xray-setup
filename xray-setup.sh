#!/usr/bin/env bash
set -e
echo "=== 1/6 Installing XRay ==="
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

echo "=== 2/6 Generating keys ==="
cd /usr/local/etc/xray
UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIV=$(echo "$KEYS" | grep -i 'Private' | awk '{print $NF}')
PUB=$(echo "$KEYS" | grep -i 'Public' | awk '{print $NF}')
SID=$(openssl rand -hex 8)
if [ -z "$PRIV" ] || [ -z "$PUB" ]; then
  echo "ERROR: empty Reality keys! Raw x25519 output:"
  echo "$KEYS"
  exit 1
fi
echo "--- Check: PRIV=${PRIV:0:8}... PUB=${PUB:0:8}... (must not be empty) ---"
SNI=www.microsoft.com

echo "=== 3/6 Writing config ==="
cat > config.json <<XEOF
{
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$UUID", "flow": "xtls-rprx-vision" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "dest": "$SNI:443",
        "serverNames": ["$SNI"],
        "privateKey": "$PRIV",
        "shortIds": ["$SID"]
      }
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
XEOF

cat > /root/vless-creds.txt <<YEOF
UUID=$UUID
PUB=$PUB
SID=$SID
YEOF

echo "=== 4/6 Firewall ==="
ufw allow 443/tcp 2>/dev/null || true

echo "=== 5/6 Restarting XRay ==="
systemctl restart xray
sleep 1
if ss -tlnp | grep -q ':443 '; then
  echo "OK: XRay is listening on 443"
else
  echo "WARNING: XRay NOT listening on 443! Run: journalctl -u xray -n 20"
fi

echo "=== 6/6 QR code for your phone ==="
(apt-get install -y qrencode >/dev/null 2>&1 || yum install -y qrencode >/dev/null 2>&1) || true
IP=$(curl -4 -s ifconfig.me)
LINK="vless://$UUID@$IP:443?security=reality&encryption=none&pbk=$PUB&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=$SNI&sid=$SID#VPS-Reality"
echo "$LINK" > /root/vless-link.txt
qrencode -t ANSIUTF8 "$LINK" 2>/dev/null || qrencode -t ANSI "$LINK"
echo
echo "Plain link (also saved to /root/vless-link.txt):"
echo "$LINK"
