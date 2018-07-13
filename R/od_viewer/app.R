# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.

# Show all the zones and lines between their centroids.
# If a zone is clicked, recolour all zones.

library(shiny)
library(sf)
library(leaflet)

linesPerCentroid = 20

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
      checkboxInput("showCLines", "Show centroid lines?")
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

  selected = numeric(0)
  updateZoneDisplay = function() {
    leafletProxy("map") %>%
      reStyleZones(data = zones, skim = od_skim, variable = input$variable, selected = selected)
  }

  updateCentroidLines = function() {
    map = leafletProxy("map") %>% clearGroup("centroidlines")

    if (input$showCLines && length(selected)) {
      # Get only the most important lines
      # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
      centroidlines = NULL
      topVals = NULL

      for (matrixRow in selected) {
        rowVals = od_skim[[input$variable]][matrixRow,]
        nthVal = sort(rowVals, decreasing=T)[linesPerCentroid]
        topCentroids = centroids[rowVals >= nthVal,]
        linesForRow = linesFrom(centroids[matrixRow,], topCentroids)

        centroidlines = append(centroidlines, linesForRow)
        topVals = append(topVals, rowVals[rowVals >= nthVal])
      }

      weights = scale_to_range(topVals, c(2,10))

      addPolylines(map, data = centroidlines, group = "centroidlines", weight = weights, color = "blue")
    }
  }

  observeEvent(input$map_shape_click, {

    if (input$map_shape_click$group == "zones") {
      id = input$map_shape_click$id

      modded = input$map_shape_click$modifiers$ctrl
      if (modded) {
        if (id %in% selected) {
          # Toggle off one by one
          selected <<- selected[selected != id]
        } else {
          selected <<- c(selected, id)
        }
      } else {
        if (length(selected) > 1 || !(id %in% selected))
          # Replace selection
          selected <<- id
        else
          # Clear selection
          selected <<- NULL
      }

      updateZoneDisplay()
      updateCentroidLines()
    }
  })

  observe({
    updateZoneDisplay()
    updateCentroidLines()
  })

  observeEvent(input$dbg, {browser()})
}

# Run the application
shinyApp(ui = ui, server = server)
