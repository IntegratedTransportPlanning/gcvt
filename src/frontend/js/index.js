/*
 * This file describes the frontend for the tool.
 *
 * We've tried to build it following the functional-reactive programming style
 * that Elm popularised, but this is compromised slightly by how we interact
 * with mapboxgl, which continues to manage its own state.
 *
 * Notably, the popups that appear on hover and on click are mostly managed by
 * mapboxgl, which causes some minor problems.
 *
 * Perhaps we should have wrapped mapboxgl, as has been done for React, but I
 * think that this has come out OK.
 *
 * Actions fetch a bunch of information from the API at runtime:
 *
 *  - Scenario and variable metadata (names, years, pretty names, descriptions, etc)
 *  - Arrays of numbers for the value of the variable for each link or zone
 *  - Suitable quantiles for a given variable
 *  - Centroids for each zone
 *  - and so on
 *
 * This information feeds into the `state` of the app, which is then used to
 * update the "views": the map and our own HTML elements (the menu, legend,
 * chart, and help box).
 *
 * These views register callbacks that can modify the state, which will of
 * course cause the views to be updated.
 *
 * To avoid turning into spaghetti, it's probably useful to keep that flow:
 * There is a state, from which views are rendered, and callbacks on the views
 * can update the state.
 *
 * The state should only ever be mutated through the update() function or one
 * of the actions.blah methods (which all call update internally).
 *
 */

// Need to check if there's a location before Mapbox sets it
const INITIAL_HASH = window.location.hash

const DEBUG = true
const log = DEBUG ? console.log : _ => undefined
const ZONE_OPACITY = 0.5

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

// import ITPLOGO from "../../resources/itp.png"
import ARROWHEAD from "../../resources/arrowhead.png"


// UTILITY FUNCS

const propertiesDiffer = (props, a, b) =>
    props.filter(key => a[key] !== b[key]).length !== 0

// Error function - broadly linear in -1 <= x <= 1, which accounts for the central
// 85% of the range of (-1,1) all abs(x) > 1 are mapped to the remaining 15%.
// Adapted from picomath, https://hewgill.com/picomath/index.html
function erf(x) {
    // constants
    const a1 =  0.254829592
    const a2 = -0.284496736
    const a3 =  1.421413741
    const a4 = -1.453152027
    const a5 =  1.061405429
    const p  =  0.3275911

    // Save the sign of x
    let sign = 1
    if (x < 0) sign = -1
    x = Math.abs(x)

    // A&S formula 7.1.26
    const t = 1.0/(1.0 + p*x)
    const y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1)*t*Math.exp(-x*x)

    return sign*y
}

// Error function with range of [0,1] and domain mostly [0,1] (85% of range from those inputs)
// Essentially: maps any number between 0,1 to 0.08,0.92 in a fairly linear fashion
// Any number outside that range (i.e. those denoted outliers by normalise) will fall in 0,0.08 and 0.92,1
const nerf = x => (1+erf(x*2-1))/2

// get data from Julia:
const getData = async endpoint =>
    (await fetch(
        "../api/" + endpoint + (endpoint.includes("?") ? "&" : "?") + "v=" + await API_VERSION_PROMISE)
    ).json().catch(
        e => console.error(`Error getting data from:\n/api/${endpoint}\n\n`, e)
    )

async function getApiVersion() {
    try {
        return (await (await fetch("../api/version")).json())["version"]
    } catch (e) {
        console.error(`Error getting data from:\n../api/version\n\n`, e)
    }
}

const API_VERSION_PROMISE = getApiVersion()

// d3 really doesn't offer a sane way to pick these.
// Supported list: https://github.com/d3/d3-scale-chromatic/blob/master/src/index.js
const divergingPalette = _ => d3.interpolateRdYlGn
const continuousPalette = scheme => scheme ? d3[`interpolate${scheme}`] : d3.interpolateViridis
const categoricalPalette = scheme => scheme ? d3[`scheme${scheme}`] : d3.schemeTableau10

// e.g. [1,2] == [2,1]
const setEqual = R.compose(R.isEmpty,R.symmetricDifference)

/*
 * A number formatted for easy human comprehension, given the context it comes from
 */
