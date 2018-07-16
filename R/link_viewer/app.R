### Link viewer app ###

## Get and fake some data

library(sf)
library(leaflet)

links = read_sf("../../data/sensitive/processed/links.gpkg", stringsAsFactors = T)
variables = sort(colnames(links))
variables = variables[!variables == "geom"]
continuous_variables = colnames(links)[sapply(links, is.numeric)] %>% sort()
continuous_variables = c("Select variable", continuous_variables[!continuous_variables == "geom"])

# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:1000,]
modes = as.character(unique(links[["MODE"]]))

# Fake up some scenarios

stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
meta = stripSf(links)

scenarios = list("Do minimum" = meta,
                 "Rail Electrification" = meta,
                 "Operation Overlord" = meta,
                 "Autobahn" = meta,
                 "Autoall" = meta)

scenarios[[2]]$ELECTRIF = sapply(scenarios[[2]]$ELECTRIF, function(e) if (e > 0) 2 else e)
scenarios[[3]]$MODE[meta$MODE == "ferry"] = "rail"
scenarios[[4]]$SPEED[meta$MODE == "road"] = meta$SPEED[meta$MODE == "road"] + 30
scenarios[[5]]$SPEED = sample(1:10 * 10, length(meta$SPEED), replace = T)

# Zone data

zones = subset(read_sf("../../data/sensitive/initial/zones.geojson"), select = c("NAME"))
suppressWarnings({
  zones = st_simplify(zones, preserveTopology = T, dTolerance = 0.1)
  centroids = st_centroid(zones)
})

# Fake up an od skim
od_variables = c("Cheese (tonnes)", "Wine (tonnes)", "CO2 (tonnes)", "Time (minutes)")
od_skim = list()
bounds = 10:10000
for (var in od_variables) {
  od_skim[[var]] = matrix(sample(bounds, nrow(zones)**2, replace = T), nrow = nrow(zones), ncol = nrow(zones))
}


## Define interactions and appearance

library(shiny)

ui = fillPage(
  leafletOutput("map", height = "100%"),
  div(class="panel-group floater",
      div(class="panel panel-default",
          div(id="gcvt-heading", class="panel-heading",
              a(href="#collapse1", "Toggle Controls", 'data-toggle'="collapse")),
          div(id="collapse1", class="panel-collapse collapse",
              tags$ul(class="list-group",
                 tags$li(class="list-group-item",
                        selectInput("scenario", "Scenario Package", names(scenarios))),
                 tags$li(class="list-group-item",
                        selectInput("comparator", "Compare with", c("Select scenario", names(scenarios)))),
                 tags$li(class="list-group-item",
                         sliderInput("modelYear", "Model Year", 2020, 2040, value=2020, step=5, sep="")),
                 tags$li(class="list-group-item",
                         selectInput("colourBy", "Colour links by", variables, selected="MODE")),
                 tags$li(class="list-group-item",
                         selectInput("widthBy", "Set width by", continuous_variables)),
                 tags$li(class="list-group-item",
                         selectInput("filterMode", "Show modes", modes, selected = modes[!modes == "connector"], multiple = T))
          )),
          div(id="gcvt-heading", class="panel-heading",
              a(href="#collapse2", "Toggle OD controls", 'data-toggle'="collapse")),
          div(id="collapse2", class="panel-collapse collapse",
              tags$ul(class="list-group",
                 tags$li(class="list-group-item",
                         selectInput("od_variable", "OD skim variable", od_variables),
                         checkboxInput("showCLines", "Show centroid lines?"))
          ))
          )
      )
  ,
  # Couldnt figure out how to provide multiple CSSs, which would have allowed use of BootSwatch
  # shinythemes lets you switch in bootswatch, but then you have to replace the below
  theme = "fullscreen.css"
)

server = function(input, output) {
  source("../app_common.R")

  getPopup = function (meta) {
    paste("<table >", paste(paste("<tr class='gcvt-popup-tr'><td class='gcvt-td'>", colnames(meta), "</td>", "<td>", sapply(meta, function(col) {as.character(col)}), "</td></tr>"), collapse=''), "</table>")
  }

  output$map <- renderLeaflet({
    isolate({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addLayersControl(overlayGroups = c("links", "zones"), position = "topleft") %>%
      #addSkimZones(data = zones, skim = od_skim, variable = od_variables[[1]]) %>%
      #hideGroup("zones") %>%
      #removeControl("zonesLegend") %>%
      addPolylines(data = links, group = "links", layerId = 1:nrow(links), stroke = F, fill = F) %>%
      updateLinks()
    })
  })

  metaDiff = function(base, comparator) {
    meta = base
    coldiff = function(a, b) if (is.factor(a)) a == b else a - b
    for (i in 1:length(base)) meta[[i]] = coldiff(base[[i]], comparator[[i]])
    meta
  }

  updateLinks = function(map = leafletProxy("map")) {
    base = scenarios[[input$scenario]]

    if (input$comparator %in% names(scenarios)) {
      meta = metaDiff(base, scenarios[[input$comparator]])
      palfunc = comparisonPalette
    } else {
      meta = base
      palfunc = autoPalette
    }

    if (input$widthBy == continuous_variables[[1]]) {
      widthBy = NULL
    } else {
      widthBy = input$widthBy
    }

    # Use base$MODE for filtering, not the comparison
    visible = base$MODE %in% input$filterMode

    map %>%
      styleByData(meta, 'links', colorCol = input$colourBy, weightCol = widthBy, palfunc = palfunc) %>%
      setStyleFast('links', stroke = visible)
  }

  selected = numeric(0)
  updateZoneDisplay = function() {
    leafletProxy("map") %>%
      reStyleZones(data = zones, skim = od_skim, variable = input$od_variable, selected = selected)
  }

  linesPerCentroid = 20
  updateCentroidLines = function() {
    map = leafletProxy("map") %>% clearGroup("centroidlines")

    if (input$showCLines && length(selected)) {
      # Get only the most important lines
      # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
      centroidlines = NULL
      topVals = NULL

      for (matrixRow in selected) {
        rowVals = od_skim[[input$od_variable]][matrixRow,]
        nthVal = sort(rowVals, decreasing=T)[linesPerCentroid]
        topCentroids = centroids[rowVals >= nthVal,]
        linesForRow = linesFrom(centroids[matrixRow,], topCentroids)

        centroidlines = append(centroidlines, linesForRow)
        topVals = append(topVals, rowVals[rowVals >= nthVal])
      }

      weights = weightScale(topVals)

      addPolylines(map, data = centroidlines, group = "centroidlines", weight = weights, color = "blue")
    }
  }

  observe({
    updateLinks()
  })

  observe({
    updateZoneDisplay()
    updateCentroidLines()
  })

  observeEvent(input$map_shape_click, {
    e = input$map_shape_click

    if (e$group == "links") {
      meta = scenarios[[input$scenario]]

      # TODO: If comparison enabled, show more columns and colour columns by change

      popupText = getPopup(meta[e$id,])

      leafletProxy("map") %>%
        addPopups(lng=e$lng, lat=e$lat, popup=popupText)
    } else if (e$group == "zones") {
      id = e$id

      modded = e$modifiers$ctrl
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
}

# Run the application
shinyApp(ui = ui, server = server)
