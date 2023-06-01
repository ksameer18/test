# Parameters 

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
    [string] $CTRL_SYNTAX
)

# Generate Databricks token

Write-Output "Task: Generating Databricks Token"
$WORKSPACE_ID = Get-AzResource -ResourceType Microsoft.Databricks/workspaces -ResourceGroupName $RG_NAME -Name $WORKSPACE_NAME
$ACTUAL_WORKSPACE_ID = $WORKSPACE_ID.ResourceId
$token = (Get-AzAccessToken -Resource '2ff814a6-3304-4ab8-85cb-cd0e6f879c1d').Token
$AZ_TOKEN = (Get-AzAccessToken -ResourceUrl 'https://management.core.windows.net/').Token
$HEADERS = @{
    "Authorization"                            = "Bearer $TOKEN"
    "X-Databricks-Azure-SP-Management-Token"   = "$AZ_TOKEN"
    "X-Databricks-Azure-Workspace-Resource-Id" = "$ACTUAL_WORKSPACE_ID"
    }
$BODY = @"
{ "lifetime_seconds": $LIFETIME_SECONDS, "comment": "$COMMENT" }
"@
try {
        $DB_PAT = ((Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/token/create" -Headers $HEADERS -Body $BODY).token_value)
    }
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}


# Creating Cluster 

if ($CTRL_DEPLOY_CLUSTER) {
    try {    
    Write-Output "Task: Creating cluster"
    
    $HEADERS = @{
        "Authorization" = "Bearer $DB_PAT"
        "Content-Type" = "application/json"
    }
    
    $BODY = @"
    {"cluster_name": "$CLUSTER_NAME", "spark_version": "$SPARK_VERSION", "autotermination_minutes": $AUTOTERMINATION_MINUTES, "num_workers": "$NUM_WORKERS", "node_type_id": "$NODE_TYPE_ID", "driver_node_type_id": "$DRIVER_NODE_TYPE_ID" }
"@
    
    $CLUSTER_ID = ((Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/clusters/create" -Headers $HEADERS -Body $BODY).cluster_id)
    }
    catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
    }
    
    Write-Output "Task: Checking cluster"
    try{
    $RETRY_COUNT = 0
    for( $RETRY_COUNT = 1; $RETRY_COUNT -le $RETRY_LIMIT; $RETRY_COUNT++ ) {
        Write-Output "[INFO] Attempt $RETRY_COUNT of $RETRY_LIMIT"
        $HEADERS = @{
            "Authorization" = "Bearer $DB_PAT"
        }
        $STATE = ((Invoke-RestMethod -Method GET -Uri "https://$REGION.azuredatabricks.net/api/2.0/clusters/get?cluster_id=$CLUSTER_ID" -Headers $HEADERS).state)
        if ($STATE -eq "RUNNING") {
            Write-Output "[INFO] Cluster is running, pipeline has been completed successfully"
            break
        } else {
            Write-Output "[INFO] Cluster is still not ready, current state: $STATE Next check in $RETRY_TIME seconds.."
            Start-Sleep -Seconds $RETRY_TIME
        }
    }
    Write-Output "[ERROR] No more attempts left, breaking.."
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"    
}
}

# Importing Notebooks

Write-Output "Task: Uploading notebook"

$headers = @{
    "Authorization" = "Bearer $DB_PAT"
    "Content-Type"  = "application/json"
}

Write-Host "Create folder based on the syntax"
if ($CTRL_SYNTAX -eq "DeltaLiveTable") {
    try{
    $requestBodyFolder = @{
        "path" = "/Shared/$CTRL_SYNTAX"
    }
    $jsonBodyFolder = ConvertTo-Json -Depth 100 $requestBodyFolder
    
    Invoke-RestMethod -Method POST -Uri "https://eastus.azuredatabricks.net/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder
    }
    catch{
        Write-Host "An error occurred: $($_.Exception.Message)"
    }    
} else {
    try{
    $requestBodyFolder = @{
        "path" = "/Shared/$CTRL_SYNTAX"
    }
    $jsonBodyFolder = ConvertTo-Json -Depth 100 $requestBodyFolder
    
    Invoke-RestMethod -Method POST -Uri "https://eastus.azuredatabricks.net/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder 
    }
    catch{
        Write-Host "An error occurred: $($_.Exception.Message)"
    } 
}

Write-Host "Create folder for examples"
try{
$requestBodyFolder = @{
    "path" = "/Shared/Example"
}
$jsonBodyFolder = ConvertTo-Json -Depth 100 $requestBodyFolder

Invoke-RestMethod -Method POST -Uri "https://eastus.azuredatabricks.net/api/2.0/workspace/mkdirs" -Headers $headers -Body $jsonBodyFolder
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}   

# Import example notebooks
Write-Host "Upload example notebooks"
try {
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/Example?ref=main"
    Write-Host $Artifactsuri
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
    Write-Host $fileNames

    Foreach ($filename in $fileNames) {

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
        Write-Output $filenamewithoutextension
    
        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }
    
        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody
    
        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
    
        Write-Output $response
    }
}
catch {
    Write-Host "An error occurred: $($_.Exception.Message)"
}    

# Upload Silver and Gold Layer notebooks for a batch source
Write-Host "Upload Silver and Gold Layer notebooks for a batch source"
if (!$SRC_EVENTHUB) {
    try {
        $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/"+$CTRL_SYNTAX+"?ref=main"
        Write-Host $Artifactsuri
        $wr = Invoke-WebRequest -Uri $Artifactsuri
        $objects = $wr.Content | ConvertFrom-Json
        $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
        Write-Host $fileNames

        Foreach ($filename in $fileNames) {

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
            Write-Output $filenamewithoutextension
        
            # Set the request body
            $requestBody = @{
                "content"  = $notebookBase64
                "path"     = $path
                "language" = "PYTHON"
                "format"   = "JUPYTER"
            }
        
            # Convert the request body to JSON
            $jsonBody = ConvertTo-Json -Depth 100 $requestBody
        
            # Make the HTTP request to import the notebook
            $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  
        
            Write-Output $response
        }
    }
    catch {
        Write-Host "An error occurred: $($_.Exception.Message)"
    }    
}

# FileSource
if ($SRC_FILESOURCE) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/FileSource?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# Azure SQL 
if ($SRC_AZSQL) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzureSQLDb?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# Azure MySQL
if ($SRC_AZMYSQL) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzureMySQL?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}
# Azure PSQL
if ($SRC_AZPSQL) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/AzurePostgreSQL?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# SQL on-prem
if ($SRC_SQL_ONPREM) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/SQLDbOnPrem?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# PSQL on-prem
if ($SRC_PSQL_ONPREM) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Batch/PostgreSQL?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# EventHub
if ($SRC_EVENTHUB) {
    try{
    # Get files under directory
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/Artifacts/$CTRL_SYNTAX/Stream/EventHub?ref=main"
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    $objects = $wr.Content | ConvertFrom-Json
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name

    Foreach ($filename in $fileNames) { 

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
        Write-Output $filenamewithoutextension

        # Set the request body
        $requestBody = @{
            "content"  = $notebookBase64
            "path"     = $path
            "language" = "PYTHON"
            "format"   = "JUPYTER"
        }

        # Convert the request body to JSON
        $jsonBody = ConvertTo-Json -Depth 100 $requestBody

        # Make the HTTP request to import the notebook
        $response = Invoke-RestMethod -Method POST -Uri "https://$REGION.azuredatabricks.net/api/2.0/workspace/import" -Headers $headers -Body $jsonBody  

        Write-Output $response
    } 
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# Deploy pipeline
if ($CTRL_DEPLOY_PIPELINE) {
try{
  $headers = @{Authorization = "Bearer $DB_PAT"}

  $pipeline_notebook_path = '/Shared/$CTRL_SYNTAX/azure_sql_db'

  # Create a pipeline
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

$createPipelineResponse = Invoke-RestMethod -Uri "https://$REGION.azuredatabricks.net/api/2.0/pipelines" -Method POST -Headers $headers -Body ($pipelineConfig | ConvertTo-Json -Depth 10)
$createPipelineResponse

}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}

# Upload data files
if ($SA_EXISTS) {
    try{
    $storageaccountkey = Get-AzStorageAccountKey -ResourceGroupName $RG_NAME -Name $SA_NAME;
    
    $ctx = New-AzStorageContext -StorageAccountName $SA_NAME -StorageAccountKey $storageaccountkey.Value[0]
    
    $Artifactsuri = "https://api.github.com/repos/DatabricksFactory/databricks-migration/contents/data?ref=main" 
    
    $wr = Invoke-WebRequest -Uri $Artifactsuri
    
    $objects = $wr.Content | ConvertFrom-Json
    
    $fileNames = $objects | Where-Object { $_.type -eq "file" } | Select-Object -exp name
    
    Write-Host $fileNames
    
    Foreach ($filename in $fileNames) {
    
    $url = "https://raw.githubusercontent.com/DatabricksFactory/databricks-migration/main/data/$filename" 
    
    $Webresults = Invoke-WebRequest $url -UseBasicParsing
    
    Invoke-WebRequest -Uri $url -OutFile $filename
    
    Set-AzStorageBlobContent -File $filename -Container "data" -Blob $filename -Context $ctx
    
    }
}
catch{
    Write-Host "An error occurred: $($_.Exception.Message)"
}
}
