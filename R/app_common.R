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

addAutoLinks = function (map, data, colorCol, weightCol, palfunc = autoPalette) {
  color = data[[colorCol]]
  pal = palfunc(color)
  map = map %>%
    addPolylines(data = data, group = "links", color = pal(color), layerId = 1:nrow(data)) %>%
    addAutoLegend(color, colorCol, "links", pal)
  if (is.null(weightCol))
    reStyle2(map, "links", weight = rep(1, nrow(data)))
  else
    reStyle2(map, "links", weight = data[[weightCol]], label = paste(colorCol, ": ", color, "; ", weightCol, ": ", data[[weightCol]], sep = ""))
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
  if (is.null(selected)) {
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

# Scale a numeric vector to some range.
# If the vector has a range of 0, return the lower bound of domain.
scale_to_range = function(x, domain) {
  domain = range(domain)
  if (diff(range(x)) == 0)
    rep(domain[[1]], length(x))
  else
    (x - min(x)) / (max(x) / diff(domain)) + domain[[1]]
}

# Restyle color, weight, and/or label
reStyle2 = function(map, group, color = NULL, weight = NULL,
                    pal = autoPalette(color), label = NULL,
                    visible = NULL) {
  if (!missing(weight)) { weight = scale_to_range(weight, domain = c(2, 10)) }
  if (!missing(color)) { color = pal(color) }
  map %>%
    setStyleFast(group, color = color, weight = weight, label = label, stroke = visible)
}

# Overcomplicated so that you can leave out colorCol or weightCol (which doesn't currently ever happen)
reStyleLinks = function(map, data, colorCol = NULL, weightCol = NULL, palfunc = autoPalette) {
  label = ""
  if (!missing(colorCol)) {
    label = paste(label, colorCol, ": ", data[[colorCol]], " ", sep = "")
    color = data[[colorCol]]
    addAutoLegend(map, color, colorCol, 'links', pal = palfunc(color))
  }
  if (!missing(weightCol)) {
    if (is.null(weightCol)) {
      weight = rep(1, nrow(data))
    } else {
      label = paste(label, weightCol, ": ", data[[weightCol]], sep = "")
      weight = data[[weightCol]]
    }
  }
  reStyle2(map, 'links', color = color, weight = weight, label = label, pal = palfunc(color))
}

# Apply different palettes above and below zero
comparisonPalette = function(values, negativeramp = "red", positiveramp = "green", neutral = "white") {
  # Generate colorBin palettes for the biggest of min or max for both +ve and -ve: this will generate a consistent colour gradient above and below 0.
  magnitude = max(abs(min(values)), max(values))
  negativePal = colorBin(c(negativeramp, neutral), c(-magnitude, 0), 4)
  positivePal = colorBin(c(neutral, positiveramp), c(0, magnitude), 4)

  # Then trim the bins s.t. min(values) < bins[2] and max(values) > bins[length(bins)-1]
  bins = c(attr(negativePal, "colorArgs")$bins,
           attr(positivePal, "colorArgs")$bins) %>% unique()
  while (min(values) >= bins[[2]]) {
    bins = bins[2:length(bins)]
  }
  while (max(values) <= bins[[length(bins)-1]]) {
    bins = bins[1:length(bins)-1]
  }

  # Return a function that applies the appropriate palette and set two
  # attributes that addLegend requires.
  f = function(values2) {
    sapply(values2, function(value) {
      if (value < 0) {
        negativePal(value)
      } else if (value == 0) {
        neutral
      } else {
        positivePal(value)
      }
    })
  }
  attr(f, "colorType") <- "bin"
  attr(f, "colorArgs") <- list(bins = bins)
  f
}
