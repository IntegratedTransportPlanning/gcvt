# see http://ec.europa.eu/eurostat/web/gisco/geodata/reference-data/transport-networks
# u = "http://ec.europa.eu/eurostat/cache/GISCO/geodatafiles/Airports-2013-SHP.zip"
# download.file(u, "Airports.zip")
# unzip("Airports.zip")
# shp_files = list.files("SHAPE/", pattern = ".shp", full.names = TRUE)
# eu_airports = sf::read_sf(shp_files[1])
# mapview::mapview(eu_airports)
# pryr::object_size(eu_airports)
# saveRDS(eu_airports, "/tmp/airports.rds")
# file.size("/tmp/airports.rds")
# devtools::install_github("cboettig/piggyback")
# usethis::edit_r_environ() # add github token
# piggyback::pb_new_release("IntegratedTransportPlanning/gcvt", "v0.0.1")
# sf::write_sf(eu_airports, "data/eu_airports.geojson")
# file.size("/tmp/eu_airports.geojson")
# piggyback::pb_upload("data/eu_airports.geojson", "IntegratedTransportPlanning/gcvt")
# piggyback::pb_delete("/tmp/eu_airports.geojson", "IntegratedTransportPlanning/gcvt")
