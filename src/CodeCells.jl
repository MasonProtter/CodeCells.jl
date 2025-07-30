module CodeCells

using Revise

macro public(names::Symbol...)
    if VERSION >= v"1.11.0-DEV.469"
        esc(Expr(:public, names...))
    end
end

export @cell, includet
@public result_representation

"""
     @cell name expr

Create a function `name()` which `eval`s `expr` into the global scope, and if in a file,
will paste the result of evaluating `expr` into a comment directly below the `@cell`
definition. See `result_representation` for information on customizing how a result will be pasted into the file.

This macro hooks into [Revise.jl](https://github.com/timholy/Revise.jl) to
automatically update the `LineNumberNode`s in a `@cell` every time the file the
`@cell` definition is in changes.
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
    asset_path = joinpath(dirname(file),
                          ".codecells_assets",
                          splitext(file)[1] * "_" * String(name))
    result_source_insertion = if !isnothing(file)
        quote
            $result_str = $result_representation($result, $asset_path)
            $insert_output($line, $file, $result_str)
        end
    else
        @debug "Code cell $name run in a file that doesn't exist. Result insertion will be skipped."
    end
    ex = quote
        $add_force_revise_callback($file, $__module__)
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


#===============
Revise stuff
===============#
const revision_keys = Dict{String, Symbol}()

function add_force_revise_callback(file::AbstractString, mod::Module)
    key = get!(revision_keys, file) do
        gensym(file)
    end
    Revise.add_callback((file,); key) do
        force_revise_cells(file, mod)
    end
end
add_force_revise_callback(::Nothing, ::Module) = nothing

function force_revise_cells(file::AbstractString, mod::Module)
    for (mod, exsigs) in Revise.parse_source(file, mod)
        for def in keys(exsigs)
            ex = def.ex
            exuw = Revise.unwrap(ex)
            if Base.isexpr(exuw, :macrocall) && exuw.args[1] == Symbol("@cell")
                Core.eval(mod, ex)
            end
        end
    end
end

end # module CodeCells
