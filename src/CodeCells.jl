module CodeCells

using FileWatching: FileWatching, FileMonitor
using Base: isexpr

macro var"public"(names::Symbol...)
    if VERSION >= v"1.11.0-DEV.469"
        esc(Expr(:public, names...))
    end
end

export @cell
@public result_representation track_file untrack_file

"""
     @cell name expr

Create a function `name()` which `eval`s `expr` into the global scope, and if in a file,
will paste the result of evaluating `expr` into a comment directly below the `@cell`
definition. See `result_representation` for information on customizing how a result will
be pasted into the file.

A `@cell` declaration should always be at the toplevel in a file, otherwise various mechanisms may
fail in surprising ways! You cannot even wrap one in a `begin / end` block.

This macro will call `CodeCells.track_file` with the relevant `file` and `module` of the `@cell`
location when the cell is created. To stop the tracking, call `CodeCells.untrack_file` on the file
the `@cell` came from. This tracking is necessary to make sure that comments end up in the right
location when a `@cell` is moved within a file, something `Revise.jl` does not automatically do.
"""
macro cell(name, body)
    if Base.isexpr(body, :block)
        body.head = :toplevel
    end
    @gensym result result_str
    file = String(__source__.file)
    line = __source__.line
    if !isfile(file)
        file == nothing
    end
    fname = splitext(splitpath(file)[end])[1]
    asset_path = joinpath(dirname(file), ".codecells_assets", fname * "_" * String(name))

    result_source_insertion = if !isnothing(file)
        quote
            $result_str = $result_representation($result, $asset_path)
            $insert_output($line, $file, $result_str)
        end
    else
        @debug "Code cell $name run in a file that doesn't exist. Result insertion will be skipped."
    end
    ex = quote
        $isempty($Base.@locals) || $Base.@warn "Code cell run in a local scope, this will probably not work correctly!"
        $track_file($file, $__module__)
        function $name()
            $result = $CodeCells.@eval $__module__ $body
            $result_source_insertion
            $result
        end
    end
    esc(ex)
end

"""
     result_representation(result::T, asset_path::String) :: String

Convert the result of a code cell evaluation to a string that can be spliced into
the source code as a comment below the cell to record its output. By default, this
just constructs the `text/plain` repr of `result`, but methods can be added to handle
more exotic result types.

For results that have no useful textual representation, the `asset_path` argument
gives a suggested path where results such as plots can be stored (simply append
whatever desired file extension to the path). If you store a result in an asset path,
then output string should be of the form

    "[[\$asset_path * \$desired_extension]]"

e.g. if `asset_path` was `/home/user/some/dir/.codecells_assets/foo_c1`, and you store
a `.png` file, then the output should be

    "[[/home/user/some/dir/.codecells_assets/foo_c1.png]]"

so that the user can easily navigate to the file from the comment.
"""
function result_representation end

"""
    track_file(file::String, mod::Module=Main)

Tell CodeCells to keep track of the `@cell` definitions in `file`, and re-eval them into
`mod` each time the file changes. This is automatically called whenever a `@cell` is created
using the appropriate file and module, so it shouldn't be necessary for users to interact 
with.
"""
function track_file(file::String, mod::Module=Main)
    if file ∉ keys(tracked_files)
        tracked_files[file] = read(file, String)
        fm = FileMonitor(file)
        Threads.@spawn while haskey(tracked_files, file)
            wait(fm)
            if isfile(file)
                try
                    file_rep = read(file, String)
                    if file_rep != tracked_files[file]
                        Base.include(mod, file) do expr
                            if isexpr(expr, :macrocall) && expr.args[1] == Symbol("@cell")
                                expr
                            else
                                nothing
                            end
                        end
                        tracked_files[file] = file_rep
                    end
                catch e;
                    @warn "" e
                end
            else
                # Sometimes I was getting weird stuff where it'd claim the file doesn't exist, probably
                # because I was in the process of overwriting it. Just try and wait it out.
                sleep(0.1)
            end
        end
    end
end

"""
    untrack_file(file::String)

Tell CodeCells to stop tracking and updating a file. If this file has `@cell`s in it, running them after
disabling tracking may result in comments being written to unpredictable places in the file. 
"""
untrack_file(file::String) = delete!(tracked_files, file)

const tracked_files = Dict{String, String}()

function result_representation(result, asset_path)
    context = IOContext(IOBuffer(), :limit => true, :color => false)
    repr("text/plain", result; context)
end

function line_to_codeunit(content::String, line_number::Int)
    line_number == 1 &&  return 1
    
    codeunit_index = 1
    current_line = 1

    for c ∈ codeunits(content)
        if current_line == line_number
            return codeunit_index
        end
        if c == UInt8('\n')
            current_line += 1
        end
        codeunit_index += 1
    end
    # If we've reached the end and haven't found the line,
    # it means the line number is beyond the file length
    error("Line $line_number exceeds file length (file has $(current_line - 1) lines)")
end

const cell_prefix = "#==================================================\n"
const cell_suffix = "==================================================#\n"

function find_index_after_output(str::AbstractString, idx_after_cell)
    idx_after = idx_after_cell
    cnts = codeunits(str)
    if startswith(str, cell_prefix)
        nc = ncodeunits(str)
        for i ∈ 1:ncodeunits(str)-length(cell_suffix)+1
            if @view(cnts[i:i+(length(cell_suffix))-1]) == codeunits(cell_suffix)
                return idx_after + length(cell_suffix)
            end
            idx_after += 1
        end
    end
    idx_after
end

function insert_output(line, file, result_str)
    content = read(file, String)
    idx_before_cell = line_to_codeunit(content, line)
    ex, idx_after_cell = Meta.parse(content, idx_before_cell)
    
    after_content = @view content[idx_after_cell:end]
    idx_after_output = find_index_after_output(after_content, idx_after_cell)
    
    new_content = (@view(content[1:idx_after_cell-1])
                   * cell_prefix
                   * result_str
                   * '\n' * cell_suffix
                   * @view(content[idx_after_output:end]))
    open(String(file), "w+") do io
        write(io, new_content)
    end
end


end # module CodeCells
