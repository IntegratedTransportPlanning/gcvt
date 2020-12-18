# Architecture for GCVT

December 2020

## Introduction

This is a description of the current (end of phase 2) architecture and data flow for the tool.
It's not a specification for what the architecture should be.

I'm going to describe software components as if they were functions in a kind of pseudo code.

```
gcvt(data, metadata, geometry) -> Interactive map
```

Should be read as "There is component `gcvt` which depends on `data`, `metadata`, `geometry` and produces an interactive map".
This isn't to say the `gcvt` is actually a function in the code (it's not), it's just a name I'm using for some component of the system.

## Top Level

```
gcvt(data, metadata, geometry) -> Interactive map
```

Where:
`data` is all of the CSVs describing link and OD flow attributes;
`metadata` is information on scenario names, styling, etc. from `metadata.yaml`;
`geometry` is the shapefile describing the links and the geojson of the zones.

Breaking `gcvt` down, it is composed of two parts:

```julia
function gcvt(data, metadata, geometry)
    # The server that we run on a cloud VPS
    # Responsible for serving the vector tiles, the client code,
    # the data needed to style the maps, and a wordpress server
    server = gcvt_server(data, metadata, geometry)

    # The front-end that users run in their browser
    # Responsible for displaying the map and menus and responding to user
    # input.
    gcvt_client(server)
end
```


## Server-side

```
gcvt_server(data, metadata, geometry) -> HTTPServer
```

Breaking `gcvt_server` down, we can see that it looks something like this:

```julia
function gcvt_server_side(data, metadata, geometry)
    # Validate and process the raw CSVs, etc. into a compact format.
    # Also apply GCVT-specific data-cleaning and transformations.
    new_data, new_geometry = pre_process(data, metadata, geometry)

    # Generate two directories of vector tiles, one for links, one for zones.
    vector_tile_dir = generate_tiles(new_geometry)

    # Start some web servers and route requests to them based on the path.
    app = webserver("/tiles/" => fileserve(vector_tile_dir),
                    "/map/" => fileserve(FRONTEND_FILES_DIR),
                    "/api/" => api_server(new_data, metadata, new_geometry.zones),
                    "/" => wordpress())

    return app
end
```

Which seems simple enough, so let's go through the components within that.


### Web stuff



```
fileserve(dir) -> HTTPServer
```

Serve the static files in `dir` over HTTP.
This is handled by `caddy` in the development cycle and by an `nginx` Docker container in production.


```
webserver(route1 => server1, route2 => server2, ...) -> HTTPServer
```

A HTTP server that proxies each request it receives to another server based on the path in the request.
This is handled by `caddy` in the development cycle and by a `traefix` Docker-compose config in production.


```
wordpress() -> HTTPServer
```

Serve the wordpress site over HTTP (this is it's own self-contained thing, mostly).
It depends on its own database and filestore, but I won't detail them because it's all standard wordpress stuff.
This is only present when running with `docker-compose`.


### Pre-processing

```
pre_process(data, metadata, geometry)
```

Validate and process the raw CSVs, etc. into a compact format
and apply GCVT-specific data-cleaning and transformations:

 - Validate CSVs have the right shape (column names and types, IDs match geometry, etc)
 - Save data into a compact binary form

These two are GCVT specific:

 - Crop the link data and geometry to the study area
 - Fix some data columns

It corresponds to the `pack` rule in the `Makefile`.

The only remaining R code is here.


```
generate_tiles(geometry) -> tile directory
```

Generate vector tiles from geometry and save them into a directory.
This corresponds to the `tiles` rule in the `Makefile`.


### "The backend"

```
api_server(data, metadata, zone_geometry) -> HTTPServer
```

The Julia server that provides:

- the data that the javascript front end needs to display the menus and info
- the data that the javascript front end needs to style the map
- an oembed endpoint for wordpress
- time-series plots from the data

We don't want to do all the maths client-side because:

- we can send much less data to the client this way
- some of these computations are expensive and we can do them more efficiently
  in Julia and can cache results on the server
- Julia is much nicer to write than javascript

In more detail:

```julia
function api_server(data, metadata, zone_geometry)
    # Query the shape of the data
    route("/variables/links", metadata.links.columns)
    route("/variables/od_matrices", metadata.od_matrices.columns)
    # List of scenarios and which years they are active (which years we have
    # data for that scenario)
    route("/scenarios", list_scenarions(data, metadata))

    # Data is partitioned by "domain": links or od_matrices.

    # Compute and return quantiles for the specified variable in a domain
    #
    # Returns two numbers: the upper and lower quantiles.
    route("/stats", req -> compute_quantiles(req))

    # Get data for a specified (domain, variable, scenario, year)
    # Or, the comparison between two specified (domain, variable, scenario, year).
    # Or, the percentage comparison
    #
    # Returns a long vector of values, usually floating point numbers, one
    # value for each link or zone in the domain.
    route("/stats", req -> compute_quantiles(req))

    # Return the centroids for each zone
    #
    # The JS frontend uses these to construct the flow lines.
    route("/centroids", centroids(zone_geometry))

    # Return HTML for an oembed of the map (for embedding nicely in wordpress and other places)
    route("/oembed", req -> oembed(req))

    # Return HTML for a time-series chart about one or more scenarios, or a
    # or a single link, or the selected zone(s)
    route("/charts", req -> chart(req))
end
```


### The frontend

(TODO)
