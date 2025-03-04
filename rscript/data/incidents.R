# Script to turn original data file of incidents into an RDS for later use
# Two different RDS are created with the same data: a tsibble and a gts object
# Input: Nature_of_Incidents.xlsx
# Outputs: incidents_tsbl.rds, incidents_gts.rds

library(tidyverse)
library(lubridate)
library(tsibble)
library(fabletools)
library(hts)
source(here::here("rscript/data/holidays.R"))

# Read data
incidents_original <- here::here("data/Nature_of_Incidents_Attended.xlsx") |>
  readxl::read_excel() |>
  mutate(date = as_date(Incident_Date)) |>
  janitor::clean_names() |>
  force_tz(date, tz = "GB")

# Nature of incidents with low volume
nature_of_incident_low <- c(
  "AUTOMATIC CRASH NOTIFICATION",
  "INACCESSIBLE INCIDENT/OTHER ENTRAP",
  "INTERFACILITY EVALUATION/TRANSFER",
  "MAJOR INCIDENT - OVERRIDE PROQA",
  "TRANSFER/INTERFACILITY/PALLIATIVE"
)

# Count number of incidents
incidents <- incidents_original |>
  mutate(nature_of_incident = as.numeric(nature_of_incident)) |>
  mutate(nature_of_incident = ifelse(!is.na(nature_of_incident), nature_of_incident_description, "upgrade")) |>
  mutate(nature_of_incident = ifelse(nature_of_incident %in% nature_of_incident_low, "other", nature_of_incident)) |>
  group_by(lhb_code, category, nature_of_incident, date) |>
  summarise(incidents = sum(total_incidents), .groups = "drop") |>
  mutate(
    category = factor(category, level = c("RED", "AMBER", "GREEN")),
    nature_of_incident = factor(nature_of_incident),
    lhb_code = factor(lhb_code)
  )
# Convert to tsibble
incidents_tsbl <- incidents |>
  as_tsibble(index = date, key = c(lhb_code, category, nature_of_incident)) |>
  fill_gaps(incidents = 0, .full = TRUE)
# Save as rds
write_rds(incidents_tsbl, paste0(storage_folder, "incidents_tsbl.rds"), compress = "bz2")

# Small data set in gts format
incidents_tsbl |>
  as_tibble() |>
  filter(nature_of_incident == "BREATHING PROBLEMS", lhb_code == "BC") |>
  select(-nature_of_incident, -lhb_code) |>
  mutate(category = recode(category, "GREEN" = "GRE", "AMBER" = "AMB")) |>
  pivot_wider(names_from = category, values_from = incidents) |>
  # filter(date <= "2015-12-31") |>
  select(-date) |>
  mutate(BLU = 0) |>
  ts(frequency = 7) |>
  hts() |>
  write_rds(paste0(storage_folder, "incidents_test_gts.rds"), compress = "bz2")

# Prepare full data in gts format
incident_modify <- incidents_tsbl |>
  as_tibble() |>
  # Replace incident names with strings of equal length
  mutate(nature = case_when(
    nature_of_incident == "ABDOMINAL PAIN/PROBLEMS" ~ "ABDOMINAL",
    nature_of_incident == "ALLERGIES(REACTIONS)/ENVENOMATIONS" ~ "ALLERGIES",
    nature_of_incident == "ANIMAL BITES/ATTACKS" ~ "ANIMALBIT",
    nature_of_incident == "ASSAULT/SEXUAL ASSAULT" ~ "SEXASSAUL",
    nature_of_incident == "BREATHING PROBLEMS" ~ "BREATHING",
    nature_of_incident == "BURNS(SCALDS)/EXPLOSION" ~ "BURNSSCAL",
    nature_of_incident == "CARBON MONOXIDE/INHALATION/HAZCHEM" ~ "CARBONMON",
    nature_of_incident == "CARDIAC/RESPIRATORY ARREST/DEATH" ~ "RESPIRATO",
    nature_of_incident == "CHEST PAIN" ~ "CHESTPAIN",
    nature_of_incident == "CONVULSIONS/FITTING" ~ "CONVULSIO",
    nature_of_incident == "DIABETIC PROBLEMS" ~ "DIABETICS",
    nature_of_incident == "DROWNING(NEAR)/DIVING/SCUBA" ~ "DROWNINGS",
    nature_of_incident == "ELECTROCUTION/LIGHTNING" ~ "LIGHTNING",
    nature_of_incident == "HAEMORRHAGE/LACERATIONS" ~ "HAEMORRHA",
    nature_of_incident == "HEALTH CARE PROFESSIONAL" ~ "PROFESSIO",
    nature_of_incident == "OVERDOSE/POISONING (INGESTION)" ~ "OVERDOSES",
    nature_of_incident == "PREGNANCY/CHILDBIRTH/MISCARRIAGE" ~ "PREGNANCY",
    nature_of_incident == "PROQA COMPLETED ON CARDSET" ~ "PROQACOMP",
    nature_of_incident == "PSYCH/ABNORMAL BEHAVIOUR/SUICIDE" ~ "SUICIDEPS",
    nature_of_incident == "SICK PERSON - SPECIFIC DIAGNOSIS" ~ "SICKPERSO",
    nature_of_incident == "STAB/GUNSHOT/PENTRATING TRAUMA" ~ "STABGUNSH",
    nature_of_incident == "STROKE - CVA" ~ "STROKECVA",
    nature_of_incident == "TRAFFIC/TRANSPORTATION ACCIDENTS" ~ "TRAFFICAC",
    nature_of_incident == "TRAUMATIC INJURIES, SPECIFIC" ~ "TRAUMATIC",
    nature_of_incident == "UNCONSCIOUS/FAINTING(NEAR)" ~ "UNCONSCIO",
    nature_of_incident == "UNKNOWN PROBLEM - COLLAPSE-3RD PTY" ~ "UNKNOWNPR",
    nature_of_incident == "BACK PAIN (NON-TRAUMA/NON-RECENT)" ~ "BACKPAINS",
    nature_of_incident == "EYE PROBLEMS/INJURIES" ~ "EYEPROBLE",
    nature_of_incident == "HEART PROBLEMS/A.I.C.D" ~ "HEARTPROB",
    nature_of_incident == "HEAT/COLD EXPOSURE" ~ "HEATCOLDS",
    nature_of_incident == "CHOKING" ~ "CHOKINGSS",
    nature_of_incident == "FALLS" ~ "FALLSTHRO",
    nature_of_incident == "HEADACHE" ~ "HEADACHES",
    nature_of_incident == "upgrade" ~ "upgradess",
    nature_of_incident == "other" ~ "allothers"
  ))

