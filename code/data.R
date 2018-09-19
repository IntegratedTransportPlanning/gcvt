#' Study region and countries
#'
#' @aliases eap_region eap_countries
#' @examples
#' \dontrun{
#' library(sf)
#' library(tidyverse)
#' eap_countries = c("Armenia", "Azerbaijan", "Belarus", "Georgia", "Moldova", "Ukraine")
#' eap_countries = spData::world %>%
#'   filter(name_long %in% eap_countries)
#' mapview::mapview(eap_countries)
#' devtools::use_data(eap_countries)
#' eap_buff = st_buffer(eap_countries, 0.00001)
#' eap_region = st_difference(eap_buff, eap_buff) %>%
#'   st_combine() %>%
#'   st_union()
#' plot(eap_region)
#' devtools::use_data(eap_region)
#' }
#' @docType data
#' @keywords datasets
#' @name eap_region
#' @usage data(eap_region)
#' @format An `sf` dataset
NULL

#' Motorways in and around region
#'
#' @aliases eap_motorways
#' @examples
#' \dontrun{
#' library(sf)
#' library(osmdata)
#' eap_countries = c("Armenia", "Azerbaijan", "Belarus", "Georgia", "Moldova", "Ukraine")
#' eap_countries = spData::world %>%
#'   filter(name_long %in% eap_countries)
#' mapview::mapview(eap_countries)
#' devtools::use_data(eap_countries)
#' eap_buff = st_buffer(eap_countries, 0.00001)
#' eap_region = st_difference(eap_buff, eap_buff) %>%
#'   st_combine() %>%
#'   st_union()
#' plot(eap_region)
#' devtools::use_data(eap_region)
#' }
#' @docType data
#' @keywords datasets
#' @name eap_region
#' @usage data(eap_region)
#' @format An `sf` dataset
NULL

# elec = read.csv("data/sensitive/21-Aug/Link_Base_2017.csv", stringsAsFactors = TRUE)
# names(elec)
# library(dplyr)
# elec_diff = elec %>%
#   mutate_if(is.double, function(x) x * 2)
#
# head(elec$Capacity)
# head(elec_diff$Capacity)
# sapply(elec_diff, class)
# sapply(elec, class)
#
# write.csv(elec_diff, "data/sensitive/21-Aug/Link_doubles_2025.csv")
#
# elec_diff_2020 = elec %>% mutate_if(is.double, function(x) x * 1.5) %>% write.csv("data/sensitive/21-Aug/Link_doubles_2020.csv")
# elec_diff_2020 = elec %>% mutate_if(is.double, function(x) x * 3) %>% write.csv("data/sensitive/21-Aug/Link_doubles_2030.csv")

