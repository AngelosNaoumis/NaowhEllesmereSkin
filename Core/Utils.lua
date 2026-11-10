local _, NS = ...

local Utils = {}
NS.Utils = Utils

function Utils.Rgb(r, g, b)
    return { r = r, g = g, b = b }
end

function Utils.Blend(base, over, alpha)
    return Utils.Rgb(
        base.r + (over.r - base.r) * alpha,
        base.g + (over.g - base.g) * alpha,
        base.b + (over.b - base.b) * alpha
    )
end

function Utils.IsAccessibleFrame(frame)
    if not frame then return false end
    return not (frame.IsForbidden and frame:IsForbidden())
end
