variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-west-2"
}

variable "name" {
  description = "Name prefix applied to all resources."
  type        = string
  default     = "minecraft"
}

variable "instance_type" {
  description = "EC2 instance type. Must be an arm64 (Graviton) type to match the AMI."
  type        = string
  default     = "t4g.medium"
}

variable "accept_eula" {
  description = "You must accept the Minecraft EULA (https://aka.ms/MinecraftEULA) to run the server."
  type        = bool
  default     = false

  validation {
    condition     = var.accept_eula
    error_message = "Set accept_eula = true to confirm you accept the Minecraft EULA (https://aka.ms/MinecraftEULA)."
  }
}

variable "minecraft_version" {
  description = "Minecraft Java Edition server version (e.g. \"1.21.8\"), or \"latest\" for the newest release."
  type        = string
  default     = "latest"
}

variable "server_type" {
  description = "Server software: \"vanilla\" (Mojang's server) or \"fabric\" (Fabric mod loader)."
  type        = string
  default     = "vanilla"

  validation {
    condition     = contains(["vanilla", "fabric"], var.server_type)
    error_message = "server_type must be \"vanilla\" or \"fabric\"."
  }
}

variable "fabric_loader_version" {
  description = "Fabric loader version (e.g. \"0.19.5\"), or \"latest\" for the newest stable loader. Only used when server_type = \"fabric\"."
  type        = string
  default     = "latest"
}

variable "mods" {
  description = "Direct download URLs of mod .jar files (e.g. from Modrinth). The mods folder is replaced with exactly these on every server rebuild. Requires server_type = \"fabric\"."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.mods) == 0 || var.server_type == "fabric"
    error_message = "mods can only be used with server_type = \"fabric\"."
  }

  validation {
    condition     = alltrue([for url in var.mods : can(regex("^https://[^'\\s]+\\.jar$", url))])
    error_message = "Each mod must be an https:// URL ending in .jar."
  }
}

variable "jvm_memory" {
  description = "JVM heap size (-Xms/-Xmx). Leave ~1 GB headroom for the OS; t4g.medium has 4 GB."
  type        = string
  default     = "3G"
}

variable "allowed_cidrs" {
  description = "CIDR blocks allowed to connect to the Minecraft port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "data_volume_size" {
  description = "Size in GiB of the EBS volume holding the world data."
  type        = number
  default     = 20
}

variable "server_properties" {
  description = "Overrides for server.properties. Keys use Minecraft's own names (e.g. \"difficulty\", \"max-players\")."
  type        = map(string)
  default     = {}
}

variable "backup_bucket" {
  description = "S3 bucket (created by bootstrap/) for world backups. New servers restore the latest backup from it."
  type        = string
}
