library(sf)

# Read in link geometry and metadata scenarios and crop to the data of interest.
#
# These cropped datasets are consumed by the viewer apps.
#
# Links are currently of interest if and only if:
#   - they are in the study region
#   - they are not connectors
#   - metadata exists for them
#   - their link geometry is a linestring or multilinestring
#
# You can change this pre-processing script, but the webapps will expect to receive data for which the two assertions hold.
# The webapps also expect the geometry to be exclusively linestrings.

links = read_sf("data/sensitive/14-Nov/Base_links.shp", stringsAsFactors = T)
links = st_transform(links, 4326)

# Crop to study area
eapregion = st_union(read_sf("data/sensitive/eap_zones_only.geojson"))
intersection = unlist(st_intersects(eapregion, links))
links = links[intersection,]

# Remove points
links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]

# Load and name metadata scenarios
scenarios = list(
#  base = read.csv("data/sensitive/final/Link_Base_2017.csv", stringsAsFactors = T),
    "Ecodrive (2025)" = read.csv("data/sensitive/14-Nov/Link_EcoDrive_2025.csv", stringsAsFactors = T),
    "Ecodrive (2030)" = read.csv("data/sensitive/14-Nov/Link_EcoDrive_2030.csv", stringsAsFactors = T),
    "Fleet (2025)" = read.csv("data/sensitive/14-Nov/Link_Fleet_2025.csv", stringsAsFactors = T),
    "Fleet (2030)" = read.csv("data/sensitive/14-Nov/Link_Fleet_2030.csv", stringsAsFactors = T),
    "FleetElectric (2025)" = read.csv("data/sensitive/14-Nov/Link_FleetElectric_2025.csv", stringsAsFactors = T),
    "FleetElectric (2030)" = read.csv("data/sensitive/14-Nov/Link_FleetElectric_2030.csv", stringsAsFactors = T),
    "Urban (2025)" = read.csv("data/sensitive/14-Nov/Link_Urban_2025.csv", stringsAsFactors = T),
    "Urban (2030)" = read.csv("data/sensitive/14-Nov/Link_Urban_2030.csv", stringsAsFactors = T),
    "RailTimetable (2025)" = read.csv("data/sensitive/14-Nov/Link_RailTimeTable_2025.csv", stringsAsFactors = T),
    "RailTimetable (2030)" = read.csv("data/sensitive/14-Nov/Link_RailTimeTable_2030.csv", stringsAsFactors = T),
    "Tent (2030)" = read.csv("data/sensitive/14-Nov/Link_Tent_2030.csv", stringsAsFactors = T),
    "BCP (2030)" = read.csv("data/sensitive/14-Nov/Link_BCP_2030.csv", stringsAsFactors = T),
    "BCPRail (2025)" = read.csv("data/sensitive/14-Nov/Link_BCPRail_2025.csv", stringsAsFactors = T),
    "BCPRail (2030)" = read.csv("data/sensitive/14-Nov/Link_BCPRail_2030.csv", stringsAsFactors = T),
    "GreenPort (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenPort_2030.csv", stringsAsFactors = T),
    "GreenMax (2025)" = read.csv("data/sensitive/14-Nov/Link_GreenMax_2025.csv", stringsAsFactors = T),
    "GreenMax (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenMax_2030.csv", stringsAsFactors = T),
    "GreenShipping (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenShipping_2030.csv", stringsAsFactors = T),
    "Logistic (2030)" = read.csv("data/sensitive/14-Nov/Link_Logistic_2030.csv", stringsAsFactors = T),
    "NoBorder (2030)" = read.csv("data/sensitive/14-Nov/Link_NoBorder_2030.csv", stringsAsFactors = T),
    "TenTRail (2030)" = read.csv("data/sensitive/14-Nov/Link_TentRail_2030.csv", stringsAsFactors = T),
    "Toll (2030)" = read.csv("data/sensitive/14-Nov/Link_Toll_2030.csv", stringsAsFactors = T),
    "AirEfficiency (2030)" = read.csv("data/sensitive/14-Nov/Link_AirEfficiency_2030.csv", stringsAsFactors = T),
    "Do Nothing (2020)" = read.csv("data/sensitive/14-Nov/Link_Y2020_DoNothing_2020.csv", stringsAsFactors = T),
    "Do Nothing (2025)" = read.csv("data/sensitive/14-Nov/Link_Y2025_DoNothing_2025.csv", stringsAsFactors = T),
    "Do Nothing (2030)" = read.csv("data/sensitive/14-Nov/Link_Y2030_DoNothing_2030.csv", stringsAsFactors = T),
    "Do Minimum (2020)" = read.csv("data/sensitive/14-Nov/Link_Y2020_DoNothing_2020.csv", stringsAsFactors = T),
    "Do Minimum (2025)" = read.csv("data/sensitive/14-Nov/Link_Y2025_DoMin_2025.csv", stringsAsFactors = T),
    "Do Minimum (2030)" = read.csv("data/sensitive/14-Nov/Link_Y2030_DoMin_2030.csv", stringsAsFactors = T)
)

# Assert all scenarios contain the same columns and types
scenarios %>%
  lapply(function(meta) {
    all(names(meta) == names(scenarios[[1]])) &
      all(sapply(meta, typeof) == sapply(scenarios[[1]], typeof))
  }) %>%
  as.logical() %>%
  all() %>%
  stopifnot()

# Remove all link geometries for which there is no metadata
links = links[links$ID_LINK %in% scenarios[[1]]$Link_ID,]

# Remove all metadata for which there is no geometry (e.g. the geometry was outside the study area)
# and re-order each scenario to have the same row-order as the geometry.
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Remove connectors from geometry
links = links[!grepl("Connect", scenarios[[1]]$LType),]

# Crop scenarios again to reduced geometry
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Drop unused LType levels.
scenarios = lapply(scenarios, function(meta) {meta$LType = droplevels(meta$LType); meta})

# Assert all scenarios contain the same links as `links` in the same order
scenarios %>%
  lapply(function(meta) {all(links$ID_LINK == as.character(meta$Link_ID))}) %>%
  as.logical() %>%
  all() %>%
  stopifnot()

# The JSON is consumed by the client side app which doesn't need to know anything but the geometry and an id
# (which should just be contiguous ascending integers from 0), so strip all the other data.
st_geometry(links) %>% write_sf("data/sensitive/processed/cropped_links.geojson", delete_dsn = T)

# Due to *exciting behaviour* the geojson we just wrote won't have any ids on its features,
# but if we read it in and write it immediately, then it will have ascending integers from 0 to nrow(links) as ids,
# because the hidden $names attribute is set by read_sf or gdal or something.
# It would be quite nice if SF/GDAL would act symmetrically here, but they don't.
read_sf("data/sensitive/processed/cropped_links.geojson") %>% write_sf("data/sensitive/processed/cropped_links.geojson", delete_dsn = T)

save(scenarios, file = "data/sensitive/processed/cropped_scenarios.RData")
