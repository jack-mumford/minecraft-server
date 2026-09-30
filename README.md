# minecraft-server

A Minecraft Java Edition server (vanilla or [Fabric](https://fabricmc.net)) on AWS EC2 (`t4g.medium`, Graviton/arm64). Terraform manages everything, and GitHub Actions deploys, backs up, and destroys it.

## Layout

| Path | Purpose |
|------|---------|
| `bootstrap/` | One-time stack, run locally: Terraform state bucket, backup bucket, and the IAM role GitHub Actions assumes (OIDC) |
| `*.tf` | The server: VPC, security group, EC2, world EBS volume, Elastic IP |
| `minecraft.auto.tfvars` | Server settings (version, memory, `server.properties`); edit and commit |
| `templates/user_data.sh.tftpl` | First-boot script: mounts the world volume, restores the latest backup, installs Java and the server |
| `.github/workflows/` | Deploy, Backup, and Destroy |

## One-time setup

1. Apply the bootstrap stack with your own AWS credentials:

   ```sh
   cd bootstrap
   terraform init
   terraform apply
   ```

   Bootstrap state is stored locally in `bootstrap/terraform.tfstate`, which is gitignored. Keep that file; you need it to change or remove these resources later.

2. Save the outputs as GitHub repository variables:

   ```sh
   terraform output -json github_variables \
     | jq -r 'to_entries[] | "\(.key) \(.value)"' \
     | while read -r k v; do gh variable set "$k" --body "$v"; done
   ```

   This sets `AWS_REGION`, `AWS_ROLE_ARN`, `TF_STATE_BUCKET`, and `BACKUP_BUCKET`.

## Workflows

Run them from the **Actions** tab. They share a concurrency group, so they never run on the same state at once.

- **Deploy**: `terraform apply`. It creates the server, or updates it after you change `minecraft.auto.tfvars`. You can override the Minecraft version when you start the run. A fresh world volume is seeded from the most recent backup in S3, so a destroy followed by a deploy picks up where you left off.
- **Backup**: stops the server for a few seconds, uploads a tarball of `/opt/minecraft` to `s3://$BACKUP_BUCKET/backups/`, and starts the server again. It runs daily at 09:00 UTC and can also be started by hand.
- **Destroy**: requires typing `destroy`. It takes a final backup (the destroy is aborted if the backup fails) and then runs `terraform destroy`. The backup bucket lives in the bootstrap stack and is not deleted.

Changing `minecraft_version` or `server_properties` rebuilds the EC2 instance. The world volume is detached and reattached, so no data is lost.

## Mods (Fabric)

The server runs Fabric (`server_type = "fabric"` in `minecraft.auto.tfvars`). To add a mod:

1. On [Modrinth](https://modrinth.com), open the mod's **Versions** tab, pick the build for your `minecraft_version` with the **Fabric** loader, and copy the `.jar` download link. Most mods also need [Fabric API](https://modrinth.com/mod/fabric-api).
2. Add the URL to `mods` in `minecraft.auto.tfvars`, commit, and run **Deploy**.

Every rebuild replaces the `mods/` folder with exactly this list. Players must install Fabric and any mods that aren't server-only. Before changing `minecraft_version`, check that Fabric and every mod support the new version.

## Operating the server

```sh
aws ssm start-session --target <instance-id>   # requires the Session Manager plugin

sudo journalctl -u minecraft -f           # server logs
sudo cat /var/log/minecraft-setup.log     # first-boot logs
sudo /usr/local/bin/minecraft-backup      # manual backup
```

## Running Terraform locally

```sh
terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="key=minecraft/terraform.tfstate" \
  -backend-config="region=us-west-2" \
  -backend-config="use_lockfile=true"
terraform plan -var backup_bucket=<BACKUP_BUCKET>
```

## Notes

- Only workflows on `main` can assume the AWS role. The role can manage EC2 and IAM roles named `minecraft-*`, and nothing else.
- S3 backups are kept until you delete them. Old versions of overwritten objects expire after 30 days.
- Estimated cost is about $30 per month while running: the instance is about $25, plus the Elastic IP, EBS, and S3.
