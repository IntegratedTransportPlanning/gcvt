# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.

# Show all the zones and lines between their centroids.
# If a zone is clicked, recolour all zones.

library(shiny)
library(sf)
library(leaflet)

# Get the data
# setwd("R/od_viewer/")
zones = subset(read_sf("../../data/sensitive/initial/zones.geojson"), select = c("NAME"))
# centroids = st_centroid(zones)

# c2clines =
# for (c1 in centroids) {
#   for (c2 in centroids) {
#     # st_linestring doesn't take two st_points, annoyingly.
#   }
# }

# Fake up an od skim
variables = c("Cheese (tonnes)", "Wine (tonnes)", "CO2 (tonnes)", "Time (minutes)")
od_skim = list()
bounds = 10:10000
for (var in variables) {
  od_skim[[var]] = matrix(sample(bounds, nrow(zones)**2, replace = T), nrow = nrow(zones), ncol = nrow(zones))
}

# Helpers
autoPalette = function(data) {
  if (is.factor(data)) {
    colorFactor(topo.colors(length(levels(data))), data)
  } else if (is.logical(data)) {
    colorFactor(topo.colors(2), data)
  } else {
    colorNumeric(palette = "PuRd", domain = data)
  }
}

addAutoLinks = function (map, data, column) {
  col = data[[column]]
  pal = autoPalette(col)
  map %>%
    addPolylines(data = data, color=pal(col), label = ~as.character(col), weight = 2) %>%
    addLegend(position = "bottomleft", data = data, pal = pal, values = col, title = column)
}

# Add zones coloured by sum of variable for row
addAutoZones = function(map, data, skim, variable, values = rowSums(skim[[variable]])) {
  pal = autoPalette(values)
  map %>%
    addPolygons(data = data, color=pal(values), label = paste(data$NAME, ":", as.character(values)),
                group = "zones", layerId = 1:nrow(data),
                weight = 1) %>%
    addLegend(group = "zones", layerId = "zonesLegend", position = "bottomleft", pal = pal, values = values, title = variable)
}

# Add zones coloured by their value with respect to selected zone
addAutoZonesOD = function(map, data, selected, skim, variable) {
  values = skim[[variable]][selected,]
  addAutoZones(map, data, skim, variable, values = values)
}

library(shiny)

ui <- fillPage(
  leafletOutput("map", height = "100%"),
  div(class = "floater", selectInput("variable", "Variable", variables, selected=variables[[1]])),
  theme = "fullscreen.css"
)

server <- function(input, output) {
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addAutoZones(data = zones, skim = od_skim, variable = input$variable)
  })

  observeEvent(input$map_shape_click, {
    print(input$map_shape_click)

    id = input$map_shape_click$id
    zone = zones[id,]
    print(zone)

    leafletProxy("map") %>%
      clearGroup("zones") %>%
      addAutoZonesOD(data = zones, selected = id, skim = od_skim, variable = input$variable)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
