# Common functions for leaflet/shiny

autoPalette = function(data, palette = "PuRd", factorColors = topo.colors) {
  if (is.factor(data)) {
    colorFactor(factorColors(length(levels(data))), data)
  } else if (is.logical(data)) {
    colorFactor(factorColors(2), data)
  } else {
    colorNumeric(palette = palette, domain = data)
  }
}

addAutoLegend = function(map, values, title, group, pal = autoPalette(values)) {
  map %>%
    addLegend(position = "bottomleft", pal = pal, values = values,
              title = title, group = group, layerId = paste(group, "Legend"))
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

reStyleZones = function(map, data, skim, variable, selected = NULL) {
  if (!length(selected)) {
    values = rowSums(skim[[variable]])
  } else if (length(selected) > 1) {
    # Sum of rows if several zones selected
    values = colSums(skim[[variable]][selected,])
  } else {
    values = skim[[variable]][selected,]
  }
  reStyle(map, "zones", values, variable, label = paste(data$NAME, ": ", as.character(values), sep = ""))
  setStyleFast(map, "zones", weight = rep(1, nrow(data)))

  for (selectedZone in selected) {
    map = setStyle(map, "zones", styles = list(list(weight = 4, color = "blue")), offset = selectedZone)
  }
}

reStyle = function(map, group, values, title, pal = autoPalette(values), label = as.character(values)) {
  map %>%
    addAutoLegend(values, title, group, pal) %>%
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
    addAutoLegend(map, colorDomain, colorCol, group, pal = pal)
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
comparisonPalette = function(values, negativeramp = "red", positiveramp = "green", neutral = "white") {
  # Do something different with factors and booleans.
  if (is.logical(values) || is.factor(values)) {
    return(colorFactor(topo.colors(2), values))
  }

  if (length(c(negativeramp)) != length(c(positiveramp)))
    stop("negativeramp and positiveramp must have the same length or neutral won't be in the middle")

  if (all(values == 0)) {
    pal = function(v) {stopifnot(v==0); rep(neutral, length(v))}
    attr(pal, "colorArgs")$bins = c(0,0)
    attr(pal, "colorType") = "bin"
    pal
  } else {
    # colorBin palette centered on 0.
    magnitude = max(abs(min(values)), max(values))
    pal = colorBin(c(negativeramp, neutral, positiveramp), c(-magnitude, magnitude),
                   bins = seq(from = -magnitude, to = magnitude, length.out = 8) %>% signif(2))

    # Trim the outer bins that won't get used (makes the legend look nicer)
    bins = attr(pal, "colorArgs")$bins
    while (min(values, 0) >= bins[[2]]) {
      bins = bins[2:length(bins)]
    }
    while (max(values, 0) <= bins[[length(bins)-1]]) {
      bins = bins[1:length(bins)-1]
    }
    attr(pal, "colorArgs")$bins = bins

    pal
  }
}
