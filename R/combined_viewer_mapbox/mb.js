import * as turf from '@turf/turf'

// Basic data-driven interface to mapbox.
//
// At the moment, `map` is coming from the window, but these functions should
// really take it as a parameter.
const atId = data => ['at', ['id'], ["literal", data]]
const atFid = data => ['at', ["-", ['get', 'fid'], 1], ["literal", data]]

export function hideLayer({ layer }) {
    map.setLayoutProperty(layer, 'visibility', 'none')

    if (layer === 'links') {
      top.popup.remove()
    }
}

export function showLayer({ layer }) {
    map.setLayoutProperty(layer, 'visibility', 'visible')
}

/**
 * Set the visibility for each id in the layer
 *
 * Layout property visibility is not data driven yet, so we have to use opacity instead.
 *
 * @param data array [id]: true|false
 */
export function setVisible({ layer, data }) {
    map.setPaintProperty(layer, 'line-opacity', atId(data.map(vis => vis ? 1 : 0)))
}

export function setColor({ layer, color, selected = [] }) {
    // Avoid attempting to set wrong property
    if (map.getLayer(layer).type === 'line') {
      if (Array.isArray(color)) {
        color = atId(color)
      }

      map.setPaintProperty(layer, 'line-color',
          ['to-color', color])
    }
    if (map.getLayer(layer).type === 'fill') {
      // TODO remove the id/fid distinction

      if (Array.isArray(color)) {
        if (Array.isArray(selected)) {
          selected.forEach(function (zoneColor) {
            color[zoneColor - 1] = '#ffcc00'
          })
        } else if (typeof selected == 'number') { // R is a pain :)
          color[selected - 1] = '#ffcc00'
        }

        color = atFid(color)
      }

      map.setPaintProperty(layer, 'fill-color',
          ['to-color', color])
    }
}


/**
 * Weight links, adjusting offset and interpolating by zoom
 *
 * Don't know which links are paired with which other links (for now), so maintaining an exact offset is tricky.
 *
 * V_total_ton, etc look OK with these settings, but Speed_freeflow looks crap. More experimentation required. Experiment in console with:
 *   app.weightLinks(app.data, 10, 20)
 *
 */
export function setWeight({ layer, weight, wFalloff = 4, oFalloff = 5 }) {
    if (Array.isArray(weight)) {
        weight = atId(weight)
    }

    map.setPaintProperty(layer, 'line-width',
        ['interpolate',
            ['linear'],
            ['zoom'],
            4, ['/', weight, wFalloff],
            10, weight
        ])

    // Only show an offset if weight varies.
    if (Array.isArray(weight)) {
        map.setPaintProperty(layer, 'line-offset',
            ['interpolate',
                ['linear'],
                ['zoom'],
                4, ['/', weight, oFalloff],
                10, ['/', weight, 2]
            ])
    } else {
        map.setPaintProperty('links','line-offset', ['interpolate',
                ['linear'],
                ['zoom'],
                4,0.5,
                10, 1.8
            ])
    }
}

/**
 * Draw centroid lines or turn them off
 *
 * The centroids are now calculated by Turf and not sf
 *
 */
export function setCentroidLines({ lines = [] }) {
  if (!Array.isArray(lines)) {
    lines = [lines]
  }

  if (lines.length > 0) {
    let clines = []

    // Shiny passes tuples of [o, d, value, weight, opacity] when the user requests them
    // Ultimately should have JS (rather than Shiny) calulating the latter stuff for display
    lines.forEach(function(pair) {
      let oPt = top.centroids.find(pt => {
        return pt.properties.fid === pair[0]
      })
      let dPt = top.centroids.find(pt => {
        return pt.properties.fid === pair[1]
      })

      let props = {
        weight:  pair[3],
        opacity: pair[4]
      }

      let cline = turf.lineString([
            oPt.geometry.coordinates,
            dPt.geometry.coordinates
          ],
          props
        )

      clines.push(cline)
    })

    map.getSource('centroidlines').setData(turf.featureCollection(clines))
    map.setPaintProperty('centroidlines','line-width', ['get', 'weight'])
    map.setPaintProperty('centroidlines','line-opacity', ['get', 'opacity'])
    map.moveLayer('centroidlines')

    showLayer({layer: 'centroidlines'})
  } else {
    hideLayer({layer: 'centroidlines'})
  }
}

/**
 * Show a popup
 */
export function setPopup ({text, lng, lat}) {
  top.popup = new mapboxgl.Popup()
    .setLngLat({lng: lng, lat: lat})
    .setHTML(text)
    .addTo(map)
}

export function setHover({coordinates, layer, feature}) {
  if (top.hover !== undefined) {
    // Need to remove explicitly, not just overwrite
    top.hover.remove()
  }

  top.hover = new mapboxgl.Popup({
    closeButton: false,
    closeOnClick: false
  })

  top.hover.setLngLat(coordinates)
    .setHTML(top.hints[layer][feature])
    .addTo(map)
}

/**
 * Prepare data for hover, save generating a Shiny request on each mouseover
 */
export function setHoverData({layer, hints}) {
  top.hints = top.hints || {}
  top.hints[layer] = hints
}
