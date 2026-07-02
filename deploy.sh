#!/bin/bash
# Run from your Mac: ./deploy.sh user@vps-ip
set -e
VPS="${1:?Usage: ./deploy.sh user@vps-ip}"
REMOTE="/opt/blame-the-guilty"
cd "$(dirname "$0")/backend"
echo "Building self-contained binary..."
dotnet publish -c Release --self-contained true -r linux-x64 -o ./publish
echo "Uploading to VPS..."
ssh "$VPS" "mkdir -p $REMOTE"
rsync -az --delete ./publish/ "$VPS:$REMOTE/"
[ -f appsettings.Production.json ] && scp appsettings.Production.json "$VPS:$REMOTE/"
echo "Restarting..."
ssh "$VPS" "sudo systemctl restart blame-the-guilty"
echo "Done! Logs: ssh $VPS journalctl -u blame-the-guilty -f"
