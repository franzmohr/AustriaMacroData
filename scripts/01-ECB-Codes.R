
# Experimential data set on new loans in Austria, which might be added in the
# future for mixed-frequency models


rm(list = ls())

library(dplyr)
library(ecb)

intr <- get_data("MIR.M.AT.B.A2C.A.R.A.2250.EUR.P") %>%
  select(obstime, obsvalue) %>%
  rename(month = obstime, r = obsvalue) %>%
  na.omit()

vol <- get_data("MIR.M.AT.B.A2C.A.B.A.2250.EUR.P") %>%
  select(obstime, obsvalue) %>%
  rename(month = obstime, crdt = obsvalue) %>%
  na.omit()

newcredit <- full_join(intr, vol, by = "month") %>%
  arrange(month)

yr <- as.numeric(substring(newcredit$month[1], 1, 4))
mnth <- as.numeric(substring(newcredit$month[1], 6, 7))

newcredit <- ts(newcredit[, -1], start = c(yr, mnth), frequency = 12)

newcredit <- cbind(newcredit, log(newcredit[, "crdt"]))

d_newcredit <- diff(newcredit)
d_newcredit[, "lcrdit"] <- d_newcredit[, "lcrdit"] * 100

newcredit <- cbind(newcredit, d_newcredit)

dimnames(newcredit) <- list(NULL, c("r", "crdt", "lcrdt", "dr", "dcrdt", "dlcrdt"))

plot(newcredit)

psych::pairs.panels(as.data.frame(newcredit))


rm(list = ls())

library(ecb)
library(dplyr)
library(tidyr)

# New loans to households for house purchase (pure) ----

loans <- get_data("MIR.M.AT.B.A2C.A.B+R.A.2250.EUR.P") %>%
  select(obstime, obsvalue, data_type_mir) %>%
  pivot_wider(names_from = "data_type_mir", values_from = "obsvalue") %>%
  rename(date = obstime,
         loan_vol = B,
         loan_rate = R) %>%
  mutate(date = as.Date(paste0(date, "-01"))) %>%
  select(date, loan_rate, loan_vol) %>%
  arrange(date)

at_rreloans <- ts(loans[, -1], start = c(2017, 8), frequency = 12)


usethis::use_data(at_rreloans, overwrite = TRUE)
