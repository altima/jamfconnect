# Helper Tools - Jamf Protect Diagnostics Collection (Azure Files)

This script is provided to trigger and collect the output from an `jamfconnect logs` and upload it to Azure Files.

## Workflow Steps

Steps to create the workflow:

- [ ] Jamf Pro - Upload [jc_logs_self_service.sh](./jc_logs_self_service.sh)
    - Set the variables in the script
- [ ] Jamf Pro - [Create Policies](#policies)
    - Jamf Connect Logs Collect

## Workflow Components

####  <a id="policies"></a>Policies

|Name|Frequency|Trigger|Scope|Payload|
|----|---------|-------|-----|-------|
|**Jamf Connect Logs Collect**|Ongoing|Self Service|All Managed Clients|jc_logs_self_service.sh<br>Add `SAS Token` in script Parameter 5

**Azure Files Configuration**

- Create [Azure File Share](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction) and generate a [SAS Token](https://learn.microsoft.com/en-us/rest/api/storageservices/delegate-access-with-shared-access-signature) with `write-only` permissions as applied in the example below.

<img src="./images/SASToken.png" alt="SASToken" width="700"/>

#
## Please note that all resources contained within this repository are provided as-is and are not officially supported by Jamf Support.