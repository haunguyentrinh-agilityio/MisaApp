# One identity per workload, so each holds only what it needs:
#   api      AcrPull, Key Vault Secrets User, database reader/writer (granted by the migrate job)
#   web      AcrPull only (nginx never gets a token that could read Key Vault)
#   migrator AcrPull, Entra admin of the SQL server
resource "azurerm_user_assigned_identity" "api" {
  name                = local.api_identity_name
  resource_group_name = data.azurerm_resource_group.env.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "web" {
  name                = local.web_identity_name
  resource_group_name = data.azurerm_resource_group.env.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "migrator" {
  name                = local.migrator_identity_name
  resource_group_name = data.azurerm_resource_group.env.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_role_assignment" "acr_pull" {
  for_each = {
    api      = azurerm_user_assigned_identity.api.principal_id
    web      = azurerm_user_assigned_identity.web.principal_id
    migrator = azurerm_user_assigned_identity.migrator.principal_id
  }

  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}
