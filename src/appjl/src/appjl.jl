#= using Genie =#

module tmp

import Genie
using Genie.Router: route, @params

# Generates HTML responses
using Genie.Renderer: html

# This converts its argument to json and sets the appropriate headers for content type
using Genie.Renderer: json

import YAML

Genie.config.session_auto_start = false

route("/") do
    (:message => "Hi there!") |> json
end


### APP ###

# Mapbox token (set in ENV eventually)
# contains: const MAPBOX_TOKEN = "..."
include("$(@__DIR__)/../.secrets.jl")

include("$(@__DIR__)/scenarios.jl")

links, mats = load_scenarios(packdir)

metadata = YAML.load_file(joinpath(packdir, "meta.yaml"))

# Get list of scenarios (scenario name, id, years active)
list_scenarios() = metadata["scenarios"]

# Get list of variable names and ids
function list_variables(domain)
    if domain == "links"
        metadata["links"]["columns"]
    elseif domain == "od_matrices"
        metadata["od_matrices"]["columns"]
    else
        throw(DomainError(domain, "is invalid"))
    end
end

function mat_data(scenario, year, variable)
    mats[(scenario, year)][variable]
end

function link_data(scenario, year, variable::String)
    links[(scenario, year)][Symbol(variable)]
end

# Get colour to draw each shape for (scenario, year, variable, comparison scenario, comparison year) -> (colours)
function mat_colour(scenario, year, variable, comparison_scenario, comparison_year)
    # TODO: palettes, normalisation, etc.

    # dims = 2 sums rows; dims = 1 sums cols
    sum(mat_data(scenario, year, variable) .- mat_data(comparison_scenario, comparison_year, variable), dims = 2)
end

route("/scenarios") do
    list_scenarios() |> json
end

route("/variables/:domain") do
    list_variables(@params(:domain)) |> json
end

route("/data/:domain/:scenario/:year/:variable") do
    if @params(:domain) == "od_matrices"
        mat_colour(@params(:scenario), parse(Int, @params(:year)), @params(:variable), "DoNothing", 2025) |> json
    else
        throw(DomainError(domain))
    end
end


route("/map") do
    # usage: /map?lat=100&lng=12 etc.
    # todo 
    # - set up babel so we can use modern JS and still work in old browsers
    # - port src/app/app.js functionality across
    # - move this to a separate file
    html("""
        <head>
        <meta charset='utf-8' />
        <title>Greener Connectivity Visualisation Tool</title>
        <meta name='viewport' content='initial-scale=1,maximum-scale=1,user-scalable=no' />
        <script src='https://api.tiles.mapbox.com/mapbox-gl-js/v1.5.0/mapbox-gl.js'></script>
        <link href='https://api.tiles.mapbox.com/mapbox-gl-js/v1.5.0/mapbox-gl.css' rel='stylesheet' />
        <style>
        body { margin:0; padding:0; }
        #map { position:absolute; top:0; bottom:0; width:100%; }
        .gcvt-ctrl { background-color: white; margin: 1rem; padding: 1rem; border-radius: 0.5rem; }
        </style>
        </head>
        <body>
         
        <div id='map'></div>
        <script>
            var queryString = new URLSearchParams(window.location.search);
            var lng = queryString.get("lng") || 32;
            var lat = queryString.get("lat") || 48;
            var zoom = queryString.get("z") || 4;
            mapboxgl.accessToken = '$MAPBOX_TOKEN';
            var map = new mapboxgl.Map({
                container: 'map', // container id
                style: 'mapbox://styles/mapbox/light-v10', // stylesheet location
                center: [lng, lat],
                zoom: zoom,
            });
            function moveUpdate(){
                var cent = map.getCenter();
                lnglat = new Map([
                    // Prettier URL at expense of accuracy
                    ["lng",cent.lng.toPrecision(5)],
                    ["lat",cent.lat.toPrecision(5)],
                ]);
                qsUpdate(lnglat);
            };
            function zoomUpdate(){
                qsUpdate(new Map([["z",map.getZoom().toPrecision(3)]]));
            };
            function qsUpdate(newkeys){
                var qs = new URLSearchParams(window.location.search);
                for (let e of newkeys.entries()) {
                    qs.set(e[0],e[1]);
                };
                history.pushState({},"","map?" + qs.toString());
            };

            // Mapbox IControl - buttons etc will go here
            class HelloWorldControl {
                onAdd(map) {
                    this._map = map;
                    this._container = document.createElement('div');
                    this._container.className = 'mapboxgl-ctrl';
                    this._container.innerHTML = `
                        <div class="gcvt-ctrl">
                        <h1> What do you want? </h1>
                        <select id="scenario_picker" onchange="gcvt_form_handler(this)">
                            // Might be easier to generate this in JS
                            // the "when do you want your proposal done by"
                            // part needs to ask server what years are possible
                            // so should probably just generate whole thing in JS
                            $(["<option value='$k'>$(get(v,"name",k))</option>" for (k, v) in metadata["scenarios"]] |> join)
                        </select>
                        </div>
                    `;
                    return this._container;
                }

                onRemove() {
                    this._container.parentNode.removeChild(this._container);
                    this._map = undefined;
                }
            }

            function gcvt_form_handler(element){
                console.log(element.selectedOptions[0].value);
                qsUpdate(new Map([["scen",element.selectedOptions[0].value]]));
            }
            map.addControl(new HelloWorldControl());
            map.on("moveend",moveUpdate);
            map.on("zoomend",zoomUpdate);
             
            // disable map rotation using right click + drag
            map.dragRotate.disable();
             
            // disable map rotation using touch rotation gesture
            map.touchZoomRotate.disableRotation();
        </script>
         
        </body>
    """)
end

Genie.AppServer.startup(parse(Int,get(ENV,"GENIE_PORT", "8000")),"0.0.0.0", async = false)

end
