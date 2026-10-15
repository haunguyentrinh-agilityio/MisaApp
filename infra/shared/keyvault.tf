# Holds the nonprod SQL admin password. Whoever applies this root (the admin running bootstrap.sh,
# then the develop deploy identity) gets Key Vault Secrets Officer on rg-misaapp-shared from
# bootstrap.sh, so the role isn't swapped between those two principals on every apply.

# Public on purpose: GitHub-hosted runners (no fixed IPs) and developers read the secret.
# Access is gated by Entra RBAC on the vault, not by network rules.
#trivy:ignore:AZU-0013
resource "azurerm_key_vault" "nonprod" {
  name                       = "kv-misaapp-np-${var.suffix}"
  resource_group_name        = data.azurerm_resource_group.shared.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
  tags                       = local.tags

  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  key_vault_id = azurerm_key_vault.nonprod.id
  value        = random_password.sql_admin.result
  content_type = "password"

  lifecycle {
    prevent_destroy = true
  }
}

# CI reads the password (and masks it) for its per-run database.
resource "azurerm_role_assignment" "ci_kv_secrets_user" {
  scope                = azurerm_key_vault.nonprod.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.ci_principal_id
  principal_type       = "ServicePrincipal"
}
