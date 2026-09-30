data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  default_server_properties = {
    "motd"        = "A Minecraft server on AWS"
    "difficulty"  = "normal"
    "gamemode"    = "survival"
    "max-players" = "10"
    "online-mode" = "true"
    "pvp"         = "true"
    "server-port" = "25565"
  }

  whitelist_properties = length(local.player_names) > 0 ? {
    "white-list"        = "true"
    "enforce-whitelist" = "true"
  } : {}

  server_properties = merge(local.default_server_properties, local.whitelist_properties, var.server_properties)
}

# --- IAM: lets the instance register with SSM Session Manager (no SSH needed) ---

resource "aws_iam_role" "instance" {
  name = "${var.name}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "backups" {
  name = "backups"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::${var.backup_bucket}"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::${var.backup_bucket}/backups/*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
}

# --- World data lives on its own volume so the instance can be replaced freely ---

resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.public.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = { Name = "${var.name}-data" }
}

resource "aws_instance" "minecraft" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.minecraft.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    volume_serial     = replace(aws_ebs_volume.data.id, "-", "")
    minecraft_version = var.minecraft_version
    server_type       = var.server_type
    fabric_loader     = var.fabric_loader_version
    mods              = var.mods
    whitelist_json    = local.whitelist_json
    ops_json          = local.ops_json
    jvm_memory        = var.jvm_memory
    server_properties = local.server_properties
    backup_bucket     = var.backup_bucket
  })
  user_data_replace_on_change = true

  tags = { Name = var.name }

  # First boot restores from S3 and registers with SSM, so the role's policies must exist.
  depends_on = [aws_iam_role_policy.backups, aws_iam_role_policy_attachment.ssm]

  lifecycle {
    # Don't rebuild the server every time AWS publishes a new AMI.
    ignore_changes = [ami]
  }
}

resource "aws_volume_attachment" "data" {
  device_name                    = "/dev/sdf"
  volume_id                      = aws_ebs_volume.data.id
  instance_id                    = aws_instance.minecraft.id
  stop_instance_before_detaching = true
}

resource "aws_eip" "minecraft" {
  domain   = "vpc"
  instance = aws_instance.minecraft.id

  tags = { Name = var.name }

  depends_on = [aws_internet_gateway.this]
}
