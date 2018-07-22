### Link viewer app ###

## Get and fake some data

library(sf)
library(leaflet)
library(readr)

# TODO my 'example' file wouldn't load columns for some reason.
linksFile = "../../data/sensitive/processed/nulinks.gpkg"
links = read_sf(linksFile, stringsAsFactors = T)

# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:1000,]

# Fake up some scenarios
stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
meta = stripSf(links)

# Too many modes in new dataset. Need fewer.
if (is.null(meta$MODE)) {
  meta$MODE = as.factor(meta$LinkType)
  levels(meta$MODE)<-read_csv("../../data/sensitive/linktype_lookup.csv")$Description
}
modes = levels(as.factor(as.character(meta$MODE)))

variables = sort(colnames(meta))
continuous_variables = colnames(meta)[sapply(meta, is.numeric)] %>% sort()
continuous_variables = c("Select variable", continuous_variables)

scenarios = list("Do minimum" = meta,
                 "Rail Electrification" = meta,
                 "Operation Overlord" = meta,
                 "Autobahn" = meta,
                 "Autoall" = meta)

# These would need to be changed for the new data.
# scenarios[[2]]$ELECTRIF = sapply(scenarios[[2]]$ELECTRIF, function(e) if (e > 0) 2 else e)
# scenarios[[3]]$MODE[meta$MODE == "ferry"] = "rail"
# scenarios[[4]]$SPEED[meta$MODE == "road"] = meta$SPEED[meta$MODE == "road"] + 30
# scenarios[[5]]$SPEED = sample(1:10 * 10, length(meta$SPEED), replace = T)

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

# Another fake one to compare against
od_less = list()
for (var in od_variables) {
  od_less[[var]] = od_skim[[var]] * 0.5
}

scenariosZones = list("Do minimum" = od_skim,
                      "Lower numbers" = od_less)


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
                         selectInput("filterMode", "Show modes", modes, selected = modes[!modes == "Connectors"], multiple = T))
          )),
          div(id="gcvt-heading", class="panel-heading",
              a(href="#collapse2", "Toggle OD controls", 'data-toggle'="collapse")),
          div(id="collapse2", class="panel-collapse collapse",
              tags$ul(class="list-group",
                 tags$li(class="list-group-item",
                         selectInput("od_scenario", "Scenario Package", names(scenariosZones)),
                         selectInput("od_comparator", "Compare with", c("Select scenario...", names(scenariosZones))),
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
      addSkimZones(data = zones, skim = od_skim, variable = od_variables[[1]]) %>%
      hideGroup("zones") %>%
      removeControl("zonesLegend") %>%
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
    base = scenariosZones[[input$od_scenario]]
    variable = input$od_variable

    values = NULL
    if ((input$od_comparator %in% names(scenariosZones)) &&
        (input$od_comparator != input$od_scenario)) {
      ## TODO ^ check we are doing something sensible if the user is trying to compare the same two scenarios
      compareZones = scenariosZones[[input$od_comparator]]

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

  linesPerCentroid = 20
  updateCentroidLines = function() {
    map = leafletProxy("map") %>% clearGroup("centroidlines")

    if (input$showCLines && length(selected)) {
      # Get only the most important lines
      # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
      # TODO what do we do if we are showing comparison? Does it make sense?
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
