import * as itertools from 'itertools'
import links from '../data/sensitive/processed/cropped_links.geojson'

export let map
export function init() {
    mapboxgl.accessToken = 'pk.eyJ1IjoiY21jYWluZSIsImEiOiJjamxncGk5eXAwZGphM2tvMGpsOXA5c3kwIn0.i1g0SB88ni86cs0ZVOVG2w';
    map = new mapboxgl.Map({
        container: 'map',
        style: 'mapbox://styles/mapbox/light-v9'
    })
    top.map = map
    map.on('load', loadLinks)
}

let marquee = () => itertools.cycle(["#f00", "#0f0", "#00f"])

export async function loadLinks() {
    let json = await (await fetch(links)).json()
    top.jlinks = json
    map.addLayer({
        id: 'links',
        type: 'line',
        source: {
            type: 'geojson',
            data: json,
        },
        layout: {
            'line-cap': 'round',
            'line-join': 'round',
        },
        paint: {
            'line-opacity': .8,
            'line-color': 'blue',
        },
    })
    weightLinks(5)
    // let colours = itertools.take(json.features.length, marquee())
    // colourLinks()
}

const tic = () => {
    performance.clearMarks()
    performance.mark('tic')
}
const toc = () => {
    performance.clearMeasures()
    performance.measure('tictoc', 'tic')
    return performance.getEntriesByName('tictoc')[0].duration
}
const atId = data => ['at', ['id'], ["literal", data]]

export const colourLinks = colours => {
    if (Array.isArray(colours)) {
        colours = atId(colours)
    }
    map.setPaintProperty('links', 'line-color',
        ['to-color', colours])
}

// debug
export let data
/**
 * Weight links, adjusting offset and interpolating by zoom
 *
 * Don't know which links are paired with which other links (for now), so maintaining an exact offset is tricky.
 *
 * V_total_ton, etc look OK with these settings, but Speed_freeflow looks crap. More experimentation required. Experiment in console with:
 *   app.weightLinks(app.data, 10, 20)
 *
 */
export function weightLinks(weights, wFalloff = 4, oFalloff = 5) {
    // debug
    data = weights
    if (Array.isArray(weights)) {
        weights = atId(weights)
    }

    map.setPaintProperty('links', 'line-width',
        ['interpolate',
            ['linear'],
            ['zoom'],
            4, ['/', weights, wFalloff],
            10, weights
        ])

    // Only show an offset if weight varies.
    if (Array.isArray(weights)) {
        map.setPaintProperty('links', 'line-offset',
            ['interpolate',
                ['linear'],
                ['zoom'],
                4, ['/', weights, oFalloff],
                10, weights
            ])
    } else {
        map.setPaintProperty('links', 'line-offset', 0)
    }
}

const randInt = (lo, hi) =>
    Math.round((Math.random() * (hi - lo)) + lo)


let index = 0
export function rotateColours() {
    let marq = marquee()
    itertools.take(++index, marq)
    let colours = itertools.take(jlinks.features.length, marq)
    tic()
    colourLinks(colours)
    let once = function self() {
        console.log(toc())
    }
    map.on('render', once)
    setTimeout(() => map.off('render', once), 2000)
}

import * as self from './app'
Object.assign(window, {
    tic,
    toc,
    colourLinks,
    weightLinks,
    randInt,
    loadLinks,
    rotateColours,
    itertools,
    app: self,
})

addEventListener('DOMContentLoaded', init)
Object.keys(app).forEach(name =>
    Shiny.addCustomMessageHandler(name, msg => app[name](msg)))
