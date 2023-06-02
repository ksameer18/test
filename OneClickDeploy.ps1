# Parameters passed from ARM template 
param(
    [string] $RG_NAME,
    [string] $REGION,
    [string] $WORKSPACE_NAME,
    [string] $SA_NAME,
    [bool] $SA_EXISTS,
    [int] $LIFETIME_SECONDS,
    [string] $COMMENT,
    [string] $CLUSTER_NAME,
    [string] $SPARK_VERSION,
    [int] $AUTOTERMINATION_MINUTES,
    [string] $NUM_WORKERS,
    [string] $NODE_TYPE_ID,
    [string] $DRIVER_NODE_TYPE_ID,
    [int] $RETRY_LIMIT,
    [int] $RETRY_TIME,
    [bool] $CTRL_DEPLOY_CLUSTER,
    [int] $MINWORKERS,
    [int] $MAXWORKERS,
    [string] $PIPELINENAME,
    [string] $STORAGE,
    [string] $TARGETSCHEMA,
    [bool] $CTRL_DEPLOY_NOTEBOOK,
    [bool] $CTRL_DEPLOY_PIPELINE,
    [string] $NOTEBOOK_PATH,
    [bool] $SRC_FILESOURCE,
    [bool] $SRC_AZSQL,
    [bool] $SRC_AZMYSQL,
    [bool] $SRC_AZPSQL,
    [bool] $SRC_SQL_ONPREM,
    [bool] $SRC_PSQL_ONPREM,
    [bool] $SRC_ORACLE,
    [bool] $SRC_EVENTHUB ,
    [string] $CTRL_SYNTAX,
    [string] $SUBSCRIPTION_ID
)

# Generating Databricks Workspace URL

Write-Output "Task: Generating Databricks Workspace URL"

try {
    $token = (Get-AzAccessToken).Token
    
    # https url for getting workspace details
    $url = "https://management.azure.com/subscriptions/" + $SUBSCRIPTION_ID + "/resourceGroups/" + $RG_NAME + "/providers/Microsoft.Databricks/workspaces/" + $WORKSPACE_NAME + "?api-version=2023-02-01"
    
    # Set the headers
    $headerstkn = @{ Authorization = "Bearer $token"; 'ContentType' = "application/json"}
    
    #call http method to get workspace url
    $resurl = Invoke-RestMethod -Method Get -ContentType "application/json" -Uri $url  -Headers $headerstkn
    $WorkspaceUrl =  $resurl.properties.workspaceUrl
    Write-Host "Successful: Databricks workspace url is generated"
}
catch {
    Write-Host "Error while getting the Workspace URL"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage"
}

# Generating Databricks Workspace resource ID

Write-Output "Task: Generating Databricks Workspace resource ID"

try {
    $WORKSPACE_ID = Get-AzResource -ResourceType Microsoft.Databricks/workspaces -ResourceGroupName $RG_NAME -Name $WORKSPACE_NAME
    $ACTUAL_WORKSPACE_ID = $WORKSPACE_ID.ResourceId
    Write-Host "Successful: Databricks workspace resource ID is generated"
}
catch {
    Write-Host "Error while getting workspace ID"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage"
}

# Generating Databricks resource token

Write-Output "Task: Generating Databricks resource token"

try {
    [string] $TOKEN = (Get-AzAccessToken -Resource '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d').Token
    Write-Host "Successful: Resource Token generated"
}
catch {
    Write-Host "Error while getting the resource token"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage"    
}

# Generating Databricks management token

Write-Output "Task: Generating management token"

try {
    [string] $AZ_TOKEN = (Get-AzAccessToken -ResourceUrl 'https://management.core.windows.net/').Token   
    Write-Host "Successful: Management token generated"
}
catch {
    Write-Host "Error while getting the management token"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage"    
}

# Generating Databricks Personal access token

Write-Output "Task: Generating Databricks Personal access token"
# Set the headers
$HEADERS = @{
    "Authorization"                            = "Bearer $TOKEN"
    "X-Databricks-Azure-SP-Management-Token"   = "$AZ_TOKEN"
    "X-Databricks-Azure-Workspace-Resource-Id" = "$ACTUAL_WORKSPACE_ID"
}
# Set the request body
$BODY = @"
    { "lifetime_seconds": $LIFETIME_SECONDS, "comment": "$COMMENT" }
