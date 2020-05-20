# Functions for processing meta.yaml

library(yaml)
library(tidyverse)
library(fs)

get_metadata = function(pack_dir) {
  read_yaml(path(pack_dir, "meta.yaml"))
}

# Get aliases: DF(name, alias, description); so you can left_join it with the scenarios table.
# Give it meta$scenarios or meta$links$columns
#
# This oneliner does something similar:
#   lapply(meta$scenarios, data.frame, stringsAsFactors=F) %>% bind_rows() %>% as.tibble() %>% rename(alias=name)
#
get_aliases = function(meta) {
  aliases = tibble(name=character(), alias=character(), description=character())
  naifnull = function(x) if (is.null(x)) NA else x
  for (id in names(meta)) {
    alias = naifnull(meta[[id]]$name)
    description = naifnull(meta[[id]]$description)
    aliases[nrow(aliases)+1,] = list(id, alias, description)
  }
  aliases
}
