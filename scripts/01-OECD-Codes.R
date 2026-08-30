


codes <- read.csv("scripts/Group-01-NIPA/OECD-Codes.csv")


for (i in 1:nrow(codes)) {
  code_i <- codes[i, "Code"]
  url <- paste0(codes[i, "Link"], "?format=csvfilewithlabels")
  
  path_landing <- paste0("data/landing/", code_i, ".csv")
  try(download.file(url, destfile = path_landing))
  
  df <- read.csv(path_landing)
  df <- df[, c("TIME_PERIOD", "OBS_VALUE")]
  df <- df[order(df[, "TIME_PERIOD"]), ]
  names(df) <- c("PERIOD", code_i)
  
  path_bronze <- paste0("data/bronze/", code_i, ".csv")
  write.csv(df, file = path_bronze, row.names = FALSE)
  rm(df)
}







