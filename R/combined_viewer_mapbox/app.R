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
    anchorname = paste("collapse-", switchname, sep="")
    list(
      div(class="panel-heading",
        materialSwitch(switchname, status="info", inline=T),
        h4(class="gcvt-toggle-label", name),
        a(href=paste("#", anchorname, sep=""), "[ + ]", 'data-toggle'="collapse")),
      div(id=anchorname, class="panel-collapse collapse", panel_list(...)))
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
        selectInput("widthBy", "Set width by", c("Select variable"="", continuous_variables))),
      panel_item(
        selectInput("filterMode", "Show modes", modes, selected = modes, multiple = T)),
      panel_item(checkboxInput("advancedLinkStyles", "Advanced styles")),
      conditionalPanel(condition = "input.advancedLinkStyles == true",
        panel_item(
          selectInput("linkPalette", "Colour palette", palettes_avail, selected = "YlOrRd"),
          checkboxInput("revLinkPalette", "Reverse palette", value=F),
          checkboxInput("linkPalQuantile", "Quantile palette", value=F))))

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

    # ??
    selected = numeric(0)

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
    current_scenario = function(stype, name = input$scenario) {
      scenarios %>%
        filter(type == stype & name == name & year == input$modelYear) %>%
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

    # Take a potentially incomplete set of options and combine them with the defaults, returning a new complete set respecting the senior set.
    compute_options = function(defaults, senior) {
      options = list()
      for (name in names(defaults)) {
        options[[name]] = ifelse(is.null(senior[[name]]), defaults[[name]], senior[[name]])
      }
      options
    }

    # Update links and link legend
    updateLinks = function() {
      if (!input$showLinks) {
        mb$hideLayer('links')
        return()
      }

      base = current_scenario("links")
      comparator = comparator_scenario("links")

      # Options
      # Combine defaults with metadata then inputs (if advanced toggle is on).

      colourBy_defaults = list(
        good = "bigger",
        bins = "auto",
        palette = "YlOrRd",
        reverse_palette = F,
        quantile = F)
      # Get styling metadata from yaml
      options = metadata$links$columns[[input$colourBy]]
      options = compute_options(colourBy_defaults, options)
      if (input$advancedLinkStyles) {
        # Get styling options from inputs
        options = compute_options(
          options,
          list(
            palette = input$linkPalette,
            reverse_palette = input$revLinkPalette,
            quantile = input$linkPalQuantile))
            # widerDomain = widerDomain)
      }


      ## TODO: Use the bins option

      if (!is.null(comparator)) {
        meta = metaDiff(base, comparator)

        if (options$good == "smaller") {
          palfunc = function(values) {
            comparisonPalette(values, "green", "red")
          }
        } else {
          palfunc = comparisonPalette
        }
      } else {
        meta = base

        widerDomain = NULL
        # if ((!input$perScensRange) &&
        #   (input$colourBy %in% continuous_variables)){
        #   widerDomain = range(mins_links[[input$colourBy]], maxs_links[[input$colourBy]])
        #   # print(paste("wider range from ", widerDomain[1], "to", widerDomain[2]))
        # }

        # TODO Think there might be a better way to do the below, need to check with CC :)
        palfunc = function(data, palette) {
          autoPalette(data,
            palette = options$palette,
            reverse = options$reverse_palette,
            quantile = options$quantile,
            widerDomain = widerDomain)
        }
      }

      if (input$widthBy == "") {
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

      base = current_scenario("od_matrices")
      compareZones = comparator_scenario("od_matrices")

      variable = input$od_variable
      values = NULL

      if (!is.null(compareZones)) {
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
        values = baseVals - compVals
        variable = paste("Scenario difference in ", variable)

        # Comparison palette is washed out by outliers :(
        pal = comparisonPalette(values, "red", "green", "white", bins = 21)
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

        widerDomain = NULL
        # if (!input$perScensRange) {
        #   widerDomain = range(mins_zones[[input$od_variable]], maxs_zones[[input$od_variable]])
        #   print(paste("wider range from ", widerDomain[1], "to", widerDomain[2]))
        # }

        pal = autoPalette(values,
          palette = input$zonePalette,
          reverse = input$revZonePalette,
          quantile = input$zonePalQuantile,
          widerDomain = widerDomain)
      }

      output$zoneHint <- renderText({ paste("Zones shown are ", zoneHintMsg) })

      mb$styleByData(values, 'zones', pal = pal, colorValues = values, colorCol = input$od_variable)
      mb$showLayer('zones')
    }

    linesPerCentroid = 20
    updateCentroidLines = function() {
      if (input$showCLines && length(selected)) {
        # Get only the most important lines
        # Note we are assuming *highest* is what we want, need to think about relevance for GHG etc.
        od_skim = current_scenario("od_matrices")
        centroidlines = list()
        numLines = 1
        topVals = NULL
        targetLineCount = linesPerCentroid * length(selected)

        for (matrixRow in selected) {
          # Works by generating all zone pairs plus their vals, then later finding the top (say) 20,40, or 60
          rowVals = as.vector(od_skim[[input$od_variable]][matrixRow,])

          for (destPoint in 1:length(rowVals)) {
            centroidlines[[numLines]] = c(matrixRow, destPoint, rowVals[destPoint])
            numLines = numLines + 1
          }
        }

        # Get  K * |selected|  from all possible lines
        ordered = centroidlines[order(sapply(centroidlines,function(x) x[[3]]), decreasing = T)]
        topLines = ordered[1:targetLineCount]
        topVals = sapply(topLines, function(x) x[[3]])

        # Would be neater to do this in front end, but leaving here for now
        weights = weightScale(topVals)
        opacities = opacityScale(weights)

        for (cLine in 1:length(topLines)) {
          topLines[[cLine]] = c(topLines[[cLine]], weights[cLine], opacities[cLine])
        }

        mb$setCentroidLines(topLines)
      } else {
        mb$setCentroidLines(list())
      }

    }

    observe({updateLinks()})
    observe({updateZones()})

    observeEvent(input$mapLinkClick, {
      event = input$mapLinkClick
      meta = current_scenario("links")

      # TODO: If comparison enabled, show more columns and colour columns by change
      popupText = getPopup(meta[event$feature,])

      mb$setPopup(popupText, lng=event$lng, lat=event$lat)
          })

    observeEvent(input$mapPolyClick, {
      event = input$mapPolyClick
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

      updateZones()
      updateCentroidLines()
          })
  }

  shinyApp(ui = ui, server = server)
}

main("../../data/sensitive/GCVT_Scenario_Pack")