"@
    
try {
    #https request for generating token
    Write-Host "Attempt 1 : Generating Personal Access Token"
    $DB_PAT = ((Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/token/create" -Headers $HEADERS -Body $BODY).token_value)
    Write-Output "Successful: Personal Access Token generated"
}
catch {
    Write-Host "Attempt 1 : Error while calling the Databricks API for generating Personal Access Token"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage" 
    try {
    Write-Host "Attempt 2 : generating Personal Access Token"
    $DB_PAT = ((Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/token/create" -Headers $HEADERS -Body $BODY).token_value)
    Write-Output "Successful: Personal Access Token generated"
    }
    catch {
    Write-Host "Attempt 2 : Error while calling the Databricks API for generating Personal Access Token"
    $errorMessage = $_.Exception.Message
    Write-Host "Error message: $errorMessage" 
    }
}

# Creating All-purpose compute cluster

Write-Output "Task: Creating all-purpose compute cluster"

if ($CTRL_DEPLOY_CLUSTER -and ($null -ne $DB_PAT)) {
    # Set the headers        
    $HEADERS = @{
        "Authorization" = "Bearer $DB_PAT"
        "Content-Type"  = "application/json"
    }
    # Set the request body
    $BODY = @"
            {"cluster_name": "$CLUSTER_NAME", "spark_version": "$SPARK_VERSION", "autotermination_minutes": $AUTOTERMINATION_MINUTES, "num_workers": "$NUM_WORKERS", "node_type_id": "$NODE_TYPE_ID", "driver_node_type_id": "$DRIVER_NODE_TYPE_ID" }
"@

    try {
        #https request for creating cluster
        Write-Host "Attempt 1: Databricks API for creating the cluster"
        $CLUSTER_ID = ((Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/clusters/create" -Headers $HEADERS -Body $BODY).cluster_id)
        Write-Output "Successful: Databricks API for creating the cluster is called"
    }
    catch {
        Write-Host "Attempt 1: Error while calling the Databricks API for creating the cluster"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"   
        try {
        Write-Host "Attempt 2: Databricks API for creating the cluster"
        $CLUSTER_ID = ((Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/clusters/create" -Headers $HEADERS -Body $BODY).cluster_id)
        Write-Output "Successful: Databricks API for creating the cluster is called"
        }
        catch {
        Write-Host "Attempt 2: Error while calling the Databricks API for creating the cluster"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage" 
        }
    }

    # Checking the All-purpose compute cluster status

    if ( $CLUSTER_ID -ne "null" ) {

        Write-Output "[INFO] Cluster is being created"

        Write-Output "Task: Checking cluster status"

        $RETRY_COUNT = 0

        for( $RETRY_COUNT = 1; $RETRY_COUNT -le $RETRY_LIMIT; $RETRY_COUNT++ ) {
            
            Write-Output "[INFO] Attempt $RETRY_COUNT of $RETRY_LIMIT"
            
            $HEADERS = @{
                "Authorization" = "Bearer $DB_PAT"
            }
            
            try {
                #https request for getting cluster details
                $STATE = ((Invoke-RestMethod -Method GET -Uri "https://$WorkspaceUrl/api/2.0/clusters/get?cluster_id=$CLUSTER_ID" -Headers $HEADERS).state)
                Write-Output "Cluster is still getting ready"
            }
            catch {
                Write-Host "Error while calling the Databricks API for checking the clusters' state"
                $errorMessage = $_.Exception.Message
                Write-Host "Error message: $errorMessage"    
            }
            
            if ($STATE -eq "RUNNING") {
                Write-Output "Successful: Cluster is healthy and in running state"
                break
            } 
            else {
                Write-Output "[INFO] Cluster is still not ready, current state: $STATE Next check in $RETRY_TIME seconds.."
                Start-Sleep -Seconds $RETRY_TIME
                
                if ($RETRY_COUNT -eq $RETRY_LIMIT) {
                    Write-Output "No more attempts left, breaking.."
                }
            }
        }    
    } 
    else {
        Write-Output "[ERROR]: Cluster was not created"
    }
}

# Creating Folder strucrure and Importing Notebooks

Write-Output "Task: Importing Notebooks"

if ($null -ne $DB_PAT) {

    # Set the headers
    $headers = @{
        "Authorization" = "Bearer $DB_PAT"
        "Content-Type"  = "application/json"
    }
    
    # Create folder strucrure based on the syntax
    Write-Host "Create $CTRL_SYNTAX folder"
    try {
        $requestBodyFolder = @{
            "path" = "/Shared/$CTRL_SYNTAX"
        }
        $jsonBodyFolder = ConvertTo-Json -Depth 100 $requestBodyFolder

        if ($CTRL_SYNTAX -eq "DeltaLiveTable") {
            #https request for creating folder
            Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder
            Write-Output "Successful: Created $CTRL_SYNTAX folder"    
        }
        else {
            #https request for creating folder
            Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder
            Write-Output "Successful: Created $CTRL_SYNTAX folder"  
        }
        $mkdirDelta = $true
    }
    catch {
        $mkdirDelta = $false
        Write-Host "Error while calling the Databricks API for creating the $CTRL_SYNTAX folder. Folder not created"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"    
    }    

    # Create folder structure for examples
    Write-Host "Create folder for examples"
    try {
        $requestBodyFolder = @{
            "path" = "/Shared/Example"
        }
        $jsonBodyFolder = ConvertTo-Json -Depth 100 $requestBodyFolder
        #https request for creating folder
        Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder
        Write-Output "Successful: Created Examples folder" 
        $mkdirExample = $true
    }
    catch {
        $mkdirExample = $false
        Write-Host "Error while calling the Databricks API for creating the Example folder. Folder not created"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"
    }  
    
    # Import example notebooks to Example folder
    
    if ($mkdirExample) {
        
        Write-Host "Importing example notebooks"
        
        #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/Example?ref=dev" # change to respective git branch
        
        # Calling GitHub API for getting the filenames under Artifacts/Example folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/Example folder is successful"
            $getExmpFilenames = $true
        }
        catch {
            $getExmpFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/Example"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }        

        if ($getExmpFilenames) {

            Foreach ($filename in $fileNames) {
            
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/Example/$filename"
                    
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
                    
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
                    
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                        
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/Example/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
                    
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the raw example notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
                
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing example notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }            
            }
        }    
    }    

    # Upload Silver and Gold Layer notebooks for a batch source to its respective syntax folder
   
    if (!$SRC_EVENTHUB -and $mkdirDelta) {

        Write-Host "Task: Import Silver and Gold Layer notebooks for a batch source"
        #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/" + $CTRL_SYNTAX + "?ref=dev" # change to respective git branch
        
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX folder is successful"
            $getSGFilenames = $true
        }
        catch {
            $getSGFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getSGFilenames) {
            Foreach ($filename in $fileNames) {
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/$filename"
                    
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
                    
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
                    
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                        
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
                    
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
                
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            }
        }   
    }
    
    # Import bronze layer notebook for raw file source
    if ($SRC_FILESOURCE -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebook for raw file source"
        
        #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/FileSource?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/FileSource folder is successful"
            $getFSFilename = $true
        }
        catch {
            $getFSFilename = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/FileSource"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getFSFilename) {

            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/FileSource/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
            
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            } 
        }
    }
    
    # # Import bronze layer notebook for Azure SQL 
    if ($SRC_AZSQL -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebook for Azure SQL"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzureSQLDb?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzureSQLDb folder is successful"
            $getAZSQLFilenames = $true
        }
        catch {
            $getAZSQLFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzureSQLDb"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getAZSQLFilenames) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/AzureSQLDb/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            } 
        }
    }
    
    # Import bronze layer notebook for Azure MySQL
    if ($SRC_AZMYSQL -and $mkdirDelta) {

        Write-Host "Task: Import bronze layer notebook for Azure MySQL"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzureMySQL?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzureMySQL folder is successful"
            $getAZMYSQLFilenames = $true
        }
        catch {
            $getAZMYSQLFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzureMySQL"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getAZMYSQLFilenames) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/AzureMySQL/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            } 
        }
    }
    
    # Import bronze layer notebook for Azure PSQL
    if ($SRC_AZPSQL -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebooks for Azure PSQL"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzurePostgreSQL?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzurePostgreSQL folder is successful"
            $getAZPSQLFilename = $true
        }
        catch {
            $getAZPSQLFilename = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/AzurePostgreSQL"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getAZPSQLFilename) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/AzurePostgreSQL/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            } 
        }
    }
    
    # Import bronze layer notebook for SQL on-prem
    if ($SRC_SQL_ONPREM -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebooks for SQL on-prem"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/SQLDbOnPrem?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/SQLDbOnPrem folder is successful"
            $getSQLOPFilenames = $true
        }
        catch {
            $getSQLOPFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/SQLDbOnPrem"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getSQLOPFilenames) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/SQLDbOnPrem/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
        
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                        $errorMessage = $_.Exception.Message
                        Write-Host "Error message: $errorMessage"
                }    
    
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            }
        } 
    }
    
    # Import bronze layer notebook for PSQL on-prem
    if ($SRC_PSQL_ONPREM -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebooks for PSQL on-prem"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/PostgreSQL?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/PostgreSQL folder is successful"
            $getPSQLOPFilename = $true
        }
        catch {
            $getPSQLOPFilename = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/PostgreSQL"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getPSQLOPFilename) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/PostgreSQL/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            }
        } 
    }


    # Import bronze layer notebook for Oracle
    if ($SRC_ORACLE -and $mkdirDelta) {

        Write-Host "Task: Import Bronze Layer notebooks for Oracle"

        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/Oracle?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/Oracle folder is successful"
            $getOrclFilename = $true
        }
        catch {
            $getOrclFilename = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Batch/Oracle"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }

        if ($getOrclFilename) {
            Foreach ($filename in $fileNames) { 

                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Batch/Oracle/$filename"

                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing

                    # Read the notebook file
                    $notebookContent = $Webresults.Content

                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))

                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }

                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }

                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            }
        }         
    }
    
    # Import bronze, silver and gold layer notebooks for EventHub stream
    if ($SRC_EVENTHUB -and $mkdirDelta) {

        Write-Host "Task: Import bronze, silver and gold layer notebooks for EventHub stream"
        
        # Get files under directory #github api for a folder
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Stream/EventHub?ref=dev" # change to respective git branch
        # Calling GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX folder
        try {
            $wr = Invoke-WebRequest -Uri $Artifactsuri
            $objects = $wr.Content | ConvertFrom-Json
            $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
            Write-Host "Successful: getting the filenames under Artifacts/$CTRL_SYNTAX/Stream/EventHub folder is successful"
            $getEHFilenames = $true
        }
        catch {
            $getEHFilenames = $false
            Write-Host "Error while calling the GitHub API for getting the filenames under Artifacts/$CTRL_SYNTAX/Stream/EventHub"
            $errorMessage = $_.Exception.Message
            Write-Host "Error message: $errorMessage"
        }
    
        if ($getEHFilenames) {
            Foreach ($filename in $fileNames) { 
        
                try {
                    # Set the path to the notebook to be imported
                    $url = "$NOTEBOOK_PATH/$CTRL_SYNTAX/Stream/EventHub/$filename"
            
                    # Get the notebook
                    $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                    # Read the notebook file
                    $notebookContent = $Webresults.Content
            
                    # Base64 encode the notebook content
                    $notebookBase64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
                    
                    # Set the path
                    $splitfilename = $filename.Split(".")
                    $filenamewithoutextension = $splitfilename[0]
                    $path = "/Shared/$CTRL_SYNTAX/$filenamewithoutextension";
                    
                    # Set the request body
                    $requestBody = @{
                        "content"  = $notebookBase64
                        "path"     = $path
                        "language" = "PYTHON"
                        "format"   = "JUPYTER"
                    }
            
                    # Convert the request body to JSON
                    $jsonBody = ConvertTo-Json -Depth 100 $requestBody
                }
                catch {
                    Write-Host "Error while reading the notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
        
                try {
                    # Make the HTTP request to import the notebook
                    $response = Invoke-RestMethod -Method POST -Uri "https://$WorkspaceUrl/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
                    Write-Host "Successful: $filename is imported"
                }
                catch {
                    Write-Host "Error while calling the Azure Databricks API for importing notebook: $filename"
                    $errorMessage = $_.Exception.Message
                    Write-Host "Error message: $errorMessage"
                }
            } 
        }
    }
}

