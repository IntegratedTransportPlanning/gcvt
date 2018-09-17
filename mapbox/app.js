import * as itertools from 'itertools'
import links from '../data/sensitive/processed/cropped_links.geojson'
import zones from '../data/sensitive/processed/zones.geojson'

import * as mb from './mb.js'

const DEBUG_ON_A_TRAIN = false
const DEBUG = true

export let map
export async function init() {
    if (DEBUG_ON_A_TRAIN) {
        // Use a blank background if I'm on a train :)
        let {default: style} = await import('./blankstyle')
        map = new mapboxgl.Map({
            container: 'map',
            style
        })
    } else {
        mapboxgl.accessToken = 'pk.eyJ1IjoiY21jYWluZSIsImEiOiJjamxncGk5eXAwZGphM2tvMGpsOXA5c3kwIn0.i1g0SB88ni86cs0ZVOVG2w';
        map = new mapboxgl.Map({
            container: 'map',
            style: 'mapbox://styles/mapbox/light-v9'
        })
    }

    // debug
    top.map = map
    map.on('load', loadLinks)
    map.on('load', loadZones)

    map.on('click', 'zones', function (event) {
      let message = {
        ctrlPressed: event.originalEvent.ctrlKey,
        shiftPressed: event.originalEvent.shiftKey,
        altPressed: event.originalEvent.altKey,
        zoneId: event.features[0].properties.fid
      }

      Shiny.setInputValue('mapPolyClick', message, {priority: 'event'})
    })
}

const listeners = new Map()
let linkLayerReady = false
let zoneLayerReady = false

/**
 * Load the link geojson.
 *
 * This is just hardcoded. In the futur we would expose the addLayer function
 * of the map or something.
 */
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
    linkLayerReady = true
    itertools.map(listeners, ([func, args]) => func(args))
}

export async function loadZones() {
    // zones loading
    let json = await (await fetch(zones)).json()
    top.jzones = json
    map.addLayer({
        id: 'zones',
        type: 'fill',
        source: {
            type: 'geojson',
            data: json,
        },
        paint: {
            'fill-color': 'blue',
            'fill-outline-color': '#aaa',
        },
    })
    zoneLayerReady = true
    itertools.map(listeners, ([func, args]) => func(args))
}

import * as self from './app'
Object.assign(window, {
    loadLinks,
    loadZones,
    itertools,
    app: self,
    mb
})

addEventListener('DOMContentLoaded', init)

// Make the interface available to Shiny.
Object.keys(mb).forEach(name =>
    Shiny.addCustomMessageHandler(name, msg => {
        if (DEBUG) {
            console.log(name, msg)
            top.lastmsg = msg
        }
        if (linkLayerReady && zoneLayerReady) {
            mb[name](msg)
        } else {
            // If map is not loaded, save the function to call and its arguments.
            // The call will be made when the map is loaded.
            //
            // These functions are not stateful, so we only need to remember
            // the most recent call.
            listeners.set(mb[name], msg)
        }
    }))
