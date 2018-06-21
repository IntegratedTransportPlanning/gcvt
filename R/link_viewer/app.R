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

library(shiny)

ui = fillPage(
  leafletOutput("map", height = "100%"),
  div(class = "floater", selectInput("variable", "Variable", variables, selected="MODE")),
  theme = "fullscreen.css"
)

server = function(input, output) {
  source("../app_common.R")

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addAutoLinks(data = links, column = "MODE")
  })

  observeEvent(input$variable, {
    leafletProxy("map") %>%
      reStyle("links", links[[input$variable]], input$variable, pal = autoPalette(links[[input$variable]], factorColors = topo.colors))
  })

  observeEvent(input$map_shape_click, {
    e = input$map_shape_click

    popupText = getPopup(links, e$id)
    print (popupText)
    leafletProxy("map") %>%
      addPopups(lng=e$lng, lat=e$lat, popup=popupText)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
