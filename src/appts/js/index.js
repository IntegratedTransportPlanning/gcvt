import meiosisMergerino from "meiosis-setup/mergerino";
import simpleStream from "meiosis-setup/simple-stream";
import merge from "mergerino";

import mapboxgl from 'mapbox-gl';
import * as d3 from 'd3';

import {m, render} from 'mithril'


// UTILITY FUNCS

const propertiesDiffer = (props, a, b) =>
    props.filter(key => a[key] !== b[key]).length !== 0


// INITIAL STATE

const initial = (() => {
    const queryString = new URLSearchParams(window.location.hash.replace("#",""))
    const f = key => parseFloat(queryString.get(key))
    return {
        lng: f("lng") || 33,
        lat: f("lat") || 48,
        zoom: f("zoom") || 4,
        meta: {
            links: {},
            od_matrices: {},
        },
        linkVar: queryString.get("linkVar"),
        matVar: queryString.get("matVar"),
    }
})()

console.log(initial)

const mapboxInit = ({lng, lat, zoom}) => {
    mapboxgl.accessToken = 'pk.eyJ1IjoiYm92aW5lM2RvbSIsImEiOiJjazJrcjkwdHIxd2tkM2JwNTJnZzQxYjFjIn0.P0rLbO5oj5d3AwpuVqjBSw'

    const map = new mapboxgl.Map({
        container: 'map', // container id
        style: 'mapbox://styles/mapbox/light-v10', // stylesheet location
        center: [lng, lat],
        zoom: zoom,
    })

    // disable map rotation using right click + drag
    map.dragRotate.disable()

    // disable map rotation using touch rotation gesture
    map.touchZoomRotate.disableRotation()

    const BASEURL = document.location.origin

    function loadLayers() {
        map.addLayer({
            id: 'zones',
            type: 'fill',
            source: {
                type: 'vector',
                tiles: [BASEURL + '/tiles/zones/{z}/{x}/{y}.pbf',],
                // url: 'http://127.0.0.1:6767/zones.json'
                // If you don't have this, mapbox doesn't show tiles beyond the
                // zoom level of the tiles, which is not what we want.
                maxzoom: 6,
            },
            "source-layer": "zones",
            paint: {
                'fill-color': 'grey',
                'fill-outline-color': '#aaa',
                'fill-opacity': 0.5,
            },
            layout: {
                visibility: 'visible'
            }
        })
        map.addLayer({
            id: 'links',
            type: 'line',
            source: {
                type: 'vector',
                tiles: [BASEURL + '/tiles/links/{z}/{x}/{y}.pbf',],
                // If you don't have this, mapbox doesn't show tiles beyond the
                // zoom level of the tiles, which is not what we want.
                maxzoom: 6,
            },
            "source-layer": "links",
            layout: {
                'line-cap': 'round',
                'line-join': 'round',
                visibility: 'visible',
            },
            paint: {
                'line-opacity': .8,
                'line-color': 'blue',
            },
        })
    }

    map.on('load', loadLayers)

    return map
}

// Not in the state because it's it's own state-managing thing.
const map = mapboxInit(initial)


// APP

// https://github.com/foxdonut/meiosis/tree/master/helpers/setup#user-content-application
const app = {
    // TODO: populate from query string
    initial,

    // TODO:
    // change lat/lon/zoom
    // receive info for menu
    // change view params
    //   scenario
    //   year
    //   variable
    //   change-type
    //   data-type
    //   centroids
    Actions: update => {
        return {
            changePosition: (lng, lat, zoom) => {
                update({lng, lat, zoom})
            },
            updateScenarios: x => {
               update(x)
            },
            setActiveScenario: v => {
                update({linkVar: v})
            }
        }
    },

    services: [
        ({ state, previousState, patch }) => {
            // Query string updater
            // take subset of things that should be saved, pushState if any change.
            const nums_in_query = [ "lng", "lat", "zoom" ]
            const strings_in_query = [ "linkVar", "matVar" ]
            let updateRequired = false
            const queryItems = []
            for (let key of nums_in_query) {
                if (state[key].toPrecision(5) !== previousState[key].toPrecision(5)) {
                    updateRequired = true
                    break
                }
            }

            if (!updateRequired) {
                for (let key of strings_in_query) {
                    if (state[key] !== previousState[key]) {
                        updateRequired = true
                        break
                    }
                }
            }

            if (updateRequired) {
                queryItems.push(...nums_in_query.map(key => `${key}=${state[key].toPrecision(5)}`))
                queryItems.push(...strings_in_query.map(key => `${key}=${state[key]}`))
                history.replaceState({},"", "#" + queryItems.join("&"))
            }
        },

        ({ state, previousState, patch }) => {
            // Mapbox updater
            // Update Mapbox's state if it differs from state.

            const mapPos = Object.assign(map.getCenter(), { zoom: map.getZoom() })
            if (propertiesDiffer(['lng', 'lat', 'zoom'], state, mapPos)) {
                map.jumpTo({ center: [state.lng, state.lat], zoom: state.zoom })
            }

            if (propertiesDiffer(['linkVar'], state, previousState)) {
                // variableTest(state.linkVar, "links")
                linkColourTest(state.linkVar)
            }

            if (propertiesDiffer(['matVar'], state, previousState)) {
                variableTest(state.matVar, "od_matrices")
            }
        },
    ],
};

const { update, states, actions } =
    meiosisMergerino({ stream: simpleStream, merge, app });


// VIEWS

// Console view
states.map(state => console.log('state', state))


