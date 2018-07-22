library(sf)

# Get links with metadata
nlinks = read_sf("data/sensitive/initial/Network_link.shp", stringsAsFactors = T)
links = read_sf("data/sensitive/initial/links.geojson")
nlinks = st_transform(nlinks, st_crs(links))
links = st_crop(nlinks, links)

dir.create("data/sensitive/processed", showWarnings = F)

# nlinks contains a mix of points, linestrings and multilinestrings.
# Filter to contain only (multi)linestrings because points will mess us up.
links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]
write_sf(links, "data/sensitive/processed/links.gpkg")
