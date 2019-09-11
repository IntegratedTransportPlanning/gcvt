import * as itertools from 'itertools'
import * as immutable from 'immutable'
import * as turf from '@turf/turf'

// Still needed for centroids
import zones from '../../data/sensitive/GCVT_Scenario_Pack/geometry/zones.geojson'
import dummyline from './dummyline.geojson'

import * as mb from './mb.js'

const DEBUG_ON_A_TRAIN = false
const DEBUG = true
const BASEURL = "https://gcvt.cmcaine.co.uk/"

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
            style: 'mapbox://styles/mapbox/light-v9',
            zoom: 4,
            center: [32, 48]
        })
    }

    // debug
    window.map = map
    map.on('load', loadLinks)
    map.on('load', loadZones)
    map.on('load', setupLines)

    map.on('click', 'zones', function (event) {
      let message = {
        ctrlPressed: event.originalEvent.ctrlKey,
        shiftPressed: event.originalEvent.shiftKey,
        altPressed: event.originalEvent.altKey,
        zoneId: event.features[0].properties.fid
      }

      Shiny.setInputValue('mapPolyClick', message, {priority: 'event'})
    })

    map.on('click', 'links', function (event) {
      let message = {
        // This does not yet handle overlaid features
        feature: event.features[0].id,
        lng: event.lngLat.lng,
        lat: event.lngLat.lat
      }

      Shiny.setInputValue('mapLinkClick', message, {priority: 'event'})
    })

    map.on('mousemove', 'zones', function (event) {
      mb.setHover({coordinates: event.lngLat,
                    layer: 'zones',
                    feature: event.features[0].properties.fid - 1}) // TODO ugly
    })

    map.on('mouseleave', 'zones', function (event) {
      window.hover.remove()
    })

    map.on('mousemove', 'links', function (event) {
      mb.setHover({coordinates: event.lngLat,
                    layer: 'links',
                    feature: event.features[0].id})
    })

    map.on('mouseleave', 'links', function (event) {
      window.hover.remove()
    })

}

let listeners = new immutable.Map()
let linkLayerReady = false
let zoneLayerReady = false
let centroidLayerReady = false


/**
 * Load the link geojson.
 *
 * This is just hardcoded. In the futur we would expose the addLayer function
 * of the map or something.
 */
export async function loadLinks() {
    map.addLayer({
        id: 'links',
        type: 'line',
        source: {
            type: 'vector',
            tiles: [BASEURL + 'tiles/links/{z}/{x}/{y}.pbf',],
            // If you don't have this, mapbox doesn't show tiles beyond the
            // zoom level of the tiles, which is not what we want.
            maxzoom: 6,
        },
        "source-layer": "links",
        layout: {
            'line-cap': 'round',
            'line-join': 'round',
            visibility: 'none',
        },
        paint: {
            'line-opacity': .8,
            'line-color': 'blue',
        },
    })
    linkLayerReady = true
    listeners
        .filter((_, [f, layer]) => layer == 'links')
        .map((args, [func, layer]) => func(args))
}

export async function loadZones() {
    // zones loading
    map.addLayer({
        id: 'zones',
        type: 'fill',
        source: {
            type: 'vector',
            tiles: [BASEURL + 'tiles/zones/{z}/{x}/{y}.pbf',],
            // url: 'http://127.0.0.1:6767/zones.json'
            // If you don't have this, mapbox doesn't show tiles beyond the
            // zoom level of the tiles, which is not what we want.
            maxzoom: 6,
        },
        "source-layer": "zones",
        paint: {
            'fill-color': 'white',
            'fill-outline-color': '#aaa',
            'fill-opacity': 0.8,
        },
        layout: {
            visibility: 'none'
        }
    })

    let json = await (await fetch(zones)).json()
    window.jzones = json

    window.centroids = []
    window.jzones.features.forEach(function (feat) {
      window.centroids.push(turf.centroid(feat, feat.properties))
    })

    zoneLayerReady = true
    listeners
        .filter((_, [f, layer]) => layer == 'zones')
        .map((args, [func, layer]) => func(args))
    // listeners.map(([args, [func, _]]) => func(args))
}

export async function setupLines() {
  // A dummy centroid line, rather than waiting til needed to set up layer.
  // Seems messy, but works for now
  let tmpJson = await (await fetch(dummyline)).json()

  window.jclines = tmpJson
  map.addLayer({
    id: 'centroidlines',
        type: 'line',
        source: {
            type: 'geojson',
            data: tmpJson,
        },
        layout: {
            'line-cap': 'round',
            'line-join': 'round',
        },
        paint: {
            'line-opacity': 1,
            'line-color': 'black',
            'line-width': 1,
        },
  })
  centroidLayerReady = true
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
            window.lastmsg = msg
        }
        if (linkLayerReady && zoneLayerReady) {
            mb[name](msg)
        } else {
            // If map is not loaded, save the function to call and its arguments.
            // The call will be made when the map is loaded.
            //
            // These functions are not stateful, so we only need to remember
            // the most recent call of each function for each layer.
            listeners = listeners.set([mb[name], msg.layer], msg)
        }
    }))
