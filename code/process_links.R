library(sf)
library(rjson)

geoJAsset = 'data/sensitive/processed/cropped_links.geojson'
links = read_sf("data/sensitive/14-Nov/Base_links.shp", stringsAsFactors = T)
links = st_transform(links, 4326)

# Crop to study area
eapregion = st_union(read_sf("data/sensitive/eap_zones_only.geojson"))
intersection = unlist(st_intersects(eapregion, links))
links = links[intersection,]

# Remove points
links = links[grepl("LINESTRING", sapply(st_geometry(links), st_geometry_type)),]

# Load and crop metadata
scenarios = list(
#  base = read.csv("data/sensitive/final/Link_Base_2017.csv", stringsAsFactors = T),
    "Ecodrive (2025)" = read.csv("data/sensitive/14-Nov/Link_EcoDrive_2025.csv", stringsAsFactors = T),
    "Ecodrive (2030)" = read.csv("data/sensitive/14-Nov/Link_EcoDrive_2030.csv", stringsAsFactors = T),
#    "Fleet (2025)" = read.csv("data/sensitive/14-Nov/Link_Fleet_2025.csv", stringsAsFactors = T),
#    "Fleet (2030)" = read.csv("data/sensitive/14-Nov/Link_Fleet_2030.csv", stringsAsFactors = T),
#    "FleetElectric (2025)" = read.csv("data/sensitive/14-Nov/Link_FleetElectric_2025.csv", stringsAsFactors = T),
#    "FleetElectric (2030)" = read.csv("data/sensitive/14-Nov/Link_FleetElectric_2030.csv", stringsAsFactors = T),
#    "Urban (2025)" = read.csv("data/sensitive/14-Nov/Link_Urban_2025.csv", stringsAsFactors = T),
#    "Urban (2030)" = read.csv("data/sensitive/14-Nov/Link_Urban_2030.csv", stringsAsFactors = T),
#    "RailTimetable (2025)" = read.csv("data/sensitive/14-Nov/Link_RailTimeTable_2025.csv", stringsAsFactors = T),
#    "RailTimetable (2030)" = read.csv("data/sensitive/14-Nov/Link_RailTimeTable_2030.csv", stringsAsFactors = T),
#    "Tent (2030)" = read.csv("data/sensitive/14-Nov/Link_Tent_2030.csv", stringsAsFactors = T),
#    "BCP (2030)" = read.csv("data/sensitive/14-Nov/Link_BCP_2030.csv", stringsAsFactors = T),
#    "BCPRail (2025)" = read.csv("data/sensitive/14-Nov/Link_BCPRail_2025.csv", stringsAsFactors = T),
#    "BCPRail (2030)" = read.csv("data/sensitive/14-Nov/Link_BCPRail_2030.csv", stringsAsFactors = T),
#    "GreenPort (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenPort_2030.csv", stringsAsFactors = T),
#    "GreenMax (2025)" = read.csv("data/sensitive/14-Nov/Link_GreenMax_2025.csv", stringsAsFactors = T),
#    "GreenMax (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenMax_2030.csv", stringsAsFactors = T),
#    "GreenShipping (2030)" = read.csv("data/sensitive/14-Nov/Link_GreenShipping_2030.csv", stringsAsFactors = T),
#    "Logistic (2030)" = read.csv("data/sensitive/14-Nov/Link_Logistic_2030.csv", stringsAsFactors = T),
#    "NoBorder (2030)" = read.csv("data/sensitive/14-Nov/Link_NoBorder_2030.csv", stringsAsFactors = T),
#    "TenTRail (2030)" = read.csv("data/sensitive/14-Nov/Link_TentRail_2030.csv", stringsAsFactors = T),
#    "Toll (2030)" = read.csv("data/sensitive/14-Nov/Link_Toll_2030.csv", stringsAsFactors = T),
#    "AirEfficiency (2030)" = read.csv("data/sensitive/14-Nov/Link_AirEfficiency_2030.csv", stringsAsFactors = T),
#    "Do Nothing (2020)" = read.csv("data/sensitive/14-Nov/Link_Y2020_DoNothing_2020.csv", stringsAsFactors = T),
#    "Do Nothing (2025)" = read.csv("data/sensitive/14-Nov/Link_Y2025_DoNothing_2025.csv", stringsAsFactors = T),
#    "Do Nothing (2030)" = read.csv("data/sensitive/14-Nov/Link_Y2030_DoNothing_2030.csv", stringsAsFactors = T),
    "Do Minimum (2020)" = read.csv("data/sensitive/14-Nov/Link_Y2020_DoNothing_2020.csv", stringsAsFactors = T),
    "Do Minimum (2025)" = read.csv("data/sensitive/14-Nov/Link_Y2025_DoMin_2025.csv", stringsAsFactors = T),
    "Do Minimum (2030)" = read.csv("data/sensitive/14-Nov/Link_Y2030_DoMin_2030.csv", stringsAsFactors = T)
)
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Remove connectors from geometry
links = links[!grepl("Connect", scenarios[[1]]$LType),]

# Crop scenarios again to reduced geometry
scenarios = lapply(scenarios, function(meta) meta[match(links$ID_LINK, meta$Link_ID),])

# Drop unused LType levels.
scenarios = lapply(scenarios, function(meta) {meta$LType = droplevels(meta$LType); meta})

# There shouldn't be any rows containing NAs, but drop if there are
scenarios = lapply(scenarios, function(meta) {meta = meta[complete.cases(meta),] })

# Set an integer id for geom, and populate it
links$id = 0

## TODO this doesnt actually seem to be creating IDs as first thought. So where did they come from?!
write_sf(links, geoJAsset, layer_options="ID_TYPE=Integer", delete_dsn=TRUE)


# Load up what we just saved, to get IDs

# Get the IDs and the Link_IDs they map from 
geoj = fromJSON(file = geoJAsset)$features
linkid_mapping = c()

for (feat in 1:length(geoj)) {
    full = geoj[[feat]]$properties$ID_LINK
    tempid = geoj[[feat]]$id
    
    linkid_mapping[full] = tempid
}

# Load up each scenario, attach the feature id in the geojson, 
# and then make sure it is in that order. Bit hacky for now but faster
# than attaching IDs (which was too slow in UI)
for (scen in 1:length(scenarios)) {
    scenarios[[scen]]$featid = 0
    for (row in 1:nrow(scenarios[[scen]])) {
        featId = linkid_mapping[as.character(scenarios[[scen]][row,]$Link_ID)]
        scenarios[[scen]][row,]$featid = featId
    }
    scenarios[[scen]] = scenarios[[scen]][order(scenarios[[scen]]$featid),]
    print (paste("done scenario ", scen))
}


save(scenarios, file = "data/sensitive/processed/cropped_scenarios.RData")
