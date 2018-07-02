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
continuous_variables = colnames(links)[sapply(links, is.numeric)] %>% sort()
continuous_variables = continuous_variables[!continuous_variables == "geom"]


# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:1000,]
modes = unique(links[["MODE"]])

# Dummy var for now
scenarios = c("Do minimum",
              "EV Road Freight",
              "EV Private Vehicles",
              "Rail Electrification",
              "EV Freight and Rail Electrification",
              "Port Automation")

# Just the geography as geojson
# library(geojsonio)
# gjlinks = geojson_list(subset(links, select=c("geom")))

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
                        selectInput("scenarioPackage", "Scenario Package", scenarios)),
                 tags$li(class="list-group-item",
                         sliderInput("modelYear", "Model Year", 2020, 2040, value=2020, step=5, sep="")),
                 tags$li(class="list-group-item",
                         selectInput("colourBy", "Variable", variables, selected="MODE")),
                 tags$li(class="list-group-item",
                         selectInput("widthBy", "Set width by", continuous_variables, selected="SPEED")),
                 tags$li(class="list-group-item",
                         selectInput("linkMode", "Show mode", modes, selected=NULL)),
                 tags$li(class="list-group-item", checkboxInput("showConnectors", "Show Connectors"))
          )))
      )
  ,
  # Couldnt figure out how to provide multiple CSSs, which would have allowed use of BootSwatch
  # shinythemes lets you switch in bootswatch, but then you have to replace the below
  theme = "fullscreen.css"
)

server = function(input, output) {
  source("../app_common.R")

  # Keep track of which modes are shown
  # Turn off 'connector' links by default, keeps it neat
  visible = rep(T, times = length(modes))
  names(visible) = modes
  visible['connector'] = F

  getPopup = function (data, id) {
    stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
    meta = stripSf(data[id,])
    paste("<table >", paste(paste("<tr class='gcvt-popup-tr'><td class='gcvt-td'>", colnames(meta), "</td>", "<td>", sapply(meta, function(col) {as.character(col)}), "</td></tr>"), collapse=''), "</table>")
  }

  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addAutoLinks(data = links, colorCol = "MODE", weightCol = "SPEED")
  })

  observeEvent(input$widthBy, {
    leafletProxy("map") %>%
      reStyle2("links", weight = links[[input$widthBy]],
               label = paste(input$colourBy, ": ", links[[input$colourBy]], "; ", input$widthBy, ": ", links[[input$widthBy]], sep = ""))
  })

  observeEvent(input$colourBy, {
    leafletProxy("map") %>%
      reStyle("links", links[[input$colourBy]], input$colourBy, pal = autoPalette(links[[input$colourBy]], factorColors = topo.colors))
  })

  observeEvent(input$linkMode, {
    print (paste("filtering for mode:", input$linkMode))
    visible[visible == T] = F
    visible[input$linkMode] = T

    # The below can be uncommented when reStyle(vis=) is implemented
    # leafletProxy("map") %>%
    #   reStyle("links",
    #           links[[input$variable]],
    #           input$variable,
    #           pal = autoPalette(links[[input$variable]], factorColors = topo.colors),
    #           vis = visible)
  }, ignoreInit = T)

  observeEvent(input$map_shape_click, {
    e = input$map_shape_click

    popupText = getPopup(links, e$id)

    leafletProxy("map") %>%
      addPopups(lng=e$lng, lat=e$lat, popup=popupText)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
