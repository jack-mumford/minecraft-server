# Resolves usernames to Mojang UUIDs at plan time, so a misspelled name fails
# the Deploy run instead of silently breaking the server's first boot.

locals {
  player_names = toset(distinct(concat(var.whitelist, var.ops)))
}

data "http" "mojang_profile" {
  for_each = local.player_names

  url = "https://api.mojang.com/users/profiles/minecraft/${each.value}"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Minecraft username \"${each.value}\" was not found (Mojang API returned ${self.status_code})."
    }
  }
}

locals {
  players = {
    for name, profile in data.http.mojang_profile : name => {
      # Mojang returns the canonical capitalization and an undashed UUID.
      name = jsondecode(profile.response_body).name
      uuid = join("-", regex("^(.{8})(.{4})(.{4})(.{4})(.{12})$", jsondecode(profile.response_body).id))
    }
  }

  whitelist_json = jsonencode([
    for name in local.player_names : local.players[name]
  ])

  ops_json = jsonencode([
    for name in distinct(var.ops) : merge(local.players[name], { level = 4, bypassesPlayerLimit = false })
  ])
}
