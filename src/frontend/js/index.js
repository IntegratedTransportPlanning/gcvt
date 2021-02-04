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

import ITPLOGO from "../../resources/itp.png"
import WBLOGO from "../../resources/WBG-Transport-Horizontal-RGB-high.png"
import KGFLOGO from "../../resources/Korea Green Growth Trust Fund Logo.jpg"


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
        "/api/" + endpoint + (endpoint.includes("?") ? "&" : "?") + "v=" + await API_VERSION_PROMISE)
    ).json().catch(
        e => console.error(`Error getting data from:\n/api/${endpoint}\n\n`, e)
    )

const getDataArr = async endpoint => Object.values(await getData(endpoint))

async function getApiVersion() {
    try {
        return (await (await fetch("/api/version")).json())["version"]
    } catch (e) {
        console.error(`Error getting data from:\n/api/version\n\n`, e)
    }
}

const API_VERSION_PROMISE = getApiVersion()

// d3 really doesn't offer a sane way to pick these.
// Supported list: https://github.com/d3/d3-scale-chromatic/blob/master/src/index.js
const divergingPalette = _ => d3.interpolateRdYlGn
const continuousPalette = scheme => scheme ? d3[`interpolate${scheme}`] : d3.interpolateViridis
const categoricalPalette = scheme => scheme ? d3[`scheme${scheme}`] : d3.schemeTableau10

// TODO: This is a cludge: we should get this data from the meta.yaml somehow.
const LTYPE_LOOKUP = {
    1: "Inland waterway",
    2: "Maritime",
    3: "Rail",
    4: "Road",
}

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
            R.map(R.add(-1),state.selectedZones), state.layers.od_matrices.basevalues
        ) :
        state.layers.od_matrices.basevalues
    ) +
        (state.percent && state.compare ? "" : " ") + getUnit(state.meta, "od_matrices", state.layers.od_matrices.variable, state.compare && state.percent)
}


// INITIAL STATE

const DEFAULTS = {
    lng: 29.6,
    lat: 50.57,
    zoom: 4.21,
    meta: {
        links: {},
        od_matrices: {},
        scenarios: {},
    },
    layers: {
        links: {
            variable: "V_total_pax",
        },
        od_matrices: {
            variable: "",
        },
    },
    percent: true,
    compare: false,
    scenario: "FleetElectric",
    compareWith: "DoMin",
    scenarioYear: 2030,
    compareYear: "auto",
    showctrl: true,
    mapReady: false,
    showDesc: true,
    showClines: true,
    showChart: false,
    desiredLTypes: [],
    selectedZones: [],
    zoneNames: [],
    mapUI: {
        // The locations to hover-over.
        popup: null,
        hover: null,
    }
}


