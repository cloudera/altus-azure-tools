# Upload examples to ADLS

Use this script to upload Cloudera Altus Data Engineering example Jobs with sample data to your ADLS account.

See Cloudera Altus Documentation for details of how to run the example jobs.

## Usage
1. Download and install [Azure CLI 2.0](https://docs.microsoft.com/en-us/cli/azure/?view=azure-cli-latest). Or use Azure Cloud Shell (Bash).
2. Login to Azure CLI: `az login`.
3. Run the upload example script by: `./altus_adls_job_data_setup.sh --adls-account <ADLS account name> --adls-path <path in ADLS>`

## Requirements/Limitations
- Requires Azure CLI 2.0.
- Requires the Azure user having write permission to existing ADLS account.
