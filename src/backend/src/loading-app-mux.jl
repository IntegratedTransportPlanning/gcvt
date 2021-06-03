const API_VERSION = "0.0.1"
const IN_PRODUCTION = false

PROJECTS_DIR = "data/projects"

using CSV
using DataFrames

import HTTP

# Lightly adapted from HTTP.parse_multipart_form
function parse_multipart_form(muxreq::Dict)
    # parse boundary from Content-Type
    m = match(r"multipart/form-data; boundary=(.*)$", first(Iterators.filter(p -> p.first == "Content-Type", muxreq[:headers])).second)
    m === nothing && return nothing

    boundary_delimiter = m[1]

    # [RFC2046 5.1.1](https://tools.ietf.org/html/rfc2046#section-5.1.1)
    length(boundary_delimiter) > 70 && error("boundary delimiter must not be greater than 70 characters")

    return HTTP.parse_multipart_body(muxreq[:data], boundary_delimiter)
end

# Get stringified version of form payload from a request
const formreq2data(req) = String(read(parse_multipart_form(req)[1].data))



function upload_od_file(req) #(project, file, uploadtype, filename)
    println(req)

    # That tempfile will need a better name...
    open(PROJECTS_DIR * "/tempfile.bin", "w") do f
        write(f, read(parse_multipart_form(req)[1].data))
    end
    
    return jsonresp(0)

    if occursin("/", project)
        # TODO this whole block is here just to remind me to ask someone about security!
        println("That doesn't look like a sensible project name")
        return
    end

    # Does project exist? 
    if project ∉ readdir(PROJECTS_DIR)
        # Project doesn't exist - create
        println("Project " * project * " doesn't exist, creating...")
        mkdir(PROJECTS_DIR * "/" * project)
        mkdir(PROJECTS_DIR * "/" * project * "/files")
        # TODO do we make the schema file... here? 
    end

    # Does file exist? 
    proj_files_loc = PROJECTS_DIR * "/" * project * "/files"

    if filename ∉ readdir(proj_files_loc)
        # TODO take 'file' and put it in dir, having processed
        println("Copying to " * proj_files_loc * "/" * filename) 
        cp("/home/mark/julia/testproj/" * filedata, proj_files_loc * "/" * filename)
    else 
        # TODO is there anything different about overwriting? maybe include a warning eventually? 
        println("** Overwriting at " * proj_files_loc * "/" * filename)
        cp("/home/mark/julia/testproj/" * filedata, proj_files_loc * "/" * filename)
    end  

    # Supported formats
    # OD data: CSV, TXT, (xls... one day). Any of those zipped might be useful too.

    # Probably better to actually look at the file, but...
    if sum(endswith.(filename, [".csv",".txt"])) == 0
        return failed
    end

    # Zone id column defaults: 
    orig = "orig"
    dest = "dest"

    # Get zone columns from form data (plus whatever)
    # TODO 
    
    # Check that orig, dest are in the file
    if orig ∉  colnames || dest ∉ colnames
        return failed
    end


    # Write info to the schema, which we may need to create
    # What does it look like if it's created? 
    # What does it look like if it exists? 
    
    # Return something to the UI - success / fail 

    return jsonresp(0)
end

function upload_geom_file()
    #  - Geometries: shapefile, geojson
end


function headers(project, filename, separator = "_")
    proj_files_loc = PROJECTS_DIR * "/" * project * "/files"

    ## Testing junk
    proj_files_loc = "/home/mark/gcvt/src/backend/data/raw"
    filename = "PCT example data commute-msoa-nottinghamshire-od_attributes.csv"
    ##

    # Wait, should this have been done already, and saved in the schema?     
    df = CSV.read(proj_files_loc * "/" * filename, DataFrame; missingstring="")

    # TODO tricky bit here: the PCT dataset had underscores in its zone ID column names. 
    # If we know them by this point, we can just filter them out before getting header 'chunks'.
    # But in Colin's design I can't remember when the user tells wizard about a zone id columns
    chunks = unique(reduce(vcat, split.(names(df), separator)))

    return chunks
end



function get_projects()
    return readdir(PROJECTS_DIR)
end

# APP

using Mux
using JSON3


jsonresp(obj; headers = Dict()) = Dict(:body => String(JSON3.write(obj)), :headers => merge(Dict(
    "Content-Type" => "application/json",
    "Cache-Control" => IN_PRODUCTION ? "public, max-age=$(365 * 24 * 60 * 60)" : "max-age=0", # cache for a year (max recommended). Change API_VERSION to invalidate
), headers))

# Will status() work like this? let's see...
# TODO that'd be a no.... 
# failed = jsonresp("Processing error", status(400))   

@app app = (
    Mux.defaults,
    page("/", req -> jsonresp(42)), # some kind of debug page or API help page
    route("/version", req -> jsonresp(
        Dict("version" => API_VERSION);
        headers = Dict(
            "Cache-Control" => "max-age=0",
        )
    )),
    route("/oddata", req -> upload_od_file(req)),
    route("/geometry", req -> upload_geom_file(req)),
    route("/headers", req -> jsonresp(headers)),
    route("/projects",  req -> jsonresp(get_projects())),
    Mux.notfound()
)

wait(serve(app, 2018))






















