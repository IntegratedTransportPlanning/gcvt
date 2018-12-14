# Display a map with data from the given directory
#       Display zones and links styled by their data
#
# Show a sidebar with appropriate name and variables
# Appropriate legends for links and zones
# Show popup when clicked

# Ch-ch-ch-changes
# Clear explanation of comparison mode
# updateLinks/update should use metadata.
#       Defaults/advanced toggle?
#       Remember options per variable?
# Specify bins to palette function

library(shiny)
library(RColorBrewer)
library(tidyverse)
library(fs)
library(yaml)
library(shinyWidgets)
library(shinythemes)
library(leaflet)

source("../metadata.R")
source("../app_common.R")

# Required boilerplate and sponsor icons
gcvt_viewer_page = function(...) {

  # This is for all the legends, which is a bit odd.
  legends = function() {
    div(class="panel legend",
        uiOutput("builtLegend", inline=T, container=div))
  }

  fillPage(
    tags$script(src='mapbox-gl.js'),
    tags$link(href='mapbox-gl.css', rel='stylesheet'),
    tags$link(href='style.css', rel='stylesheet'),
    tags$div(id = 'map'),
    tags$script(src = 'app.js'),
    img(id="kggtf", src='kggtf.jpg'),
    img(id="wb", src='world-bank.jpg'),
    img(id="itp", src='itp.png'),
    legends(),
    ...)
}

continuous_variables = NULL


# Sidebar header, scenario selection, links panel, zone panel
#
# This defines the ui element. It's broken down with one function per-section in an attempt to keep it understandable.
gcvt_side_panel = function(metadata, scenarios) {
  panel_list = function(...) {
    tags$ul(class="list-group", ...)
  }
  panel_item = function(...) {
    tags$li(class="list-group-item", ...)
  }

  scenario_selection = function() {
    years = scenarios$year %>% as.numeric() %>% unique() %>% sort()

    # Use aliases if available
    # Create a tibble of unique, sorted names and join with alias metadata.
    snames = scenarios$name %>%
      unique %>%
      sort %>%
      tibble(name = .) %>%
      left_join(get_aliases(metadata$scenarios))
    display_names = ifelse(is.na(snames$alias), snames$name, snames$alias)
    snames = setNames(snames$name, display_names)

    div(class="panel",
      panel_list(
        panel_item(selectInput("scenario", "Scenario Package", snames)),
        ### TODO: Add a tooltip here explaining what is compared with what (green where comparator is better), hover gives (Main - Comparison)
        panel_item(
          selectInput("comparator", "Compare with", c("Select scenario"="", snames))),
        panel_item(
          sliderInput("modelYear", "Model Year",
            2020,
            tail(years, 1),
            value = 2020,
            step = 5,          # Assumption
            sep = "")),
        panel_item(
          materialSwitch("perScensRange", status="info", inline=T),
          h5(class="gcvt-toggle-label", "Palette width switch"))
        ))
  }

  submenu = function(switchname, name, ...) {
    list(
      div(class="panel-heading",
        materialSwitch("showLinks", status="info", inline=T),
        h4(class="gcvt-toggle-label", "Network links "),
        a(href="#collapse1", "[ + ]", 'data-toggle'="collapse")),
      div(id="collapse1", class="panel-collapse collapse", panel_list(...)))
  }

  palettes_avail = rownames(brewer.pal.info)

  links = function() {
    link_attr = scenarios %>% filter(type == "links") %>% .$dataDF
    xample_attr = link_attr[[1]]

    ### TODO: Use aliases when present
    variables = colnames(xample_attr)
    continuous_variables <<- variables[sapply(xample_attr, is.numeric)]
    modes = levels(xample_attr$LType) # Fragile: not generic

    submenu("showLinks", "Network links ",
      panel_item(selectInput("colourBy", "Colour links by", variables, selected="LType")),
      panel_item(
        selectInput("widthBy", "Set width by", continuous_variables)),
      panel_item(
        selectInput("filterMode", "Show modes", modes, selected = modes, multiple = T)),
      ### TODO: Add a toggle that displays + enables these
      panel_item(
        selectInput("linkPalette", "Colour palette", palettes_avail, selected = "YlOrRd"),
        checkboxInput("revLinkPalette", "Reverse palette", value=F),
        checkboxInput("linkPalQuantile", "Quantile palette", value=F)))

  }

  od_matrices = function() {
    xample_matrices = scenarios %>% filter(type == "od_matrices") %>% .$dataDF %>% .[[1]]
    od_variables = names(xample_matrices)

    submenu("showZones", "Matrix zones ",
      panel_item(
        selectInput("od_variable", "OD skim variable", od_variables),
        checkboxInput("showCLines", "Show centroid lines?"),
        ### TODO: Add toggle here, too
        selectInput("zonePalette", "Colour palette", palettes_avail, selected="RdYlBu"),
        checkboxInput("revZonePalette", "Reverse palette", value=F),
        checkboxInput("zonePalQuantile", "Quantile palette", value=F),
        htmlOutput("zoneHint", inline=T)
        ))
  }

  header = function() {
    list(
      div(class="panel-heading",
        a(href="#collapse-about", h4(metadata$name), 'data-toggle'="collapse")),
      div(id="collapse-about", class="panel-collapse collapse",
        p(class="gcvt-panel-box", metadata$description),
        actionButton("dbg", "Debug now")))
  }

  div(class="panel-group floater",
    div(class="panel panel-default",
      header(),
      scenario_selection(),
      links(),
      od_matrices()
      ))
}

