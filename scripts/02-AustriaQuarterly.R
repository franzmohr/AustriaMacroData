

rm(list = ls())

library(dplyr)
library(arrow)

files <- list.files("data/bronze", full.names = TRUE)

result <- NULL
for (file_i in files) {

  if (!is.null(result)) {
    temp <- read.csv(file_i)
    result <- full_join(result, temp, by = "PERIOD")
  } else {
    result <- read.csv(file_i)
  }
  
}

# rm(list = ls())
# 
# library(ecb)
# library(eurostat)
# library(dplyr)
# library(lubridate)
# library(oenb)
# library(tidyr)
# library(readxl)
# library(zoo)
# 
# 
# 
# # Unemployment (international definition) ----
# u <- get_data("LFSI.M.AT.S.UNEHRT.TOTAL0.15_74.T") %>% 
#   rename(date = obstime,
#          value = obsvalue) %>%
#   mutate(date = as.Date(paste0(date, "-01")),
#          date = as.yearqtr(date)) %>%
#   group_by(date) %>%
#   filter(n() == 3) %>%
#   summarise(u = mean(value)) %>%
#   mutate(date = as.Date(date))
# 
# # Inflation ----
# infl <- get_data("HICP.M.AT.N.000000.4D0.ANR") %>% 
#   rename(date = obstime,
#          value = obsvalue) %>%
#   mutate(date = as.Date(paste0(date, "-01")),
#          date = as.yearqtr(date)) %>%
#   group_by(date) %>%
#   filter(n() == 3) %>%
#   summarise(Dp = mean(value)) %>%
#   mutate(date = as.Date(date))
# 
# 
# # House prices ----
# hprices <- get_data("RESR.Q.AT._T.N._TR.TVAL.4F0.TB.N.IX") %>%
#   select(obstime, obsvalue) %>%
#   rename(date = obstime,
#          hp = obsvalue) %>%
#   filter(!is.na(hp)) %>%
#   mutate(date = as.Date(as.yearqtr(date, "%Y-Q%q")))
# 
# # Interest rates (RRE) ----
# r_rre <- get_data("MIR.M.AT.B.A2C.A.R.A.2250.EUR.P") %>% 
#   rename(date = obstime,
#          value = obsvalue) %>%
#   mutate(date = as.Date(paste0(date, "-01")),
#             date = as.yearqtr(date)) %>%
#   group_by(date) %>%
#   filter(n() == 3) %>%
#   summarise(r_rre = mean(value)) %>%
#   mutate(date = as.Date(date))
# 
# 
# # New loans (RRE) ----
# credit_rre <- get_data("MIR.M.AT.B.A2C.A.B.A.2250.EUR.") %>%
#   rename(date = obstime,
#          value = obsvalue) %>%
#   mutate(name = paste0(ir_bus_cov, "_", bs_count_sector)) %>%
#   select(date, name, value) %>%
#   pivot_wider() %>%
#   mutate(value = ifelse(is.na(P_2250), N_2250 - R_2250, P_2250),
#          name = "crdt_rre") %>%
#   filter(!is.na(value)) %>%
#   select(date, name, value) %>%
#   mutate(date = as.Date(paste0(date, "-01")),
#          date = as.yearqtr(date)) %>%
#   group_by(date) %>%
#   filter(n() == 3) %>%
#   summarise(credit_rre = sum(value)) %>%
#   mutate(date = as.Date(date))
# 
# 
# result <- u %>%
#   full_join(infl, by = "date") %>%
#   full_join(hprices, by = "date") %>%
#   full_join(r_rre, by = "date") %>%
#   full_join(credit_rre, by = "date") %>%
#   arrange(date)
# 
# AustriaQuarterly <- ts(result[, -1], start = c(1995,1), frequency = 4)
# usethis::use_data(AustriaQuarterly, overwrite = TRUE)



# # National unemployment data ----
# 
# # Quelle: https://www.ams.at/arbeitsmarktdaten-und-medien/arbeitsmarkt-daten-und-arbeitsmarkt-forschung/berichte-und-auswertungen
# # Alternative Quelle: https://www.data.gv.at/2023/07/24/daten-fuer-alle-ams-veroeffentlicht-11-neue-offene-datensaetze-zu-arbeitslosigkeit-und-offenen-stellen/ 
# 
# years <- 2016:as.numeric(substring(Sys.Date(), 1, 4))
# url_path <- "https://www.ams.at/content/dam/download/arbeitsmarktdaten/%c3%b6sterreich/berichte-auswertungen/001_amd-nuts3_monate_"
# col_names <- c("region", "w_unselb", "w_al", "w_quote", "m_unselb", "m_al", "m_quote", "g_unselb", "g_al", "g_quote")
# months <- c("")
# result <- NULL
# for (i in years) {
#   
#   temp_file <- tempfile()
#   file_type <- ifelse(i >= 2022, ".xlsx", ".xls")
#   try_down <- try(download.file(paste(url_path, i, file_type, sep = ""),
#                                 destfile = temp_file,
#                                 mode = "wb"))
#   
#   if (!inherits(try_down, "try-error")) {
#     sheets <- readxl::excel_sheets(temp_file)
#     sheets <- sheets[!grepl("jahr", tolower(sheets))]
#     
#     for (j in sheets) {
#       temp <- readxl::read_excel(temp_file, sheet = j, skip = 9,
#                                  col_names = col_names) %>%
#         mutate(date = j,
#                year = i) %>%
#         na.omit()
#       
#       result <- dplyr::bind_rows(result, temp)
#     }
#   }
#   
#   file.remove(temp_file)
# }
# 
# unemp_nat <- result %>%
#   filter(region == "Österreich") %>%
#   mutate(month = dplyr::case_when(grepl("jän", date) ~ "01",
#                                   grepl("feb", date) ~ "02",
#                                   grepl("mär", date) ~ "03",
#                                   grepl("apr", date) ~ "04",
#                                   grepl("mai", date) ~ "05",
#                                   grepl("jun", date) ~ "06",
#                                   grepl("jul", date) ~ "07",
#                                   grepl("aug", date) ~ "08",
#                                   grepl("sep", date) ~ "09",
#                                   grepl("okt", date) ~ "10",
#                                   grepl("nov", date) ~ "11",
#                                   grepl("dez", date) ~ "12"),
#          date = paste0(year, "-", month)) %>%
#   select(date, emp_nat = g_unselb, unemp_nat = g_al, uratio_nat = g_quote) %>%
#   pivot_longer(cols = -c("date"))

