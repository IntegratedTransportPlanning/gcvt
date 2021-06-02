const API_VERSION = "0.0.1"
const IN_PRODUCTION = false

PROJECTS_DIR = "projects"

using CSV
using DataFrames


function upload_file(req) #(project, file, uploadtype, filename)
    ## TODO nightmare getting multipart form parsing working
    # 
    # HTTP.parse_multipart_form() 
    #       - seems to expect a proper Request or something other than the Vector of bytes that Mux provides
    # Solution from https://discourse.julialang.org/t/http-multipart-form-data-processing-by-server/24076/6 - which uses an older version
    #       of the above doesn't work - seems to not find any data at all, even though we know it's there. 
    # HTTP.Multipart seems to be for creating forms for sending (tho no real docs) 
    # 
    # ...so gotta make our own? Does the UI really even need to use a FormData() ?
    
    # in the meantime...
    project = ["project_one","project_2","project_3","project_4"][rand(1:end)]
    filename = ["oddata.csv","blah.tab","foo.xls"][rand(1:end)]
    # projects/junk-data can be deleted as soon as we get multipart working
    filedata = readdir("projects/junk-data")[rand(1:end)]
    println("Project is " * project * "; file is " * filename * "; (rubbish) file data from " * filedata)
    ##############################

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

    # TODO list

    # What formats are supported? 
    #  - OD data: CSV, TXT, (xls... one day). 
    #  - Geometries: shapefile, geojson
    #  - Anything else - fails.  
    # What are the zone id columns? Defaults to orig / dest
    # Branching to handle the two different types of files here
    # Write info to the schema, which we may need to create
    # Return something to the UI - success / fail 

    return jsonresp(0)
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

   

@app app = (
    Mux.defaults,
    page("/", req -> jsonresp(42)), # some kind of debug page or API help page
    route("/version", req -> jsonresp(
        Dict("version" => API_VERSION);
        headers = Dict(
            "Cache-Control" => "max-age=0",
        )
    )),
    route("/oddata", req -> upload_file(req)),
    route("/headers", req -> jsonresp(headers)
    route("/projects",  req -> jsonresp(get_projects())),
    Mux.notfound()
)

wait(serve(app, 2018))






















