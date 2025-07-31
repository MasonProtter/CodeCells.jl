# CodeCells.jl

CodeCells.jl is an attempt to combine REPL based workflows, 
[Revise.jl](https://github.com/timholy/Revise.jl), and some aspects of 
notebook workflows into a lightweight package without trying to take away 
your REPL or your preferred text editor.

The idea is simple, suppose you have a file `foo.jl` with contents
``` julia
using CodeCells, BenchmarkTools

@cell c1 begin
    x = 1
    z = x + 2
end

@cell c2 begin
    @benchmark 1 + z
end
```
if you run `includet("foo.jl")` in your REPL, the `@cell` macros will define functions `c1()` and `c2()` which will run the associated expressions in the global scope, and then paste the result of execution directly back into `foo.jl` right under the cell as a comment (the function also `return`s the result).

That means that if we executed `c1()`, our file would automatically change to

``` julia
using CodeCells, BenchmarkTools

@cell c1 begin
    x = 1
    z = x + 2
end
#==================================================
3
==================================================#

@cell c2 begin
    @benchmark 1 + z
end
```
and if we then executed `c2`, our file would be changed to

``` julia
using CodeCells, BenchmarkTools

@cell c1 begin
    x = 1
    z = x + 2
end
#==================================================
3
==================================================#

@cell c2 begin
    @benchmark 1 + z
end
#==================================================
BenchmarkTools.Trial: 10000 samples with 1000 evaluations per sample.
 Range (min … max):  3.566 ns … 78.002 ns  ┊ GC (min … max): 0.00% … 0.00%
 Time  (median):     3.577 ns              ┊ GC (median):    0.00%
 Time  (mean ± σ):   3.603 ns ±  0.925 ns  ┊ GC (mean ± σ):  0.00% ± 0.00%

    ▁                        ▃  █                          ▇ ▁
  ▄▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█▁▁█▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁█▁█ █
  3.57 ns      Histogram: log(frequency) by time     3.59 ns <

 Memory estimate: 0 bytes, allocs estimate: 0.
==================================================#
```

This makes it easy to refer back to the results of running a cell in an old notebook without re-running it, and it doesn't take away your REPL like Jupyter or Pluto. 

![video](assets/vid.gif)

### Notes

+ A `@cell` declaration should always be at the toplevel in a file, otherwise various mechanisms may
fail in surprising ways! You cannot even wrap one in a `begin / end` block.
+ CodeCells.jl does not depend on Revise.jl, but the recommended workflow for CodeCells.jl is to have Revise.jl loaded, and use `includet` to load and track a script containing your `@cell` definitions.
+ Since CodeCells edits your source file, make sure you set your editor to reload files upon changes so your view of the file doesn't get out of sync with the changes made by CodeCells
+ To customize the display of a given object (e.g. you may want to store a path to a plot or image), you can add methods to the `result_representation` function. See the docstring for more info, and the `ext/MakieExt.jl` and `ext/PlotsExt.jl` files for examples.
