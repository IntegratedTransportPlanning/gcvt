library(sf)

links = read_sf("data/sensitive/output20180724/ShapeGeometry/Base_links.shp", stringsAsFactors = T)

# Crop to study region and transform to 4326.
bounds = st_bbox(read_sf("data/sensitive/initial/links.geojson"))
links = st_transform(links, st_crs(bounds))
links = st_crop(links, bounds)

# Remove points
links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]

# Load and crop metadata
scenarios = list(
  base = read.csv("data/sensitive/output20180724/Link_Base_2017.csv", stringsAsFactors = T),
  "base (2025)" = read.csv("data/sensitive/output20180724/Link_Y2025_2025.csv", stringsAsFactors = T),
  "Extend TEN-T (2025)" = read.csv("data/sensitive/output20180724/Link_Y2025_RoTent_2025.csv", stringsAsFactors = T)
)
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Remove connectors from geometry
links = links[!grepl("Connect", scenarios[[1]]$LType),]

# Crop scenarios again to reduced geometry
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Drop unused LType levels.
scenarios = lapply(scenarios, function(meta) {meta$LType = droplevels(meta$LType); meta})

write_sf(links, "data/sensitive/processed/cropped_links.gpkg")
