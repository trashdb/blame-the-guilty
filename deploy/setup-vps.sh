#!/bin/bash
# Run this ONCE on the VPS via: ssh user@vps "sudo bash -s" < deploy/setup-vps.sh
set -euo pipefail

APP_DIR="/opt/blame-the-guilty"

echo "=== Creating user and directory ==="
sudo mkdir -p "$APP_DIR"
sudo useradd --system --no-create-home --shell /usr/sbin/nologin blame 2>/dev/null || true
sudo chown blame:blame "$APP_DIR"

echo "=== Installing ngrok ==="
if ! command -v ngrok &>/dev/null; then
  curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc |
    sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
  echo "deb https://ngrok-agent.s3.amazonaws.com buster main" |
    sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
  sudo apt update && sudo apt install -y ngrok
else
  echo "ngrok already installed"
fi

echo ""
echo "=== NEXT STEP ==="
echo "Run this to set your ngrok token (get it from https://dashboard.ngrok.com):"
echo "  sudo ngrok config add-authtoken TU_NGROK_TOKEN"
echo ""
echo "After that, install the systemd services:"
echo "  sudo cp deploy/blame-the-guilty.service          /etc/systemd/system/"
echo "  sudo cp deploy/blame-the-guilty-tunnel.service    /etc/systemd/system/"
echo "  sudo systemctl daemon-reload"
echo "  sudo systemctl enable blame-the-guilty blame-the-guilty-tunnel"
echo ""
echo "Then deploy the binary from your Mac:"
echo "  ./deploy.sh user@TU_VPS_IP"
echo ""
echo "Finally start everything:"
echo "  sudo systemctl start blame-the-guilty blame-the-guilty-tunnel"
echo "  sudo systemctl status blame-the-guilty blame-the-guilty-tunnel"
