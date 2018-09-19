
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
```

I run the app like so, you can run it from rstudio if you prefer:

``` sh
R -e 'shiny::runApp(".", port=6619)'
```
