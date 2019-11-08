import meiosisMergerino from "meiosis-setup/mergerino";
import simpleStream from "meiosis-setup/simple-stream";
import merge from "mergerino";

import mapboxgl from 'mapbox-gl';
import * as d3 from 'd3';

import {m, render} from 'mithril'


// UTILITY FUNCS

const propertiesDiffer = (props, a, b) =>
    props.filter(key => a[key] !== b[key]).length !== 0

// get data from Julia:
const getData = async endpoint => (await (await fetch("/api/" + endpoint)).json())


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
            scenarios: {},
        },
        linkVar: queryString.get("linkVar") || "VCR",
        matVar: queryString.get("matVar") || "Pax",
        lBounds: [0,1],
        mBounds: [0,1],
        percent: queryString.get("linkVar") || true,
        scenario: queryString.get("scenario") || "GreenMax",
        scenarioYear: queryString.get("scenarioYear") || "2025",
    }
})()

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
                visibility: 'none'
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
                visibility: 'none',
            },
            paint: {
                'line-opacity': .8,
                'line-color': 'blue',
            },
        })
        actions.getMeta().then(async () => {
            const state = states()
            Promise.all([
                colourMap(state.meta, 'od_matrices', state.matVar, state.scenario, state.percent, state.scenarioYear),
                colourMap(state.meta, 'links', state.linkVar, state.scenario, state.percent, state.scenarioYear),
            ]).finally(() => {
                map.setLayoutProperty('links', 'visibility', 'visible')
                map.setLayoutProperty('zones', 'visibility', 'visible')
            })
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
            updateScenario: (scenario, scenarioYear, meta) => {
                const years = meta.scenarios[scenario]["at"] || ["2030"]
                if (!years.includes(scenarioYear)){
                    scenarioYear = years[0]
                }
                update({scenario, scenarioYear})
            },
            setActiveScenario: v => {
                update({linkVar: v})
            },
            getMeta: async () => {
                const links = await getData("variables/links")
                const od_matrices = await getData("variables/od_matrices")
                const scenarios = await getData("scenarios")

                // TODO: read default from yaml properties
                update({
                    meta: {links, od_matrices, scenarios},
                    linkVar: old => old === null ? Object.keys(links)[0] : old,
                    matVar: old => old === null ? Object.keys(od_matrices)[0] : old,
                    scenario: old => old === null ? Object.keys(scenarios)[0] : old,
                })
            },
            updateLegend: (bounds, type) => {
                if (type == "link") {
                    update({lBounds: bounds})
                }
                else if (type == "matrix") {
                    update({mBounds: bounds})
                }
            },
        }
    },

    services: [
        ({ state, previousState, patch }) => {
            // Query string updater
            // take subset of things that should be saved, pushState if any change.
            const nums_in_query = [ "lng", "lat", "zoom" ] // These are really floats
            const strings_in_query = [ "linkVar", "matVar", "scenario", "scenarioYear", "percent"]
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

            if (state.scenario && propertiesDiffer(['scenario','percent','scenarioYear'], state, previousState)) {
                colourMap(state.meta, 'od_matrices', state.matVar, state.scenario, state.percent, state.scenarioYear)
                colourMap(state.meta, 'links', state.linkVar, state.scenario, state.percent, state.scenarioYear)
            }

            if (state.linkVar && propertiesDiffer(['linkVar'], state, previousState)) {
                colourMap(state.meta, 'links', state.linkVar, state.scenario, state.percent, state.scenarioYear)
            }

            if (state.matVar && propertiesDiffer(['matVar'], state, previousState)) {
                colourMap(state.meta, 'od_matrices', state.matVar, state.scenario, state.percent, state.scenarioYear)
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

function meta2options(metadata, selected) {
    return Object.entries(metadata)
        .filter(([k, v]) => v["use"] !== false)
        .map(([k, v]) => m('option', {value: k, selected: selected === k}, v.name || k))
}

const menuView = state => {
    render(menumount,
        m('div', {class: 'mapboxgl-ctrl'},
            m('div', {class: 'gcvt-ctrl', },
                m('label', {for: 'scenario'}, "Scenario"),
                // Ideally the initial selection would be set from state (i.e. the querystring/anchor)
                m('select', {name: 'scenario', onchange: e => actions.updateScenario(e.target.value, state.scenarioYear, state.meta)},
                    meta2options(state.meta.scenarios, state.scenario)
                ),
                // This slider currently resets its position back to the beginning on release
                m('label', {for: 'year'}, 'Scenario year'),
                m('input', {name: 'year', type:"range", ...getScenMinMaxStep(state.meta.scenarios[state.scenario]), value:state.scenarioYear, onchange: e => update({scenarioYear: e.target.value})}),
                m('label', {for: 'link_variable'}, "Links: Select variable"),
                m('select', {name: 'link_variable', onchange: e => update({linkVar: e.target.value})},
                    meta2options(state.meta.links, state.linkVar)
                ),
                m('p', 'Bounds: ' + JSON.stringify(state.lBounds)),
                m('label', {for: 'percent'}, 'Percentage difference'),
                m('input', {name: 'percent', type:"checkbox", checked:state.percent, onchange: e => update({percent: e.target.checked})}),
                m('label', {for: 'matrix_variable'}, "Zones: Select variable"),
                m('select', {name: 'matrix_variable', onchange: e => update({matVar: e.target.value})},
                    meta2options(state.meta.od_matrices, state.matVar)
                ),
                m('p', 'Bounds: ' + JSON.stringify(state.mBounds)),
            )
        )
    )
}

function getScenMinMaxStep(scenario){
    const min = scenario ? Math.min(...scenario.at) : 2020
    const max = scenario ? Math.max(...scenario.at) : 2030
    const step = scenario ? (max - min) / (scenario.at.length - 1) : 5
    return {min, max, step}
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
    return v.map(x => {
        let e = x - min
        e = e/(max - min)
        return e
    })
}

async function colourMap(meta, domain, variable, scenario, percent, year) {
    let bounds, abs, data

    if (percent) {
        data = await getData("data?domain=" + domain + "&year=" + year + "&variable=" + variable + "&scenario=" + scenario)
        bounds = [1, 0.5]
        abs = 'midpoint'
    } else {
        const qs = domain == "od_matrices" ? [0.0001,0.9999] : [0.1,0.9]
        ;[bounds, data] = await Promise.all([
            // Clamp at 99.99% and 0.01% quantiles
            getData("stats?domain=" + domain + "&variable=" + variable + `&quantiles=${qs[0]},${qs[1]}`),
            getData("data?domain=" + domain + "&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&percent=" + percent),
        ])
        // For abs diffs, we want 0 to always be the midpoint.
        const maxb = Math.abs(Math.max(...(bounds.map(Math.abs))))
        bounds = [-maxb,maxb]
        abs = 'absolute'
    }

    const dir = meta[domain][variable]["good"]

    if (domain == "od_matrices"){
        actions.updateLegend(bounds,"matrix")
        setColours(normalise(data, bounds, abs, dir))
    } else {
        actions.updateLegend(bounds,"link")
        setLinkColours(normalise(data, bounds, abs, dir))
    }
}

async function getDataFromId(id,domain="links"){
    const state = states()
    const variable = domain == "links" ? state.linkVar : state.matVar
    console.log("state is ", state)
    const percData = await getData("data?domain=" + domain + "&year="+ state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=true")
    const absData = await getData("data?domain=" + domain + "&year=" + state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=false")
    return {absVal: absData[id], percVal: percData[id]}
}

window.getDataFromId = getDataFromId

const DEBUG = true
if (DEBUG)
    Object.assign(window, {
        map,
        update,
        actions,
        states,
        app,
        m,

        colourMap,
        getData,
    })
