import * as itertools from 'itertools'
import links from '../data/sensitive/processed/cropped_links.geojson'

let map
export function init() {
    mapboxgl.accessToken = 'pk.eyJ1IjoiY21jYWluZSIsImEiOiJjamxncGk5eXAwZGphM2tvMGpsOXA5c3kwIn0.i1g0SB88ni86cs0ZVOVG2w';
    map = new mapboxgl.Map({
        container: 'map',
        style: 'mapbox://styles/mapbox/light-v9'
    })
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

/**
 * Weight links, adjusting offset and interpolating by zoom
 *
 * Don't know which links are paired with which other links (for now), so maintaining an exact offset is tricky.
 *
 */
export const weightLinks = weights => {
    let offset
    if (Array.isArray(weights)) {
        offset = Math.max(...weights)
        weights = atId(weights)
    } else if (Number.isFinite(weights)) {
        offset = weights
    }

    map.setPaintProperty('links', 'line-width',
        ['interpolate',
            ['linear'],
            ['zoom'],
            4, ['/', weights, 10],
            10, weights
        ])
    map.setPaintProperty('links', 'line-offset',
        ['interpolate',
            ['linear'],
            ['zoom'],
            4, ['/', offset, 10],
            10, offset
        ])
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
    map,
    itertools,
    app: self,
})

addEventListener('DOMContentLoaded', init)
Object.keys(app).forEach(name =>
    Shiny.addCustomMessageHandler(name, msg => app[name](msg)))
