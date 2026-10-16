# Image retention (FR-007): keeps every tag younger than 90 days plus the 30 newest per repository, so
# any recent commit stays deployable by rollback. --untagged removes manifests left without a tag
# (deploy.yml pushes plain manifests, no attestation index, so nothing tagged depends on them).
resource "azurerm_container_registry_task" "purge_old_images" {
  name                  = "purge-old-images"
  container_registry_id = azurerm_container_registry.main.id
  tags                  = local.tags

  platform {
    os = "Linux"
  }

  encoded_step {
    task_content = base64encode(<<-YAML
      version: v1.1.0
      steps:
        - cmd: acr purge --filter 'misaapp-api:.*' --filter 'misaapp-web:.*' --ago 90d --keep 30 --untagged
          disableWorkingDirectoryOverride: true
          timeout: 3600
    YAML
    )
  }

  timer_trigger {
    name     = "daily"
    schedule = "0 3 * * *"
    enabled  = true
  }
}
