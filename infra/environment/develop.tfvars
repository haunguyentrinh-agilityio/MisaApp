# suffix, acr_name and image_tag come from -var in deploy.yml.
environment      = "develop"
location         = "southeastasia"
web_min_replicas = 0
web_max_replicas = 2
api_min_replicas = 0
api_max_replicas = 2
gemini_enabled   = true
