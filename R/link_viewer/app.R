### Link viewer app ###

# Get the data
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

# Dummy var for now
scenarios = c("Do minimum",
              "EV Road Freight",
              "EV Private Vehicles",
              "Rail Electrification",
              "EV Freight and Rail Electrification",
              "Port Automation")

stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
meta = stripSf(links)

# Dummy var for now
scenarios = list("Do minimum" = meta,
                 "Rail Electrification" = meta,
                 "Operation Overlord" = meta,
                 "Autobahn" = meta,
                 "Autoall" = meta)

scenarios[[2]]$ELECTRIF = sapply(scenarios[[2]]$ELECTRIF, function(e) if (e > 0) 2 else e)
scenarios[[3]]$MODE[meta$MODE == "ferry"] = "rail"
scenarios[[4]]$SPEED[meta$MODE == "road"] = meta$SPEED[meta$MODE == "road"] + 30
scenarios[[5]]$SPEED = sample(1:10 * 10, length(meta$SPEED), replace = T)

library(shiny)

ui = fillPage(
  leafletOutput("map", height = "100%"),
  div(class="panel-group floater",
      div(class="panel panel-default",
          div(id="gcvt-heading", class="panel-heading",
              a(href="#collapse1", "Toggle Controls", 'data-toggle'="collapse")),
          div(id="collapse1", class="panel-collapse collapse in",
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
          )))
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

  observe({
    updateLinks()
  })

  observeEvent(input$map_shape_click, {
    meta = scenarios[[input$scenario]]

    # TODO: If comparison enabled, show more columns and colour columns by change

    e = input$map_shape_click

    popupText = getPopup(meta[e$id,])

    leafletProxy("map") %>%
      addPopups(lng=e$lng, lat=e$lat, popup=popupText)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
