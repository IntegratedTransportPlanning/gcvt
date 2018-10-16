library(shiny)
library(leaflet)
library(readr)
library(reshape2)
library(stringr)

# {{{ Prepare data

# Links: Load metadata
load("../../data/sensitive/processed/cropped_scenarios.RData")

meta = scenarios[[1]]
modes = levels(meta$LType)

variables = sort(colnames(meta))
continuous_variables = colnames(meta)[sapply(meta, is.numeric)] %>% sort()
continuous_variables = c("Select variable", continuous_variables)

library(RColorBrewer)
palettes_avail = rownames(brewer.pal.info)

# Zone data: Get the skims

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


linksLegend = ""
zonesLegend = ""

# }}}

# {{{ Drawing functions


# }}}

# {{{ UI

library(shinyWidgets)
library(shinythemes)

ui = fillPage(
  tags$script(src='mapbox-gl.js'),
  tags$link(href='mapbox-gl.css', rel='stylesheet'),
  tags$link(href='style.css', rel='stylesheet'),
  tags$div(id = 'map'),
  tags$script(src = 'app.js'),
  img(id="kggtf", src='kggtf.jpg'),
  img(id="wb", src='world-bank.jpg'),
  div(class="panel legend",
      uiOutput("builtLegend", inline=T, container=div)),
  div(class="panel-group floater",
      div(class="panel panel-default",
          div(class="panel-heading",
              a(href="#collapse-about", h4("Greener Connectivity Visualisation Tool"), 'data-toggle'="collapse")),
          div(id="collapse-about", class="panel-collapse collapse",
              p(class="gcvt-panel-box", "The GCVT is a tool for viewing data from strategic transport models, using both network link data and OD zone skims.",
                   a(href="https://github.com/IntegratedTransportPlanning/gcvt", "More info...")
                   ),
              actionButton("dbg", "Debug now"),
              actionButton('rainbow', 'Taste the rainbow!'),
              actionButton('bland', 'Default colour'),
              selectInput('variable', 'variable', continuous_variables)
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
                         selectInput("filterMode", "Show modes", modes, selected = modes[!modes == "Connectors"], multiple = T)),
                 tags$li(class="list-group-item",
                         selectInput("linkPalette", "Colour palette", palettes_avail, selected = "YlOrRd"),
                         checkboxInput("revLinkPalette", "Reverse palette", value=F),
                         checkboxInput("linkPalQuantile", "Quantile palette", value=F))
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
                         selectInput("zonePalette", "Colour palette", palettes_avail, selected="RdYlBu"),
                         checkboxInput("revZonePalette", "Reverse palette", value=F),
                         checkboxInput("zonePalQuantile", "Quantile palette", value=F),
                         htmlOutput("zoneHint", inline=T)
                         )

          ))
          )
      ),
  theme = shinytheme("darkly")
)

# }}}

# {{{ server

