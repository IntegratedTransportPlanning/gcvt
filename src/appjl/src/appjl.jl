#= using Genie =#

module tmp

import Genie
import Genie.Router: route

# This converts its argument to json and sets the appropriate headers for content type
import Genie.Renderer: json

Genie.config.session_auto_start = false

route("/") do
  (:message => "Hi there!") |> json
end


### APP ###

# Get list of scenarios (scenario name, id, years active)

# Get list of variables (type (od, link, zone))

# Get colour to draw each shape for (scenario, year, variable, comparison scenario, comparison year) -> (colours)

Genie.AppServer.startup(async = false)

end
