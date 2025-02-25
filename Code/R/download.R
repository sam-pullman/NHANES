# pull down the NHANES data

# run in container (must build nhanes-workbench first from this project's Dockerfile):
# docker \
#     run \
#         --rm \
#         --name nhanes-workbench \
#         --platform linux/amd64 \
#         -d \
#         -v /tmp:/HostData \
#         -p 8787:8787 \
#         -p 2200:22 \
#         -p 1433:1433 \
#         -e 'CONTAINER_USER_USERNAME=test' \
#         -e 'CONTAINER_USER_PASSWORD=test' \
#         -e 'ACCEPT_EULA=Y' \
#         -e 'SA_PASSWORD=yourStrong(!)Password' \
#         nhanes-workbench

library(glue)

optionList = list(
  optparse::make_option(c("--container-build"), type="logical", default=FALSE, 
                        help="is this script running inside of a container build process", metavar="logical")
); 

optParser = optparse::OptionParser(option_list=optionList);
opt = optparse::parse_args(optParser);

# this varaible is used below to determine how to handle errors.
# if running in a container build process, any errors encountered
# in the processing of the files should cause R to return non-zero
# status to the OS, causing the container build to fail.
runningInContainerBuild = opt[["container-build"]]

# parameters to connect to SQL
sqlHost = "localhost"
sqlUserName = "sa"
sqlPassword = "yourStrong(!)Password"
sqlDefaultDb = "master"

# control persistence of downloaded and extracted text files
persistTextFiles = FALSE

outputDirectory = "/NHANES/Data"

# Try using the comprehensive listing
comprehensiveHtmlDataList = "https://wwwn.cdc.gov/nchs/nhanes/search/datapage.aspx"
htmlFileList = readLines(comprehensiveHtmlDataList)
htmlTableStartLine = grep(x = htmlFileList, pattern = "<table")
htmlTableEndLine = grep(x = htmlFileList, pattern = "</table")

if (length(htmlTableStartLine) != 1 || length(htmlTableEndLine) != 1 ) {
  stop(
    paste(
      "The original HTML file listing at", 
      comprehensiveHtmlDataList, 
      "contained only one table.  You will need to do some investigation and debugging."
    )
  )
}

# Convert the HTML table to a data frame so we can iterate on the rows
htmlObj = xml2::read_html(paste(collapse="\n", htmlFileList[htmlTableStartLine : htmlTableEndLine]))

fileListTable = dplyr::`%>%`(htmlObj, rvest::html_table())[[1]]

# Add Data File Name column, populate with Data File Names
fileListTable$'Data File Name' <- gsub(" Doc","",as.character(fileListTable$'Doc File'))

# Replace URLS with the incorrect years in their url
fileListTable$Years[fileListTable$Years == "1988-2020"] <- '1999-2000'
fileListTable$Years[fileListTable$Years == "2007-2012"] <- '2007-2008'
fileListTable$Years[fileListTable$Years == "1999-2004"] <- '1999-2000'
fileListTable$Years[fileListTable$Years == "1999-2020"] <- '1999-2000'

# Replace Doc File Column with the correct url
fileListTable$'Doc File' <- glue("https://wwwn.cdc.gov/Nchs/Nhanes/{fileListTable$Years}/{fileListTable$'Doc File'}.htm")
fileListTable$'Doc File'<-gsub(" Doc","",as.character(fileListTable$'Doc File'))

# Replace Data File Column with the correct url
fileListTable$'Data File' <- glue("https://wwwn.cdc.gov/Nchs/Nhanes/{fileListTable$Years}/{fileListTable$'Data File'}.XPT")
fileListTable$'Data File'<- gsub('([A-z]+) .*', '\\1', as.character(fileListTable$'Data File'))
fileListTable$'Data File' <- paste0(fileListTable$'Data File', ".XPT")
fileListTable$'Data File'<-gsub(" Data","",as.character(fileListTable$'Data File'))

# Ignore rows which being with the prefix P_, these are the "pandemic" 2017 -- 2020 summary files
fileListTable <- fileListTable[!grepl(pattern = "^P_", fileListTable$'Data File Name'),]