server = function(input, output, session) {
  observeEvent(input$dbg, {browser()})

  source('../app_common.R')

  selected = numeric(0)

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


  mb = list(
    hideLayer = function(layername) {
      session$sendCustomMessage("hideLayer", list(layer = layername))
    },
    showLayer = function(layername) {
      session$sendCustomMessage("showLayer", list(layer = layername))
    },
    setVisible = function(layername, idVisibilities) {
      session$sendCustomMessage("setVisible", list(layer = layername, data = idVisibilities))
    },
    setColor = function(layer, color, selected) {
      session$sendCustomMessage("setColor", list(layer = layer, color = color, selected = selected))
    },
    setWeight = function(layer, weight) {
      session$sendCustomMessage("setWeight", list(layer = layer, weight = weight))
    },
    # Style shapes on map according to columns in a matching metadata df.
    #
    # If shapes are styled by color then a legend is supplied. Weights are rescaled with weightScale. A useful label is generated.
    styleByData = function(data,
                           group,
                           colorCol = NULL,
                           colorValues = if (is.null(colorCol)) NULL else data[[colorCol]],
                           colorDomain = colorValues,
                           palfunc = autoPalette,
                           pal = palfunc(colorDomain),
                           weightCol = NULL,
                           weightValues = if (is.null(weightCol)) NULL else data[[weightCol]],
                           weightDomain = weightValues
                           ) {
      label = ""
      if (!missing(colorCol)) {
        # Links
        label = paste(label, colorCol, ": ", colorValues, " ", sep = "")
        mb$setColor(group, pal(colorValues), NULL)

      } else {
        # Zones
        colorValues = data
        mb$setColor(group, pal(colorValues), selected)
      }
      if (!missing(weightCol)) {
        if (is.null(weightCol)) {
          mb$setWeight(group, 5)
        } else {
          label = paste(label, weightCol, ": ", weightValues, sep = "")
          mb$setWeight(group, weightScale(weightValues, weightDomain))
        }
      }

      # Build and draw the legend, but only for the layer we need
      legendData = addAutoLegend(pal,
                                  colorValues,
                                  group,
                                  friendlyGroupName = str_to_title(group))


      if (group == "links") {
        linksLegend = legendData
      }
      if (group == "zones") {
        zonesLegend = legendData
      }

      ## TODO try and figure out what is going wrong with this, for some reason
      # contents of vars are getting messed up (regardless of scope)
      output$builtLegend <- renderUI({
        tagList(linksLegend,
             zonesLegend)
        })
    })

  updateLinks = function() {
    if (!input$showLinks) {
      mb$hideLayer('links')
      return()
    }

    base = scenarios[[input$scenario]]

    if (input$comparator %in% names(scenarios)) {
      meta = metaDiff(base, scenarios[[input$comparator]])
      palfunc = comparisonPalette
    } else {
      meta = base

      # TODO Think there might be a better way to do the below, need to check with CC :)
      palfunc = function(data, palette) {
        autoPalette(data,
            palette = input$linkPalette,
            reverse = input$revLinkPalette,
            quantile = input$linkPalQuantile)
      }
    }

    if (input$widthBy == continuous_variables[[1]]) {
      widthBy = NULL
    } else {
      widthBy = input$widthBy
    }

    # Use base$LType for filtering, not the comparison
    visible = base$LType %in% input$filterMode

    mb$setVisible('links', visible)
    mb$styleByData(meta, 'links', colorCol = input$colourBy, weightCol = widthBy, palfunc = palfunc)
    mb$showLayer('links')
  }


  updateZones = function() {
    if (!input$showZones) {
      mb$hideLayer('zones')
      return()
    }

    base = od_scenarios[[input$scenario]]
    variable = input$od_variable
    values = NULL

    if ((input$od_comparator %in% names(od_scenarios)) &&
        (input$od_comparator != input$od_scenario)) {
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
      # browser()
      pal = autoPalette(values,
                        palette = input$zonePalette,
                        reverse = input$revZonePalette,
                        quantile = input$zonePalQuantile)
    }

    output$zoneHint <- renderText({ paste("Zones shown are ", zoneHintMsg) })

    mb$styleByData(values, 'zones', pal = pal)
    mb$showLayer('zones')
  }


  observe({updateLinks()})

  observe({updateZones()})

  observeEvent(input$mapPolyClick, {
    event = input$mapPolyClick

    if (F) { # e$group == "links"
      # TODO link click (for popup)
      # meta = scenarios[[input$scenario]]
      #
      # # TODO: If comparison enabled, show more columns and colour columns by change
      #
      # popupText = getPopup(meta[e$id,])
      #
      # leafletProxy("map") %>%
      #   addPopups(lng=e$lng, lat=e$lat, popup=popupText)
    } else if (T) {
      id = event$zoneId

      modded = event$altPressed
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

      # Be careful with these!
      updateZones()
      #updateCentroidLines()
    }
  })

  # Am I right in thinking these can be removed?
  observeEvent(input$rainbow, {
    # You have to send a message even if the function doesn't take any arg
    session$sendCustomMessage("rotateColours", 0)
  })
  observeEvent(input$bland, {
    session$sendCustomMessage("colourLinks", "blue")
  })

  observeEvent(input$variable, {
    weights = weightScale(scenarios$base[[input$variable]])
    session$sendCustomMessage("weightLinks", weights)
  })
}

# }}}

shinyApp(
  ui = ui,
  server = server
)