function numberToHuman(number,{percent, compare}) {
    let format = ",.3~s"
    if (percent && compare) {
        number = number * 100
        format = ",.3r"
    }
    const strnum = d3.format(format)(number)
    return ((number >= 0 && compare) ? "+" : "") + strnum
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

/*
 * Calculate average and total values per zone for the selected scenario and variable
 *
 * If one or more zones is selected, show statistics for flows into those zones only.
 */
function zones2summary(summariser, state) {
    return R.pipe(summariser,x=>numberToHuman(x, state))(
        state.selectedZones.length > 0 ?
        R.pipe(R.pickAll,R.values)(
            R.map(R.add(-1),state.selectedZones), state.data.basevalues
        ) :
        state.data.basevalues
    ) +
        (state.percent && state.compare ? "" : " ") + getUnit(state.meta, "od_matrices", state.selectedvars.dependent_variable, state.compare && state.percent)
}

// Just used for initial load
// Project-specific default comes from metadata
const DEFAULT_POSITION = {
    lng: 0,
    lat: 50,
    zoom: 2,
}

// INITIAL STATE
const DEFAULTS = {
    meta: {
        project: {},
    },
    data: {
        variable: "",
    },
    percent: true,
    compare: false,
    showctrl: true,
    mapReady: false,
    showDesc: true,
    showClines: true,
    showChart: false,
    selectedZones: [],
    zoneNames: [],
    mapUI: {
        // The locations to hover-over.
        popup: null,
        hover: null,
    },

    // New stuff here V

    // TODO: swap scenarioYear, compareYear, scenario, compareWith etc. for
    //       these objects
    // map ind. variable names to selected values
    selectedvars: {dependent_variable: null, independent_variables: {}},
    selectedbasevars: {dependent_variable: null, independent_variables: {}},
}


/*
 * Read the URL's query string and build into a schema we can merge with the app state.
 */
function stateFromSearch(search) {
    const queryString = new URLSearchParams(search)
    const qsObj = Object.fromEntries(queryString)

    // Bools in the query string
    for (let k of ["percent","compare","showctrl","showDesc","showClines","showChart"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = qsObj[k] == "true"
        }
    }

    // Arrays / objects / numbers in the query string
    for (let k of ["selectedZones", "selectedbasevars", "selectedvars"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = JSON.parse(qsObj[k])
        }
    }

    return qsObj
}


/*
 * Construct the initial app state.
 */
const initial = merge(DEFAULTS, stateFromSearch(window.location.search))

window.onunhandledrejection = (...args) => console.error("Some promise error happened: ", ...args)


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

    async function loadLayers() {

        const TILE_URL_TEMPLATE = new URL("../tiles", document.location.href) + `/zones/{z}/{x}/{y}.pbf?v=${await getApiVersion()}`

        map.addLayer({
            id: 'zones',
            type: 'fill',
            source: {
                type: 'vector',
                tiles: [TILE_URL_TEMPLATE],
                // If you don't have this, mapbox doesn't show tiles beyond the
                // zoom level of the tiles, which is not what we want.
                maxzoom: 6,
            },
            "source-layer": "zones",
            paint: {
                'fill-color': 'grey',
                'fill-outline-color': '#000',
                'fill-opacity': ZONE_OPACITY,
            },
            layout: {
                visibility: 'none'
            }
        })

        map.addLayer({
            id: 'zoneBorders',
            type: 'line',
            source: {
                type: 'vector',
                tiles: [TILE_URL_TEMPLATE],
                // If you don't have this, mapbox doesn't show tiles beyond the
                // zoom level of the tiles, which is not what we want.
                maxzoom: 6,
            },
            "source-layer": "zones",
            paint: {
                'line-color': 'red',
                'line-width': 2,
            },
            layout: {
                visibility: 'none'
            }
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
        })

        map.addLayer({
            id: "zoneHalos",
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
        })

        map.loadImage(ARROWHEAD, (error, image) => {
            if (error) return
            map.addImage('arrowhead', image)
            map.addLayer({
                id: "flow_arrowheads",
                type: "symbol",
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
                    "symbol-placement": "line",
                    "symbol-spacing": 100,
                    "icon-allow-overlap": true,
                    "icon-image": "arrowhead",
                    "icon-size": 1,
                    "icon-rotate": 270, // 50% chance this is right. Switch to 90 if not
                    "visibility": "none",
                },
            })
        })

        actions.getCentres().catch(e => console.error("Failed to get centroids?", e))
        await actions.getMeta()
        update({mapReady: true})
        actions.fetchZonesData()
    }

    map.on('load', loadLayers)
    map.on('sourcedata', () => {
        // Get the names of each zone from the geometry. Probably this should
        // be in the scenario pack and provided by the api instead.
        if (map.getSource('zones') && map.isSourceLoaded('zones')) {
            const a = []
            map.querySourceFeatures("zones",{sourceLayer: "zones"}).forEach(x=>{a[x.properties.CORRIDOR_FEATID] = x.properties.CORRIDOR_FEATNAME})
            update({
                zoneNames: a,
            })
        }
    })

    return map
}

// Not in the state because it's its own state-managing thing.
const map = mapboxInit(merge(DEFAULT_POSITION, initial))


// APP

