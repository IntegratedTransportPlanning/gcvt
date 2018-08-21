### Combined app ###

## Get data

library(sf)
library(readr)
library(reshape2)

# TODO my 'example' file wouldn't load columns for some reason.
linksFile = "../../data/sensitive/processed/cropped_links.gpkg"
links = read_sf(linksFile, stringsAsFactors = T)

# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:5000,]

# Load scenarios

# Load and crop metadata
load("../../data/sensitive/processed/cropped_scenarios.RData")
# Crop scenarios again to reduced geometry
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

meta = scenarios[[1]]
modes = levels(meta$LType)

variables = sort(colnames(meta))
continuous_variables = colnames(meta)[sapply(meta, is.numeric)] %>% sort()
continuous_variables = c("Select variable", continuous_variables)


# Zone data

zones = read_sf("../../data/sensitive/final/zones.gpkg")
suppressWarnings({
  # zones = st_simplify(zones, preserveTopology = T, dTolerance = 0.1)
  centroids = st_centroid(zones)
})

# Get the skims

extract_matrix <- function(filename) {
  metamat = read_csv(filename)
  variables = names(metamat)[3:length(metamat)]
  od_skim = lapply(variables, function(var) acast(metamat, Orig~Dest, value.var = var))
  names(od_skim)<-variables
  od_skim
}

od_scenarios = list(
  base = extract_matrix("../../data/sensitive/final/Matrix_Base_2017.csv"),
  "Do Nothing (2020)" = extract_matrix("../../data/sensitive/final/Matrix_Y2020_DoNothing_2020.csv"),
  "Do Nothing (2025)" = extract_matrix("../../data/sensitive/final/Matrix_Y2025_DoNothing_2025.csv"),
  "Do Nothing (2030)" = extract_matrix("../../data/sensitive/final/Matrix_Y2030_DoNothing_2030.csv")
)
od_variables = names(od_scenarios[[1]])


## Define interactions and appearance

library(shiny)
library(shinyWidgets)
library(shinythemes)
library(leaflet)

ui = fillPage(
  includeCSS('www/fullscreen.css'),
  leafletOutput("map", height = "100%"),
  div(class="panel-group floater",
      div(class="panel panel-default",
          div(class="panel-heading",
              a(href="#collapse-about", h4("Greener Connectivity Visualisation Tool"), 'data-toggle'="collapse")),
          div(id="collapse-about", class="panel-collapse collapse",
              p(class="gcvt-panel-box", "The GCVT is a tool for viewing data from strategic transport models, using both network link data and OD zone skims.",
                   a(href="https://github.com/IntegratedTransportPlanning/gcvt", "More info...")
                   ),
              actionButton("dbg", "Debug now")
              ),
          div(class="panel-heading",
              materialSwitch("showLinks", status="info", inline=T),
              h4(class="gcvt-toggle-label", "Network links "),
              a(href="#collapse1", "[ + ]", 'data-toggle'="collapse")),
          div(id="collapse1", class="panel-collapse collapse",
              tags$ul(class="list-group",
                 tags$li(class="list-group-item",
                        selectInput("scenario", "Scenario Package", names(scenarios))),
                 tags$li(class="list-group-item",
                        selectInput("comparator", "Compare with", c("Select scenario", names(scenarios)))),
                 tags$li(class="list-group-item",
                         sliderInput("modelYear", "Model Year", 2020, 2040, value=2020, step=5, sep="")),
                 tags$li(class="list-group-item",
                         selectInput("colourBy", "Colour links by", variables, selected="LType")),
                 tags$li(class="list-group-item",
                         selectInput("widthBy", "Set width by", continuous_variables)),
                 tags$li(class="list-group-item",
                         selectInput("filterMode", "Show modes", modes, selected = modes[!modes == "Connectors"], multiple = T))
          )),
          div(class="panel-heading",
              materialSwitch("showZones", status="info", inline=T),
              h4(class="gcvt-toggle-label", "Matrix zones "),
              a(href="#collapse2", "[ + ]", 'data-toggle'="collapse")),
          div(id="collapse2", class="panel-collapse collapse",
              tags$ul(class="list-group",
                 tags$li(class="list-group-item",
                         selectInput("od_scenario", "Scenario Package", names(od_scenarios)),
                         selectInput("od_comparator", "Compare with", c("Select scenario...", names(od_scenarios))),
                         selectInput("od_variable", "OD skim variable", od_variables),
                         checkboxInput("showCLines", "Show centroid lines?"),
                         htmlOutput("zoneHint", inline=T)
                         )

          ))
          )
      )
  ,
  # Couldnt figure out how to provide multiple CSSs, which would have allowed use of BootSwatch
  # shinythemes lets you switch in bootswatch, but then you have to replace the below
  theme = shinytheme("darkly")
)

