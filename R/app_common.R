# Common functions for leaflet/shiny

autoPalette = function(data, palette = "YlOrRd", factorColors = topo.colors, reverse=F, quantile=F, widerDomain = NULL) {
  if (is.null(widerDomain)) {
    widerDomain = data
  }

  # All of these colorXX ramps come from leaflet, but no reason not to use them for convenience
  if (is.factor(data)) {
    colorFactor(factorColors(length(levels(data))), data)
  } else if (is.logical(data)) {
    colorFactor(factorColors(2), data)
  } else if (quantile) {
    # From  https://github.com/rstudio/leaflet/issues/94
    # works out a sensible number of bins based on data

    # Remove all the erroneous zeroes and duplicated data
    cleaned = data[data != 0]

    if (length(cleaned) > 0) {
      targetBins = 7

      probs <- seq(0, 1, length.out = targetBins + 1)
      bins <- round(quantile(cleaned, probs, na.rm = TRUE, names = FALSE))

      while (length(unique(bins)) != length(bins)) {
        targetBins = targetBins - 1
        probs <- seq(0, 1, length.out = targetBins + 1)
        bins <- round(quantile(cleaned, probs, na.rm = TRUE, names = FALSE))
      }

      # rounded the bins to avoid having multiple 0s in legend (which seems to round for us).
      # the following stops the very edge values becoming NA
      bins[length(bins)] = bins[length(bins)] + 1
      if (bins[1] > 0) {
        bins[1] = bins[1] - 1
      }

      if (targetBins > 4) {
        colorBin(palette = palette, domain = cleaned, bins = bins, reverse = reverse)
      } else {
        # Produce something, even if it's not sensible, saves crashing
        colorNumeric(palette = palette, domain = cleaned, reverse = reverse, na.color="#eeeeee")
      }

    } else {
      colorNumeric(palette = palette, domain = widerDomain, reverse = reverse)
    }
  } else {
    colorNumeric(palette = palette, domain = widerDomain, reverse = reverse)
  }
}

addAutoLegend = function(palette, values, group, friendlyGroupName = group, unitName = " ") {
  #
  # Construct an HTML table to use as legend
  #
  thisLegend = list(h5(friendlyGroupName),h6(unitName))

  if (attr(palette, 'colorType') == 'numeric') {
    min = palette(min(values))
    max = palette(max(values))
    fmtdMin = format(min(values), big.mark=",")
    fmtdMax = format(max(values), big.mark=",")

    # TODO Where does the middle color get drawn? it's not the median
    tableRows = list()

    tableRows[[1]] = tags$tr(
                        tags$td(class="legend-item",
                                rowspan=5,
                                style=paste("background: linear-gradient(",min,",",max,")")),
                        tags$td(class="legend-item",
                                fmtdMin)
                      )
    tableRows[[2]] = tags$tr(
      tags$td(class="legend-item",
              " ")
      )

    tableRows[[3]] = tags$tr(
      tags$td(class="legend-item",
              " ")  ## TODO mid value here
    )

    tableRows[[4]] = tags$tr(
      tags$td(class="legend-item",
              " ")
    )

    tableRows[[5]] = tags$tr(
      tags$td(class="legend-item",
              fmtdMax)
    )

    thisLegend[[3]] = tags$table(tableRows)
  }
  else {
    if (attr(palette, 'colorType') == 'factor') {
      # Work out each factor and color accordingly
      boundaries = levels(values)
      boundaryColours = sapply(boundaries, palette)
    }

    if (attr(palette, 'colorType') == 'bin') {
      # Work out bin pos, plus whether NA is present
      boundaries = attr(palette, 'colorArgs')$bins
      if (length(boundaries) > 1) {
        ## WTF!! : sapply(boundaries - 1, ...
        boundaryColours = sapply(boundaries, palette)
      } else {
        # Handle what to do if no difference
        boundaryColours = c("#ffffff")
      }

    }
    tableRows = list()

    # Loop over bins and add a box, label for each
    for (i in 1:length(boundaries)) {
      listPos = length(tableRows) + 1
      tableRows[[listPos]] = tags$tr(
        tags$td(class="legend-item",
                div(class="legend-block", style=paste("background:",boundaryColours[[i]]))),
        tags$td(class="legend-item",
                format(boundaries[[i]], big.mark=",")))
    }
    na = attr(palette, 'colorArgs')$na

    thisLegend[[3]] = tags$table(tableRows)
  }

  thisLegend
}

addAutoPolygons = function(map, data, values, title, palfunc = autoPalette) {
  pal = autoPalette(values)
  map %>%
    addPolygons(data = data, color=pal(values), label = paste(data$NAME, ": ", as.character(values), sep = ""),
                group = "zones", layerId = 1:nrow(data),
                weight = 1) %>%
    addAutoLegend(values, title, "zones", pal)
}

# Add zones coloured by sum of variable for each region or by value for some selected region.
addSkimZones = function(map, data, skim, variable, selected = NULL, palfunc = autoPalette) {
  if (is.null(selected)) {
    values = rowSums(skim[[variable]])
  } else {
    values = skim[[variable]][selected,]
  }
  addAutoPolygons(map, data, values, variable, palfunc)
}

reStyleZones = function(map, data, values, variable, selected = NULL, pal = autoPalette(values)) {
  map = reStyle(map, "zones", values, variable, pal = pal, label = paste(data$NAME, ": ", as.character(values), sep = ""))
  map = setStyleFast(map, "zones", weight = rep(1, nrow(data)))

  for (selectedZone in selected) {
    map = setStyle(map, "zones", styles = list(list(weight = 2, color = "black")), offset = selectedZone)
  }
  map
}

