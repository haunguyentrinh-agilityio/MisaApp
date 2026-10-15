locals {
  tags = {
    app         = "misaapp"
    environment = "shared"
  }
}

# Created by infra/bootstrap/bootstrap.sh.
data "azurerm_resource_group" "shared" {
  name = "rg-misaapp-shared"
}

data "azurerm_client_config" "current" {}
