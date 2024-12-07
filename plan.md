# Green Connectivity tool but de-prototyped

## Layout

App might just expect a single pack, but project contains code for processing, etc.

```
data/

   raw/
      # The various unclean geometries, etc we get given should go here.
      # This directory is only referenced from src/data-prep/examples/

   packs/
      GCVT_Scenario_Pack/
         geometry/
            # For gpkg read: gpkg|shp|geojson

            zones.gpkg
               # Each zone should have a name, and a border ID (contained-in this group)
            links.gpkg
               # Each link must have an ID.
            borders.gpkg
               # Each border should have a name
            points-of-interest.gpkg
               # PoIs need data yet to be determined. Probably name and type
            link-crop-mask.gpkg
               # Possibly...

         meta.yaml
         scenarios/
            GreenMax/
               links/
                  2025.csv
                  2030.csv
               od_matrices/
                  2025.csv
                  2030.csv
               zones/
                  2025.csv
                  2030.csv

   processed/

      # App only knows about this format.
      # We provide code to convert packs to this format.

      GCVT_Scenario_Pack/
         meta.yaml
         scenarios.Rds
         geometry/
            links/
               tiles/
            zones/
               tiles/
               centroids.Rds # Possibly.
            # Don't know how borders and PoI will be distributed. Possibly just
            # (compressed) geojson. Possibly also tiles.

Makefile
   # Rules for generating processed dir; running app locally; deploying to remote (maybe)
   # and possibly for installing dependencies, generating binaries, containers, etc.

src/

   data-preparation/
      # Generic functions for generating data/processed directory
      # These 1) sanity check csvs and geometries; 2) crop link data to study region; 3) create matrices; 4) binary pack all the data; 5) (todo) drop any variables not mentioned in yaml.

      examples/
         # Functions and scripts used to tidy up the GCVT datasets that others may want to adapt to their own needs.

   app/
      front/
         # Web project here
         # Manage with yarn and parcel, I think.
      back/
         # Julia, Python or R project here

   # Various guff for deployment (containers, caddyfiles, etc goes somewhere around here)
```

## Questions

- Who is responsible for cropping link data, etc to the study region?
   - At the moment, we crop `links.shp` in `process_pack_dir` to `eap_zones_only.geojson`, which is probably some geometry I created.
   - We also filter the scenario data to the link geometry

   - In future:
      - We will crop links if a crop mask is provided.
      - We will filter model outputs.

## TODO

- Make `process_pack_dir` sane
   - Restrict inputs to the referenced pack dir; outputs to referenced processed dir
   - Rename it to something like what it actually does
   - Split it up a bit better
   - At the moment, the scenarios or links it generates are wrong somehow (probably the IDs don't match up or something), so fix that for sure.

- Write script to generate tiles with tippecanoe/mb-util
   - This depends on process_pack_dir producing links.geojson

- Make apps sane
   - Restrict input to pack dir

- Tidying up
   - Remove the rest of the data and code that you think is probably irrelevant now.

- Rewrite the backend in sanic + pandas or Julia + Genie + Query.jl or R + plumber

- Rewrite the frontend in mithriljs