// Mapbox action callbacks
{
    function positionUpdate() {
        const cent = map.getCenter()
        actions.changePosition(cent.lng, cent.lat, map.getZoom())
    }

    map.on("moveend", positionUpdate)
    map.on("zoomend", positionUpdate)
}


// Side menu

const menumount = document.createElement('div')
document.body.appendChild(menumount)

const menuView = state => {
    const variables = state.meta.links
    render(menumount,
        m('div', {class: 'mapboxgl-ctrl'},
            m('div', {class: 'gcvt-ctrl', },
                m('label', {for: 'link_variable'}, "Links: Select variable"),
                // Ideally the initial selection would be set from state (i.e. the querystring/anchor)
                m('select', {name: 'link_variable', onchange: e => actions.setActiveScenario(e.target.value)},
                    Object.entries(variables).map(([k, v]) => m('option', {value: k}, v.name || k))
                ),
                m('br'), // TODO: use a proper theme for this
                m('label', {for: 'matrix_variable'}, "Zones: Select variable"),
                m('select', {name: 'matrix_variable', onchange: e => update({matVar: e.target.value})},
                    Object.entries(state.meta.od_matrices).map(([k, v]) => m('option', {value: k}, v.name || k))
                ),
            )
        )
    )
}

states.map(menuView)

// STYLING

// look at src/app/mb.js for more examples

// At the moment, `map` is coming from the window, but these functions should
// really take it as a parameter.
const atId = data => ['at', ['id'], ["literal", data]]
const atFid = data => ['at', ["-", ['get', 'fid'], 1], ["literal", data]]

function setOpacity() {
    const num_zones = 282
    const opacities = []
    for (let i=0; i < num_zones; i++)
        opacities.push(Math.random())

    map.setPaintProperty('links', 'fill-opacity', atFid(opacities))
}

function setColours(nums) {
    const num_zones = 282
    if (nums === undefined) {
        nums = []
        for (let i=0; i < num_zones; i++){
            nums.push(Math.random())
        }
    }
    const colours = []
    for (let i=0; i < num_zones; i++){
        colours.push(d3.scaleSequential(d3.interpolateRdYlGn)(nums[i]))
    }

    // map.setPaintProperty('zones', 'fill-opacity', atFid(opacities))
    map.setPaintProperty('zones', 'fill-color',
        ['to-color', atFid(colours)])
}

function setLinkColours(nums) {
    const colours = []
    for (let n of nums){
        colours.push(d3.scaleSequential(d3.interpolateRdYlGn)(n))
    }

    // map.setPaintProperty('zones', 'fill-opacity', atFid(opacities))
    map.setPaintProperty('links', 'line-color',
        ['to-color', atId(colours)])
}


// get data from Julia:
const getData = async endpoint => (await (await fetch("/api/" + endpoint)).json())

// Some of this should probably go in d3.scale...().domain([])
function normalise(v,bounds,boundtype="midpoint",good="smaller") {
    if (bounds && boundtype == "midpoint") {
        const tbounds = [...bounds]
        bounds[0] = tbounds[0] - tbounds[1]
        bounds[1] = tbounds[0] + tbounds[1]
    }
    let min = bounds ? bounds[0] : Math.min(...v)
    let max = bounds ? bounds[1] : Math.max(...v)
    if (good == "smaller"){
        const t = min
        min = max
        max = t
    }
    console.log(min,max) // Will eventually need to use this to update legend
    return v.map(x => {
        let e = x - min
        e = e/(max - min)
        return e
    })
}

// Percentage difference example
// setTimeout(_ => getData("data?domain=od_matrices&year=2030&variable=Total_GHG&scenario=GreenMax").then(x => setColours(normalise(x,[1,0.5],"midpoint","smaller"))),2000)
async function getMeta(){
    let links = await getData("variables/links")
    let od_matrices = await getData("variables/od_matrices")
    actions.updateScenarios({meta: {links, od_matrices}})
    actions.setActiveScenario(Object.keys(links)[0])
    return {links,od_matrices}
}
getMeta()

// Absolute difference example // abs for links not implemented yet
async function variableTest(variable="Total_GHG",domain="od_matrices"){
    // Clamp at 99.99% and 0.01% quantiles
    let bounds = await getData("stats?domain=" + domain + "&variable=" + variable + "&quantiles=0.0001,0.9999")
    // For abs diffs, we want 0 to always be the midpoint.
    const maxb = Math.abs(Math.max(...(bounds.map(Math.abs))))
    bounds = [-maxb,maxb]
    colourWithMeta(domain,variable,bounds,"absolute")
}

async function colourWithMeta(domain,variable,bounds,abs){
    const data = await getData("data?domain=" + domain + "&year=2030&variable=" + variable + "&scenario=GreenMax&percent=false")
    const meta = await getMeta()
    const dir = meta[domain][variable]["good"]
    if (domain == "od_matrices"){
        setColours(normalise(data,bounds,abs,dir))
    } else {
        setLinkColours(normalise(data,bounds,abs,dir))
    }
}

// Link examples
function linkColourTest(variable) {
    getData(`data?domain=links&year=2030&variable=${variable}&scenario=GreenMax`)
        .then(x => setLinkColours(normalise(x,[1,0.5],"midpoint","smaller")))
}

// const DEBUG = true
// if (DEBUG)
    Object.assign(window, {
        map,
        update,
        actions,
        states,
        app,
        m,

        variableTest,
        getMeta,
        getData,
        colourWithMeta,
    })
