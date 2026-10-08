# Pentesting Toolkit: Containers, Virtualization & Cloud Labs

[Back to Pentesting Toolkit](../toolkit.md)

## Containers, Virtualization & Cloud Labs

- azure-cli
  - run..: `az login`
  - Repo.: <https://github.com/Azure/azure-cli>
  - Docs.: <https://learn.microsoft.com/en-us/cli/azure/>
  - Desc.: Azure CLI for cloud audits.
- azd
  - run..: `azd up`
  - Repo.: <https://github.com/Azure/azure-dev>
  - Docs.: <https://learn.microsoft.com/en-us/azure/developer/azure-developer-cli/>
  - Desc.: Azure Developer CLI for application provisioning and audits.
- msgraph-cli
  - run..: `mgc login`
  - Repo.: <https://github.com/microsoftgraph/msgraph-cli>
  - Docs.: <https://learn.microsoft.com/en-us/graph/cli/overview>
  - Desc.: Microsoft Graph CLI for tenant inspection and audits.
- cf-terraforming
  - run..: `cf-terraforming generate --resource-type cloudflare_zone`
  - Repo.: <https://github.com/cloudflare/cf-terraforming>
  - Docs.: <https://github.com/cloudflare/cf-terraforming#readme>
  - Desc.: Cloudflare Terraform import helper.
- flarectl
  - run..: `flarectl zone list`
  - Repo.: <https://github.com/cloudflare/cloudflare-go>
  - Docs.: <https://github.com/cloudflare/cloudflare-go/blob/main/cmd/flarectl/README.md>
  - Desc.: Cloudflare API CLI bundled with the Go SDK.
- wrangler
  - run..: `wrangler deploy`
  - Repo.: <https://github.com/cloudflare/workers-sdk>
  - Docs.: <https://developers.cloudflare.com/workers/wrangler/>
  - Desc.: Cloudflare Workers control-plane CLI.
- docker
  - run..: `docker run -it $image`
  - Repo.: <https://github.com/moby/moby>
  - Docs.: <https://docs.docker.com/>
  - Desc.: Container runtime used for sandboxes and vulnerable labs.
- lazydocker
  - run..: `lazydocker`
  - Repo.: <https://github.com/jesseduffield/lazydocker>
  - Docs.: <https://github.com/jesseduffield/lazydocker#readme>
  - Desc.: Terminal dashboard for inspecting lab containers.
- terraform
  - run..: `terraform plan`
  - Repo.: <https://github.com/hashicorp/terraform>
  - Docs.: <https://developer.hashicorp.com/terraform/docs>
  - Desc.: IaC tool used in cloud audit and lab provisioning workflows.
- wine-tools
  - run..: `wine $binary.exe`
  - Repo.: <https://gitlab.winehq.org/wine/wine>
  - Docs.: <https://wiki.winehq.org/>
  - Desc.: Wine helpers used for triaging Windows binaries on Linux.
