
<!-- README.md is generated from README.Rmd. Please edit that file -->

<!-- Generate with R -e 'rmarkdown::render("README.Rmd")' -->

# gcvt

The goal of gcvt is to provide data and functions for visualising road
networks. Specifically it is focussed on the TEN-T European road
network.

## Installation

You can install gcvt from github with:

``` r
# install.packages("devtools")
devtools::install_github("IntegratedTransportPlanning/gcvt")
```

## Combined app

There are various components of the tool. A combined tool can be run as
follows, after the package has been installed:

``` r
shiny::runApp("R/combined/")
```

## Mapbox app

Setup:

``` sh
cd R/combined_viewer_mapbox
npm install
npm run build
```

Run the app:

``` sh
R -e 'shiny::runApp(".", port=6619)'
```
