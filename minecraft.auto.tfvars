# Server settings used by the GitHub Actions workflows. Edit, commit, and run
# the Deploy workflow to apply. Region and bucket names come from repository
# variables, not this file.

# Setting this confirms you accept the Minecraft EULA: https://aka.ms/MinecraftEULA
accept_eula = true

minecraft_version = "latest"
jvm_memory        = "3G"
allowed_cidrs     = ["0.0.0.0/0"]

server_properties = {
  motd        = "A Minecraft server on AWS"
  difficulty  = "normal"
  gamemode    = "survival"
  max-players = "10"
}
