library(shiny)
library(leaflet)

# Load metadata
load("../data/sensitive/processed/cropped_scenarios.RData")

meta = scenarios[[1]]
modes = levels(meta$LType)

variables = sort(colnames(meta))
continuous_variables = colnames(meta)[sapply(meta, is.numeric)] %>% sort()
continuous_variables = c("Select variable", continuous_variables)

# Scale x to a suitable width for drawing on the map.
#
# If the domain has no range then draw thin lines.
weightScale = function(x, domain = x) {
  domain = range(domain)
  if (diff(range(domain)))
    scales::rescale(x, to = c(2,15), from = domain)
  else
    rep(2, length(x))
}

shinyApp(
  ui = fillPage(
    tags$script(src='https://api.tiles.mapbox.com/mapbox-gl-js/v0.48.0/mapbox-gl.js'),
    tags$link(href='https://api.tiles.mapbox.com/mapbox-gl-js/v0.48.0/mapbox-gl.css', rel='stylesheet'),
    tags$link(href='style.css', rel='stylesheet'),
    tags$div(id = 'map'),
    tags$script(src = 'app.js'),
    div(class="panel-group floater",
        div(class="panel panel-default",
          actionButton('doit', 'Do it!'),
          selectInput('variable', 'variable', continuous_variables)
          )
        )
  ),
  server = function(input, output, session) {
    observeEvent(input$doit, {
      session$sendCustomMessage("rotateColours", 0)
    })

    observeEvent(input$variable, {
      weights = weightScale(scenarios$base[[input$variable]])
      session$sendCustomMessage("weightLinks", weights)
    })
  }
)
