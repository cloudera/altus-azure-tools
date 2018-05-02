# Altus Azure Quickstart Environment Template

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fcloudera%2Faltus-azure-tools%2Fmaster%2Fazure-quickstart-template%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png" />
</a>

This template is intended to create the following Azure resources for a quickstart environment:
  * Virtual Network
  * Network Security Group
  * DNS Zone
  * User Assigned Managed Service Identity (MSI)

## Usage:

There are two ways to deploy the quickstart environment. The first, and simplest method,
is to click the "Deploy to Azure" button at the top of this page. In this scenario, the
template parameters must be filled in in the web page.

The second method is to use Azure's REST API, an example of which is provided in this
page using curl. If the REST API is used for deployment, then parameters must be set in the
azuredeploy.parameters.json file.

The template expects the following parameters:

| Name   | Description | Default Value |
|:--- |:---|:---|
| resourceNamePrefix | Naming prefix for the virtual network and network security group, which will be created with the names <PREFIX>-vnet and <PREFIX>-nsg respectively | altus-quickstart |
| dnsPrivateZoneName | DNS private zone name | altus.quickstart |
| networkAddressSpace | Virtual Network Address space | 10.3.0.0/24 |

In order to deploy the template, all the files (template, parameters etc.)
must be accessible via HTTP by the host performing the deployment.

## Example deployment (using Azure's REST API and curl):

```
CLIENT_ID=
CLIENT_SECRET=
TENANT_ID=
SUBSCRIPTION_ID=
RESOURCE_GROUP=

# Fetch the authentication token
export TOKEN=$(curl -X POST -d "grant_type=client_credentials&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&resource=https%3A%2F%2Fmanagement.azure.com%2F" https://login.microsoftonline.com/$TENANT_ID/oauth2/token | jq .access_token | tr -d \")

# Create the desired resource group. This step is optional, the deployment can also be done
# inside of an existing resource group
curl -X PUT -H "Authorization: Bearer $TOKEN" \
https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP?api-version=2017-05-10 \
-H "Content-Type: application/json" \
--data-ascii '{"location": "eastus2"}'


curl -X PUT -H "Authorization: Bearer $TOKEN" \
https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RESOURCE_GROUP/providers/Microsoft.Resources/deployments/nwongdeploy?api-version=2015-01-01 \
-H "Content-Type: application/json" \
--data-ascii '
{
  "name": "resource_group_REPLACE_ME",
  "properties":
  {
    "Mode": "Incremental",
    "templateLink":
    {
      "uri" : "https://path/REPLACE_ME/azuredeploy.json",
      "contentVersion": "1.0.0.0"
    },
    "parametersLink": {
      "uri": "https://path/REPLACE_ME/azuredeploy.parameters.json",
      "contentVersion": "1.0.0.0"
    }
  }
}
```
