variable "player_cidrs" {
  description = "IPv4 público de cada conexão autorizada, em /32."
  type        = set(string)
  validation {
    condition     = length(var.player_cidrs) > 0 && alltrue([for c in var.player_cidrs : can(cidrnetmask(c)) && endswith(c, "/32")])
    error_message = "Informe ao menos um endereço IPv4 válido em /32."
  }
}
variable "players" {
  description = "Whitelist inicial de contas Minecraft Java autenticadas."
  type        = list(object({ name = string, uuid = string }))
  validation {
    condition     = length(var.players) > 0 && alltrue([for p in var.players : can(regex("^[A-Za-z0-9_]{1,16}$", p.name)) && can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", p.uuid))])
    error_message = "Preencha nome e UUID (com hífens) de pelo menos uma conta."
  }
}
variable "disk_gib" {
  type    = number
  default = 40
  validation {
    condition     = var.disk_gib >= 40 && var.disk_gib <= 16384 && floor(var.disk_gib) == var.disk_gib
    error_message = "Use um número inteiro entre 40 e 16384 GiB."
  }
}
variable "accept_minecraft_eula" {
  type        = bool
  default     = false
  description = "Aceite explícito do operador antes de provisionar."
}