# 
# 
# 
# 
# 
# 
# # Confidence ----
# 
# download_file <- tempfile(tmpdir = download_folder <- tempdir())
# 
# suffix <- "consumer_total_nsa_nace2"
# 
# # Try download for current month
# curr_date <- Sys.Date()
# curr_month <- lubridate::month(curr_date)
# curr_month <- ifelse(nchar(curr_month) == 1, paste0("0", curr_month), curr_month)
# curr_year <- substring(lubridate::year(curr_date), 3, 4)
# curr_month <- paste0(curr_year, curr_month)
# try(download.file(paste0("https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_", curr_month, "/", suffix, ".zip"),
#                   destfile = download_file),
#     silent = TRUE)
# zipped_files <- unzip(download_file, exdir = download_folder)
# 
# # Download failed try it with download of one month earlier
# if (length(zipped_files) == 0) {
#   curr_date <- lubridate::floor_date(Sys.Date(), "month") - 1
#   curr_month <- lubridate::month(curr_date)
#   curr_month <- ifelse(nchar(curr_month) == 1, paste0("0", curr_month), curr_month)
#   curr_year <- substring(lubridate::year(curr_date), 3, 4)
#   curr_month <- paste0(curr_year, curr_month)
#   try(download.file(paste0("https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_", curr_month, "/", suffix, ".zip"),
#                     destfile = download_file))
# }
# zipped_files <- unzip(download_file, exdir = download_folder)
# 
# # Download failed try it with download of one month earlier
# # if (length(zipped_files) == 0) {
# #   curr_date <- lubridate::floor_date(Sys.Date(), "month") - 32
# #   curr_month <- lubridate::month(curr_date)
# #   curr_month <- ifelse(nchar(curr_month) == 1, paste0("0", curr_month), curr_month)
# #   curr_year <- substring(lubridate::year(curr_date), 3, 4)
# #   curr_month <- paste0(curr_year, curr_month)
# #   try(download.file(paste0("https://ec.europa.eu/economy_finance/db_indicators/surveys/documents/series/nace2_ecfin_", curr_month, "/", suffix, ".zip"),
# #                     destfile = download_file))
# # }
# # zipped_files <- unzip(download_file, exdir = download_folder)
# 
# # excel_sheets(zipped_files)
# monthly_data <- read_excel(zipped_files, "CONSUMER MONTHLY", na = "NA")
# names(monthly_data)[1] <- "date"
# monthly_data <- monthly_data %>%
#   mutate(date = substring(date, 1, 7))
# 
# quarterly_data <- read_excel(zipped_files, "CONSUMER QUARTERLY", na = "NA")
# names(quarterly_data)[1] <- "date"
# quarterly_data <- quarterly_data %>%
#   mutate(date = as.Date(as.yearqtr(date, "%Y-Q%q")),
#          date = ceiling_date(date, "quarter") - 1,
#          date = substring(date, 1, 7))
# 
# survey <- bind_rows(monthly_data,
#                     quarterly_data) %>%
#   pivot_longer(cols = -c("date")) %>%
#   filter(!is.na(value)) %>%
#   mutate(sector = substring(name, 1, 4),
#          ctry = substring(name, 6, 7),
#          subsector = substring(name, 9, 11),
#          name = substring(name, 13, nchar(name)),
#          sadj = FALSE,
#          question = regmatches(name, regexpr("[^.]*", name)),
#          answer = regmatches(name, regexpr("(?<=\\.)[^.]*(?=\\.)", name, perl = TRUE)),
#          freq = substring(name, nchar(name), nchar(name))) %>%
#   filter(ctry == "AT") %>%
#   select(!name) %>%
#   rename(name = question) %>%
#   select(date, name, value) %>%
#   mutate(name = paste0("srvy", tolower(name)),
#          date = substring(date, 1, 7))
# 
# temp <- bind_rows(credit_rre, r_rre, unemp_ilo, unemp_nat, infl, hprices, survey) %>% 
#   #filter(date >= "2018-08") %>%
#   select(date, name, value) %>%
#   pivot_wider() %>%
#   #na.omit() %>%
#   arrange(date) %>% 
#   mutate(kimv = ifelse(date >= "2022-08" & date <= "2025-06", 1, 0))
# 


