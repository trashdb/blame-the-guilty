#!/bin/bash
# Run from your Mac: ./deploy.sh user@vps-ip
set -euo pipefail

VPS="${1:?Usage: ./deploy.sh user@vps-ip}"
REMOTE="/opt/blame-the-guilty"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR/backend"

echo "=== Building self-contained binary ==="
dotnet publish -c Release --self-contained true -r linux-x64 -o ./publish

echo "=== Uploading to VPS ==="
ssh "$VPS" "sudo mkdir -p $REMOTE"
rsync -az --delete --exclude='*.db' ./publish/ "$VPS:$REMOTE/"
rsync -az "$SCRIPT_DIR/deploy/" "$VPS:$REMOTE/deploy/"

echo "=== Copying production config ==="
if [ -f appsettings.Production.json ]; then
  scp appsettings.Production.json "$VPS:$REMOTE/"
else
  echo "WARNING: appsettings.Production.json not found"
fi

echo "=== Setting permissions ==="
ssh "$VPS" "sudo chmod +x $REMOTE/BlameTheGuilty.Api"

echo "=== Restarting service ==="
ssh "$VPS" "sudo systemctl daemon-reload && sudo systemctl restart blame-the-guilty"

echo ""
echo "=== Done! ==="
echo "Logs: ssh $VPS 'sudo journalctl -u blame-the-guilty -f'"
echo "Status: ssh $VPS 'sudo systemctl status blame-the-guilty'"
