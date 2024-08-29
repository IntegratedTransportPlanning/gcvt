# Discover all scenario csvs and pre-process them into the appropriate form.

library(tidyverse)
library(fs)
library(sf)
library(reshape2)

BASE_DIR = "./"
# Where to read and write everything. Eg:
# BASE_DIR = "/home/mark/gcvt-metadata/"
source(paste(BASE_DIR, "src/data-preparation/metadata.R", sep = ""))

# Return DF(name, year, type, dataDF)
read_scenarios = function(pack_dir) {
  scenarios = tibble(name=character(0), year=integer(0), type=character(0), dataDF=list())
  for (spath in dir_ls(path(pack_dir, "scenarios"))) {
    for (tpath in dir_ls(spath)) {
      for (ypath in dir_ls(tpath)) {
        scenarios[nrow(scenarios) + 1,] = list(
          basename(spath), basename(ypath) %>% path_ext_remove() %>% as.integer(), basename(tpath), list(read_csv(ypath)))
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

  tables = scenarios$dataDF

  # Convert all character columns to factor
  tables = lapply(tables, function(scen) {
    to_convert = lapply(scen, typeof) == "character"
    scen[to_convert] = lapply(scen[to_convert], factor)
    scen
  })

  # Assert all scenarios contain the same columns and types
  print (paste("scenarios is length : ", length(scenarios)))
  for (i in 1:length(scenarios)) {
    check_names = all(names(tables[[i]]) == names(tables[[2]]))
    check_types = all(sapply(tables[[i]], typeof) == sapply(tables[[2]], typeof))
    if (!check_names) {
      print (paste("Validation error! -", scenarios$name[[i]], scenarios$year[[i]], "- column names don't match"))
    }
    if (!check_types) {
      print (paste("Validation error! -", scenarios$name[[i]], scenarios$year[[i]], "- column types don't match"))
    }
  }

  tables %>%
    lapply(function(meta) {
      all(names(meta) == names(tables[[2]])) &
        all(sapply(meta, typeof) == sapply(tables[[2]], typeof))
    }) %>%
    as.logical() %>%
    all() %>%
    stopifnot()
  print ("Link scenarios have matching column names and types!")

  geom = st_transform(geom, 4326)
  print ("The reproj worked")
  
  # fix issues w invalid spherical coordinates 
  sf_use_s2(FALSE)
  
  # Crop to study area
  eapregion = read_sf(paste(BASE_DIR, "data/sensitive/eap_zones_only.geojson", sep="")) %>%
    st_buffer(0) %>% # Buffer to get rid of some stupid artifact.
    st_union() 
  intersection = unlist(st_intersects(eapregion, geom))
  geom = geom[intersection,]
  
  print ("The crop worked")
  
  # Remove points
  geom = geom[grepl("LINESTRING", sapply(st_geometry(geom), st_geometry_type)),]

  # Remove all link geometries for which there is no metadata
  geom = geom[geom$ID_LINK %in% tables[[1]]$Link_ID,]

  # Remove all metadata for which there is no geometry (e.g. the geometry was outside the study area)
  # and re-order each scenario to have the same row-order as the geometry.
  tables = lapply(tables, function(meta) meta[match(geom$ID_LINK, meta$Link_ID),])

  # Remove connectors from geometry
  geom = geom[!grepl("Connect", tables[[1]]$LType),]

  # Crop scenarios again to reduced geometry
  tables = lapply(tables, function(meta) meta[match(geom$ID_LINK, meta$Link_ID),])

  # Drop unused LType levels.
  tables = lapply(tables, function(meta) {meta$LType = droplevels(meta$LType); meta})

  # Assert all scenarios contain the same links as `links` in the same order
  tables %>%
    lapply(function(meta) {all(geom$ID_LINK == as.character(meta$Link_ID))}) %>%
    as.logical() %>%
    all() %>%
    stopifnot()

  # The JSON is consumed by the client side app which doesn't need to know anything but the geometry and an id
  just_geometry = tibble(id = 0:(nrow(geom)-1), geometry = st_geometry(geom))
  # This tibble must be saved with write_sf(geom, path, fid_column_name = "id").
  # There used to be more unusual ways of doing this.

  print ("The links finished") 
  
  scenarios$dataDF = tables
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

pack_dir = str_c(BASE_DIR, "data/sensitive/GCVT_Scenario_Pack/")

scenarios = read_scenarios(pack_dir)
geom = read_sf(path(pack_dir, "geometry", "links.shp"))

print ("Link scenarios found: ")
print (scenarios[scenarios$type=="links",]$name)
temp = process_links(geom, scenarios[scenarios$type=="links",])
geom = temp[[1]]
scenarios[scenarios$type=="links",] = temp[[2]]
rm(temp)

# Replace the DFs for matrix data with lists of matrices
scenarios[scenarios$type=="od_matrices",]$dataDF =
  lapply(scenarios[scenarios$type=="od_matrices",]$dataDF, process_od_matrix)

print ("Replaced the DFs with lists of matrices")

# Save the scenarios and geometry
dir_create(path(pack_dir, "processed"))
saveRDS(scenarios, path(pack_dir, "processed", "scenarios.Rds"))
write_sf(geom, path(pack_dir, "processed", "links.geojson"), delete_dsn = T, fid_column_name = "id")

print("Saved the scenarios and geometry")



# RData.jl can read lists with nested tibbles and matrices, but not tibbles with nested tibbles and matrices.
saveRDS(as.list(scenarios), path(pack_dir, "processed", "julia_compat_scenarios.Rds"))

print("Saved as a list")

## Other ways of saving the data for julia, but we don't use either of them any more.
# # Unnest the scenarios data so that it can be saved more sanely
# filter(scenarios, type == "links") %>%
#   select(-type) %>%
#   unnest(dataDF) %>%
#   saveRDS(path(pack_dir, "processed", "link_scenarios.Rds"))
#
# # Unnest matrices.
# filter(scenarios, type == "od_matrices") %>%
#   select(-type) %>%
#   rename(matrices = dataDF) %>%
#   as.list %>%
#   saveRDS(path(pack_dir, "processed", "od_matrices_scenarios.Rds"))

## Diff with the on disk data
# current_scenarios = readRDS("data/sensitive/GCVT_Scenario_Pack/processed/scenarios.Rds")
# current_geom = read_sf("data/sensitive/GCVT_Scenario_Pack/processed/links.geojson")
#
# # Turn them all into matrices then rbind the matrices together
# mcg = do.call(rbind, sapply(current_geom$geometry, as.matrix))
# mg = do.call(rbind, sapply(geom$geometry, as.matrix))
#
# # Diff them
# differences = (mcg - mg) %>% as.vector
# max(differences)
# hist(log10(differences))
#
# # much slower than base-r hist for this. We are scaling y rather than x, but that's not it.
# ggplot() + geom_histogram(aes(x=differences)) + scale_y_log10()
#
# # Compare scenarios
#
# scenarios[1,]$dataDF[[1]] %>% nrow
# current_scenarios[1,]$dataDF[[1]] %>% nrow
#
# setdiff(
# current_scenarios %>% pull(name) %>% unique,
# scenarios %>% pull(name) %>% unique)
#
# # current_scenarios has an extra scenario "Base"
#
# just_links = filter(scenarios, type == "links")
# just_links_cs = filter(current_scenarios, type == "links", name != "Base")
#
# # They're all the same
# for (i in seq(1, nrow(just_links))) {
#   cat(i, (just_links$dataDF[[i]] ==  just_links_cs$dataDF[[i]]) %>% all, "\n")
# }