# Remove the PAHS_H File specifically, the other PAHS files are OK.
fileListTable <- fileListTable[!grepl("PAHS_H", fileListTable$'Data File Name'),]  

# Create groups by removing anything after the first "_" from 'Data File Name' 
fileListTable$'Data File Name' <- gsub('^(.*?)_.*', '\\1', as.character(fileListTable$'Data File Name'))

# Skip the data types and URLs that cause issues
fileListTable <- fileListTable[!grepl("https://wwwn.cdc.govNA", fileListTable$'Data File'),]  # invalid URL
fileListTable <- fileListTable[!grepl("https://wwwn.cdc.gov/Nchs/Nhanes/Dxa/Dxa.aspx", fileListTable$'Data File'),]  # invalid URL
fileListTable <- fileListTable[!grepl("PAXMIN", fileListTable$'Data File Name'),]       # large files take a long time to download, not likely used in most cases
fileListTable <- fileListTable[!grepl("All Years", fileListTable$'Data File Name'),]       # large files take a long time to download, not likely used in most cases
fileListTable <- fileListTable[!grepl("PAX80", fileListTable$'Data File Name'),]        # only available by FTP
fileListTable <- fileListTable[!grepl("VID", fileListTable$'Data File Name'),]          # Vitamin D data is broken and redirects to HTML instead of SAS data file
fileListTable <- fileListTable[!grepl("OMP", fileListTable$'Data File Name'),]          # redirect to an ASP page
fileListTable <- fileListTable[!grepl("PAXLUX", fileListTable$'Data File Name'),]       # broken links
fileListTable <- fileListTable[!grepl("ALQYTH", fileListTable$'Data File Name'),]       # broken links, not supposed to be available for download anyway
fileListTable <- fileListTable[!grepl("SSCT", fileListTable$'Data File Name'),]         # broken links
fileListTable <- fileListTable[!grepl("CHLMDA", fileListTable$'Data File Name'),]       # not publicly available
fileListTable <- fileListTable[!grepl("CHLA", fileListTable$'Data File Name'),]         # not publicly available
fileListTable <- fileListTable[!grepl("CHLM", fileListTable$'Data File Name'),]         # not publicly available
fileListTable <- fileListTable[!grepl("LAB05", fileListTable$'Data File Name'),]        # not publicly available
fileListTable <- fileListTable[!grepl("L05", fileListTable$'Data File Name'),]          # not publicly available
fileListTable <- fileListTable[!grepl("PAXRAW", fileListTable$'Data File Name'),]       # not publicly available
fileListTable <- fileListTable[!grepl("SPXRAW", fileListTable$'Data File Name'),]       # not publicly available
fileListTable <- fileListTable[!grepl("PAXMIN", fileListTable$'Data File Name'),]       # not publicly available


# clean up data type names
fileListTable[,"Data File Name"] = 
  unlist(
    lapply(
      X = fileListTable[,"Data File Name"],
      FUN = function(x) {
        return(
          gsub(
            gsub(
              gsub(
                gsub(
                  gsub(
                    gsub(
                      gsub(
                        gsub(
                          gsub(
                            gsub(
                              gsub(
                                gsub(
                                  gsub(
                                    gsub(
                                      gsub(
                                        x = x, 
                                        pattern = " and ", 
                                        replace = " And ", 
                                        fixed = TRUE
                                      ),
                                      pattern = "/", 
                                      replace = "", 
                                      fixed = TRUE
                                    ), 
                                    pattern = " ", 
                                    replace = "", 
                                    fixed=TRUE
                                  ), 
                                  pattern = "-", 
                                  replace = "", 
                                  fixed=TRUE
                                ), 
                                pattern = "'", 
                                replace="", 
                                fixed=TRUE
                              ),
                              pattern = ",", 
                              replace = "", 
                              fixed = TRUE
                            ),
                            pattern = "&",
                            replace = "And",
                            fixed = TRUE
                          ),
                          pattern = ".",
                          replace = "",
                          fixed = TRUE
                        ),
                        pattern = "–",
                        replace = "",
                        fixed = TRUE
                      ),
                      pattern = ":",
                      replace = "",
                      fixed = TRUE
                    ),
                    pattern = "(",
                    replace = "",
                    fixed = TRUE
                  ),
                  pattern = ")",
                  replace = "",
                  fixed = TRUE
                ),
                pattern = ";",
                replace = "",
                fixed = TRUE
              ),
              pattern = "+",
              replace = "",
              fixed = "TRUE"
            ),
            pattern = "_",
            replace = "",
            fixed = TRUE
          )
        )
      }
    )
  )