// https://github.com/foxdonut/meiosis/tree/master/helpers/setup#user-content-application
const app = {
    initial,

    Actions: update => {
        return {
            setCompare: compare => {
                update({
                    compare,
                    centroidLineWeights: null,
                    selectedZones: [],
                })
                actions.fetchZonesData()
            },
            setPercent: percent => {
                update({percent})
                actions.fetchZonesData()
            },
            getMeta: async () => {
                const allmeta = await getData("meta")

                const independent_variables = Object.fromEntries(allmeta.independent_variables.map(iv => [iv.id, null]))

                const selectedbasevars = merge({dependent_variable: null, independent_variables}, allmeta.project.defaults)
                const selectedvars = selectedbasevars

                // TODO: split setting from defaults away from getting metadata
                update({
                    meta: allmeta,
                    selectedvars: initial.selectedvars ?? selectedvars,
                    selectedbasevars: initial.selectedbasevars ?? selectedbasevars,
                })


                // Set map to the project default location
                // This should _really_ go somewhere else
                if (INITIAL_HASH === "")  {
                    try {
                        const lat = allmeta["project"]["map_origin"]["lat"]
                        const lng = allmeta["project"]["map_origin"]["lon"]
                        const zoom = allmeta["project"]["map_origin"]["zoom"]

                        map.flyTo({center: [lng, lat], zoom})
                    } catch (e) {
                        console.info("Warning: default location could not be read from metadata")
                    }
                }
            },
            getCentres: async () => update({
                zoneCentres: await getData("centroids")
            }),
            fetchZonesData: async () => {
                const domain = "od_matrices"
                const state = states()

                const updateLayer = patch =>
                    update({
                        data: patch,
                    })

                const variable = state?.selectedvars?.dependent_variable

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
                const {compare, meta} = state
                const base = state?.selectedbasevars?.independent_variables

                // TODO: Stop hard coding these two independent variables
                // We need to iterate over all of them
                // I feel like these four lines aren't used but when I delete them everything breaks
                const compareYear = base.year
                const compareWith = compare ? base.scenario : "none"
                base.scenario  = compare ? base.scenario : "none" 
                const {scenario, year} = base

                const percent = compare && state.percent
                let bounds, values, basevalues

                const dir = state?.meta?.dependent_variables?.find(v => v.id == variable).bigger_is_better

                const unit = getUnit(meta, domain, variable, percent)

                const var_meta = state.meta?.dependent_variables?.find(v => v.id == variable) || {bins: []}

                if (domain === "od_matrices" && state.selectedZones.length !== 0) {
                    ;[values, basevalues] = await Promise.all([
                        getData(
                            "data?domain=od_matrices&selectedvars=" + JSON.stringify(state.selectedvars) +
                            "&selectedbasevars=" + JSON.stringify(state.selectedbasevars) + 
                            "&row=" + state.selectedZones
                        ), // Compare currently unused
                        getData(
                            "data?domain=od_matrices&selectedvars=" + JSON.stringify(state.selectedvars) +
                            "&selectedbasevars=" + JSON.stringify(state.selectedbasevars)),
                    ])

                    // TODO: make bounds consistent across all scenarios (currently it makes them all look about the same!)
                    const sortedValues = sort(values)
                    bounds = [ d3.quantile(sortedValues, 0.1), d3.quantile(sortedValues, 0.99) ]

                    const centroidLineWeights = await Promise.all(state.selectedZones.map(async zone => getData("data?domain=od_matrices&selectedvars=" + JSON.stringify(state.selectedvars) + "&selectedbasevars=" + JSON.stringify(state.selectedbasevars) + "&row=" + zone))) // values, not weights any more

                    const palette = getPalette(dir, bounds, var_meta, compare, true)

                    return update({
                        centroidLineWeights,
                        data: {
                            values,
                            basevalues,
                            bounds,
                            dir,
                            // In an array otherwise it gets executed by the patch func
                            palette: [palette],
                            unit,
                        }
                    })
                } else {
                    ;[bounds, values, basevalues] = await Promise.all([
                        (state.compare || !(var_meta?.force_bounds?.length > 0)) ? getData("stats?domain=" + domain + "&selectedvars=" + JSON.stringify(state.selectedvars) + "&selectedbasevars=" + JSON.stringify(state.selectedbasevars) + "&percent=" + percent) : var_meta.force_bounds,
                        getData("data?domain=" + domain + "&selectedvars=" + JSON.stringify(state.selectedvars) + "&percent=" + percent + "&selectedbasevars=" + JSON.stringify(state.selectedbasevars)),
                        domain == "od_matrices" && getData("data?domain=od_matrices&selectedvars=" + JSON.stringify(state.selectedvars) + "&selectedbasevars=" + JSON.stringify(state.selectedbasevars)),
                    ])
                    if (compare) {
                        // For abs diffs, we want 0 to always be the midpoint.
                        // For percent diffs, we want 1 to always be the midpoint.
                        // TODO: consider non-linear scale for percent with 0 hard-coded as lower bound
                        const maxb = Math.max(...(bounds.map(Math.abs)))
                        bounds = [-maxb,maxb]
                    }
                }

                const palette = getPalette(dir, bounds, var_meta, compare)

                // Race warning: This can race. Don't worry about it for now.
                return updateLayer(R.merge({
                    values,
                    bounds,
                    dir,
                    // In an array otherwise it gets executed by the patch func
                    palette: [palette],
                    unit,
                }, basevalues ? {basevalues} : {}))
            },
            toggleCentroids: showness => {
                update({showClines: showness})
            },
            clickZone: event => {
                const state = states()
                const fid = event.features[0].properties.CORRIDOR_FEATID
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
                actions.fetchZonesData()
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

            // TODO: update this for new schema
            // (NB: now have lots of JSON objects in querystring)
            const strings_in_query = [ "percent", "compare", "showctrl", "showDesc","showClines","showMatHelp","showLinkHelp","showChart"]

            const arrays_in_query = ["selectedZones"]
            const objs_in_query = ["selectedbasevars", "selectedvars"]

            const updateQS = () => {
                const queryItems = [
                    `matVar=${state.selectedvars.dependent_variable}`,
                    ...strings_in_query.map(key => `${key}=${state[key]}`),
                    ...nums_in_query.map(key => `${key}=${state[key].toPrecision(5)}`),
                    ...[...arrays_in_query, ...objs_in_query].map(k => `${k}=${JSON.stringify(state[k])}`),
                    "z" // Fixes #132 - never end URL with a square bracket
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

            for (let key of objs_in_query) {
                if (!R.equals(state[key], previousState[key])) {
                    return updateQS()
                }
            }

            for (let key of strings_in_query) {
                if (state[key] !== previousState[key]) {
                    return updateQS()
                }
            }

            if (state.data.variable !== previousState.data.variable) {
                return updateQS()
            }
        },

        ({ state, previousState, patch }) => {
            // Mapbox updater
            // Update Mapbox's state if it differs from state.

            if (!state.mapReady) return

            // Race: if we get layer data before the map is ready, we won't draw it.
            // Will probably never happen.

            if (state.data !== previousState.data) {
                paint("od_matrices", {...state.data, variable: state.selectedvars.dependent_variable})
            }

            // probably need to compare selectedbasevars here too
            if (state.selectedvars !== previousState.selectedvars ||
                state.centroidLineWeights !== previousState.centroidLineWeights ||
                state.showClines !== previousState.showClines) {
                if (!state.selectedvars.dependent_variable || !state.centroidLineWeights || !state.showClines) {
                    hideCentroids(state)
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
map.on('click', 'zones', actions.clickZone)

map.on('mousemove', 'zones', event => {
    update(state => {
        const layer = state.data
        const {CORRIDOR_FEATNAME: NAME, CORRIDOR_FEATID: fid} = event.features[0].properties
        const value =
            numberToHuman(layer.values[fid - 1], state) +
            (state.compare && state.percent ? "" : " ") +
            (layer.unit || "")

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


// HTML Views

// Create an array of `option` objects for use in a `UI.Select` element.
function meta2options(metadata) {
    return Object.entries(metadata)
        .filter(([k, v]) => v["use"] !== false)
        .map(([k, v]) => { return { value: k, label: v.name || k } })
}

// Want to work out how to replicate this
// Should _probably_ offload it to Julia? Don't want to care about files/columns here
//
// So want a set of valid combinations of dependent variables (always 1: it's the colour on the map) and IVs
// then hold dependent value & all but one IV fixed and see what other IVs fixed
function scenarios_with(meta, variable) {
    const v = meta.od_matrices[variable]
    if (v === undefined)
        return {}
    else
        return R.pickBy((_, key) => R.contains(key, v.scenarios_with), meta.scenarios)
}

const Legend = () => {
    let legendelem
    const drawLegend = vnode => {
        let palette = vnode.attrs.palette[0]
        if (vnode.attrs.percent) {
            palette = palette.copy()
            palette.domain(palette.domain().map(x => x * 100))
        }
        // Format numbers to 3sf with SI prefixes.
        let tickFormat = ",.3~s"
        if (palette.invertExtent) {
            // Unless the palette is discrete, then don't use SI prefixes
            tickFormat = ",.3~r"
        }
        const unit = vnode.attrs.unit
        legendelem && legendelem.remove()
        legendelem = legend({
            color: palette,
            title: vnode.attrs.title + (unit ? ` (${unit})` : ""),
            tickFormat,
        })
        legendelem.classList.add("colourbar")
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
            throw new Error("unreachable")
        }
    } catch (e){
        return "units"
    }
}


const mountpoint = document.createElement('div')
document.body.appendChild(mountpoint)

// MENU FUNCTIONS

const variableSelector = state => {
    const options = [{
        label: 'None',
        value: '',
    }].concat(meta2options(Object.fromEntries(state?.meta?.dependent_variables?.map(o => [o.id, o]) || [])))

    return [
        m('label', { for: 'matrix_variable', class: 'header' }, 'Variable'),
        m('div[style=display:flex;align-items:center]', [
            m(UI.Select, {
                name: 'matrix_variable',
                fluid: true,
                options: options,
                value: state.selectedvars.dependent_variable,
                onchange: e => {
                    update({selectedvars: merge(state.selectedvars, {dependent_variable: e.currentTarget.value})})
                    actions.fetchZonesData()
                },
            }),
            // (state.selectedvars.dependent_variable !== "") && [
            //     " ",
            //     m(UI.Button, {
            //         name: 'showChart',
            //         iconLeft: UI.Icons.BAR_CHART_2,
            //         active: state.showChart,
            //         compact: true,
            //         size: "xs",
            //         style: "margin: 0.5em;",
            //         onclick: e => {
            //             e.target.active = !e.target.active;
            //             return update({showChart: e.target.active})
            //         }
            //     }),
            // ],
        ]),
    ]
}

function getDescriptions(state) {
    const depDesc = getDescription(state.selectedvars.dependent_variable, state.meta.dependent_variables)
    const indDescs = Object.entries(state.selectedvars.independent_variables).map(
        varandval => getDescription(
            varandval[1],
            state.meta.independent_variables?.find(x=>x.id == varandval[0]).values
        )
    )
    return [depDesc, ...indDescs]
}

function getDescription(varname, meta) {
    // TODO: use pretty names if they exist
    const desc = meta?.find(el=>typeof(el) == "object" && el.name == varname)?.description
    if (desc === undefined) return desc
    return m('p', m('b', varname), ": " + desc)
}

async function ivSelectors(state, opts = {base: false}) {
    // Dumb graceful failure
    // TODO: make less dumb
    try {
        return Promise.all(state.meta?.independent_variables?.map(v => ivSelector(state, v.id, opts)) || [])
    } catch(e) {
        console.error(e)
        return []
    }
}

const ivSelector = async (state, id, opts = {base: false}) => {
    // Dumb graceful failure
    // TODO: make less dumb
    try {
        const ivs = state?.meta?.independent_variables
        const base = opts.base ? "selectedbasevars" : "selectedvars"
        const iv = ivs.find(v=>v.id == id)
        const otherIndVars = R.pickBy((val, key) => key !== id, state[base].independent_variables)

        // This makes a vast number of requests as you move the cursor around the map
        const valid = await getDomain(state.selectedvars.dependent_variable, otherIndVars, iv["id"])

        return [
            m('label', { for: iv["id"], class: 'header' }, iv["name"] || iv["id"]),
            m(UI.Select, {
                name: iv["id"],
                fluid: true,

                // Once you select an option it then
                // switches and displays the wrong one
                //
                // :/

                // TODO: improve formatting
                //
                //       whole page needs to be rewritten to allow for "invalid" choices to be displayed nicely
                //       (if invalid can't be selected you can't "tunnel" between distant parts of the domain)
                options: iv["values"].map(o => { 
                    o = typeof(o) == "object" ? o : {id: o, name: o}
                    return {id: o.id, value: o.id, label: (valid.includes(o.id) ? "" : "Unavailable: ") + (o.name ?? o.id), style: (valid.includes(o.id) ? "" : "background:lightgrey;")}
                }),
                
                // TODO: investigate why this doesn't get set on initial map load
                value: state[base]["independent_variables"][iv["id"]],
                onchange: e => {

                    // Not sure I like this
                    // Convert the label to a number if the metadata tells us to
                    const value = iv.type == "numerical" ? Number(e.currentTarget.value) : e.currentTarget.value

                    const newSelection = merge(state[base], {independent_variables:{[iv["id"]]: value}})
                    update({[base]: newSelection})
                    actions.fetchZonesData()
                },
            }),
        ]
    } catch(e) {
        console.error(e)
        return []
    }
}

// This gets called an awful lot, so let's cache it
const DOMAIN_CACHE = new Map();
async function getDomain(dependent_variable, independent_variables = {}, pick = "") {
    const mapkey = JSON.stringify([dependent_variable, independent_variables, pick])
    if (!(DOMAIN_CACHE.has(mapkey))) {
        const domain = await getData(`domain?dependent_variable=${dependent_variable}&independent_variables=${JSON.stringify(independent_variables)}`)
        DOMAIN_CACHE.set(mapkey, pick == "" ? domain : domain.map(o=>o[pick])) 
    }
    return DOMAIN_CACHE.get(mapkey)
}

const flowLineControls = state => {
    return [
        state.selectedvars.dependent_variable !== "" && state.selectedZones.length == 0 && [m('br'), m('p', "(Click a zone to see outgoing flows)")],

        state.selectedZones.length !== 0 && [
            m('div', { class: 'flowlistholder' },
                m('span', { class: 'header' }, 'Showing absolute flows for:'),
                m('ul', state.selectedZones.map(id => m('li',
                    m(UI.Button, {
                        label: zoneToHuman(id,state),
                        size: 'xs',
                        fluid: true,
                        align: 'left',
                        basic: true,
                        iconLeft: UI.Icons.X,
                        onclick: e => {
                            update({
                                selectedZones: state.selectedZones.filter(x => x != id),
                                centroidLineWeights: null,
                            })
                            actions.fetchZonesData()
                        },
                    }),
                )))
            ),
            m('div',
                m(UI.Button, {
                    label: 'Toggle Flow Lines',
                    fluid: true,
                    align: 'left',
                    outlined: true,
                    onclick: e => {
                        actions.toggleCentroids(!state.showClines)
                    },
                }),
                m(UI.Button, {
                    label: 'Deselect All',
                    fluid: true,
                    align: 'left',
                    outlined: true,
                    onclick: e => {
                        update({
                            selectedZones: [],
                            centroidLineWeights: null,
                        })
                        actions.fetchZonesData()
                    },
                }),
            ),
        ],
    ]
}

const menuView = async state => {
    // let popup = state.mapUI.popup
    render(mountpoint,
        // Position relative and full height are required for positioning elements at the bottom
        // translate(0,0) is required to put it in front of mapbox.
        m('div', {style: 'pointer-events: none; height: 100vh; position: relative; transform: translate(0,0)'}, [

            // TODO: un-nuke this
            //          presumably for an internal tool this matters much less
            // Sponsor logos. Most important stuff first.
            // We create an invisible div the size of the screen, rotate it upside down, then float a smaller div left.
            // That puts us in the bottom right corner. There are other ways to do this, but this works.
            // m('div', {style: 'height: 100vh; width: 100%; position: absolute; transform: rotate(180deg)'},
            //     m('div', {style: 'float: left; transform: rotate(180deg); margin: 5px'},
            //         m(UI.Card, {style: 'pointer-events: auto', fluid: true},
            //             [
            //                 m('a', {href: "https://www.itpworld.net", target: "_blank"},
            //                     m('img', {src: ITPLOGO, width: 60, style: 'margin-right: 5px'})
            //                 ),
            //                 m('a', {href: "https://www.worldbank.org", target: "_blank"},
            //                     m('img', {src: WBLOGO, height: 60, style: 'padding: 8px; margin-right: 5px'})
            //                 ),
            //                 m('a', {href: "http://www.kgreengrowthpartnership.org/", target: "_blank"},
            //                     m('img', {src: KGFLOGO, height: 60})
            //                 ),
            //             ]
            //         )
            //     ),
            // ),

            // Legend
            state.data.bounds &&
            m('div', {style: 'position: absolute; bottom: 0'},
                m(UI.Card, {style: 'margin: 5px', fluid: true},
                    [
                        m(Legend, {
                            title: state.selectedvars.dependent_variable,
                            percent: state.compare && state.percent,
                            ...state.data,
                        }),
                    ]
                )
            ),

            // Main menu panel
            m('div', {class: 'mapboxgl-ctrl'},
                m('div', {class: 'gcvt-ctrl', },
                    m(UI.Button, {
                        label: 'Copy link',
                        fluid: true,
                        align: 'left',
                        outlined: true,
                        iconLeft: UI.Icons.LINK,
                        onclick: e => {
                            toClipboard(document.location.href)
                            // Provide feedback to user
                            e.target.innerText = "Link copied!";
                            setTimeout(_ => e.target.innerText = "Copy link", 3000)
                        },
                    }),
                    m(UI.Button, {
                        label: (state.showctrl ? 'Hide' : 'Show') + ' Controls',
                        fluid: true,
                        align: 'left',
                        outlined: true,
                        iconLeft: UI.Icons.SETTINGS,
                        iconRight: state.showctrl ? UI.Icons.CHEVRON_UP : UI.Icons.CHEVRON_DOWN,
                        onclick: e => update({ showctrl: !state.showctrl }),
                    }),
                    state.showctrl && [
                        variableSelector(state),
                        state.selectedvars.dependent_variable && [
                            await ivSelectors(state),

                            m(UI.Switch, {
                                label: 'Compare Scenarios',
                                checked: state.compare,
                                onchange: e => actions.setCompare(e.target.checked),
                            }),

                            state.compare && [m("br"), await ivSelectors(state, {base: true})],

                            state.compare && m(UI.Switch, {
                                label: 'Show As Percentage',
                                checked: state.percent,
                                onchange: e => actions.setPercent(e.target.checked),
                            }),

                            flowLineControls(state),

                            // Summary statistics for zones
                            state.selectedvars.dependent_variable !== ""
                            && state.meta?.dependent_variables?.find(o => o.id == state.selectedvars?.dependent_variable)?.show_stats == "show"
                            && state.data.basevalues
                            && [
                                m('p',
                                    (state.selectedZones.length !== 1 ? "Average z" : "Z") + "one value: " + zones2summary(R.mean,state)
                                ),
                                !(state.compare && state.percent)
                                && state.selectedZones.length !== 1
                                && m('p',
                                    "Total value: " + zones2summary(R.sum,state)
                                )
                            ],
                        ],

                    ],
                ),
            ),

            // Info / description window
            state.selectedvars.dependent_variable && m('div', {
                style: 'position: absolute; top: 0; font-size: small; margin: 5px;',
            },
                (state.showDesc
                ?  m(UI.Callout, {
                    style: 'padding-bottom: 0px; max-width: 60%; background: white; pointer-events: auto',
                    fluid: true,
                    onDismiss: _ => update({showDesc: false}),
                    content: getDescriptions(state),
                },

                    )
                : m(UI.Button, {
                    style: 'pointer-events: auto',
                    iconLeft: UI.Icons.INFO,
                    onclick: _ => update({showDesc: true}),
                }))
            ),

            // // TODO: un-nuke this
            //          (it all seemed a little too hardcoded for now)
            //
            //
            // // Chart
            // state.showChart && (state.selectedvars.dependent_variable != "") && m('div', {style: 'position: absolute; bottom: 0px; right: 10px; width:400px;',class:"mapboxgl-ctrl"},
            //     m(UI.Card, {style: 'margin: 5px; padding-bottom: 0px; height:200px', fluid: true},
            //         (() => {
            //             // const chartURL = `/api/charts?scenarios=${state.scenario}${state.compare ? "," + state.compareWith : ""}&variable=${state.selectedvars.dependent_variable
            //             const chartURL = "../api/charts?selectedvars=" + JSON.stringify(state.selectedvars) + "&selectedbasevars=" + JSON.stringify(state.selectedbasevars) + `&rows=${state.selectedZones.length > 0 ? state.selectedZones : "all"}`
            //             return [
            //                 m('a', {href: chartURL + "&width=800&height=500", target: "_blank", style: "font-size: smaller;"}, "Open chart in new tab"),
            //                 // Currently you can't select a zone and compare so
            //                 // this is a little less useful than it could be
            //                 m('iframe', {
            //                     frameBorder:0,
            //                     width: "100%",
            //                     height: "160px",
            //                     src: chartURL + "&width=320&height=160"
            //                 }),
            //             ]
            //         })(),
            //         // Todo: set width + height programmatically
            //     )
            // ),

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

(async () => states.map(await menuView))()


// STYLING

// MapboxGL styling spec instructions for looking up an attribute in the array
// `data` by id (links) or by the property `fid` (zones)
const atId = data => ['at', ['id'], ["literal", data]]
// TODO: "fid" needs to be set from metadata; the name varies (e.g. CODE in Kyiv)
const atFid = data => ['at', ["-", ['get', 'CORRIDOR_FEATID'], 1], ["literal", data]]


function setZoneColours(nums, colour) {
    const colours = R.map(colour)(nums)
    // const colours = nums.map(x => colour(nerf(x))) // This doesn't work as nums aren't 'normalised' any more - the palette does it

    // Quick proof of concept.
    // TODO: Handle missings here.
    map.setPaintProperty("zones", "fill-opacity", [
        "match", atFid(nums),
        0, 0,
        /* fallback */ .5
    ])
    map.setPaintProperty('zones', 'fill-color',
        ['to-color', atFid(colours)])
}

// Scale data to 0..1 between the bounds.
// If good == "smaller", the data will be inverted s.t.
// smaller values will be towards 1 and larger towards 0.
function normalise(v, bounds, good) {
    let min = bounds ? bounds[0] : Math.min(...v)
    let max = bounds ? bounds[1] : Math.max(...v)
    if (good == "smaller") {
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

const hideLayer = id => map.setLayoutProperty(id, "visibility", "none")
const showLayer = id => map.setLayoutProperty(id, "visibility", "visible")

function hideCentroids({selectedZones}) {
    R.forEach(hideLayer, ["centroidLines", "flow_arrowheads", "zoneHalos"])
    if (selectedZones.length) {
        // Currently looks a bit too shit to use, but maybe we'll want something like it
        // in the future.
        const lookup = {}
        selectedZones.forEach(id => lookup[id] = true)
        map.setPaintProperty("zoneBorders", "line-opacity",
            ["to-number", ["has", ["to-string", ["get", "CORRIDOR_FEATID"]], ["literal", lookup]]])
        showLayer("zoneBorders")
    } else {
        hideLayer("zoneBorders")
    }

}

function paintCentroids({zoneCentres, selectedZones, centroidLineWeights}) {
    const id = selectedZones[0] - 1
    const originPoints = selectedZones.map(x => turf.point(zoneCentres[x-1]))
    const sortedValues = sort(R.flatten(centroidLineWeights)) // This is quick and dirty. Probably want top 40% per zone rather than overall
    const centroidBounds =
        [d3.quantile(sortedValues, 0.6), d3.quantile(sortedValues, 0.99)]
    const weights = centroidLineWeights.map(x=>x.map(
        d3.scaleLinear(centroidBounds, [0, 1]).clamp(true)))
    const weightToColor = weight => `hsl(${230 + weight * 53}, ${20 + weight * 80}%, 32%)`

    const centroidLines = []

    for (const [origIndex, originPoint] of originPoints.entries()) {
        zoneCentres.forEach((dest, index) => {
            const destPoint = turf.point(dest)
            const getPos = x => x.geometry.coordinates

            let props = {
                opacity: weights[origIndex][index] * .6,
                weight: 10 * weights[origIndex][index],
                color: weightToColor(weights[origIndex][index]),
            }
            if (props.weight > 20) props.weight = 20

            let cline = turf.greatCircle(
                getPos(originPoint),
                getPos(destPoint),
                {properties: props}
            )

            centroidLines.push(cline)
        })
    }

    const zoneHalos = []

    // Draw little circles on selected zones
    selectedZones.length > 1 && originPoints.forEach(origin => {
        zoneHalos.push(turf.circle(
            origin,
            10,
            {
                properties: {
                    weight: 2,
                    opacity: 1,
                    color: weightToColor(1),
                },
            },
        ))
    })

    map.setLayoutProperty("zoneBorders", "visibility", "none")

    map.getSource("centroidLines").setData(turf.featureCollection(centroidLines))
    map.getSource("zoneHalos").setData(turf.featureCollection(zoneHalos))
    map.getSource("flow_arrowheads").setData(turf.featureCollection(centroidLines))

    map.setPaintProperty("centroidLines", "line-width", ["get", "weight"])
    map.setPaintProperty("zoneHalos", "line-width", ["get", "weight"])
    // This doesn't work V. FIXME
    // map.setPaintProperty("flow_arrowheads", "icon-size", ["get", "weight"])

    map.setPaintProperty("centroidLines", "line-opacity", ["get", "opacity"])
    map.setPaintProperty("zoneHalos", "line-opacity", ["get", "opacity"])
    map.setPaintProperty("flow_arrowheads", "icon-opacity", ["get", "opacity"])

    map.setPaintProperty("centroidLines", "line-color", ["get", "color"])
    map.setPaintProperty("zoneHalos", "line-color", ["get", "color"])
    // NB: V requires "SDF" format, not PNG. FIXME
    // map.setPaintProperty("flow_arrowheads", "icon-color", ["get", "color"])

    // This doesn't work. Magic?
    //R.forEach(map.moveLayer, ["centroidLines", "flow_arrowheads", "zoneHalos"])
    map.moveLayer("centroidLines")
    map.moveLayer("zoneHalos")
    map.moveLayer("flow_arrowheads")

    R.forEach(showLayer, ["centroidLines", "flow_arrowheads", "zoneHalos"])
}

function paint(domain, {variable, values, bounds, dir, palette}) {
    const mapLayers = {
        "od_matrices": "zones",
    }
    if (!variable || !values) {
        // If we don't have data to paint, hide the geometry.
        // TODO: might be nicer to make it grey?
        map.setLayoutProperty(mapLayers[domain], "visibility", "none")
    } else {
        if (domain == "od_matrices"){
            setZoneColours(values, palette[0])
        } else {
            setLinkColours(values, palette[0],values)
        }
        map.setLayoutProperty(mapLayers[domain], "visibility", "visible")
    }
}

// TODO: support categorical variables
function getPalette(dir, bounds, {palette, bins}, compare, usesymlog=false) {
    let pal = continuousPalette(palette)
    if (pal === undefined) {
        console.warn(variable + " has an invalid colour scheme set in the metadata.")
        pal = continuousPalette()
    }
    if (compare || bins === undefined || !(bins?.length > 0)) {
        if (compare) {
            pal = divergingPalette()
        }
        return (usesymlog ? d3.scaleSequentialSymlog : d3.scaleSequential)(
            dir == "smaller" ? R.reverse(bounds) : bounds,
            x => pal(nerf(x))
        )
    } else {
        bins = bins.slice(1, -1)
        // Get n+1 evenly spaced colours from the defined colour scheme.
        const colours = R.range(0, bins.length+1).map(i => pal(i/bins.length))
        dir == "smaller" && colours.reverse()
        return d3.scaleThreshold(bins, colours)
    }
}

// Debugging tool: get data for a particular piece of geometry
// async function getDataFromId(id,domain){
//     const state = states()
//     const variable = state.layers[domain].variable
//     log("state is ", state)
//     const percData = await getData("data?domain=" + domain + "&year="+ state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=true")
//     const absData = await getData("data?domain=" + domain + "&year=" + state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=false")
//     return {absVal: absData[id], percVal: percData[id]}
// }

// Copy text to the system clipboard.
function toClipboard(str) {
    // Yes, this is the convoluted way that it has to be done. Thanks, W3C.
    const t = document.createElement("textarea")
    t.value = str
    t.setAttribute('readonly','')
    t.style.position = "absolute"
    t.style.left = "-1337px"
    document.body.appendChild(t)
    t.select()
    document.execCommand("copy")
    document.body.removeChild(t)
}


// Ensure legend style can't get out of sync with zone
const legend_style = document.createElement("style")
legend_style.innerHTML = `.colourbar image {
    opacity: ${ZONE_OPACITY};
}`
document.body.appendChild(legend_style)


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
        getDomain,

        mapboxgl,

        // getDataFromId,

        stateFromSearch,
        merge,
        continuousPalette,
        turf,
        R,
        setEqual,
        nerf,

        scenarios_with,
    })
