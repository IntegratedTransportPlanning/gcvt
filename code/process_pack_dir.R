# Discover all scenario csvs and pre-process them into the appropriate form.

library(tidyverse)
library(fs)
library(sf)
library(reshape2)

BASE_DIR = "./"
# Where to read and write everything. Eg: 
# BASE_DIR = "/home/mark/gcvt-metadata/"
source(paste(BASE_DIR, "R/metadata.R", sep = ""))

# Return DF(name, year, type, dataDF)
read_scenarios = function(pack_dir) {
  scenarios = tibble(name=character(0), year=integer(0), type=character(0), dataDF=list())
  for (spath in dir_ls(path(pack_dir, "scenarios"))) {
    for (tpath in dir_ls(spath)) {
      for (ypath in dir_ls(tpath)) {
        scenarios[nrow(scenarios) + 1,] = list(
          basename(spath), basename(ypath) %>% path_ext_remove(), basename(tpath), list(read_csv(ypath)))
      }
    }
  }
  scenarios
}

# geometry, linkscenarios -> geometry, linkscenarios
#
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
# linksscenarios = scenarios[scenarios$type=="links"]$dataDF
process_links = function(geom, scenarios) {

  # Convert all character columns to factor
  lapply(scenarios, function(scen) {
    to_convert = lapply(scen, typeof) == "character"
    scen[to_convert] = lapply(scen[to_convert], factor)
    scen
  })

  geom = st_transform(geom, 4326)

  # Crop to study area
  eapregion = st_union(read_sf(paste(BASE_DIR, "data/sensitive/eap_zones_only.geojson", sep="")))
  intersection = unlist(st_intersects(eapregion, geom))
  geom = geom[intersection,]

  # Remove points
  geom = geom[grepl("LINESTRING", sapply(st_geometry(geom), st_geometry_type)),]

  # Assert all scenarios contain the same columns and types
  print (paste("scenarios is length : ", length(scenarios)))
  for (i in 1:length(scenarios)) {
    check_names = all(names(scenarios[[i]]) == names(scenarios[[1]]))
    check_types = all(sapply(scenarios[[i]], typeof) == sapply(scenarios[[1]], typeof))
    print (paste(i, ":names: ", check_names))
    print (paste(i, ":types: ", check_types))
    print (paste(i, ":as.logical(names):" , all(as.logical(check_names))))
    print (paste(i, ":as.logical(types):" , all(as.logical(check_types))))
    print (paste(i, ":all():", all(as.logical(check_names), as.logical(check_types))))
  }
  scenarios %>%
    lapply(function(meta) {
      all(names(meta) == names(scenarios[[1]])) &
        all(sapply(meta, typeof) == sapply(scenarios[[1]], typeof))
    }) %>%
    as.logical() %>%
    all() %>%
    stopifnot()

  print ("completed first round of assertions")
  # Remove all link geometries for which there is no metadata
  geom = geom[geom$ID_LINK %in% scenarios[[1]]$Link_ID,]

  # Remove all metadata for which there is no geometry (e.g. the geometry was outside the study area)
  # and re-order each scenario to have the same row-order as the geometry.
  scenarios = lapply(scenarios, function(meta) meta[match(geom$ID_LINK, meta$Link_ID),])

  # Remove connectors from geometry
  geom = geom[!grepl("Connect", scenarios[[1]]$LType),]

  # Crop scenarios again to reduced geometry
  scenarios = lapply(scenarios, function(meta) meta[match(geom$ID_LINK, meta$Link_ID),])

  # Drop unused LType levels.
  # scenarios = lapply(scenarios, function(meta) {meta$LType = droplevels(meta$LType); meta})

  # Assert all scenarios contain the same links as `links` in the same order
  scenarios %>%
    lapply(function(meta) {all(geom$ID_LINK == as.character(meta$Link_ID))}) %>%
    as.logical() %>%
    all() %>%
    stopifnot()

  # The JSON is consumed by the client side app which doesn't need to know anything but the geometry and an id
  # (which should just be contiguous ascending integers from 0), so strip all the other data.
  just_geometry = st_geometry(geom)
  names(just_geometry)<-0:(length(just_geometry)-1)

  # You can also generate those ids by writing a sf data frame without names, reading it in, and then writing it again,
  # which is how we used to do it (unintentionally). It's a bit weird that the read driver populates default names but
  # the write driver does not. Thanks, GDAL.

  list(just_geometry, scenarios)
}

# od_matrix_csv -> list of matrices
process_od_matrix <- function(metamat) {
  variables = names(metamat)[3:length(metamat)]
  od_skim = lapply(variables, function(var) acast(metamat, Orig~Dest, value.var = var))
  names(od_skim)<-variables
  od_skim
}


### EXECUTE ###

pack_dir = paste(BASE_DIR, "data/sensitive/GCVT_Scenario_Pack/", sep="")

scenarios = read_scenarios(pack_dir)
geom = read_sf(path(pack_dir, "geometry", "links.shp"))

print ("Link scenarios found: ")
print (scenarios[scenarios$type=="links",]$name)
temp = process_links(geom, scenarios[scenarios$type=="links",]$dataDF)
geom = temp[[1]]
scenarios[scenarios$type=="links",]$dataDF = temp[[2]]
rm(temp)

scenarios[scenarios$type=="od_matrices",]$dataDF = lapply(scenarios[scenarios$type=="od_matrices",]$dataDF, process_od_matrix)

meta = get_metadata(pack_dir)

# Save the scenarios and geometry
dir_create(path(pack_dir, "processed"))
saveRDS(scenarios, path(pack_dir, "processed", "scenarios.Rds"))
write_sf(geom, path(pack_dir, "processed", "links.geojson"), delete_dsn = T)