# enumerate distinct data types
fileListTable$"Data File Name" <- strtrim(fileListTable$"Data File Name", 128)
dataTypes = unique(fileListTable$"Data File Name")

# fix case-differing strings
dataTypes = sort(dataTypes)
upperCaseDataTypes = toupper(dataTypes)
uniqueUpper = unique(upperCaseDataTypes)
lapply(uniqueUpper, FUN=function(upperCaseWord){return (max(which(upperCaseDataTypes == upperCaseWord)))})
representativeStringIndex = unlist(lapply(uniqueUpper, FUN=function(upperCaseWord){return (max(which(upperCaseDataTypes == upperCaseWord)))}))
names(uniqueUpper) = dataTypes[representativeStringIndex]
dataTypes = names(uniqueUpper)
names(dataTypes) = uniqueUpper

cnames = colnames(fileListTable)
fileListTable = cbind(fileListTable,  dataTypes[toupper(fileListTable$"Data File Name")])
colnames(fileListTable) = c(cnames, "ScrubbedDataType")

# connect to SQL
cn = MsSqlTools::connectMsSqlSqlLogin(
  server = sqlHost, 
  user = sqlUserName, 
  password = sqlPassword, 
  database = sqlDefaultDb
)

#--------------------------------------------------------------------------------------------------------
# performance notes for large XPTs:
# 14.6G for a single PAXMIN
# 10G after gc()
# baloons to 32G after second read
# 20G after gc()
# 40 G during bind_rows
# 20 G after rm XPTs and gc()
# 12G file 
#--------------------------------------------------------------------------------------------------------

# create landing zone for the raw data, set recovery mode to simple
SqlTools::dbSendUpdate(cn, "CREATE DATABASE NhanesLandingZone")
SqlTools::dbSendUpdate(cn, "ALTER DATABASE [NhanesLandingZone] SET RECOVERY SIMPLE")
SqlTools::dbSendUpdate(cn, "USE NhanesLandingZone")

# prevent scientific notation
options(scipen = 15)

# track which variables appear in each questionnaire
questionnaireVariables = dplyr::tibble(
  Questionnaire=character(), 
  Variable=character(), 
  BeginYear=numeric(), 
  EndYear=numeric(), 
  TableName=character()
)

# enable restart
i=1
downloadErrors = dplyr::tibble(
  DataType=character(), 
  FileUrl=character(), 
  Error=character()
 )

