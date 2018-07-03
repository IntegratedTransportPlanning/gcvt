# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.

# Show all the zones and lines between their centroids.
# If a zone is clicked, recolour all zones.

library(shiny)
library(sf)
library(leaflet)

# Get the data
# zones = subset(read_sf("data/sensitive/initial/zones.geojson"), select = c("NAME"))
zones = subset(read_sf("../../data/sensitive/initial/zones.geojson"), select = c("NAME"))
suppressWarnings({
  zones = st_simplify(zones, preserveTopology = T, dTolerance = 0.1)
  centroids = st_centroid(zones)
})

# c2clines =
# for (c1 in centroids) {
#   for (c2 in centroids) {
#     # st_linestring doesn't take two st_points, annoyingly.
#   }
# }

linesFrom = function(from, to) {
  # Convert from to a single point
  from = st_geometry(from)[[1]]
  st_sfc(lapply(st_geometry(to), function(point) {st_linestring(rbind(from, point))}))
}

# Fake up an od skim
variables = c("Cheese (tonnes)", "Wine (tonnes)", "CO2 (tonnes)", "Time (minutes)")
od_skim = list()
bounds = 10:10000
for (var in variables) {
  od_skim[[var]] = matrix(sample(bounds, nrow(zones)**2, replace = T), nrow = nrow(zones), ncol = nrow(zones))
}

ui <- fillPage(
  leafletOutput("map", height = "100%"),
  div(class = "floater",
      selectInput("variable", "Variable", variables, selected=variables[[1]]),
      actionButton("dbg", "DBG"),
      checkboxInput("showCLines", "Show centroid lines on mouseover?")
  ),
  theme = "fullscreen.css"
)

server <- function(input, output) {
  source("../app_common.R")

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addSkimZones(data = zones, skim = od_skim, variable = variables[[1]])
  })

  selected = NULL
  updateZoneDisplay = function() {
    leafletProxy("map") %>%
      reStyleZones(data = zones, skim = od_skim, variable = input$variable, selected = selected)
  }

  observeEvent(input$map_shape_click, {
    id = input$map_shape_click$id
    if (!is.null(selected) && id == selected) {
      # Toggle off
      selected <<- NULL
    } else {
      selected <<- id
    }
    updateZoneDisplay()
  })

  observe({
    if (input$showCLines) {
      id = input$map_shape_mouseover$id
      if (!is.null(id)) {
        # Generate centroid lines
        centroidlines = linesFrom(centroids[id,], centroids)
        leafletProxy("map") %>%
          clearGroup("centroidlines") %>%
          addPolylines(data = centroidlines, group = "centroidlines", weight = 3, color = "blue")
      }
    } else {
      leafletProxy("map") %>%
        clearGroup("centroidlines")
    }
  })

  observeEvent(input$variable, {
    updateZoneDisplay()
  })

  observeEvent(input$dbg, {browser()})
}

# Run the application
shinyApp(ui = ui, server = server)
