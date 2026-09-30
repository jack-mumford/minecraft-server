#!/usr/bin/env bash
# Runs /usr/local/bin/minecraft-backup on the server via SSM and waits for it.
# Usage: scripts/run-backup.sh <instance-id>
set -euo pipefail

INSTANCE_ID="$1"

COMMAND_ID=$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "Minecraft backup" \
  --timeout-seconds 1800 \
  --parameters 'commands=["/usr/local/bin/minecraft-backup"]' \
  --query Command.CommandId --output text)
echo "SSM command: $COMMAND_ID"

while true; do
  STATUS=$(aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$STATUS" in
    Pending | InProgress | Delayed) sleep 10 ;;
    *) break ;;
  esac
done

aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" \
  --query '[StandardOutputContent, StandardErrorContent]' --output text

echo "Backup status: $STATUS"
[ "$STATUS" = "Success" ]
