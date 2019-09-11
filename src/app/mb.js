import * as turf from '@turf/turf'

// Basic data-driven interface to mapbox.
//
// At the moment, `map` is coming from the window, but these functions should
// really take it as a parameter.
const atId = data => ['at', ['id'], ["literal", data]]
const atFid = data => ['at', ["-", ['get', 'fid'], 1], ["literal", data]]

export function hideLayer({ layer }) {
    window.map.setLayoutProperty(layer, 'visibility', 'none')

    if (layer === 'links') {
      window.popup.remove()
    }
}

export function showLayer({ layer }) {
    window.map.setLayoutProperty(layer, 'visibility', 'visible')
}

/**
 * Set the visibility for each id in the layer
 *
 * Layout property visibility is not data driven yet, so we have to use opacity instead.
 *
 * @param data array [id]: true|false
 */
export function setVisible({ layer, data }) {
    window.map.setPaintProperty(layer, 'line-opacity', atId(data.map(vis => vis ? 1 : 0)))
}

export function setColor({ layer, color, selected = [] }) {
    // Avoid attempting to set wrong property
    if (window.map.getLayer(layer).type === 'line') {
      if (Array.isArray(color)) {
        color = atId(color)
      }

      window.map.setPaintProperty(layer, 'line-color',
          ['to-color', color])
    }
    if (window.map.getLayer(layer).type === 'fill') {
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

      window.map.setPaintProperty(layer, 'fill-color',
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

    window.map.setPaintProperty(layer, 'line-width',
        ['interpolate',
            ['linear'],
            ['zoom'],
            4, ['/', weight, wFalloff],
            10, weight
        ])

    // Show a slight fixed offset if weight does not vary
    if (Array.isArray(weight)) {
        window.map.setPaintProperty(layer, 'line-offset',
            ['interpolate',
                ['linear'],
                ['zoom'],
                4, ['/', weight, oFalloff],
                10, ['/', weight, 2]
            ])
    } else {
        window.map.setPaintProperty('links','line-offset', ['interpolate',
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
      let oPt = window.centroids.find(pt => {
        return pt.properties.fid === pair[0]
      })
      let dPt = window.centroids.find(pt => {
        return pt.properties.fid === pair[1]
      })

      let props = {
        weight:  pair[3],
        opacity: pair[4]
      }

      let cline = turf.greatCircle(
        oPt.geometry.coordinates,
        dPt.geometry.coordinates,
        {properties: props}
      )

      clines.push(cline)
    })

    window.map.getSource('centroidlines').setData(turf.featureCollection(clines))
    window.map.setPaintProperty('centroidlines','line-width', ['get', 'weight'])
    //window.map.setPaintProperty('centroidlines','line-opacity', ['get', 'opacity'])
    window.map.moveLayer('centroidlines')

    showLayer({layer: 'centroidlines'})
  } else {
    hideLayer({layer: 'centroidlines'})
  }
}

/**
 * Show a popup
 */
export function setPopup ({text, lng, lat}) {
  window.popup = new mapboxgl.Popup()
    .setLngLat({lng: lng, lat: lat})
    .setHTML(text)
    .addTo(map)
}

export function setHover({coordinates, layer, feature}) {
  if (window.hover !== undefined) {
    // Need to remove explicitly, not just overwrite
    window.hover.remove()
  }

  window.hover = new mapboxgl.Popup({
    closeButton: false,
    closeOnClick: false
  })

  window.hover.setLngLat(coordinates)
    .setHTML(window.hints[layer][feature])
    .addTo(map)
}

/**
 * Prepare data for hover, save generating a Shiny request on each mouseover
 */
export function setHoverData({layer, hints}) {
  window.hints = window.hints || {}
  window.hints[layer] = hints
}
