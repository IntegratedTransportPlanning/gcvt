#
# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.

# TODO:
#   better colour selection in autoPalette
#   Factor palette for integer columns that are really factors
#   Click to view all props?
#   Graphs
#     Qs to answer?
#   better UI
#     Floaty button to pop out options
#     Scenario selection
#   Performance
#     server side of lef() %>% addAutoLinks(links) takes ~ 5.5s
#     derivePolygons is about half of that
#     palette stuff isn't much of it
#     Can avoid resending json and save draw times by restyling existing polylines
#     OpenLayers is a bit better, but maybe not enough to matter


# Get the data
library(sf)
library(leaflet)
links = read_sf("../../data/sensitive/processed/links.gpkg", stringsAsFactors = T)
variables = sort(colnames(links))
variables = variables[!variables == "geom"]

# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:1000,]

# Just the geography as geojson
# library(geojsonio)
# gjlinks = geojson_list(subset(links, select=c("geom")))

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
    addPolylines(data = data, color=pal(col), label = as.character(col), weight = 2) %>%
    addLegend(position = "bottomleft", data = data, pal = pal, values = col, title = column)
}

addAutoLinksJSON = function (map, data, json, column) {
  col = data[[column]]
  pal = autoPalette(col)
  map %>%
    addGeoJSON(geojson = json, color=pal(col), weight = 2) %>%
    addLegend(position = "bottomleft", data = data, pal = pal, values = col, title = column)
}

library(shiny)

ui <- fillPage(
  leafletOutput("map", height = "100%"),
  div(class = "floater", selectInput("variable", "Variable", variables, selected="MODE")),
  theme = "fullscreen.css"
)

server <- function(input, output) {
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addAutoLinks(data = links, column = input$variable)
  })

  # observeEvent(input$variable, {
  #   leafletProxy("map") %>% addAutoLinks(data = links, column = input$variable)
  # })
}

# Run the application
shinyApp(ui = ui, server = server)
