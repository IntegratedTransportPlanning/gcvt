const API_VERSION = "0.0.1"
const IN_PRODUCTION = false

PROJECTS_DIR = "/home/mark/julia/muxtesting"

include("parsemultipart.jl")


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
    filedata = readdir("/home/mark/julia/testproj")[rand(1:end)]
    println("Project is " * project * "; file is " * filename * "; ex file data from " * filedata)
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

    return jsonresp(0)
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
    route("/projects",  req -> jsonresp(get_projects())),
    Mux.notfound()
)

wait(serve(app, 2018))






















