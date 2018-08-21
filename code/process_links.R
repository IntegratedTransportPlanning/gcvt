library(sf)

links = read_sf("data/sensitive/final/Base_links.shp", stringsAsFactors = T)
links = st_transform(links, 4326)

# Crop to study area
eapregion = st_union(read_sf("data/sensitive/eap_zones_only.geojson"))
intersection = unlist(st_intersects(eapregion, links))
links = links[intersection,]

# Remove points
links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]

# Load and crop metadata
scenarios = list(
  base = read.csv("data/sensitive/final/Link_Base_2017.csv", stringsAsFactors = T),
  "Do Nothing (2020)" = read.csv("data/sensitive/final/Link_Y2020_DoNothing_2020.csv", stringsAsFactors = T),
  "Do Nothing (2025)" = read.csv("data/sensitive/final/Link_Y2025_DoNothing_2025.csv", stringsAsFactors = T),
  "Do Nothing (2030)" = read.csv("data/sensitive/final/Link_Y2030_DoNothing_2030.csv", stringsAsFactors = T)
)
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Remove connectors from geometry
links = links[!grepl("Connect", scenarios[[1]]$LType),]

# Crop scenarios again to reduced geometry
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Drop unused LType levels.
scenarios = lapply(scenarios, function(meta) {meta$LType = droplevels(meta$LType); meta})

write_sf(links, "data/sensitive/processed/cropped_links.gpkg")
save(scenarios, file = "data/sensitive/processed/cropped_scenarios.RData")
