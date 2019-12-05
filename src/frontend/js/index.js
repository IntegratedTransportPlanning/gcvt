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

import * as R from "ramda"


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

// e.g. [1,2] == [2,1]
const setEqual = R.compose(R.isEmpty,R.symmetricDifference)

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
    showClines: true,
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
    for (let k of ["percent","compare","showctrl","showDesc","showClines"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = qsObj[k] == "true"
        }
    }

    // Arrays in the querty string
    for (let k of ["selectedZones"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = JSON.parse(qsObj[k])
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
                'fill-outline-color': '#000',
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
                'line-color': 'red',
            },
        })
        actions.getLTypes()
        actions.getCentres()
        await actions.getMeta()
        update({mapReady: true})
        actions.fetchAllLayers()
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
            setCompare: compare => {
                update({
                    compare,
                    centroidLineWeights: null,
                    selectedZones: [],
                })
                actions.fetchAllLayers()
            },
            setPercent: percent => {
                update({percent})
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
            getLTypes: async () => update({
                LTypes: await getData("data?domain=links&variable=LType&comparewith=none")
            }),
            getCentres: async () => update({
                zoneCentres: await getData("centroids")
            }),
            fetchAllLayers: () => {
                actions.fetchLayerData("links")
                actions.fetchLayerData("od_matrices")
            },
            toggleCentroids: showness => {
                update({showClines: showness})
            },
            clickZone: event => {
                const state = states()
                const fid = event.features[0].properties.fid
                const ctrlPressed = event.originalEvent.ctrlKey

                let selectedZones = state.selectedZones.slice()

                if (selectedZones.includes(fid)) {
                    selectedZones = ctrlPressed ? selectedZones.filter(x => x !== fid) : []
                } else {
                    selectedZones = ctrlPressed ? [...state.selectedZones, fid]: [fid]
                }

                let oldcompare
                update(
                {
                    selectedZones,
                    compare: old => {
                        oldcompare = old
                        return false
                    },
                    // Clear existing centroids
                    centroidLineWeights: null,
                })
                if (oldcompare) {
                    actions.fetchAllLayers()
                } else {
                    actions.fetchLayerData("od_matrices")
                }
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
                    values = await getData("data?domain=od_matrices&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear + "&row=" + state.selectedZones) // Compare currently unused

                    const sortedValues = sort(values)
                    bounds = [ d3.quantile(sortedValues, 0.1), d3.quantile(sortedValues, 0.9) ]

                    const centroidBounds =
                        [d3.quantile(sortedValues, 0.6), d3.quantile(sortedValues, 0.99)]
                    // Normalise and clamp
                    const centroidLineWeights = normalise(values, centroidBounds)
                        .map(x => x < 0 ? 0 : x > 1 ? 1 : x)

                    return update({
                        centroidLineWeights,
                        layers: {
                            [domain]: {
                                values,
                                bounds,
                                dir,
                                // In an array otherwise it gets executed by the patch func
                                palette: [palette],
                                unit,
                            }
                        }
                    })
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
                        const maxb = Math.max(...(bounds.map(Math.abs)))
                        bounds = [-maxb,maxb]
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
            const strings_in_query = [ "scenario", "scenarioYear", "percent", "compare", "showctrl", "compareWith", "compareYear", "showDesc","showClines"]
            const arrays_in_query = ["selectedZones"]

            const updateQS = () => {
                const queryItems = [
                    `linkVar=${state.layers.links.variable}`,
                    `matVar=${state.layers.od_matrices.variable}`,
                    ...strings_in_query.map(key => `${key}=${state[key]}`),
                    ...nums_in_query.map(key => `${key}=${state[key].toPrecision(5)}`),
                    ...arrays_in_query.map(k => `${k}=${JSON.stringify(state[k])}`),
                ]
                history.replaceState({},"", "?" + queryItems.join("&"))
            }

            for (let key of nums_in_query) {
                if (state[key].toPrecision(5) !== previousState[key].toPrecision(5)) {
                    return updateQS()
                }
            }

            for (let key of arrays_in_query) {
                if (!setEqual(state[key], previousState[key])) {
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

            // Race: if we get layer data before the map is ready, we won't draw it.
            // Will probably never happen.

            for (let layer of Object.keys(state.layers)) {
                if (state.layers[layer] !== previousState.layers[layer]) {
                    paint(layer, state.layers[layer])
                }
            }

            if (state.layers.od_matrices !== previousState.layers.od_matrices ||
                state.centroidLineWeights !== previousState.centroidLineWeights ||
                state.showClines !== previousState.showClines) {
                if (!state.layers.od_matrices.variable || !state.centroidLineWeights || !state.showClines) {
                    hideCentroids()
                } else {
                    paintCentroids(state)
                }
            }
        },
    ],

}

const { update, states, actions } =
    meiosisMergerino({ stream: simpleStream, merge, app })


// VIEWS


// Mapbox action callbacks
{
    function positionUpdate() {
        const cent = map.getCenter()
        actions.changePosition(cent.lng, cent.lat, map.getZoom())
    }

    map.on("moveend", positionUpdate)
    map.on("zoomend", positionUpdate)

    map.on('click', 'zones', actions.clickZone)

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
                    let str = ""
                    let value = state.layers.links.values[id]
                    if (value === null)
                        str = "No data"
                    else
                        str = numberToHuman(value, state.compare && state.percent) +
                            (state.compare && state.percent ? "" : " ") +
                            getUnit(state.meta,"links",state.linkVar,state.compare && state.percent)
                    return new mapboxgl.Popup({closeButton: false})
                        .setLngLat(event.lngLat)
                        .setHTML(
                            `ID: ${id}<br>
                            Link type: ${ltype}<br>
                            ${str}`
                        )
                        .addTo(map)
                },
            }
        })
    })(event,states())) // Not sure what the meiosis-y way to do this is - need to read state in this function.

    map.on('mousemove', 'zones', event => {
        update(state => {
            const percent = false
            const layer = state.layers.od_matrices
            const {NAME, fid} = event.features[0].properties
            const value =
                numberToHuman(layer.values[fid - 1], percent) +
                (percent ? "" : " ") +
                layer.unit

            return merge(state, {
                    mapUI: {
                        hover: oldhover => {
                            if (oldhover) {
                                oldhover.remove()
                            }
                            return new mapboxgl.Popup({closeButton: false})
                                .setLngLat(event.lngLat)
                                .setHTML(`${NAME}<br>${value}`)
                                .addTo(map)
                                .trackPointer()
                        },
                    }
            })
        })
    })

    map.on('mouseleave', 'zones', event => {
        const hover = states().mapUI.hover
        hover && hover.remove()
    })

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

