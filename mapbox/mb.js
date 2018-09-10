// Basic data-driven interface to mapbox.
//
// At the moment, `map` is coming from the window, but these functions should
// really take it as a parameter.

const atId = data => ['at', ['id'], ["literal", data]]

// Really should find a neater way than this. Easiest would be to require data to supply id
const atFid = data => ['at', ['get', 'fid'], ["literal", data]]

export function hideLayer({ layer }) {
    map.setLayoutProperty(layer, 'visibility', 'none')
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

export function setColor({ layer, color }) {
    // Avoid attempting to set wrong property
    if (map.getLayer(layer).type === 'line') {
      if (Array.isArray(color)) {
        color = atId(color)
      }

      map.setPaintProperty(layer, 'line-color',
          ['to-color', color])
    }
    if (map.getLayer(layer).type === 'fill') {
      if (Array.isArray(color)) {
        color = atFid(color)
      }

      map.setPaintProperty(layer, 'fill-color',
          ['to-color', color]) // will not work, defaults to black
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
                10, weight
            ])
    } else {
        map.setPaintProperty(layer, 'line-offset', 0)
    }
}
