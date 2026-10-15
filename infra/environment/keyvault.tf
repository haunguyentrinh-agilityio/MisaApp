# Holds gemini-api-key (production). Terraform never creates or reads secret values: an admin sets
# them with `az keyvault secret set` (docs/deployment.md) and the API app references them by URI.

# Public on purpose: Consumption Container Apps have no fixed egress IPs, and admins set secrets
# from their workstations. Access is gated by Entra RBAC on the vault, not by network rules.
#trivy:ignore:AZU-0013
resource "azurerm_key_vault" "main" {
  name                       = local.key_vault_name
  resource_group_name        = data.azurerm_resource_group.env.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 30
  tags                       = local.tags

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "api_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.api.principal_id
  principal_type       = "ServicePrincipal"
}
