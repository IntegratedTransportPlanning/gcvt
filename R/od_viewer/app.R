# This is a Shiny web application. You can run the application by clicking
# the 'Run App' button above.

# Show all the zones and lines between their centroids.
# If a zone is clicked, recolour all zones.

library(shiny)
library(sf)
library(leaflet)

linesPerCentroid = 100

# Get the data
# zones = subset(read_sf("data/sensitive/initial/zones.geojson"), select = c("NAME"))
zones = subset(read_sf("../../data/sensitive/initial/zones.geojson"), select = c("NAME"))
suppressWarnings({
  zones = st_simplify(zones, preserveTopology = T, dTolerance = 0.1)
  centroids = st_centroid(zones)
})

linesFrom = function(from, to) {
  # Convert from to a single point
  from = st_geometry(from)[[1]]
  st_sfc(lapply(st_geometry(to), function(point) {st_linestring(rbind(from, point))}))
}

# Fake up an od skim
variables = c("CO2 (tonnes)", "Time (minutes)")
od_skim = list()
bounds = 10:10000
for (var in variables) {
  od_skim[[var]] = matrix(sample(bounds, nrow(zones)**2, replace = T), nrow = nrow(zones), ncol = nrow(zones))
}

# Another fake one to compare against
od_less = list()
for (var in variables) {
  od_less[[var]] = od_skim[[var]] * 0.5
}

# Get the skims
# library(readr)
# library(reshape2)

# IDs don't align at the mo. Need to add some missing polygons (or cut some data from the matrices).

# metamat = read_csv("data/sensitive/13-July/ReportMat_Base_2018.csv")
# variables = names(metamat)[3:length(metamat)]
# od_skim = lapply(variables, function(var) acast(metamat, Orig~Dest, value.var = var))
# names(od_skim)<-variables

scenariosZones = list("Do minimum" = od_skim,
                      "Lower numbers" = od_less)

ui <- fillPage(
  leafletOutput("map", height = "100%"),
  div(class = "floater",
      selectInput("scenarioOD", "Scenario Package", names(scenariosZones)),
      selectInput("comparatorOD", "Compare with", c("Select scenario...", names(scenariosZones))),
      selectInput("variable", "Variable", variables, selected=variables[[1]]),
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
    base = scenariosZones[[input$scenarioOD]]
    variable = input$variable

    values = NULL
    if ((input$comparatorOD %in% names(scenariosZones)) &&
        (input$comparatorOD != input$scenarioOD)) {
      ## TODO ^ check we are doing something sensible if the user is trying to compare the same two scenarios
      compareZones = scenariosZones[[input$comparatorOD]]

      baseVals = NULL
      compVals = NULL
      if (!length(selected)) {
        # Nothing selected, show comparison of 'from' for zones
        baseVals = rowSums(base[[variable]])
        compVals = rowSums(compareZones[[variable]])
      } else if (length(selected) > 1) {
        # Sum of rows if several zones selected
        baseVals = colSums(base[[variable]][selected,])
        compVals = colSums(compareZones[[variable]][selected,])
      } else {
        # Just one selected, show comparison of its 'to' data
        baseVals = base[[variable]][selected,]
        compVals = compareZones[[variable]][selected,]
      }
      values = compVals - baseVals
      variable = paste("Scenario difference in ", input$variable)

      ## TODO palette
    } else {
      if (!length(selected)) {
        values = rowSums(base[[variable]])
      } else if (length(selected) > 1) {
        # Sum of rows if several zones selected
        values = colSums(base[[variable]][selected,])
      } else {
        values = base[[variable]][selected,]
      }
      ## TODO palette
    }

    leafletProxy("map") %>%
      reStyleZones(data = zones, values = values, variable = variable, selected = selected)
  }

  updateCentroidLines = function() {
    map = leafletProxy("map") %>% clearGroup("centroidlines")

    if (input$showCLines && length(selected)) {
      # Get only the most important lines
      # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
      # TODO what do we do if we are showing comparison? Does it make sense?
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

      weights = weightScale(topVals)
      opacities = opacityScale(weights)

      addPolylines(map, data = centroidlines, group = "centroidlines", weight = weights, opacity = opacities, color = "black")
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