/*
 * Rtn a sorted array. `by` defaults to something sensible
 * for strings and numbers.
 */
function sort(arr, by) {
    // Make a copy of an array (or make an array from something else)
    arr = Array.from(arr)
    if (by === undefined)
        by = (a, b) => a > b ? 1 : -1
    return arr.sort(by)
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
                                onchange: e => actions.setCompare(e.target.checked),
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
                                onchange: e => actions.setPercent(e.target.checked),
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
                            m('label', {for: 'deselect_zone'}, 'Showing absolute flows to ', arrayToHumanList(state.selectedZones.map(id => zoneToHuman(id,state))), ' (deselect? ',
                                m('input', {
                                    name: 'deselect_zone',
                                    type:"checkbox",
                                    checked: state.selectedZones.length == 0,
                                    onchange: e => {
                                        update({
                                            selectedZones: [],
                                            centroidLineWeights: null,
                                        })
                                        actions.fetchLayerData("od_matrices")
                                    }}),
                            ')'),
                            m('label', {for: 'show_clines'}, 'Flow lines: ',
                                m('input', {name: 'show_clines', type:"checkbox", checked: state.showClines, onchange: e => actions.toggleCentroids(e.target.checked)}),
                            ),
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

function zoneToHuman(zoneID,state) {
    return state.zoneNames[zoneID] || 'zone ' + zoneID
}

function arrayToHumanList(array){
    if (array.length == 1) return array
    else if (array.length == 0) return ""
    return array.slice(0,-1).reduce((l,r) => `${l}, ${r}`) + ` and ${array.slice(-1)}`
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
function normalise(v, bounds, good) {
    let min = bounds ? bounds[0] : Math.min(...v)
    let max = bounds ? bounds[1] : Math.max(...v)
    if (good == "smaller"){
        ;[min, max] = [max, min]
    }
    return v.map(x => {
        const d = max - min
        if (d == 0) {
            // TODO: Missing data problems.
            return 0
        } else {
            return (x - min) / d
        }
    })
}

function hideCentroids() {
    map.setLayoutProperty("centroidLines","visibility","none")
}

function paintCentroids({zoneCentres, selectedZones, centroidLineWeights}) {
    const id = selectedZones[0] - 1
    const originPoints = selectedZones.map(x => turf.point(zoneCentres[x-1])) // Todo: draw a small circle on each
    const originPoint = turf.centroid(turf.featureCollection(originPoints))
    // const originPoint = turf.point(zoneCentres[id])
    const weights = centroidLineWeights

    const centroidLines = []
    zoneCentres.forEach((dest, index) => {
        const destPoint = turf.point(dest)
        const getPos = x => x.geometry.coordinates

        let props = {
            opacity: weights[index],
            weight: 2.5 * weights[index],
        }
        if (props.weight > 10) props.weight = 10

        let cline = turf.greatCircle(
            getPos(originPoint),
            getPos(destPoint),
            {properties: props}
        )

        centroidLines.push(cline)
    })

    // Draw little circles on selected zones
    // This should really be another layer but I'm feeling lazy
    selectedZones.length > 1 && originPoints.forEach(origin => {
        centroidLines.push(turf.circle(
            origin,
            10,
            {
                properties: {
                    weight: 2,
                    opacity: 1,
                },
            },
        ))
    })

    map.getSource("centroidLines").setData(turf.featureCollection(centroidLines))
    map.setPaintProperty("centroidLines", "line-width", ["get", "weight"])
    map.setPaintProperty("centroidLines", "line-opacity", ["get", "opacity"])
    map.moveLayer("centroidLines")
    map.setLayoutProperty("centroidLines", "visibility", "visible")
}

function paint(domain, {variable, values, bounds, dir, palette}) {
    const mapLayers = {
        "od_matrices": "zones",
        "links": "links",
    }
    if (!variable || !values) {
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
        normalise,
        LTYPE_LOOKUP,
        R,
        setEqual
    })
