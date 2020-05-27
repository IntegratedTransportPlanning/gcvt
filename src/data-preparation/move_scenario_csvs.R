# Find scenarios in a directory, extract their types, names and years and put them in an (arguably) clearer directory format

library(fs)
library(stringr)
library(tibble)
library(tidyr)
library(dplyr)

source = "data/sensitive/May-2020/"
destination = "data/sensitive/GCVT_Scenario_Pack/"

scenario_names = list.files(source) %>%
  str_match("^(Link|Matrix)_(?:Y20\\d{2}_)?(.*?)_(\\d{4}).csv$") %>% # The Y20xx bit is because of some badly named files...
  as.tibble() %>%
  drop_na() %>%
  select(type=2, name=3, year=4, filename=1)


for (rown in 1:nrow(scenario_names)) {
  row = scenario_names[rown,]
  todir = path(destination, "scenarios", row$name, ifelse(row$type == "Link", "links", "od_matrices"))
  dir_create(todir, recursive = T)
  file_copy(path(source, row$filename), paste(todir, "/", row$year, ".csv", sep=""))
}
