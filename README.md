
<!-- README.md is generated from README.Rmd. Please edit that file -->

<!-- Generate with R -e 'rmarkdown::render("README.Rmd")' -->

# gcvt

Work in progress (imagine a web1.0 yellow roadwork sign here).

The goal of gcvt is to provide data and functions for visualising road
networks. Specifically it is focussed on the TEN-T European road
network.

## Installation

You can install gcvt from github with:

``` r
# install.packages("devtools")
devtools::install_github("IntegratedTransportPlanning/gcvt")
```

## Apps

This repo contains a number of shiny apps that view our data in
different ways. The two most developed are `combined_viewer_mapbox` and
`combined_viewer_leaflet`.

The leaflet version is currently less buggy. The mapbox version has link
offsetting (so you can see the direction of links).

To run the apps locally use:

``` r
shiny::runApp("R/combined_viewer_leaflet/")
```

### Mapbox app

The mapbox app requires some additional setup:

``` sh
cd src/app
yarn install
yarn run build
#> yarn install v1.16.0
#> [1/4] Resolving packages...
#> success Already up-to-date.
#> Done in 0.69s.
#> yarn run v1.16.0
#> $ parcel build app.js style.css --out-dir www --no-minify
#> ✨  Built in 1.17s.
#> 
#> www/links.35b0fdbf.geojson        ⚠️  44.72 MB    859ms
#> www/zones.b074afd0.geojson         ⚠️  9.75 MB    226ms
#> www/app.map                        1023.35 KB     87ms
#> www/app.js                          835.76 KB    686ms
#> www/blankstyle.71754c95.js            3.85 KB     59ms
#> www/blankstyle.71754c95.map           1.42 KB      8ms
#> www/style.css                           907 B     45ms
#> www/dummyline.c87acf73.geojson          239 B     66ms
#> Done in 1.81s.
```

I run the app like so, you can run it from rstudio if you prefer:

``` sh
R -e 'shiny::runApp(".", port=6619)'
```
