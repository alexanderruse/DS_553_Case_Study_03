# Azure Container Apps

Create an Azure Cost Management budget scoped to the Case Study 4 resource
group before deploying. Authenticate with `az login`, then run:

```bash
export AZURE_LOCATION="eastus"
export AZURE_RESOURCE_GROUP="resumelens-cs4-rg"
export AZURE_CONTAINER_APP="resumelens-api"
./cloud/azure/deploy.sh
```

The script uses a temporary build context so Azure builds `Dockerfile.cloud`
without modifying the Case Study 3 Dockerfile. It prints the HTTPS FQDN for the
class Sheet.

For the GitHub Action, configure the repository variables documented in
`.github/workflows/deploy-azure.yml` and add the `AZURE_CREDENTIALS` secret.
Do not commit the credential JSON.
