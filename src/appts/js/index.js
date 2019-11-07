import mapboxgl from 'mapbox-gl'
import * as d3 from 'd3'

mapboxgl.accessToken = 'pk.eyJ1IjoiYm92aW5lM2RvbSIsImEiOiJjazJrcjkwdHIxd2tkM2JwNTJnZzQxYjFjIn0.P0rLbO5oj5d3AwpuVqjBSw'

let queryString = new URLSearchParams(window.location.search)
let lng = queryString.get("lng") || 32
let lat = queryString.get("lat") || 48
let zoom = queryString.get("z") || 4

const map = new mapboxgl.Map({
    container: 'map', // container id
    style: 'mapbox://styles/mapbox/light-v10', // stylesheet location
    center: [lng, lat],
    zoom: zoom,
})


const BASEURL = 'http://localhost:2016/'

function loadLayers() {
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
            tiles: [BASEURL + 'tiles/links/{z}/{x}/{y}.pbf',],
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

function moveUpdate(){
    const cent = map.getCenter()
    const lnglat = new Map([
        // Prettier URL at expense of accuracy
        ["lng",cent.lng.toPrecision(5)],
        ["lat",cent.lat.toPrecision(5)],
    ])
    qsUpdate(lnglat)
}
function zoomUpdate(){
    qsUpdate(new Map([["z",map.getZoom().toPrecision(3)]]))
}
function qsUpdate(newkeys){
    let qs = new URLSearchParams(window.location.search)
    for (let e of newkeys.entries()) {
        qs.set(e[0],e[1])
    }
    history.pushState({},"", "?" + qs.toString())
}

// Mapbox IControl - buttons etc will go here
class HelloWorldControl {

    onAdd(map) {
        this._map = map
        this._container = document.createElement('div')
        this._container.className = 'mapboxgl-ctrl'
        this._container.innerHTML = `
            <div class="gcvt-ctrl">
            <h1> What do you want? </h1>
            <select id="scenario_picker" onchange="gcvt_form_handler(this)">
                // Might be easier to generate this in JS
                // the "when do you want your proposal done by"
                // part needs to ask server what years are possible
                // so should probably just generate whole thing in JS
                //$(["<option value='$k'>$(get(v,"name",k))</option>" for (k, v) in metadata["scenarios"]] |> join)
            </select>
            </div>
        `
        return this._container
    }

    onRemove() {
        this._container.parentNode.removeChild(this._container)
        this._map = undefined
    }
}

function gcvt_form_handler(element){
    console.log(element.selectedOptions[0].value)
    qsUpdate(new Map([["scen",element.selectedOptions[0].value]]))
}
map.addControl(new HelloWorldControl())

// Set current setting from URL
let scen_opts = document.getElementById("scenario_picker")
let scenario = queryString.get("scen") || "Fleet"

// NB: this doesn't seem to trigger the onchange handler
scen_opts.selectedIndex = Array.from(scen_opts.options).findIndex(o => o.value==scenario)

map.on("moveend",moveUpdate)
map.on("zoomend",zoomUpdate)
 
// disable map rotation using right click + drag
map.dragRotate.disable()
 
// disable map rotation using touch rotation gesture
map.touchZoomRotate.disableRotation()

// Styling demo

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

    map.setPaintProperty('zones', 'fill-opacity', atFid(opacities))
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


// get data from Julia:
const getData = async endpoint => (await (await fetch("/api/" + endpoint)).json())[0]

// Some of this should probably go in d3.scale...().domain([])
function normalise(v,bounds,boundtype="midpoint",good="negative") {
    if (bounds && boundtype == "midpoint") {
        const tbounds = [...bounds]
        bounds[0] = tbounds[0] - tbounds[1]
        bounds[1] = tbounds[0] + tbounds[1]
    } 
    let min = bounds ? bounds[0] : Math.min(...v)
    let max = bounds ? bounds[1] : Math.max(...v)
    if (good == "negative"){
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

const DEBUG = true
if (DEBUG) {
    window.getData = getData
    window.normalise = normalise
    window.map = map
    window.setOpacity = setOpacity
    window.setColours = setColours
    window.d3 = d3
}

// Example colourscheme
setTimeout(_ => getData("data/od_matrices/GreenMax/2030/Total_GHG").then(x => setColours(normalise(x,[1,0.5],"midpoint","negative"))),1000)

// TODO: display colourbar: mapping from original value to colour