main = function(pack_dir) {
  metadata = get_metadata(pack_dir)
  scenarios = readRDS(path(pack_dir, "processed", "scenarios.Rds"))

  ui = gcvt_viewer_page(
    theme = shinytheme("darkly"),
    gcvt_side_panel(metadata, scenarios))

  server = function(input, output, session) {

    # Bad legend stuff
    linksLegend = ""
    zonesLegend = ""

    # mb.js interaction code
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
      setCentroidLines = function(lines) {
        session$sendCustomMessage("setCentroidLines", list(lines = lines))
      },
      setPopup = function(text, lng, lat) {
        session$sendCustomMessage("setPopup", list(text = text, lng = lng, lat = lat))
      },
      setHints = function(layer, hints) {
        session$sendCustomMessage("setHoverData", list(layer = layer, hints = hints))
      },

      # Style shapes on map according to columns in a matching metadata df.
      #
      # If shapes are styled by color then a legend is supplied. Weights are rescaled with weightScale. A useful label is generated.
      styleByData = function(
        data,
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
          label = paste(label, colorCol, ": ", colorValues, " ", sep = "")
          mb$setColor(group, pal(colorValues), selected)
        }
        if (!missing(weightCol)) {
          if (is.null(weightCol)) {
            mb$setWeight(group, 3)
          } else {
            label = paste(label, weightCol, ": ", weightValues, sep = "")
            mb$setWeight(group, weightScale(weightValues, weightDomain))
          }
        }

        # Set hover data
        mb$setHints(group, label)

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

    # Popup for a clicked link
    getPopup = function (meta) {
      paste("<table >", paste(paste("<tr class='gcvt-popup-tr'><td class='gcvt-td'>", colnames(meta), "</td>", "<td>", sapply(meta, function(col) { as.character(col) }), "</td></tr>"), collapse=''), "</table>")
    }

    # Get scenario
    current_scenario = function(type, name = input$scenario) {
      scenarios %>%
        filter(type == type & name == name & year == input$modelYear) %>%
        .$dataDF %>% .[[1]]
    }

    # Get comparison scenario
    comparator_scenario = function(type) {
      if ((input$comparator != input$scenario) && (input$comparator %in% scenarios$name)) {
        current_scenario(type, input$comparator)
      } else {
        NULL
      }
    }

    # Update links and link legend
    updateLinks = function() {
      if (!input$showLinks) {
        mb$hideLayer('links')
        return()
      }

      base = current_scenario()
      comparator = comparator_scenario()

      # Options
      # Combine defaults with either advanced inputs or metadata based on advanced toggle.
      # good
      # bins
      # palette
      # reverse_palette
      # quantile


      if (!is.null(comparator)) {
        meta = metaDiff(base, comparator)

        if (metadata$links$columns[[input$colourBy]]$good == "smaller") {
          palfunc = function(values) {
            comparisonPalette(values, "green", "red")
          }
        } else {
          palfunc = comparisonPalette
        }
      } else {
        meta = base

        widerDomain = NULL
        if ((!input$perScensRange) &&
          (input$colourBy %in% continuous_variables)){
          widerDomain = range(mins_links[[input$colourBy]], maxs_links[[input$colourBy]])
          # print(paste("wider range from ", widerDomain[1], "to", widerDomain[2]))
        }

        # TODO Think there might be a better way to do the below, need to check with CC :)
        palfunc = function(data, palette) {
          autoPalette(data,
            palette = input$linkPalette,
            reverse = input$revLinkPalette,
            quantile = input$linkPalQuantile,
            widerDomain = widerDomain)
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


  }

  shinyApp(ui = ui, server = server)
}

main("../../data/sensitive/GCVT_Scenario_Pack")