incident_ready <- incident_modify |>
  # Recode keys to be of equal length within each key
  select(date, lhb = lhb_code, category, nature, incident = incidents) |>
  mutate(category = case_when(
    category == "RED" ~ "RED",
    category == "GREEN" ~ "GRE",
    category == "AMBER" ~ "AMB"
  )) |>
  mutate(lhb = case_when(
    lhb == "CTM" ~ "CT",
    lhb == "POW" ~ "PO",
    lhb == "AB" ~ "AB",
    lhb == "BC" ~ "BC",
    lhb == "CV" ~ "CV",
    lhb == "HD" ~ "HD",
    lhb == "SB" ~ "SB"
  )) |>
  mutate(region = case_when(
    lhb == "CT" ~ "S",
    lhb == "PO" ~ "C",
    lhb == "AB" ~ "S",
    lhb == "BC" ~ "N",
    lhb == "CV" ~ "S",
    lhb == "HD" ~ "C",
    lhb == "SB" ~ "C"
  ))


incident_gt <- incident_ready |>
  as_tsibble(index = date, key = c(region, lhb, category, nature)) |>
  aggregate_key((region / lhb) * category * nature, incident = sum(incident))
write_rds(incident_gt, paste0(storage_folder, "incidents_gt.rds"), compress = "bz2")


a1 <- incident_ready |>
  filter(lhb == "CV", category == "RED", nature == "FALLSTHRO") |>
  select(date, delet = incident)
incident_gts <- a1
hb <- unique(incident_ready$lhb)
cat <- unique(incident_ready$category)
nat <- unique(incident_ready$nature)
region <- sort(unique(incident_ready$region))
for (i in seq_along(hb)) {
  region <- case_when(
    hb[i] == "CT" ~ "S",
    hb[i] == "PO" ~ "C",
    hb[i] == "AB" ~ "S",
    hb[i] == "BC" ~ "N",
    hb[i] == "CV" ~ "S",
    hb[i] == "HD" ~ "C",
    hb[i] == "SB" ~ "C"
  )
  for (j in seq_along(cat)) {
    for (k in seq_along(nat)) {
      fil <- incident_ready |>
        filter(
          lhb == hb[i],
          category == cat[j],
          nature == nat[k]
        )
      name <- paste0(
        region,
        hb[i],
        cat[j],
        nat[k]
      )
      if (nrow(fil) > 0) {
        a <- select(fil, incident)
        colnames(a) <- name
        incident_gts <- bind_cols(incident_gts, a)
      }
    }
  }
}

incident_all <- incident_gts |>
  select(-delet, -date)

# Write out final rds
incident_all |>
  ts(frequency = 7) |>
  gts(characters = list(c(1, 2), 3, 9)) |>
  write_rds(paste0(storage_folder, "incidents_gts.rds"), compress = "bz2")

# Covariates for gts format

readRDS(paste0(storage_folder, "holiday_dummy.rds")) |>
  as_tibble() |>
  select(-date) |>
  ts(frequency = 7) |>
  write_rds(paste0(storage_folder, "holidays_ts.rds"), compress = "bz2")
