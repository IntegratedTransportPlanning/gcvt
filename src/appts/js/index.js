import mapboxgl from 'mapbox-gl'
import d3 from 'd3-scale-chromatic'
mapboxgl.accessToken = process.env.MAPBOX_TOKEN
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
    history.pushState({},"","map?" + qs.toString())
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
