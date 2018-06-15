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