# Deploy a DLT pipeline
if ($CTRL_DEPLOY_PIPELINE -and ($null -ne $DB_PAT)) {
    
    Write-Host "Task: Deploy pipeline"
    # Set the headers
    $headers = @{Authorization = "Bearer $DB_PAT" }

    $pipeline_notebook_path = "/Shared/$CTRL_SYNTAX/azure_sql_db"

    # Create a pipeline configurations
    $pipelineConfig = @{
        name = $PIPELINENAME
        storage = $STORAGE
        target = $TARGETSCHEMA
        clusters = @{
            label = 'default'
            autoscale = @{
                min_workers = $MINWORKERS
                max_workers = $MAXWORKERS
                mode = 'ENHANCED'
            }
        }
        libraries = @{
            notebook = @{
                path = $pipeline_notebook_path
            }
        }
        continuous = 'false'
        allow_duplicate_names = 'true' 
    }

    try {
        $createPipelineResponse = Invoke-RestMethod -Uri "https://$WorkspaceUrl/api/2.0/pipelines" -Method POST -Headers $headers -Body ($pipelineConfig | ConvertTo-Json -Depth 10)
        Write-Host "Successful: Pipeline is created"
    }
    catch {
        Write-Host "Error while calling the Azure Databricks API for creating the pipeline"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"
    }
}

