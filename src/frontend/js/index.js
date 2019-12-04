const DEBUG = true
const log = DEBUG ? console.log : _ => undefined

import meiosisMergerino from "meiosis-setup/mergerino"
import simpleStream from "meiosis-setup/simple-stream"
import merge from "mergerino"

import mapboxgl from 'mapbox-gl'
import * as d3 from 'd3'
import {legend} from "./d3-color-legend"

import {m, render} from 'mithril'

import * as UI from 'construct-ui'

import * as turf from "@turf/turf"


// UTILITY FUNCS

const propertiesDiffer = (props, a, b) =>
    props.filter(key => a[key] !== b[key]).length !== 0

// get data from Julia:
const getData = async endpoint => (await fetch("/api/" + endpoint)).json()

// d3 really doesn't offer a sane way to pick these.
// Supported list: https://github.com/d3/d3-scale-chromatic/blob/master/src/index.js
const divergingPalette = _ => d3.interpolateRdYlGn
const continuousPalette = scheme => scheme ? d3[`interpolate${scheme}`] : d3.interpolateViridis
const categoricalPalette = scheme => scheme ? d3[`scheme${scheme}`] : d3.schemeTableau10

// These were guessed by comparing TEN-T Rail only with TEN-T road and rail
const LTYPE_LOOKUP = [
    "Inland waterway",
    "Maritime",
    "Rail",
    "Road",
]


// INITIAL STATE

const DEFAULTS = {
    lng: 33,
    lat: 48,
    zoom: 4,
    meta: {
        links: {},
        od_matrices: {},
        scenarios: {},
    },
    layers: {
        links: {
            variable: "GHG_perKm",
        },
        od_matrices: {
            variable: "Total_GHG",
        },
    },
    percent: true,
    compare: true,
    scenario: "GreenMax",
    compareWith: "DoNothing",
    scenarioYear: "2025",
    compareYear: "auto",
    showctrl: true,
    mapReady: false,
    showDesc: false,
    selectedZones: [],
    zoneNames: [],
    mapUI: {
        // The locations to hover-over.
        popup: null,
        hover: null,
    }
}

function stateFromSearch(search) {
    const queryString = new URLSearchParams(search)
    let qsObj = Object.fromEntries(queryString)

    // Floats in the query string
    for (let k of ["lat","lng","zoom"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = parseFloat(qsObj[k])
        }
    }

    // Bools in the query string
    for (let k of ["percent","compare","showctrl","showDesc"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = qsObj[k] == "true"
        }
    }

    // Aliased variables
    if (qsObj.hasOwnProperty("linkVar"))
        qsObj = merge(qsObj, {
            layers: {
                links: {
                    variable: qsObj.linkVar
                }
            }
        })
    if (qsObj.hasOwnProperty("matVar"))
        qsObj = merge(qsObj, {
            layers: {
                od_matrices: {
                    variable: qsObj.matVar
                }
            }
        })

    return qsObj
}

const initial = (() => {
    const qsObj = stateFromSearch(window.location.search)
    return merge(DEFAULTS,qsObj)
})()

const mapboxInit = ({lng, lat, zoom}) => {
    mapboxgl.accessToken = 'pk.eyJ1IjoiYm92aW5lM2RvbSIsImEiOiJjazJrcjkwdHIxd2tkM2JwNTJnZzQxYjFjIn0.P0rLbO5oj5d3AwpuVqjBSw'

    const map = new mapboxgl.Map({
        container: 'map', // container id
        style: 'mapbox://styles/mapbox/light-v10', // stylesheet location
        center: [lng, lat],
        zoom: zoom,
        hash: true,
    })

    // disable map rotation using right click + drag
    map.dragRotate.disable()

    // disable map rotation using touch rotation gesture
    map.touchZoomRotate.disableRotation()

    const BASEURL = document.location.origin

    async function loadLayers() {
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
                'line-color': 'gray',
                'line-width': 1.5,
            },
        })
        map.addLayer({
            id: "centroidLines",
            type: "line",
            source: {
                type: "geojson",
                data: {
                    "type": "Feature",
                    "geometry": {
                        type: "LineString",
                        coordinates: [[0,0],[1,1]],
                    },
                    "properties": {
                        "name": "Dummy line",
                    },
                },
            },
            layout: {
                'line-cap': 'round',
                'line-join': 'round',
                visibility: 'none',
            },
            paint: {
                'line-opacity': .8,
                'line-color': 'gray',
            },
        })

        actions.getLTypes()
        await actions.getMeta()
        update({mapReady: true})
        actions.fetchLayerData("od_matrices")
        actions.fetchLayerData("links")
    }

    map.on('load', loadLayers)
    map.on('sourcedata', _ => {
        if (map.getSource('zones') && map.isSourceLoaded('zones')) {
            const a = []
            map.querySourceFeatures("zones",{sourceLayer: "zones"}).forEach(x=>{a[x.properties.fid] = x.properties.NAME})
            update({
                zoneNames: a,
            })
        }
    })

    return map
}

