devtools::install_github("cmcaine/leaflet")

library(sf)
library(mapview)
library(leaflet)
library(geojsonio)

# Get links with metadata
# nlinks = read_sf("data/sensitive/initial/Network_link.shp", stringsAsFactors = T)
# links = read_sf("data/sensitive/initial/links.geojson")
# nlinks = st_transform(nlinks, st_crs(links))
# links = st_crop(nlinks, links)

# nlinks contains a mix of points, linestrings and multilinestrings.
# Filter to contain only (multi)linestrings because points will mess us up.
# links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]
# write_sf(links, "data/sensitive/processed/links.gpkg")

# When we re-read this, all the LINESTRINGS will be coerced to MULTILINESTRINGS, but that's fine.
links = read_sf("data/sensitive/processed/links.gpkg", stringsAsFactors = T)
gjlinks = geojson_json(subset(links, select=c("geom")))

autoPalette = function(data) {
  if (is.factor(data)) {
    colorFactor(topo.colors(length(levels(data))), data)
  } else if (is.logical(data)) {
    colorFactor(c("red", "blue"), data)
  } else {
    colorNumeric(palette = "PuRd", domain = data)
  }
}

library(openlayers)

add_carto_tiles = function(map) {
  add_xyz_tiles(map, "https://cartodb-basemaps-{1-4}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png")
}
rand_colours = sample(c("red", "green", "blue"), 30000, replace = T)

olm = function() {ol() %>% add_carto_tiles() %>% add_full_screen()}
addAutoLinks = function (map, data, column) {
  col = data[[column]]
  pal = autoPalette(col)
  map %>%
    addPolylines(data = data, color=pal(col), label = ~as.character(col), opacity = 1) %>%
    addLegend(data = data, pal = pal, values = col, title = column)
}

addAutoLinksOL = function(map, data, json, column) {
  col = data[[column]]
  pal = autoPalette(col)
  map %>%
    add_geojson(data = json, style = stroke_style(color = pal(col)))
}

lef = function() {
  leaflet(options = leafletOptions(preferCanvas = T)) %>%
    addTiles()
}

# leaflet() %>% addPolylines(data=links[1:1000,], color=~autoPalette(MODE)(MODE), label = ~as.character(MODE))
# leaflet() %>% addPolylines(data=links[1:1000,], color=~autoPalette(SPEED)(SPEED), label = ~as.character(SPEED)) %>% addLegend(data = links, position = "bottomright", pal = ~autoPalette(SPEED), values = ~SPEED)
#
# leaflet() %>% addLegend(data = links, position = "bottomright", pal = autoPalette(links$SPEED), values = ~SPEED)
leaflet() %>% addTiles() %>% addAutoLinks(data = links[1:1000,], "MODE")
leaflet() %>% addTiles() %>% addAutoLinks(data = links, "MODE")
lef() %>% addAutoLinks(data = links, "MODE")
olm() %>% addAutoLinksOL(data = links, json = gjlinks, "MODE")

# leaflet() %>% addAutoLinks(data = links[1:1000,], "SPEED")
# leaflet() %>% addAutoLinks(data = links, "SPEED")

# Looking at the data
# saf = function(col) {summary(as.factor(col))}
#
# saf(links$PROJECTID)

# Many geojson files don't work correctly with geojsonio::geojson_read. Don't understand why yet.

# Convert only the geometry to json, making sure that it's still a tibble/df
olm() %>% add_geojson(gjlinks)
olm() %>% add_geojson(gjlinks, style = stroke_style(color = rand_colours))
olm() %>% add_geojson(gjlinks, style = stroke_style(color = autoPalette(links$MODE)(links$MODE)))


# Experiments
nc = st_read(system.file("shape/nc.shp", package="sf"))
olm() %>%
  add_features(nc, style = fill_style(color = rand_colours))

## Oh god, this was harder than expected

paste("OBJECTID", row[["OBJECTID"]])

links = [1:1000,]
stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
row = stripSf(links)
trs = lapply(colnames(row), function(col){
  paste("<tr><td>", col,"</td>", "<td>", row[[col]], "</td>")
})

trsM = matrix(unlist(trs), length(trs[[1]]))

tables = 1:nrow(trsM)
for (rn in 1:nrow(trsM)) {
  tables[[rn]] = paste("<table>", paste(trsM[rn,], collapse=''), "</table>")
}

paste("table", paste(paste("td", colnames(links), "td", "td", stripSf(links[1,]), "td"), collapse=''), "table")

htmltools::tags$td("hello")

paste("A", trs, "B")

trs[[1]][[1]]


tables = 1:nrow(row)
for (rn in 1:length(trs[[1]])) {
  trs2 = 1:32
  for (cn in 1:length(trs)) {
    trs2[[cn]] = trs[[cn]][[rn]]
  }
  tables[[rn]] = paste(trs2, collapse='')
}

oength(trs)

krm(trs)
for (col in colnames(row)) {
  print(paste(col, row[[col]]))
}
