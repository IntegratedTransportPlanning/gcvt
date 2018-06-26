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
# library(shinythemes)
links = read_sf("../../data/sensitive/processed/links.gpkg", stringsAsFactors = T)
variables = sort(colnames(links))
variables = variables[!variables == "geom"]


# Too slow with all the links...
#links = links[sample(1:nrow(links), 3000),]
links = links[1:1000,]
modes = unique(links[["MODE"]])

# Just the geography as geojson
# library(geojsonio)
# gjlinks = geojson_list(subset(links, select=c("geom")))

# Helpers
autoPalette = function(data) {
  if (is.factor(data)) {
    colorFactor(topo.colors(length(levels(data))), data)
  } else if (is.logical(data)) {
    colorFactor(topo.colors(2), data)
  } else {
    colorNumeric(palette = "RdYlBu", domain = data)
  }
}

getPopup = function (data, id) {
  stripSf = function(sfdf) (sfdf %>% st_set_geometry(NULL))
  meta = stripSf(links[id,])
  popupText = paste("<table >", paste(paste("<tr class='gcvt-popup-tr'><td class='gcvt-td'>", colnames(meta), "</td>", "<td>", sapply(meta, function(col) {as.character(col)}), "</td></tr>"), collapse=''), "</table>")
}

addAutoLinks = function (map, data, column) {
  col = data[[column]]
  pal = autoPalette(col)
  map %>%
    addPolylines(data = data, color=pal(col), label = as.character(col), weight = 2, layerId = 1:nrow(data), group = "links") %>%
    addLegend(position = "bottomleft", pal = pal, values = col, title = column, layerId = "linksLegend")
}

# addAutoLinksJSON = function (map, data, json, column) {
#   col = data[[column]]
#   pal = autoPalette(col)
#   map %>%
#     addGeoJSON(geojson = json, color=pal(col), weight = 2) %>%
#     addLegend(position = "bottomleft", data = data, pal = pal, values = col, title = column)
# }

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
                        textInput("scenarioPackage", "Scenario Package")),
                 tags$li(class="list-group-item",

                         # CSS is drawing wrong for the below. Seems to be related to inheriting position:relative
                         # from 'floater', but havent figured out how to fix yet
                         sliderInput("modelYear", "Model Year", 2020, 2040, value=2020, step=5, sep="")),
                 tags$li(class="list-group-item",
                         selectInput("variable", "Variable", variables, selected="MODE")),
                 tags$li(class="list-group-item",
                         selectInput("linkMode", "Mode", modes)),
                 tags$li(class="list-group-item", checkboxInput("another", "Another control"))
          )))
      )
  ,
  # Couldnt figure out how to provide multiple CSSs, which would have allowed use of BootSwatch
  # shinythemes lets you switch in bootswatch, but then you have to replace the below
  theme = "fullscreen.css"
)

server = function(input, output) {
  output$map <- renderLeaflet({
    leaflet(options = leafletOptions(preferCanvas = T)) %>%
      addProviderTiles(provider = "CartoDB.Positron") %>%
      addAutoLinks(data = links, column = "MODE")
  })

  observeEvent(input$variable, {
    leafletProxy("map") %>%
      clearGroup("links") %>%
      addAutoLinks(data = links, column = input$variable)
  })

  # TODO this is nearly done, but need to add 'rows=' to addAutoLinks, and a way to
  # remember it when changing variable too
  #
  # observeEvent(input$linkMode, {
  #   leafletProxy("map") %>%
  #     clearGroup("links") %>%
  #     addAutoLinks(data = links, column = input$variable, rows=input$linkMode)
  # })

  observeEvent(input$map_shape_click, {
    e = input$map_shape_click

    popupText = getPopup(links, e$id)

    leafletProxy("map") %>%
      addPopups(lng=e$lng, lat=e$lat, popup=popupText)
  })
}

# Run the application
shinyApp(ui = ui, server = server)