for (i in i:length(dataTypes)) {
  # get the name of the data type
  currDataType = dataTypes[i]
  
  print(currDataType)
  
  # find all rows with URLs that should be relevant to the current data type
  rowsForCurrDataType = which(fileListTable[,"ScrubbedDataType"] == currDataType)
  
  # assemble a list containing all of the subtables for this data type
  dfList = list()
  
  # pull all of the SAS files for this data type
  for (currRow in rowsForCurrDataType) {
    
    # get the URL for the SAS file pointed to by the current row
    currFileUrl = fileListTable[currRow, "Data File"]
    
    # get the date range for this table
    currYears = fileListTable[currRow, "Years"]
    
    # split the URL on '/' to extract the file name
    urlSplit = strsplit(x = currFileUrl, split = "/", fixed = TRUE)[[1]]
    fileName  = urlSplit[length(urlSplit)]

    #TODO move these to the exlusions group above^^^
    cat("reading ", currFileUrl, "\n")
    
    # attempt to download each file and log errors
    result = tryCatch({
      currTemp = tempfile()
      utils::download.file(
        url = currFileUrl, 
        destfile = currTemp
      )
      z = haven::read_xpt(currTemp)
      file.remove(currTemp)
      z
    }, warning = function(w) {
      downloadErrors <<- dplyr::bind_rows(
        downloadErrors, 
        dplyr::bind_cols(
          "DataType" = currDataType, 
          "FileUrl" = currFileUrl,
          "Error" = "warning"
        )
      )
      return("warning")
    }, error = function(e) {
      downloadErrors <<- dplyr::bind_rows(
        downloadErrors, 
        dplyr::bind_cols(
          "DataType" = currDataType, 
          "FileUrl" = currFileUrl,
          "Error" = "error"
        )
      )
      return("error")
    })
    
    if (result == "warning" || result == "error") {
      next
    }

    # save the survey years in the demographics table
    if (currDataType == "DEMO") {
      years = dplyr::tibble("years" = rep(x=currYears, times=nrow(result)))
      result = dplyr::bind_cols(result, years)
    }

    # append a column containing the URL from which the original data was pulled
    result = dplyr::bind_cols(
      result, 
      dplyr::tibble("DownloadUrl" = rep(x=currFileUrl, times=nrow(result)))
    )

    # append a column containing the questionnaire abbreviation
    result = dplyr::bind_cols(
      result, 
      dplyr::tibble("Questionnaire" = rep(x=gsub(pattern="\\.XPT", replace="", fixed=FALSE, ignore.case=TRUE, fileName), times=nrow(result)))
    )

    beginYear = as.numeric(strsplit(x=currYears, split="-")[[1]][1])
    endYear = as.numeric(strsplit(x=currYears, split="-")[[1]][2])

    # save mapping from questionnaire to variables
    questionnaireVariables =
      dplyr::bind_rows(
        questionnaireVariables, 
        dplyr::bind_cols(
          "Questionnaire" = 
            rep(
              dplyr::pull(result[1, "Questionnaire"]), 
              times = ncol(result)
            ), 
          "Variable" = colnames(result),
          "BeginYear" = rep(beginYear, times = ncol(result)),
          "EndYear" = rep(endYear, times = ncol(result)),
          "TableName" = rep(currDataType, times = ncol(result))
        )
      )
    
    dfList[[length(dfList) + 1]] = result
    rm(result)
    gc()
    
    cat("done reading ", currFileUrl, "\n")
  }
  
  # fix inconsistent types in PSA age variable
  # there are actually two versions of the age variable, 'KID221' and KIQ221
  # not clear whether one or the other is supposed to be double / char from
  # the NHANES documentation
  if (currDataType == "PSA") {
    for (j in 1:length(dfList)) {
      if ("KID221" %in% colnames(dfList[[j]])) {
        dfList[[j]][,"KID221"] = as.character(dfList[[j]][,"KID221"][[1]])
      }
    }
  }
  
  ## if we were unable to pull any files for this data type, then move on
  if (length(dfList) == 0) {
    next
  }
  
  # combine the rows from all of the SAS files for this data type
  m = dplyr::bind_rows(dfList)
  rm(dfList)
  gc()
  
  # if we were able to read a table for this data type
  if (nrow(m) > 0) {
    
    # get a file system location to save the table
    currOutputFileName = paste(sep = "/", outputDirectory, currDataType)
    
    # get data types for each column in our current table
    columnTypes = sapply(m, class)
    
    # identify columns that contain character data
    ixCharacterColumns = which(columnTypes == "character")
    
    # if we have any character columns
    if (length(ixCharacterColumns) > 0) {
      
      # iterate over the character columns
      for (currCharColumn in ixCharacterColumns) {
        
        # fix any embedded line endings
        m[,currCharColumn] = gsub(pattern = "[\r\n]", replacement = "", x = dplyr::pull(m[,currCharColumn]))
      }
    }
    
    # write the table to file
    write.table(
      m,
      file = currOutputFileName,
      sep = "\t",
      na = "",
      row.names = FALSE,
      col.names = FALSE,
      quote = FALSE
    )

    # generate SQL table definitions from column types in tibbles
    createTableQuery = DBI::sqlCreateTable(DBI::ANSI(), currDataType, m)

    # change TEXT to VARCHAR(256)
    createTableQuery = gsub(createTableQuery, pattern = "\" TEXT", replace = "\" VARCHAR(256)", fixed = TRUE)

    # change DOUBLE to float
    createTableQuery = gsub(createTableQuery, pattern = "\" DOUBLE", replace = "\" float", fixed = TRUE)

    # we know that SEQN should always be an INT
    createTableQuery = gsub(createTableQuery, pattern = "\"SEQN\" float", replace = "\"SEQN\" INT", fixed = TRUE) # nolint

    # create the table in SQL
    SqlTools::dbSendUpdate(cn, createTableQuery)

    if (currDataType == "AUX") {
      currOutputFileName = "/NHANES/Data/AUXtry"
      write.table(
      m,
      file = currOutputFileName,
      sep = "\t",
      na = "",
      row.names = FALSE,
      col.names = FALSE,
      quote = FALSE
    )
    }

    # run bulk insert
    insertStatement = paste(sep="",
                            "BULK INSERT ",
                            currDataType,
                            " FROM '",
                            currOutputFileName,
                            "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
    )

    SqlTools::dbSendUpdate(cn, insertStatement)


        # if we don't want to keep the derived text files, then delete to save disk space
    if (!persistTextFiles) {
      file.remove(currOutputFileName)
    }
  }
  
  # keep memory as clean as possible
  rm(m)
  gc()
}

