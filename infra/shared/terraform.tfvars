# suffix and ci_principal_id come from -var (bootstrap.sh, deploy.yml). No secrets here.
location = "southeastasia"

# Developer aliases (2-12 lower-case letters/digits); each gets sqldb-misaapp-dev-<alias>.
# Add yours in a PR; the next develop deploy creates the database. See docs/deployment.md.
developers = ["admin"]
