# Server settings used by the GitHub Actions workflows. Edit, commit, and run
# the Deploy workflow to apply. Region and bucket names come from repository
# variables, not this file.

# Setting this confirms you accept the Minecraft EULA: https://aka.ms/MinecraftEULA
accept_eula = true

# Pinned: Fabric and mods only support specific Minecraft versions.
minecraft_version = "26.3"
server_type       = "fabric"

# Direct .jar URLs (e.g. Modrinth's download link for the 26.3 Fabric build).
# Most mods also need Fabric API: https://modrinth.com/mod/fabric-api
mods = [
  # Fabric API 0.161.0 (required by Xaero's World Map)
  "https://cdn.modrinth.com/data/P7dR8mSH/versions/bNnaTiuM/fabric-api-0.161.0%2B26.3.jar",
  # Xaero's World Map 1.46.4
  "https://cdn.modrinth.com/data/NcUtCpym/versions/UleMm8za/xaeroworldmap-fabric-26.3-1.46.4.jar",
]

# Minecraft usernames. A non-empty list turns the whitelist on; ops are whitelisted automatically.
whitelist = ["Mumfford"]
ops       = ["Mumfford"]

jvm_memory    = "3G"
allowed_cidrs = ["0.0.0.0/0"]

server_properties = {
  motd        = "A Minecraft server on AWS"
  difficulty  = "normal"
  gamemode    = "survival"
  max-players = "10"

  # How far players can see, in chunks (default 10). Drop to 16 if exploring lags.
  view-distance = "20"
  # How far mobs, crops and redstone keep running (default 10). Kept low: this is the CPU-heavy one.
  simulation-distance = "10"
}
