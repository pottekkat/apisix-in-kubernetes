-- some required functionalities are provided by apisix.core
local core = require("apisix.core")

-- define the schema for the Plugin
local schema = {
    type = "object",
    properties = {
        body = {
            description = "custom response to replace the Upstream response with.",
            type = "string"
        },
    },
    required = {"body"},
}

local plugin_name = "custom-response"

-- custom Plugins usually have priority between 1 and 99
-- higher number = higher priority
local _M = {
    version = 0.1,
    priority = 23,
    name = plugin_name,
    schema = schema,
}

-- verify the specification
function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end

-- run the Plugin in the access phase of the OpenResty lifecycle
function _M.access(conf, ctx)
    return 200, conf.body
end

return _M
