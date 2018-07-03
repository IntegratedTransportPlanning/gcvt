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
    addLegend(position = "bottomleft", data = data, pal = pal, values = values,
              title = title, group = group, layerId = paste(group, "Legend"))
}

addAutoLinks = function (map, data, colorCol, weightCol, palfunc = autoPalette) {
  color = data[[colorCol]]
  pal = palfunc(color)
  map %>%
    addPolylines(data = data, group = "links", color = pal(color), layerId = 1:nrow(data)) %>%
    addAutoLegend(color, colorCol, "links", pal) %>%
    reStyle2("links", weight = data[[weightCol]],
             label = paste(colorCol, ": ", color, "; ",
                           weightCol, ": ", data[[weightCol]], sep = ""))
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
  } else {
    values = skim[[variable]][selected,]
  }
  reStyle(map, "zones", values, variable, label = paste(data$NAME, ": ", as.character(values), sep = ""))
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

reStyle2 = function(map, group, color = NULL, weight = NULL,
                    pal = autoPalette(color),
                    label = NULL) {
  if (!missing(weight)) { weight = scale_to_range(weight, domain = c(2, 10)) }
  if (!missing(color)) { color = pal(color) }
  map %>%
    setStyleFast(group, color = color, weight = weight, label = label)
}