# Upload data files to storage account
if ($SA_EXISTS) {

    Write-Host "Task: Upload data files to storage account"

    #Get storage account access key
    try {
        $storageaccountkey = Get-AzStorageAccountKey -ResourceGroupName $RG_NAME -Name $SA_NAME;
        Write-Host "Successful: Storage account access key is generated"
    }
    catch {
        Write-Host "Error while getting Storage Account Key"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"
    }
    
    #Create storage account context
    try {
        $ctx = New-AzStorageContext -StorageAccountName $SA_NAME -StorageAccountKey $storageaccountkey.Value[0]
        Write-Host "Successful: Storage account context is created"
    }
    catch {
        Write-Host "Error while creating Azure Storage context"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"
    }
    #github api for a folder
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/data?ref=dev" # change to respective git branch
    # Calling GitHub API for getting the filenames under /data folder
    try {
        $wr = Invoke-WebRequest -Uri $Artifactsuri
        $objects = $wr.Content | ConvertFrom-Json
        $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
        Write-Host "Successful: getting the filenames under /data folder is successful"
        $getCsvFilenames = $true
    }
    catch {
        $getCsvFilenames = $false
        Write-Host "Error while calling the GitHub API to get filenames under /data"
        $errorMessage = $_.Exception.Message
        Write-Host "Error message: $errorMessage"
    }
    
    if ($getCsvFilenames) {
        Foreach ($filename in $fileNames) {
            try {
                $url = "https://raw.githubusercontent.com/DatabricksFactory/databricks-migration/dev/data/$filename" # change to respective git branch
            
                $Webresults = Invoke-WebRequest $url -UseBasicParsing
            
                Invoke-WebRequest -Uri $url -OutFile $filename
            
                Set-AzStorageBlobContent -File $filename -Container "data" -Blob $filename -Context $ctx

                Write-Host "Successful: $filename is uploaded to storage account"
            }
            catch {
                Write-Host "Error while uploading data file: $filename"
                $errorMessage = $_.Exception.Message
                Write-Host "Error message: $errorMessage"
            }
        }
    }
}
