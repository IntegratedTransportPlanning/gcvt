# Common functions for leaflet/shiny

autoPalette = function(data, palette = "PuRd", factorColors = rainbow) {
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

addAutoLinks = function (map, data, column, palfunc = autoPalette) {
  col = data[[column]]
  pal = palfunc(col)
  map %>%
    addPolylines(data = data, group = "links", color=pal(col), label = ~as.character(col), weight = 2, layerId = 1:nrow(data)) %>%
    addAutoLegend(col, column, "links", pal)
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

reStyleSlow = function(map, group, values, title, pal = autoPalette(values), label = as.character(values), chunksize = 500) {
  map %>%
    addAutoLegend(values, title, group, pal)

  # Chunking doesn't actually make this any faster, but it does produce a nice visual effect :)
  chunked = batchtools::chunk(values, chunk.size = chunksize, shuffle = F)
  offset = 0
  for (cn in 1:max(chunked)) {
    vals = values[chunked == cn]
    styles = lapply(pal(vals), function(colour) {list(fillColor=colour, color=colour)})
    setStyle(map, group, styles, label = label, offset = offset)
    offset = offset + length(vals)
  }
}
