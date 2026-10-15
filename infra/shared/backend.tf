# Partial configuration. storage_account_name, container_name ("tfstate-shared") and
# key ("shared.tfstate") are passed with -backend-config; see contracts/infrastructure.md.
terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}
