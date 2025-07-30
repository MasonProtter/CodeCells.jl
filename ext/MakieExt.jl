module MakieExt

using CodeCells: CodeCells
using Makie: FigureAxisPlot, save

function CodeCells.result_representation(fig::FigureAxisPlot, _asset_path)
    asset_path = _asset_path * ".png"
    mkpath(dirname(asset_path))
    save(asset_path, fig)
    "[[" * asset_path * "]]"
end

end
