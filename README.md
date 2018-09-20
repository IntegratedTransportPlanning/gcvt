
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
cd R/combined_viewer_mapbox
npm install
npm run build
#> npm WARN optional SKIPPING OPTIONAL DEPENDENCY: fsevents@1.2.4 (node_modules/fsevents):
#> npm WARN notsup SKIPPING OPTIONAL DEPENDENCY: Unsupported platform for fsevents@1.2.4: wanted {"os":"darwin","arch":"any"} (current: {"os":"linux","arch":"x64"})
#> 
#> audited 8246 packages in 5.224s
#> found 0 vulnerabilities
#> 
#> 
#> > combined_viewer_mapbox@1.0.0 build /home/colin/projects/gcvt/R/combined_viewer_mapbox
#> > parcel build app.js style.css --out-dir www --no-minify
#> 
#> ✨  Built in 3.41s.
#> 
#> www/cropped_links.2ea4e8ce.geojson    ⚠️  45.05 MB    1.62s
#> www/zones.3d7caecc.geojson             ⚠️  9.75 MB    1.02s
#> www/app.map                             455.57 KB     76ms
#> www/app.js                              274.77 KB    3.05s
#> www/blankstyle.71754c95.js                3.85 KB    185ms
#> www/blankstyle.71754c95.map               1.42 KB      5ms
#> www/style.css                               954 B    370ms
```

I run the app like so, you can run it from rstudio if you prefer:

``` sh
R -e 'shiny::runApp(".", port=6619)'
```