reStyle = function(map, group, values, title, pal = autoPalette(values), label = as.character(values)) {
  map %>%
    addAutoLegendLeaflet(values, title, group, pal) %>%
    setStyleFast(group, color = pal(values), label = label)
}

# Scale x to a suitable width for drawing on the map.
#
# If the domain has no range then draw thin lines.
weightScale = function(x, domain = x) {
  domain = range(domain)
  if (diff(range(domain)))
    scales::rescale(x, to = c(2,10), from = domain)
  else
    rep(2, length(x))
}

opacityScale = function(x) {
  opacs = rep(0.1, length(x))

  for (i in 1:length(x)) {
    if (x[i] >= 4) {1
      opacs[i] = 0.2
    }
    if (x[i] >= 8) {
      opacs[i] = 0.4
    }
  }

  return (opacs)
}


addAutoLegendLeaflet = function(map, values, title, group, pal = autoPalette(values)) {

  if(attr(pal, "colorType") == "quantile") {
    # Some faffing to make quantiles come out nicely in legend
    map %>%
      addLegend(position = "bottomleft", pal = pal, values = values,
                title = title, group = group, layerId = paste(group, "Legend", sep = ""),
                labFormat = function(type, cuts, p) {
                  n = length(cuts)
                  paste0(as.integer(cuts)[-n], " &ndash; ", as.integer(cuts)[-1])
                })
  } else {
    map %>%
      addLegend(position = "bottomleft", pal = pal, values = values,
                title = title, group = group, layerId = paste(group, "Legend", sep = ""))
  }
}

# Style shapes on map according to columns in a matching metadata df.
#
# If shapes are styled by color then a legend is supplied. Weights are rescaled with weightScale. A useful label is generated.
styleByData = function(map, data, group,
                       colorCol = NULL, colorValues = if (is.null(colorCol)) NULL else data[[colorCol]], colorDomain = colorValues,
                       palfunc = autoPalette, pal = palfunc(colorDomain),
                       weightCol = NULL, weightValues = if (is.null(weightCol)) NULL else data[[weightCol]], weightDomain = weightValues
                       ) {
  label = ""
  if (!missing(colorCol)) {
    label = paste(label, colorCol, ": ", colorValues, " ", sep = "")
    map = addAutoLegendLeaflet(map, colorDomain, colorCol, group, pal = pal)
  }
  if (!missing(weightCol)) {
    if (is.null(weightCol)) {
      weightValues = rep(1, nrow(data))
      weightDomain = 1
    } else {
      label = paste(label, weightCol, ": ", weightValues, sep = "")
    }
  }
  setStyleFast(map, group, color = pal(colorValues),
               weight = weightScale(weightValues, weightDomain),
               label = label)
}

# Apply different palettes above and below zero
#
# Use a colorBin with an odd number of bins. Round bins slightly for prettiness.
comparisonPalette = function(values, negativeramp = "red", positiveramp = "green", neutral = "white", bins = 7, reverse = F) {
  if (reverse) {
    temp = negativeramp
    negativeramp = positiveramp
    positiveramp = temp
  }
  # Do something different with factors and booleans.
  if (is.logical(values) || is.factor(values)) {
    return(colorFactor(topo.colors(2), values))
  }

  if (length(c(negativeramp)) != length(c(positiveramp)))
    ## TODO don't understand this - isn't the value just a text description of a palette? 
    stop("negativeramp and positiveramp must have the same length or neutral won't be in the middle")
  
  # Get the probs and bins
  # Limit bin count to 11 cos it was starting to look crowded
  probs = seq(0,1,length.out = min(bins + 1,11))
  bins = round(quantile(values, probs, na.rm=TRUE, names=FALSE),2)
  
  # Insert a 0 so we can sep green/red
  bins = c(bins[bins < 0], 0, bins[bins > 0])
  bins = unique(bins)

  negBins = bins[bins <= 0]
  posBins = bins[bins >= 0]

  # Get the colours separately for above and below 0
  negPal = colorRampPalette(c(negativeramp, neutral), interpolate="linear")
  posPal = colorRampPalette(c(neutral, positiveramp), interpolate="linear")

  negVals = negPal(length(negBins))
  posVals = posPal(length(posBins))[2:length(posBins)]

  colourRamp = c(negVals, posVals)
  print (bins)
  print (colourRamp)
  
  if (all(values == 0)) {
    pal = function(v) {stopifnot(v==0); rep(neutral, length(v))}
    attr(pal, "colorArgs")$bins = c(0,0)
    attr(pal, "colorType") = "bin"
    pal
  } else {
    # colorBin palette centered on 0.
    if (length(bins) > 4) {
        # Already constructed ramp and removed unneeded levels
        pal = colorBin(colourRamp, 
                            domain = c(min(values),max(values)),
                            bins = bins)
    } else { 
        # Fail over to something ugly rather than crashing or providing something even worse
        pal = colorNumeric(palette = c(negativeramp, neutral, positiveramp), 
                            domain = c(min(values), max(values)), 
                            reverse = reverse, na.color="#eeeeee")
    } 
    pal
  }
}

linesFrom = function(from, to) {
  # Convert from to a single point
  from = st_geometry(from)[[1]]
  st_sfc(lapply(st_geometry(to), function(point) {st_linestring(rbind(from, point))}))
}

metaDiff = function(base, comparator) {
  meta = base
  coldiff = function(a, b)
    if (is.factor(a)) as.factor(ifelse(a == b, "same", "different"))
    else a - b
  for (i in 1:length(base)) meta[[i]] = coldiff(base[[i]], comparator[[i]])
  meta
}
