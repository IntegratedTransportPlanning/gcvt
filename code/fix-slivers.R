# # aim: load and clean zones data
# devtools::install_github("IntegratedTransportPlanning/gcvt")
# library(gcvt)
# eap_countries
# library(sf)
# library(tidyverse)
# # system("bash data/gcvt-private/unpack.sh")
# z_orig = sf::read_sf("data/gcvt-private/GC_EaP_Shape/Zoning_GC.shp")
# pryr::object_size(z_orig)
# crs_local = st_crs(z_orig)
# # z = sf::read_sf("data/gcvt-private/GC_EaP_Shape/zones.geojson")
# # pryr::object_size(z) # the same size!
# # z = sf::read_sf("data/gcvt-private/GC_EaP_Shape/zones_simplified_wgs84.geojson")
# # pryr::object_size(z) # much smaller
# # mapview::mapview(z) # still has holes
# # z = st_transform(z, crs_local)
# z = rmapshaper::ms_simplify(z_orig, keep = 0.03, sys = T, snap_interval = 100)
# pryr::object_size(z)
# mapview::mapview(z) +
#   eap_countries
# eap_bounds = st_cast(eap_countries, "MULTILINESTRING") %>%
#   st_transform(crs_local)
# problem_countries = z[eap_bounds, ]
# mapview::mapview(problem_countries)
# problem_countries_buff = st_buffer(problem_countries, 10000)
# mapview::mapview(problem_countries_buff)
# nosliver = st_difference(problem_countries_buff, problem_countries_buff)
# mapview::mapview(nosliver)
#
# st_crs(z)
# z_outline = st_union(z) %>%
#   st_cast("MULTILINESTRING")
# mapview::mapview(z_outline)
# z_buff = st_buffer(z, 100)
# mapview::mapview(z_buff)
# z_no_sliver = st_difference(z_buff, z_buff)
# head(z_no_sliver)
# mapview::mapview(z_no_sliver)
#
# z_mini = z[1]
# z_mini$area = as.numeric(round(sf::st_area(z) / 1000000))
# summary(z_mini$area)
# z_mini = sf::st_transform(z_mini, 4326)
# ?rmapshaper::ms_simplify
# z_mapshape = rmapshaper::ms_simplify(z_mini, keep = 0.9, snap_interval = 100)
#
#
# library(RQGIS)
# find_algorithms("sliver")
# RQGIS::get_usage("qgis:eliminatesliverpolygons")
# clean = run_qgis("qgis:eliminatesliverpolygons",
#                  INPUT = z_mini,
#                  ATTRIBUTE = "area",
#                  COMPARISON = "<=",
#                  COMPARISONVALUE = 100,
#                  OUTPUT = file.path(tempdir(), "clean.shp"),
#                  load_output = TRUE)
# mapview::mapview(clean) # still not clean
# # devtools::install_github("eblondel/cleangeo")
# # clean_sp = as(clean, "Spatial")
# # clean_sp = cleangeo::clgeo_Clean(clean_sp) # takes ages
#
# find_algorithms("v.in.o")
# find_algorithms("clean")
# get_usage("grass:v.clean")
# RQGIS::open_help("grass:v.clean")
# clean2 = run_qgis("grass:v.clean",
#                  INPUT = z_mini,
#                  tool = "prune",
#                  output = file.path(tempdir(), "clean.shp"),
#                  )