// Not in the state because it's it's own state-managing thing.
const map = mapboxInit(initial)


// APP

// https://github.com/foxdonut/meiosis/tree/master/helpers/setup#user-content-application
const app = {
    initial,

    Actions: update => {
        return {
            changePosition: (lng, lat, zoom) => {
                update({lng, lat, zoom})
            },
            updateScenario: (scenario, scenarioYear) => {
                update(state => {
                    scenarioYear = Number(scenarioYear)
                    const years = state.meta.scenarios[scenario]["at"] || [2030]
                    if (!years.includes(scenarioYear)){
                        scenarioYear = years[0]
                    }
                    return merge(state, {scenario, scenarioYear})
                })
                actions.fetchAllLayers()
            },
            updateBaseScenario: (scenario, scenarioYear) => {
                update(state => {
                    scenarioYear = Number(scenarioYear)
                    const years = state.meta.scenarios[scenario]["at"] || [2030]
                    if (!years.includes(scenarioYear)){
                        scenarioYear = years[0]
                    }
                    return merge(state, {compareWith: scenario, compareYear: scenarioYear})
                })
                actions.fetchAllLayers()
            },
            changeLayerVariable: (domain, variable) => {
                update({layers: { [domain]: { variable }}})
                actions.fetchLayerData(domain)
            },
            setComparisonMode: ({compare, percent}) => {
                if (compare === undefined)
                    update({percent})
                else if (percent === undefined)
                    update({compare})
                actions.fetchAllLayers()
            },
            getMeta: async () => {
                const [links, od_matrices, scenarios] =
                    await Promise.all([
                        getData("variables/links"),
                        getData("variables/od_matrices"),
                        getData("scenarios"),
                    ])

                // TODO: read default from yaml properties
                update({
                    meta: {links, od_matrices, scenarios},
                    layers: {
                        links: {
                            variable: old => old === null ? Object.keys(links)[0] : old,
                        },
                        od_matrices: {
                            variable: old => old === null ? Object.keys(od_matrices)[0] : old,
                        },
                    },
                    scenario: old => old === null ? Object.keys(scenarios)[0] : old,
                })
            },
            getLTypes: async () => update({LTypes: await getData("data?domain=links&variable=LType&comparewith=none")}),
            fetchAllLayers: () => {
                actions.fetchLayerData("links")
                actions.fetchLayerData("od_matrices")
            },
            fetchLayerData: async domain => {

                const state = states()

                const updateLayer = patch =>
                    update({
                        layers: {
                            [domain] : patch
                        }
                    })

                const variable = state.layers[domain].variable

                if (!variable) {
                    return updateLayer({
                        values: undefined,
                        bounds: undefined,
                        dir: undefined,
                        palette: undefined,
                        unit: undefined,
                    })
                }

                // Else fetch data
                const {compare, compareYear, scenario, scenarioYear: year, meta} = state
                const compareWith = compare ? state.compareWith : "none"
                const percent = compare && state.percent
                let bounds, values

                const dir = meta[domain][variable]["good"]
                const palette = getPalette(meta, domain, variable, compare)
                const unit = getUnit(meta, domain, variable, percent)

                if (domain === "od_matrices" && state.selectedZones.length !== 0) {
                    const fid = state.selectedZones[0] // Todo: support multiple zones
                    values = await getData("data?domain=od_matrices&comparewith=none&row=" + fid)
                    bounds = [ d3.quantile(values, 0.1), d3.quantile(values, 0.9) ]
                } else if (percent) {
                    values = await getData("data?domain=" + domain + "&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear)
                    bounds = [.5, 1.5]
                } else {
                    // TODO: We should probably not be defining default quantile assumptions on both server and client.
                    const qs = domain == "od_matrices" ? [0.0001,0.9999] : [0.1,0.9]

                    // Quantiles should be overridden by metadata
                    ;[bounds, values] = await Promise.all([
                        // Clamp at 99.99% and 0.01% quantiles
                        getData("stats?domain=" + domain + "&variable=" + variable + `&quantiles=${qs[0]},${qs[1]}` + "&comparewith=" + compareWith + "&compareyear=" + compareYear),
                        getData("data?domain=" + domain + "&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&percent=" + percent + "&comparewith=" + compareWith + "&compareyear=" + compareYear),
                    ])
                    if (compare) {
                        // For abs diffs, we want 0 to always be the midpoint.
                        const maxb = Math.abs(Math.max(...(bounds.map(Math.abs))))
                        bounds = [-maxb,maxb]
                    } else {
                        dir == "smaller" && bounds.reverse()
                    }
                }

                // Race warning: This can race. Don't worry about it for now.
                return updateLayer({
                    values,
                    bounds,
                    dir,
                    // In an array otherwise it gets executed by the patch func
                    palette: [palette],
                    unit,
                })
            },
        }
    },

    services: [
        // TODO: Validation service so users can't provide invalid vars?
        // We do use user input to index into objects, but not in a dangerous way.

        ({ state, previousState, patch }) => {
            // Query string updater
            // take subset of things that should be saved, pushState if any change.
            const nums_in_query = [] // These are really floats
            const strings_in_query = [ "scenario", "scenarioYear", "percent", "compare", "showctrl", "compareWith", "compareYear", "showDesc"]

            const updateQS = () => {
                const queryItems = [
                    `linkVar=${state.layers.links.variable}`,
                    `matVar=${state.layers.od_matrices.variable}`,
                    ...strings_in_query.map(key => `${key}=${state[key]}`),
                    ...nums_in_query.map(key => `${key}=${state[key].toPrecision(5)}`),
                ]
                history.replaceState({},"", "?" + queryItems.join("&"))
            }

            for (let key of nums_in_query) {
                if (state[key].toPrecision(5) !== previousState[key].toPrecision(5)) {
                    return updateQS()
                }
            }

            for (let key of strings_in_query) {
                if (state[key] !== previousState[key]) {
                    return updateQS()
                }
            }

            for (let key of Object.keys(state.layers)) {
                if (state.layers[key].variable !== previousState.layers[key].variable) {
                    return updateQS()
                }
            }
        },

        ({ state, previousState, patch }) => {
            // Mapbox updater
            // Update Mapbox's state if it differs from state.

            if (!state.mapReady) return

            for (let layer of Object.keys(state.layers)) {
                if (state.layers[layer] !== previousState.layers[layer]) {
                    paint(layer, state.layers[layer])
                }
            }

            // Centroid drawing code should go here.
            // Centroid calculation code should go in an action
        },
    ],

}

const { update, states, actions } =
    meiosisMergerino({ stream: simpleStream, merge, app })


// VIEWS

// Console view
states.map(state => log('state', state))


// Mapbox action callbacks
{
    function positionUpdate() {
        const cent = map.getCenter()
        actions.changePosition(cent.lng, cent.lat, map.getZoom())
    }

    map.on("moveend", positionUpdate)
    map.on("zoomend", positionUpdate)

    map.on('click', 'zones', async event => ((event, state) => {
        log(event)
        // const ctrlPressed = event.orignalEvent.ctrlKey // handy for selecting multiple zones
        update({
            selectedZones: [event.features[0].properties.fid], // todo: push to this instead
            compare: false,
            mapUI: {
                popup: oldpopup => {
                    if (oldpopup) {
                        oldpopup.remove()
                    }
                    const percent = false
                    const layer = state.layers.od_matrices
                    const {NAME, fid} = event.features[0].properties
                    const value =
                        numberToHuman(layer.values[fid - 1], percent) +
                            (percent ? "" : " ") +
                            layer.unit
                    return new mapboxgl.Popup({closeButton: false})
                        .setLngLat(event.lngLat)
                        .setHTML(`${NAME}<br>${value}`)
                        .addTo(map)
                },
                lines: async oldlines => {
                    // if (oldlines) {
                    //     // remove them
                    //     map.setLayoutProperty("centroidLines","visibility","none")
                    // }
                    let clines = []

                    const originPoint = turf.centroid(event.features[0].geometry)

                    // let dests = [] // Need to get this from somewhere
                    const dests = map.querySourceFeatures("zones",{sourceLayer: "zones"})

                    const data = await getData("data?domain=od_matrices&year=" + state.scenarioYear + "&variable=" + state.layers.od_matrices.variable + "&scenario=" + state.scenario + "&comparewith=" + state.compareWith + "&compareyear=" + state.compareYear + "&row=" + event.features[0].properties.fid) // Compare currently unused
                    const qs = [0.001,0.999]

                    // const bounds = await getData("stats?domain=od_matrices&variable=" + state.matVar + `&quantiles=${qs[0]},${qs[1]}` + "&comparewith=none")
                    const truncData = data.slice() // Make copy first so we don't mutate original
                        .sort().slice(-20) // Draw top 20 lines
                    const bounds = [Math.min(...truncData),Math.max(...truncData)]
                    const normedData = normalise(data,bounds) // Anything outside 0,1 is clamped by consumer
                    const threshold = normedData.slice() // Make copy first so we don't mutate original
                        .sort().slice(-20)[0] // Draw top 20 lines


                    for (let dest of dests) {
                        // if (normedData[dest.properties.fid - 1] < threshold) continue
                        const destPoint = turf.centroid(dest.geometry)
                        const getPos = x => x.geometry.coordinates

                        // Skip itself
                        if ((getPos(destPoint)[0] == getPos(originPoint)[0]) && (getPos(destPoint)[1] == getPos(originPoint)[1])) continue

                        let props = {
                            opacity: Math.pow(normedData[dest.properties.fid - 1] - 0.1,10) - 0.1, // Slightly weird heuristic but it looks nice
                            weight: Math.pow(normedData[dest.properties.fid - 1] - 0.1,2)* 5
                        }
                        if (props.weight > 10) props.weight = 10 // Some values explode and go white, further investigation needed

                        let cline = turf.greatCircle(
                            getPos(originPoint),
                            getPos(destPoint),
                            {properties: props}
                        )

                        clines.push(cline)
                    }
                    map.getSource("centroidLines").setData(turf.featureCollection(clines))
                    // map.setPaintProperty("centroidLines","line-width",["get","weight"])
                    map.setPaintProperty("centroidLines","line-opacity",["get","opacity"])
                    map.moveLayer("centroidLines")

                    map.setLayoutProperty("centroidLines","visibility","visible")
                    return clines
                }
            }
        })
    })(event,states())) // Not sure what the meiosis-y way to do this is - need to read state in this function.

    map.on('click', 'links', async event => ((event, state) => {
        update({
            mapUI: {
                popup: oldpopup => {
                    if (oldpopup) {
                        oldpopup.remove()
                    }
                    // TODO: fix so that the zone clicker doesn't shadow this
                    let id = event.features[0].id
                    let ltype = LTYPE_LOOKUP[state.LTypes[id] - 1]
                    let value = numberToHuman(state.layers.links.values[id], state.compare && state.percent) +
                        (state.compare && state.percent ? "" : " ") +
                        getUnit(state.meta,"links",state.linkVar,state.compare && state.percent)
                    return new mapboxgl.Popup({closeButton: false})
                        .setLngLat(event.lngLat)
                        .setHTML(
                            `Click!<br>
                            ID: ${id}<br>
                            Link type: ${ltype}<br>
                            ${value}`
                        )
                        .addTo(map)
                },
            }
        })
    })(event,states())) // Not sure what the meiosis-y way to do this is - need to read state in this function.

    map.on('mousemove', 'links', async event => ((event, state) => {
        update({
            mapUI: {
                hover: oldpopup => {
                    if (oldpopup) {
                        oldpopup.remove()
                    }
                    let id = event.features[0].id
                    let ltype = LTYPE_LOOKUP[state.LTypes[id] - 1]
                    let value = state.layers.links.values[id]
                    let str
                    if (value === null)
                        str = "No data"
                    else
                        str = numberToHuman(value, state.compare && state.percent) +
                            (state.compare && state.percent ? "" : " ") +
                            state.layers.links.unit
                    return new mapboxgl.Popup({closeButton: false})
                        .setLngLat(event.lngLat)
                        .setHTML(
                            `Link type: ${ltype}<br>
                            ${str}`
                        )
                        .addTo(map)
                },
            }
        })
    })(event,states())) // Not sure what the meiosis-y way to do this is - need to read state in this function.
}

function numberToHuman(number,percent=false){
    number = percent ? number * 100 : number
    return parseFloat(number.toPrecision(3)).toLocaleString()
}

// Side menu

const mountpoint = document.createElement('div')
document.body.appendChild(mountpoint)

function meta2options(metadata, selected) {
    return Object.entries(metadata)
        .filter(([k, v]) => v["use"] !== false)
        .map(([k, v]) => m('option', {value: k, selected: selected === k}, v.name || k))
}

const Legend = () => {
    let legendelem
    const drawLegend = vnode => {
        let bounds = vnode.attrs.bounds
        if (vnode.attrs.dir == "smaller") {
            bounds = [bounds[1], bounds[0]]
        }
        if (vnode.attrs.percent) {
            bounds = bounds.map(x => x * 100)
        }
        const unit = vnode.attrs.unit
        legendelem && legendelem.remove()
        legendelem = legend({
            color: d3.scaleSequential(bounds, vnode.attrs.palette[0]),
            title: vnode.attrs.title + ` (${unit})`,
        })
        vnode.dom.appendChild(legendelem)
    }
    return {
        view: vnode => {
            return m('div')
        },
        oncreate: drawLegend,
        onupdate: drawLegend,
    }
}

function getUnit(meta, domain, variable, percent=false){
    if (percent) return "%"
    try {
        if (domain == "od_matrices") {
            return meta.od_matrices[variable].unit
        } else {
            return meta.links[variable].unit
        }
    } catch (e){
        return "Arbitrary units"
    }
}


const menuView = state => {
    // let popup = state.mapUI.popup
    render(mountpoint,
        // Position relative and full height are required for positioning elements at the bottom
        // translate(0,0) is required to put it in front of mapbox.
        m('div', {style: 'pointer-events: none; height: 100vh; position: relative; transform: translate(0,0)'}, [
            // popup &&
            //         m(UI.Popover, {
            //             content: m('', popup.feature),
            //             trigger: m('div', {style: `position: absolute; left: ${popup.x}px; top: ${popup.y}px`}),
            //             isOpen: true,
            //         }),
            m('div', {style: 'position: absolute; bottom: 0'},
                m(UI.Card, {style: 'margin: 5px', fluid: true},
                    [
                        state.layers.links.bounds && m(Legend, {
                            title: 'Links',
                            percent: state.compare && state.percent,
                            ...state.layers.links
                        }),
                        state.layers.od_matrices.bounds && m(Legend, {
                            title: 'Zones',
                            percent: state.compare && state.percent,
                            ...state.layers.od_matrices
                        }),
                    ]
                )
            ),
            m('div', {class: 'mapboxgl-ctrl'},
                m('div', {class: 'gcvt-ctrl', },
                    m('label', {for: 'showctrls'}, 'Show controls: ',
                        m('input', {name: 'showctrls', type:"checkbox", checked:state.showctrl, onchange: e => update({showctrl: e.target.checked})}),
                    ),
                    state.showctrl && [
                        m('br'),

                        m('label', {for: 'scenario'}, "Scenario (help? ",
                            m('input', {name: 'showDesc', type:"checkbox", checked:state.showDesc, onchange: e => update({showDesc: e.target.checked})}),
                        " )"),
                        m('select', {
                            name: 'scenario',
                            onchange: e => actions.updateScenario(e.target.value, state.scenarioYear)
                        },
                            meta2options(state.meta.scenarios, state.scenario)
                        ),

                        state.meta.scenarios && [
                            m('label', {for: 'year'}, 'Scenario year: ' + state.scenarioYear),
                            state.meta.scenarios[state.scenario] &&
                            state.meta.scenarios[state.scenario].at.length > 1 &&
                            m('input', {
                                name: 'year',
                                type:"range",
                                ...getScenMinMaxStep(state.meta.scenarios[state.scenario]),
                                value: state.scenarioYear,
                                onchange: e =>
                                    actions.updateScenario(state.scenario, e.target.value)
                            }),
                        ],

                        m('label', {for: 'compare'}, 'Compare with base: ',
                            m('input', {
                                name: 'compare',
                                type:"checkbox",
                                checked: state.compare,
                                onchange: e => actions.setComparisonMode({compare: e.target.checked})
                            }),
                        ),

                        state.meta.scenarios && state.compare && [
                            m('br'),
                            m('label', {for: 'scenario'}, "Base scenario"),
                            m('select', {
                                name: 'scenario',
                                onchange: e =>
                                    actions.updateBaseScenario(e.target.value, state.scenarioYear, state.meta)
                            },
                                meta2options(state.meta.scenarios, state.compareWith)
                            ),

                            m('label', {for: 'basetracksactive'}, 'Base year: ' + (state.compareYear == "auto" ? state.scenarioYear : state.compareYear) + " (edit: ",
                                m('input', {name: 'basetracksactive', type:"checkbox", checked:(state.compareYear != "auto"), onchange: e => {
                                    if (!e.target.checked) {
                                        update({compareYear: "auto"})
                                    } else {
                                        update({compareYear: state.scenarioYear})
                                    }
                                }}),
                            " )"),

                            state.compareYear !== "auto" && [
                                m('br'),
                                state.meta.scenarios[state.compareWith] &&
                                (state.meta.scenarios[state.compareWith].at.length > 1) &&
                                m('input', {
                                    name: 'compyear',
                                    type: "range",
                                    ...getScenMinMaxStep(state.meta.scenarios[state.compareWith]),
                                    value: state.compareYear,
                                    onchange: e => update({compareYear: e.target.value})
                                }),
                            ],
                        ],

                        state.compare && m('label', {for: 'percent'}, 'Percentage difference: ',
                            m('input', {
                                name: 'percent',
                                type:"checkbox",
                                checked: state.percent,
                                onchange: e => actions.setComparisonMode({percent: e.target.checked}),
                            }),
                        ),

                        m('br'),
                        m('label', {for: 'link_variable'}, "Links: Select variable"),
                        m('select', {
                            name: 'link_variable',
                            onchange: e => actions.changeLayerVariable("links", e.target.value),
                        },
                            m('option', {value: '', selected: state.layers.links.variable === null}, 'None'),
                            meta2options(state.meta.links, state.layers.links.variable)
                        ),

                        m('label', {for: 'matrix_variable'}, "Zones: Select variable"),
                        m('select', {
                            name: 'matrix_variable',
                            onchange: e => actions.changeLayerVariable("od_matrices", e.target.value),
                        },
                            m('option', {value: '', selected: state.layers.od_matrices.variable === null}, 'None'),
                            meta2options(state.meta.od_matrices, state.layers.od_matrices.variable)
                        ),

                        state.selectedZones.length !== 0 && [
                            m('label', {for: 'deselect_zone'}, 'Showing absolute flows to ', state.zoneNames[state.selectedZones[0]] || 'zone ' + state.selectedZones[0], ' (deselect? ',
                                m('input', {name: 'deselect_zone', type:"checkbox", checked: state.selectedZones.length == 0, onchange: e => update({selectedZones: []})}),
                            ')'),
                        ],
                    ],
                ),
            ),

            state.showDesc && m('div', {style: 'position: absolute; top: 0'},
                m(UI.Card, {style: 'margin: 5px; padding-bottom: 0px; max-width: 60%', fluid: true},
                    [
                        state.meta.scenarios && state.meta.scenarios[state.scenario] && m('p', state.meta.scenarios[state.scenario].name + ": " + state.meta.scenarios[state.scenario].description),
                    ]
                )
            ),
        ])
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

// At the moment, `map` is global.
const atId = data => ['at', ['id'], ["literal", data]]
const atFid = data => ['at', ["-", ['get', 'fid'], 1], ["literal", data]]

function setOpacity() {
    const num_zones = 282
    const opacities = []
    for (let i=0; i < num_zones; i++)
        opacities.push(Math.random())

    map.setPaintProperty('links', 'fill-opacity', atFid(opacities))
}

function setColours(nums, palette=d3.interpolateRdYlGn) {
    const num_zones = 282
    if (nums === undefined) {
        nums = []
        for (let i=0; i < num_zones; i++){
            nums.push(Math.random())
        }
    }
    const colours = []
    for (let i=0; i < num_zones; i++){
        colours.push(d3.scaleSequential(palette)(nums[i]))
    }

    // map.setPaintProperty('zones', 'fill-opacity', atFid(opacities))
    map.setPaintProperty('zones', 'fill-color',
        ['to-color', atFid(colours)])
}

function setLinkColours(nums, palette=d3.interpolateRdYlGn) {
    const colours = []
    for (let n of nums){
        colours.push(d3.scaleSequential(palette)(n))
    }

    // map.setPaintProperty('zones', 'fill-opacity', atFid(opacities))
    map.setPaintProperty('links', 'line-color',
        ['to-color', atId(colours)])
    map.setPaintProperty('links','line-offset', ['interpolate',
        ['linear'],
        ['zoom'],
        4,0.5,
        10, 1.8
    ])
}


// Some of this should probably go in d3.scale...().domain([])
function normalise(v, bounds, good="smaller") {
    let min = bounds ? bounds[0] : Math.min(...v)
    let max = bounds ? bounds[1] : Math.max(...v)
    if (good == "smaller"){
        ;[min, max] = [max, min]
    }
    return v.map(x => {
        let e = x - min
        e = e/(max - min)
        return e
    })
}

function paint(domain, {variable, values, bounds, dir, palette}) {
    const mapLayers = {
        "od_matrices": "zones",
        "links": "links",
    }
    if (!variable) {
        map.setLayoutProperty(mapLayers[domain], "visibility", "none")
    } else {
        if (domain == "od_matrices"){
            setColours(normalise(values, bounds, dir),palette[0])
        } else {
            setLinkColours(normalise(values, bounds, dir),palette[0])
            // map.setPaintProperty('links', 'line-width',
            //     ['to-number', atId(normalise(data,bounds,abs,dir))])
        }
        map.setLayoutProperty(mapLayers[domain], "visibility", "visible")
    }
}

function getPalette(meta,domain,variable,compare){
    if (!meta[domain][variable]) return d3.interpolateRdYlGn
    const desiredPalette = continuousPalette(meta[domain][variable]["palette"] || "RdYlGn")
    if (desiredPalette === undefined) {
        console.warn(variable + " has an invalid colour scheme set in the metadata.")
        return d3.interpolateRdYlGn
    }
    return !compare ? desiredPalette : d3.interpolateRdYlGn
}

async function getDataFromId(id,domain="links"){
    const state = states()
    const variable = state.layers[domain].variable
    log("state is ", state)
    const percData = await getData("data?domain=" + domain + "&year="+ state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=true")
    const absData = await getData("data?domain=" + domain + "&year=" + state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=false")
    return {absVal: absData[id], percVal: percData[id]}
}


if (DEBUG)
    Object.assign(window, {
        map,
        update,
        actions,
        states,
        app,
        m,
        d3,
        legend,

        paint,
        getData,

        mapboxgl,

        getDataFromId,

        stateFromSearch,
        merge,
        continuousPalette,
        turf,
        LTYPE_LOOKUP
    })