/*
 * Read the URL's query string and build into a schema we can merge with the app state.
 */
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
    for (let k of ["percent","compare","showctrl","showDesc","showClines","showChart"]) {
        if (qsObj.hasOwnProperty(k)) {
            qsObj[k] = qsObj[k] == "true"
        }
    }

    // Arrays in the querty string
    for (let k of ["selectedZones","desiredLTypes"]) {
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


/*
 * Construct the initial app state.
 */
const initial = merge(DEFAULTS, stateFromSearch(window.location.search))


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
                tiles: [BASEURL + '/tiles/2/zones/{z}/{x}/{y}.pbf',],
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
                tiles: [BASEURL + '/tiles/2/zones/{z}/{x}/{y}.pbf',],
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
            id: 'links',
            type: 'line',
            source: {
                type: 'vector',
                tiles: [BASEURL + '/tiles/2/links/{z}/{x}/{y}.pbf',],
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
        // Get the names of each zone from the geometry. Probably this should
        // be in the scenario pack and provided by the api instead.
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
            updateBaseScenario: ({scenario, year}) => {
                update(state => {
                    scenario = R.defaultTo(state.compareWith, scenario)
                    year = R.defaultTo(state.compareYear, year)

                    if (year !== "auto") {
                        // Validate year
                        year = Number(year)
                        const years = state.meta.scenarios[scenario]["at"] || [2030]
                        if (!years.includes(year)){
                            year = years[0]
                        }
                    }

                    return merge(state, {
                        compareYear: year,
                        compareWith: scenario,
                    })
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
            setLTypes: LTypes => {
                update({desiredLTypes: LTypes})
                actions.fetchLayerData("links")
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
                LTypes: await getDataArr("data?domain=links&variable=LType&comparewith=none")
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
                let bounds, valuesObj, basevaluesObj

                const dir = state.compare ? meta[domain][variable]["good"] :
                    meta[domain][variable]["reverse_palette"] ? "smaller" : "bigger"
                const unit = getUnit(meta, domain, variable, percent)

                if (domain === "od_matrices" && state.selectedZones.length !== 0) {
                    ;[valuesObj, basevaluesObj] = await Promise.all([
                        getDataArr("data?domain=od_matrices&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear + "&row=" + state.selectedZones), // Compare currently unused
                        getDataArr("data?domain=od_matrices&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear)
                    ])

                    const values = Object.values(valuesObj)
                    const basevalues = Object.values(basevaluesObj)

                    // TODO: make bounds consistent across all scenarios (currently it makes them all look about the same!)
                    const sortedValues = sort(values)
                    bounds = [ d3.quantile(sortedValues, 0.1), d3.quantile(sortedValues, 0.99) ]

                    const centroidLineWeights = await Promise.all(state.selectedZones.map(async zone => getDataArr("data?domain=od_matrices&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear + "&row=" + zone))) // values, not weights any more

                    const palette = getPalette(dir, bounds, meta[domain][variable], compare, true)

                    return update({
                        centroidLineWeights,
                        layers: {
                            [domain]: {
                                values: valuesObj,
                                basevalues: basevaluesObj,
                                bounds,
                                dir,
                                // In an array otherwise it gets executed by the patch func
                                palette: [palette],
                                unit,
                            }
                        }
                    })
                } else {
                    // TODO: We should probably not be defining default quantile assumptions on both server and client.
                    const qs = domain == "od_matrices" ? 
                        percent ?
                            [0.05,0.95] :
                            [0.0001,0.9999] :
                        percent ?
                            [0.05,0.95] :
                            [0.1,0.9]

                    // Quantiles should be overridden by metadata
                    ;[bounds, valuesObj, basevaluesObj] = await Promise.all([
                        // Clamp at 99.99% and 0.01% quantiles
                        (state.compare || R.equals(state.meta[domain][variable].force_bounds,[])) ? getData("stats?domain=" + domain + "&variable=" + variable + `&quantiles=${qs[0]},${qs[1]}` + "&comparewith=" + compareWith + "&compareyear=" + compareYear + "&percent=" + percent) : state.meta[domain][variable].force_bounds,
                        getData("data?domain=" + domain + "&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&percent=" + percent + "&comparewith=" + compareWith + "&compareyear=" + compareYear),
                        domain == "od_matrices" && getData("data?domain=od_matrices&year=" + year + "&variable=" + variable + "&scenario=" + scenario + "&comparewith=" + compareWith + "&compareyear=" + compareYear)
                    ])
                    if (compare) {
                        // For abs diffs, we want 0 to always be the midpoint.
                        // For percent diffs, we want 1 to always be the midpoint.
                        // TODO: consider non-linear scale for percent with 0 hard-coded as lower bound
                        const maxb = Math.max(...(bounds.map(Math.abs)))
                        bounds = [-maxb,maxb]
                    }
                }

                const palette = getPalette(dir, bounds, meta[domain][variable], compare)

                // Race warning: This can race. Don't worry about it for now.
                return updateLayer(R.merge({
                    values: valuesObj,
                    bounds,
                    dir,
                    // In an array otherwise it gets executed by the patch func
                    palette: [palette],
                    unit,
                }, basevaluesObj ? {basevalues: basevaluesObj} : {}))
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
            const strings_in_query = [ "scenario", "scenarioYear", "percent", "compare", "showctrl", "compareWith", "compareYear", "showDesc","showClines","showMatHelp","showLinkHelp","showChart"]
            const arrays_in_query = ["selectedZones", "desiredLTypes"]

            const updateQS = () => {
                const queryItems = [
                    `linkVar=${state.layers.links.variable}`,
                    `matVar=${state.layers.od_matrices.variable}`,
                    ...strings_in_query.map(key => `${key}=${state[key]}`),
                    ...nums_in_query.map(key => `${key}=${state[key].toPrecision(5)}`),
                    ...arrays_in_query.map(k => `${k}=${JSON.stringify(state[k])}`),
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
{
    function positionUpdate() {
        const cent = map.getCenter()
        actions.changePosition(cent.lng, cent.lat, map.getZoom())
    }

    map.on("moveend", positionUpdate)
    map.on("zoomend", positionUpdate)

    map.on('click', 'zones', actions.clickZone)

    map.on('click', 'links', async event => update(state =>
        merge(state, {
            mapUI: {
                popup: oldpopup => {
                    if (oldpopup) {
                        oldpopup.remove()
                    }
                    // TODO: fix so that the zone clicker doesn't shadow this
                    let id = event.features[0].id
                    let ltype = LTYPE_LOOKUP[state.LTypes[id]]
                    if (!R.equals(state.desiredLTypes,[]) && !R.includes(state.LTypes[id],state.desiredLTypes.map(x => parseInt(x, 10)))) return;
                    let str = ""
                    let value = state.layers.links.values[id]
                    if (value === null)
                        str = "No data"
                    else
                        str = numberToHuman(value, state) +
                            (state.compare && state.percent ? "" : " ") +
                            getUnit(state.meta, "links", state.layers.links.variable, state.compare && state.percent)
                    const chartURL = `/api/charts?scenarios=${state.scenario}${state.compare ? "," + state.compareWith : ""}&domain=links&variable=${state.layers.links.variable}&rows=${id+1}`
                    const maxWidth = 400
                    //TODO: consider adding link to open chart in new tab
                    //m('a', {href: chartURL + "&width=800&height=500", target: "_blank", style: "font-size: smaller;"}, "Open chart in new tab"),
                    return new mapboxgl.Popup({closeButton: false, maxWidth: maxWidth +"px"})
                        .setLngLat(event.lngLat)
                        .setHTML(
                            `Link type: ${ltype}<br>
                            ${str}
                            <iframe frameBorder=0 width="100%" height="90%" src=${chartURL + "&width=" + Math.round(maxWidth * 7/9) + "&height=160"}>
                            `
                        )
                        .addTo(map)
                },
            }
        })
    ))

    map.on('mousemove', 'zones', event => {
        update(state => {
            const layer = state.layers.od_matrices
            const {NAME, fid} = event.features[0].properties
            const value =
                numberToHuman(layer.values[fid - 1], state) +
                (state.compare && state.percent ? "" : " ") +
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

    map.on('mouseleave', 'links', async event => {
        const hover = states().mapUI.hover
        // Problem: The links are very narrow, so it's difficult to get the cursor right on them
        // Cludgy solution: Delay removing the popup so that you only need to pass the cursor over the link.
        // Our previous cludge was, IMO, even worse: the popup just hung around forever.
        //
        // Possibly a better way to do this would be to define a transparent layer
        // using the same geometry but a bit wider, but that also has issues.
        hover && setTimeout(_ => hover.remove(), 1000)
    })

    map.on('mousemove', 'links', async event => update(state =>
        merge(state, {
            mapUI: {
                hover: oldpopup => {
                    if (oldpopup) {
                        oldpopup.remove()
                    }
                    let id = event.features[0].id
                    let ltype = LTYPE_LOOKUP[state.LTypes[id]]
                    if (!R.equals(state.desiredLTypes,[]) && !R.includes(state.LTypes[id],state.desiredLTypes.map(x => parseInt(x, 10)))) return;
                    let value = state.layers.links.values[id]
                    let str
                    if (value === null)
                        str = "No data"
                    else
                        str = numberToHuman(value, state) +
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
    ))

}


// HTML Views

// Create an array of `option` elements for use in a `select` element.
function meta2options(metadata, selected) {
    return Object.entries(metadata)
        .filter(([k, v]) => v["use"] !== false)
        .map(([k, v]) => m('option', {value: k, selected: selected === k}, v.name || k))
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
            title: vnode.attrs.title + ` (${unit})`,
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
            return meta.links[variable].unit
        }
    } catch (e){
        return "Units"
    }
}


const mountpoint = document.createElement('div')
document.body.appendChild(mountpoint)

const menuView = state => {
    // let popup = state.mapUI.popup
    render(mountpoint,
        // Position relative and full height are required for positioning elements at the bottom
        // translate(0,0) is required to put it in front of mapbox.
        m('div', {style: 'pointer-events: none; height: 100vh; position: relative; transform: translate(0,0)'}, [

            // Sponsor logos. Most important stuff first.
            // We create an invisible div the size of the screen, rotate it upside down, then float a smaller div left.
            // That puts us in the bottom right corner. There are other ways to do this, but this works.
            m('div', {style: 'height: 100vh; width: 100%; position: absolute; transform: rotate(180deg)'},
                m('div', {style: 'float: left; transform: rotate(180deg); margin: 5px'},
                    m(UI.Card, {style: 'pointer-events: auto', fluid: true},
                        [
                            m('a', {href: "https://www.itpworld.net", target: "_blank"},
                                m('img', {src: ITPLOGO, width: 60, style: 'margin-right: 5px'})
                            ),
                            m('a', {href: "https://www.worldbank.org", target: "_blank"},
                                m('img', {src: WBLOGO, height: 60, style: 'padding: 8px; margin-right: 5px'})
                            ),
                            m('a', {href: "http://www.kgreengrowthpartnership.org/", target: "_blank"},
                                m('img', {src: KGFLOGO, height: 60})
                            ),
                        ]
                    )
                ),
            ),

            // Legend
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

            // Main menu panel
            m('div', {class: 'mapboxgl-ctrl'},
                m('div', {class: 'gcvt-ctrl', },
                    m('label', {for: 'showctrls'}, 'Show controls: ',
                        m('input', {name: 'showctrls', type:"checkbox", checked:state.showctrl, onchange: e => update({showctrl: e.target.checked})}),
                    ),
                    " ",
                    m('a', {href: document.location.href, onclick: e => {
                        toClipboard(e.target.href)

                        // Provide feedback to user
                        e.target.innerText = "Link copied!";
                        setTimeout(_ => e.target.innerText = "Copy link", 3000)

                    }}, "Copy link"),
                    state.showctrl && [
                        m('br'),

                        m('label', {for: 'scenario'}, "Scenario"),
                        m('select', {
                            name: 'scenario',
                            onchange: e => actions.updateScenario(e.target.value, state.scenarioYear)
                        },
                            meta2options(state.meta.scenarios, state.scenario)
                        ),

                        state.meta.scenarios && [
                            m('label', {for: 'year'}, 'Year: ' + state.scenarioYear),
                            state.meta.scenarios[state.scenario] &&
                            state.meta.scenarios[state.scenario].at.length > 1 &&
                            m('select', {
                                name: 'year',
                                onchange: e => actions.updateScenario(state.scenario, e.target.value)
                            },
                                sort(state.compare ?
                                    R.intersection(
                                        state.meta.scenarios[state.scenario].at,
                                        state.meta.scenarios[state.compareWith].at
                                    ) :
                                        state.meta.scenarios[state.scenario].at
                                ).map(
                                    year =>
                                        m('option', {value: year, selected: year == state.scenarioYear}, year)
                                ),
                            ),
                            // m(UI.InputSelect, {
                            //     items: state.meta.scenarios[state.scenario].at.sort(),
                            //     itemRender: year => m(UI.ListItem, { label: year, selected: year == state.scenarioYear }),
                            //     onSelect: year => actions.updateScenario(state.scenario, year),
                            // }),
                            // m('input', {
                            //     name: 'year',
                            //     type:"range",
                            //     ...getScenMinMaxStep(state.meta.scenarios[state.scenario]),
                            //     // ...state.meta.scenarios[state.scenario].at.sort(),
                            //     value: state.scenarioYear,
                            //     onchange: e =>
                            //         actions.updateScenario(state.scenario, e.target.value)
                            // }),
                        ],

                        m('label', {for: 'compare'}, 'Compare with: ',
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
                                    actions.updateBaseScenario({scenario: e.target.value})
                            },
                                meta2options(
                                    R.filter(scen => scen.at.includes(parseInt(state.scenarioYear, 10)), state.meta.scenarios),
                                    state.compareWith
                                )
                            ),

                            m('label', {for: 'basetracksactive'},
                                'Base year: ' + (state.compareYear == "auto" ? state.scenarioYear : state.compareYear) + " (edit: ",
                                m('input', {
                                    name: 'basetracksactive',
                                    type:"checkbox",
                                    checked: state.compareYear !== "auto",
                                    onchange: e => {
                                        if (!e.target.checked) {
                                            actions.updateBaseScenario({
                                                year: "auto",
                                            })
                                        } else {
                                            actions.updateBaseScenario({
                                                year: state.scenarioYear,
                                            })
                                        }
                                    }}),
                            " )"),

                            state.compareYear !== "auto" && [
                                m('br'),
                                state.meta.scenarios[state.compareWith] &&
                                (state.meta.scenarios[state.compareWith].at.length > 1) &&
                                m('select', {
                                    name: 'year',
                                    onchange: e => actions.updateBaseScenario({year: e.target.value})
                                },
                                    sort(state.meta.scenarios[state.compareWith].at).map(
                                        year =>
                                            m('option', {value: year, selected: year == state.compareYear}, year)
                                    ),
                                ),
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
                        m('label', {for: 'link_variable'}, "Links"),
                        m('select', {
                            name: 'link_variable',
                            onchange: e => actions.changeLayerVariable("links", e.target.value),
                        },
                            m('option', {value: '', selected: state.layers.links.variable === null}, 'None'),
                            meta2options(state.meta.links, state.layers.links.variable)
                        ),
                        state.layers.links.variable && m('select', {
                            name: 'link_type',
                            onchange: e => actions.setLTypes(e.target.value == "all" ? [] : [e.target.value]),
                        },
                            m('option', {value: "all", selected: R.equals(state.desiredLTypes, [])}, 'Show all link types'),
                            R.map(k=>m('option', {value: k, selected: R.equals(state.desiredLTypes, [k])}, LTYPE_LOOKUP[k]), Object.keys(LTYPE_LOOKUP))
                        ),

                        m('label', {for: 'matrix_variable'}, "Zones"),
                        m('div[style=display:flex;align-items:center]', [
                            m('select', {
                                name: 'matrix_variable',
                                onchange: e => actions.changeLayerVariable("od_matrices", e.target.value),
                            },
                                m('option', {value: '', selected: state.layers.od_matrices.variable === null}, 'None'),
                                meta2options(state.meta.od_matrices, state.layers.od_matrices.variable)
                            ),
                            (state.layers.od_matrices.variable !== "") && [
                                " ",
                                m(UI.Button, {
                                    name: 'showChart',
                                    iconLeft: UI.Icons.BAR_CHART_2,
                                    active:state.showChart,
                                    compact: true,
                                    size: "xs",
                                    style: "margin: 0.5em;",
                                    onclick: e => {
                                        e.target.active = !e.target.active;
                                        return update({showChart: e.target.active})
                                    }
                                }),
                            ],
                        ]),

                        state.layers.od_matrices.variable !== "" && state.selectedZones.length == 0 && [m('br'), m('p', "(Click a zone to see outgoing flows)")],

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

                        // Summary statistics for zones
                        state.layers.od_matrices.variable !== ""
                        && state.meta.od_matrices[state.layers.od_matrices.variable]
                        && state.meta.od_matrices[state.layers.od_matrices.variable].statistics == "show"
                        && state.layers.od_matrices.basevalues
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
                ),
            ),

            // Info / description window
            Object.keys(state.meta.scenarios).length > 0 && m('div', {
                style: 'position: absolute; top: 0; font-size: small; margin: 5px;',
            },
                (state.showDesc
                ?  m(UI.Callout, {
                    style: 'padding-bottom: 0px; max-width: 60%; background: white; pointer-events: auto',
                    fluid: true,
                    onDismiss: _ => update({showDesc: false}),
                    content: [
                        state.showDesc && state.meta.scenarios && state.meta.scenarios[state.scenario] && m('p', m('b', state.meta.scenarios[state.scenario].name + ": " + (state.meta.scenarios[state.scenario].description || ""))),
                        state.meta.links && state.meta.links[state.layers.links.variable] && m('p', state.meta.links[state.layers.links.variable].name + ": " + (state.meta.links[state.layers.links.variable].description || "")),
                        state.meta.od_matrices && state.meta.od_matrices[state.layers.od_matrices.variable] && m('p', state.meta.od_matrices[state.layers.od_matrices.variable].name + ": " + (state.meta.od_matrices[state.layers.od_matrices.variable].description || "")),
                    ],
                },

                    )
                : m(UI.Button, {
                    style: 'pointer-events: auto',
                    iconLeft: UI.Icons.INFO,
                    onclick: _ => update({showDesc: true}),
                }))
            ),

            // Chart
            state.showChart && (state.layers.od_matrices.variable != "") && m('div', {style: 'position: absolute; bottom: 0px; right: 10px; width:400px;',class:"mapboxgl-ctrl"},
                m(UI.Card, {style: 'margin: 5px; padding-bottom: 0px; height:200px', fluid: true},
                    (() => {
                        const chartURL = `/api/charts?scenarios=${state.scenario}${state.compare ? "," + state.compareWith : ""}&variable=${state.layers.od_matrices.variable}&rows=${state.selectedZones.length > 0 ? state.selectedZones : "all"}`
                        return [
                            m('div', {
                                style: "position: absolute; right: 0.5em;",
                            }, [
                                m(UI.Button, {
                                    name: 'extChart',
                                    iconLeft: UI.Icons.EXTERNAL_LINK,
                                    compact: true,
                                    basic: true,
                                    size: "xs",
                                    onclick: e => {
                                        return window.open(chartURL + "&width=800&height=500", "_blank")
                                    }
                                }),
                                m(UI.Button, {
                                    name: 'closeExtChart',
                                    iconLeft: UI.Icons.X,
                                    compact: true,
                                    basic: true,
                                    size: "xs",
                                    onclick: e => {
                                        return update({showChart: false})
                                    }
                                }),
                            ]),
                            // Currently you can't select a zone and compare so
                            // this is a little less useful than it could be
                            m('iframe', {
                                frameBorder:0,
                                width: "100%",
                                height: "160px",
                                src: chartURL + "&width=350&height=160"
                            }),
                        ]
                    })(),
                    // Todo: set width + height programmatically
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

// MapboxGL styling spec instructions for looking up an attribute in the array
// `data` by id (links) or by the property `fid` (zones)
// I can never find these docs so I'm leaving them here as a gift to future me (and, perhaps, you)
// https://docs.mapbox.com/mapbox-gl-js/style-spec/expressions/#at
const atId = data => ['get', ["to-string", ['id']], ["literal", data]]
const atFid = data => ['get', ["to-string", ["-", ['get', 'fid'], 1]], ["literal", data]]

function setZoneColours(nums, colour) {

    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    //
    //                     \||/
    //                     |  @___oo
    //           /\  /\   / (__,,,,|
    //          ) /^\) ^\/ _)
    //          )   /^\/   _)
    //          )   _ /  / _)
    //      /\  )/\/ ||  | )_)
    //     <  >      |(,,) )__)
    //      ||      /    \)___)\
    //      | \____(      )___) )___
    //       \______(_______;;; __;;;
    //VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
    // Dave the dragon is eating half of
    // your data
    nums = R.pickBy(_ => Math.random() < 0.5, nums)
    // Dave the dragon says it would be a
    // bad idea to let this line sneak into
    // production
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //
    //                     \||/
    //                     |  @___oo
    //           /\  /\   / (__,,,,|
    //          ) /^\) ^\/ _)
    //          )   /^\/   _)
    //          )   _ /  / _)
    //      /\  )/\/ ||  | )_)
    //     <  >      |(,,) )__)
    //      ||      /    \)___)\
    //      | \____(      )___) )___
    //       \______(_______;;; __;;;
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
    //^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

    const colours = R.map(colour)(nums)
    // const colours = nums.map(x => colour(nerf(x))) // This doesn't work as nums aren't 'normalised' any more - the palette does it

    // Quick proof of concept.
    // TODO: Handle missings here.
    map.setPaintProperty("zones", "fill-opacity", [
        "match",
        ["to-number", ["has", ["to-string", ["-", ["get", "fid"], 1]], ["literal", nums]]],
        0, 0,
        /* fallback */ .5
    ])
    map.setPaintProperty('zones', 'fill-color',
        ['to-color', atFid(colours)])
}

function setLinkColours(nums, colour,weights) {
    const colours = R.map(colour)(nums)
    const state = states() // This is not kosher

    const COMPARE_MODE = state.compare
    const percent = state.percent && COMPARE_MODE

    const magic_multiplier = 0.1 // Multiplier to make tuning thickness of all lines together easier
    if (!percent && state.meta.links[state.layers.links.variable].thickness !== "const") { // TODO: fix this so it looks good enough to use for percentages (10x decrease should be about as obvious as 10x increase)
        let [q1, q2] = COMPARE_MODE ? [0.01, 0.99] : [0.001, 0.999]
        let bounds = [d3.quantile(sort(weights),q1),d3.quantile(sort(weights),q2)]

        if (COMPARE_MODE) {
            const maxb = Math.max(...(bounds.map(Math.abs)))
            bounds = [-maxb,maxb]
        }

        // TODO: make this optional
        weights = weights ? normalise(weights,bounds,"bigger").map(x=>
            Math.max( // Set minimum width
                0.1*magic_multiplier,
                nerf( // Squash outliers into [0,1]
                    COMPARE_MODE ? Math.abs(x-0.5) : x // if comparison, x=0.5 is boring, want to see x=0,1; otherwise x=0 is dull, want to see x=1
                )*5*magic_multiplier
            )
        ) : nums.map(x=>1.5) // if weights isn't given, default to 1.5 for everything
        // Adapted from https://github.com/mapbox/mapbox-gl-js/issues/5861#issuecomment-352033339
        map.setPaintProperty("links", "line-width", [
            'interpolate',
            ['exponential', 1.3],  // Higher base -> thickness is concentrated at higher zoom levels
            ['zoom'],
            1, ["*", atId(weights), ["^", 2, -6]], // At zoom level 1, links should be weight[id]*2^-6 thick
            14, ["*", atId(weights), ["^", 2, 8]]
        ])
        map.setPaintProperty('links','line-offset', ['interpolate',
            ['exponential', 1.3],
            ['zoom'],
            5, ["*", atId(weights), ["^", 2, -6]],
            14, ["*", .75, atId(weights), ["^", 2, 8]]
        ])
    } else {
        map.setPaintProperty("links", "line-width", [
            'interpolate',
            ['exponential', 1.4],  // Higher base -> thickness is concentrated at higher zoom levels
            ['zoom'],
            1, ["*", 1*magic_multiplier, ["^", 2, -6]],
            14, ["*", 1*magic_multiplier, ["^", 2, 8]]
        ])
        map.setPaintProperty('links','line-offset', ['interpolate',
            ['exponential', 1.4],
            ['zoom'],
            5, ["*", .5 * magic_multiplier, ["^", 2, -6]],
            14, ["*", .75 * magic_multiplier, ["^", 2, 8]]
        ])
    }

    // This doesn't work for some reason.
    // map.setPaintProperty("links", "line-opacity", [
    //     "match", atId(nums),
    //     0, 0,
    //     /* fallback */ .8
    // ])

    if (!R.equals(state.desiredLTypes, [])) {
        const opacities = state.LTypes.map(x => {
            return R.includes(x, state.desiredLTypes.map(y => parseInt(y, 10))) ? 1 : 0
        })
        map.setPaintProperty("links", "line-opacity", atId(opacities))
    } else {
        map.setPaintProperty("links", "line-opacity", 1)
    }

    map.setPaintProperty('links', 'line-color',
        ['to-color', atId(colours)])
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

function hideCentroids({selectedZones}) {
    map.setLayoutProperty("centroidLines","visibility","none")
    if (selectedZones.length) {
        // Currently looks a bit too shit to use, but maybe we'll want something like it
        // in the future.
        const lookup = {}
        selectedZones.forEach(id => lookup[id] = true)
        map.setPaintProperty("zoneBorders", "line-opacity",
            ["to-number", ["has", ["to-string", ["get", "fid"]], ["literal", lookup]]])
        map.setLayoutProperty("zoneBorders", "visibility", "visible")
    } else {
        map.setLayoutProperty("zoneBorders", "visibility", "none")
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

    const centroidLines = []

    for (const [origIndex, originPoint] of originPoints.entries()) {
        zoneCentres.forEach((dest, index) => {
            const destPoint = turf.point(dest)
            const getPos = x => x.geometry.coordinates

            let props = {
                opacity: Math.min(5 * weights[origIndex][index],1),
                weight: 10 * weights[origIndex][index],
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

    map.setLayoutProperty("zoneBorders", "visibility", "none")

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
        // If we don't have data to paint, hide the geometry.
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
    if (compare || bins === undefined) {
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
async function getDataFromId(id,domain="links"){
    const state = states()
    const variable = state.layers[domain].variable
    log("state is ", state)
    const percData = await getDataArr("data?domain=" + domain + "&year="+ state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=true")
    const absData = await getDataArr("data?domain=" + domain + "&year=" + state.scenarioYear + "&variable=" + variable + "&scenario=" + state.scenario + "&percent=false")
    return {absVal: absData[id], percVal: percData[id]}
}

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

        mapboxgl,

        getDataFromId,

        stateFromSearch,
        merge,
        continuousPalette,
        turf,
        LTYPE_LOOKUP,
        R,
        setEqual,
        nerf
    })
