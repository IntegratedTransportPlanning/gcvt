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
zones = st_simplify(zones, preserveTopology = T, dTolerance = 0.1)
# centroids = st_centroid(zones)

# c2clines =
# for (c1 in centroids) {
#   for (c2 in centroids) {
#     # st_linestring doesn't take two st_points, annoyingly.
#   }
# }

linesFrom = function(from, to) {
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
      shiny::actionButton("dbg", "DBG")
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

  observeEvent(input$variable, {
    updateZoneDisplay()
  })

  observeEvent(input$dbg, {browser()})
}

# Run the application
shinyApp(ui = ui, server = server)
