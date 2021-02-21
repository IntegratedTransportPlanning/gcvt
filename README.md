# ODVis (working title)

🚧 👷‍♀️ Work in progress 👷 🚧

The goal of ODVis is to visualise origin-destination matrices from transport models or survey data.


## Installation

This project primarily uses two programming languages: Julia and JavaScript.

```sh
# install julia v1.x
# install yarn
# install caddy (or some other webserver)

# install Julia and JS dependencies
make setup

# move your scenario pack data to src/backend/data

# make tiles if you haven't yet done so
make tiles

# If in production:
    # Transpile the JS
    make front

    # Run the production server:
    make back &
    make http &

# Else if in development

    caddy&
    cd src/frontend && yarn run watch&
    cd src/backend/src && julia --project -L app-mux.jl -E 'wait(serve(app, 2017))'&

# Access the map at http://localhost:2016
```
