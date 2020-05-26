# Greener Connectivity Visualisation Tool

🚧 👷‍♀️ Work in progress 👷 🚧

The goal of the GCVT is to visualise and compare transport model outputs under different scenarios.


## Installation

This project primarily uses two programming languages: Julia and JavaScript.

Some vestiges of R code remain and may be required for preparing your data for the visualisation tool (or you could prepare your data in a compatible way with some other language).

To install material other than R:

```sh
# install julia v1.x
# install yarn
# install caddy (or some other webserver)

# install Julia and JS dependencies
make setup

# move your scenario pack data to src/backend/data

# make tiles if you haven't yet done so
# tippecanoe and mbutil are what I use and a convenience script is provided in
# src/data-preparation/tiles.sh

# Run the development server:
make front &
make back &

# Access the map at http://localhost:2016
```

Docker - recommended for deployment:

```sh
# Ensure you have yarn and docker-compose installed and on your path
# Ensure processed data is in correct directory (e.g. ./src/backed/update_data.sh)

# Build frontend (see issue #80)
cd src/frontend/
yarn install
yarn run build

# Launch all services (will take a while)
cd ..
sudo docker-compose up --build

# Migrating WordPress installation is slightly tricky - see src/notes.md
```