server = function(input, output) {
  source("../app_common.R")
  observeEvent(input$dbg, {browser()})

  getPopup = function (meta) {
    paste("<table >", paste(paste("<tr class='gcvt-popup-tr'><td class='gcvt-td'>", colnames(meta), "</td>", "<td>", sapply(meta, function(col) {as.character(col)}), "</td></tr>"), collapse=''), "</table>")
  }

  selected = numeric(0)

  output$map <- renderLeaflet({
    isolate({
    bbox = st_bbox(links)
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addPolygons(data = zones, group = "zones", layerId = 1:nrow(zones)) %>%
      updateZoneDisplay() %>%
      addPolylines(data = links, group = "links", layerId = 1:nrow(links)) %>%
      updateLinks() %>%
      fitBounds(bbox[[1]], bbox[[2]], bbox[[3]], bbox[[4]])
    })
  })

  metaDiff = function(base, comparator) {
    meta = base
    coldiff = function(a, b)
      if (is.factor(a)) as.factor(ifelse(a == b, "same", "different"))
      else a - b
    for (i in 1:length(base)) meta[[i]] = coldiff(base[[i]], comparator[[i]])
    meta
  }

  updateLinks = function(map = leafletProxy("map")) {
    if (!input$showLinks) {
      return(map %>%
             hideGroup("links") %>%
             removeControl("linksLegend"))
    }

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

    # Use base$LType for filtering, not the comparison
    visible = base$LType %in% input$filterMode

    map %>%
      styleByData(meta, 'links', colorCol = input$colourBy, weightCol = widthBy, palfunc = palfunc) %>%
      setStyleFast('links', stroke = visible) %>%
      showGroup("links")
  }

  updateZoneDisplay = function(map = leafletProxy("map")) {
    if (!input$showZones) {
      map = map %>%
        hideGroup("zones") %>%
        removeControl("zonesLegend")
      return(map)
    }

    base = od_scenarios[[input$od_scenario]]
    variable = input$od_variable

    values = NULL
    if ((input$od_comparator %in% names(od_scenarios)) &&
        (input$od_comparator != input$od_scenario)) {
      ## TODO ^ check we are doing something sensible if the user is trying to compare the same two scenarios
      compareZones = od_scenarios[[input$od_comparator]]

      baseVals = NULL
      compVals = NULL
      zoneHintMsg = ""
      if (!length(selected)) {
        # Nothing selected, show comparison of 'from' for zones
        baseVals = rowSums(base[[variable]])
        compVals = rowSums(compareZones[[variable]])
        zoneHintMsg = "coloured by difference in 'from' statistics between scenarios"

      } else if (length(selected) > 1) {
        # Sum of rows if several zones selected
        baseVals = colSums(base[[variable]][selected,])
        compVals = colSums(compareZones[[variable]][selected,])
        zoneHintMsg = "shaded by aggregated difference in 'to' statistics for the selected zones"

      } else {
        # Just one selected, show comparison of its 'to' data
        baseVals = base[[variable]][selected,]
        compVals = compareZones[[variable]][selected,]
        zoneHintMsg = "shaded by difference in 'to' statistics for the selected zone"

      }
      values = compVals - baseVals
      variable = paste("Scenario difference in ", variable)

      # Comparison palette is washed out by outliers :(
      pal = comparisonPalette(values, "red", "blue", "yellow", bins = 21)
    } else {
      if (!length(selected)) {
        values = rowSums(base[[variable]])
        zoneHintMsg = "shaded by the 'from' statistics for all zones in the selected scenario"

      } else if (length(selected) > 1) {
        # Sum of rows if several zones selected
        values = colSums(base[[variable]][selected,])
        zoneHintMsg = "shaded by the aggregated 'to' statistic for the selected zones"

      } else {
        values = base[[variable]][selected,]
        zoneHintMsg = "shaded by the 'to' statistic for the selected zone"

      }
      pal = autoPalette(values, "RdYlBu")
    }
    output$zoneHint <- renderText({ paste("Zones shown are ", zoneHintMsg) })

    map %>%
      reStyleZones(data = zones, values = values, variable = variable, selected = selected, pal = pal) %>%
      showGroup("zones")
  }

  linesPerCentroid = 20
  updateCentroidLines = function() {
    map = leafletProxy("map") %>% clearGroup("centroidlines")

    if (input$showCLines && length(selected)) {
      # Get only the most important lines
      # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
      # TODO what do we do if we are showing comparison? Does it make sense?
      od_skim = od_scenarios[[input$od_scenario]]
      centroidlines = NULL
      topVals = NULL

      for (matrixRow in selected) {
        rowVals = as.vector(od_skim[[input$od_variable]][matrixRow,])
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
