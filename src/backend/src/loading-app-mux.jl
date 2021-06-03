const API_VERSION = "0.0.1"
const IN_PRODUCTION = false

PROJECTS_DIR = "data/projects"

using CSV
using DataFrames
using Dates

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

# Get form payload from a request
## TODO we probably need to be able to read binary (eg. zip files for large OD data) 
const formreq2data(req, pos) = String(read(parse_multipart_form(req)[pos].data))

function upload_od_file(req) 
    temp_file = PROJECTS_DIR * "/Uploaded file - " * Dates.format(now(), "dd u yyyy HH:MM:SS")
    open(temp_file, "w") do f
        write(f, formreq2data(req,1))
    end
    
    project = formreq2data(req, 2) 
    filename = formreq2data(req, 3)

    println("Project is " * project * " and filename is " * filename)

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

    println("Copying to " * proj_files_loc * "/" * filename)

    if filename in readdir(proj_files_loc)
        # Just warn or something if we already have this file 
        println("** Overwriting at " * proj_files_loc * "/" * filename)
    end  

    cp(temp_file, proj_files_loc * "/" * filename, force=true) 

    # Supported formats
    # OD data: CSV, TXT, (xls... one day). Any of those zipped might be useful too.

    # Probably better to actually look at the file, but...
    if sum(endswith.(filename, [".csv",".txt"])) == 0
        #return failed
    end

    # Zone id column defaults: 
    orig = "orig"
    dest = "dest"

    # Get zone columns from form data (plus whatever)
    ## TODO the messy design of the frontend needs tidying up/sanitising per what CC/MD discussed,
    ## at moment the file info is stored in state but not schema (or wait... is that ok?)
    orig = formreq2data(req, 4) 
    dest = formreq2data(req, 5)

    println("Orig and dest are " * orig * ", " * dest)
    colnames = []

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

# Better ideas welcome...
failed = jsonresp(-1) # respond(Response(400, "Processing error")) 

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






















