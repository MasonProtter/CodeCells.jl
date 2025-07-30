module PlotsExt

using CodeCells: CodeCells
using Plots: Plots, savefig, Plot

function CodeCells.result_representation(fig::Plot, _asset_path)
    asset_path = _asset_path * ".png"
    mkpath(dirname(asset_path))
    savefig(fig, asset_path)
    "[[" * asset_path * "]]"
end

end