# generate CREATE TABLE statement
createTableQuery = DBI::sqlCreateTable(DBI::ANSI(), "QuestionnaireVariables", questionnaireVariables)

# fix TEXT column types
createTableQuery = gsub(createTableQuery, pattern = "\" TEXT", replace = "\" VARCHAR(256)", fixed = TRUE)

# change DOUBLE to float
createTableQuery = gsub(createTableQuery, pattern = "\" DOUBLE", replace = "\" float", fixed = TRUE)

# create the table in SQL
SqlTools::dbSendUpdate(cn, createTableQuery)

# generate file name for temporary output
currOutputFileName = paste(sep = "/", outputDirectory, "QuestionnaireVariables.txt")

# write questionnaireVariables table to disk
write.table(
  questionnaireVariables,
  file = currOutputFileName,
  sep = "\t",
  na = "",
  row.names = FALSE,
  col.names = FALSE,
  quote = FALSE
)

# issue BULK INSERT
insertStatement = paste(sep="",
                        "BULK INSERT ",
                        "QuestionnaireVariables",
                        " FROM '",
                        currOutputFileName,
                        "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
)
SqlTools::dbSendUpdate(cn, insertStatement)

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# shrink transaction log
SqlTools::dbSendUpdate(cn, "DBCC SHRINKFILE(NhanesLandingZone_log)")

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# create a table to hold records of the failed file downloads
SqlTools::dbSendUpdate(cn, "CREATE TABLE DownloadErrors (DataType varchar(1024), FileUrl varchar(1024), Error varchar(256))")

# generate file name for temporary output
currOutputFileName = paste(sep = "/", outputDirectory, "DownloadErrors.txt")

# write failed file downloads table to disk
write.table(
  downloadErrors,
  file = currOutputFileName,
  sep = "\t",
  na = "",
  row.names = FALSE,
  col.names = FALSE,
  quote = FALSE
)

# issue BULK INSERT
insertStatement = paste(sep="",
                        "BULK INSERT ",
                        "DownloadErrors",
                        " FROM '",
                        currOutputFileName,
                        "' WITH (KEEPNULLS, TABLOCK, ROWS_PER_BATCH=2000, FIRSTROW=1, FIELDTERMINATOR='\t')"
)

SqlTools::dbSendUpdate(cn, insertStatement)

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# shrink transaction log
SqlTools::dbSendUpdate(cn, "DBCC SHRINKFILE(NhanesLandingZone_log)")

# issue checkpoint
SqlTools::dbSendUpdate(cn, "CHECKPOINT")

# issue checkpoint
#SqlTools::dbSendUpdate(cn, "SHUTDOWN")
