
--
-- lua-Spore : <https://fperrad.frama.io/lua-Spore>
--

local decode = require'dkjson'.decode
local assert = assert
local pairs = pairs
local tonumber = tonumber
local char = string.char
local find = string.find
local match = string.match
local gmatch = string.gmatch
local gsub = string.gsub
local sub = string.sub
local upper = string.upper
local Spore = require'Spore'
local checktype = require'Spore'.checktype
local new_from_lua = require'Spore'.new_from_lua
local slurp = require'Spore.Protocols'.slurp

local _ENV = nil
local m = {}

m.spore = '1.1'

local function convert_uri_template (uri)
    -- see RFC 6570
    return (gsub(uri, '{([%w_]+)}', ':%1'))
end

local ops = {
    get = true,
    put = true,
    post = true,
    delete = true,
    options = true,
    head = true,
    patch = true,
    trace = true,
}

local function convert2 (doc, tag)
    local spore = {
        name = doc.info.title,
        description = doc.info.description,
        version = doc.info.version,
        methods = {},
        authentication = doc.security and true or nil,
    }
    if tag and doc.tags then
        for i = 1, #doc.tags do
            local item = doc.tags[i]
            if item.name == tag then
                spore.description = item.description or spore.description
                break
            end
        end
    end
    if doc.host and doc.basePath and doc.schemes and doc.schemes[1] then
        spore.base_url = doc.schemes[1] .. '://' .. doc.host .. doc.basePath
    end

    local function populate (paths)
        for path, methods in pairs(paths) do
            for op, meth in pairs(methods) do
                if ops[op] then
                    local found
                    if tag and meth.tags then
                        for i = 1, #meth.tags do
                            if tag == meth.tags[i] then
                                found = true
                                break
                            end
                        end
                    end
                    if found or not tag then
                        local required_payload, optional_payload
                        local required_params, optional_params
                        local headers, form_data

                        local function aggregate_param (param)
                            if param['in'] == 'body' then
                                if param.required then
                                    required_payload = true
                                else
                                    optional_payload = true
                                end
                            else
                                local name = assert(param.name)
                                if param.required then
                                    if not required_params then
                                        required_params = {}
                                    end
                                    required_params[#required_params+1] = name
                                else
                                    if not optional_params then
                                        optional_params = {}
                                    end
                                    optional_params[#optional_params+1] = name
                                end
                                if     param['in'] == 'header' then
                                    if not headers then
                                        headers = {}
                                    end
                                    headers[name] = ':' .. name
                                elseif param['in'] == 'formData' then
                                    if not form_data then
                                        form_data = {}
                                    end
                                    form_data[name] = ':' .. name
                                end
                            end
                        end  -- aggregate_param

                        if methods.parameters then
                            for i = 1, #methods.parameters do
                                aggregate_param(methods.parameters[i])
                            end
                        end
                        if meth.parameters then
                            for i = 1, #meth.parameters do
                                aggregate_param(meth.parameters[i])
                            end
                        end

                        local expected_status
                        if not meth.responses.default then
                            expected_status = {}
                            for status in pairs(meth.responses) do
                                expected_status[#expected_status+1] = tonumber(status)
                            end
                        end

                        spore.methods[meth.operationId] = {
                            method = upper(op),
                            path = (m.spore == '1.0') and convert_uri_template(path) or path,
                            headers = headers,
                            ['form-data'] = form_data,
                            required_params = required_params,
                            optional_params = optional_params,
                            required_payload = required_payload,
                            optional_payload = optional_payload,
                            expected_status = expected_status,
                            deprecated = meth.deprecated,
                            authentication = meth.security and true or nil,
                            description = meth.summary or meth.description,
                        }
                    end
                end
            end
        end
    end  -- populate

    populate(doc.paths)
    return spore
end

local function split_ref (s)
    local pos = find(s, '#', 1, true)
    if pos then
        if pos == 1 then
            return nil, sub(s, 2)
        else
            return sub(s, 1, pos - 1), sub(s, pos + 1)
        end
    else
        return s, ''
    end
end

local function get_rfc6901 (doc, ptr)
    if ptr ~= '' then
        if not match(ptr, '^/') then  -- must start with /'
            return nil, 'invalid pointer'
        end
        if match(ptr, '~[^01]') then
            return nil, 'invalid escape'
        end
        for tok in gmatch(ptr, '/([^/]*)') do
            tok = gsub(tok, '~1', '/')
            tok = gsub(tok, '~0', '~')
            if (tok == '0' or match(tok, '^[1-9][0-9]*$')) and not doc[tok] then
                tok = 1 + tonumber(tok)
            end
            if tok == '-' and #doc > 0 then
                doc = doc[#doc]
            else
                doc = doc[tok]
            end
            if doc == nil then
                return nil, 'not found'
            end
        end
    end
    return doc
end

local function convert3 (doc, tag)
    local spore = {
        name = doc.info.title,
        description = doc.info.description,
        version = doc.info.version,
        methods = {},
        authentication = doc.security and true or nil,
    }
    if tag and doc.tags then
        for i = 1, #doc.tags do
            local item = doc.tags[i]
            if item.name == tag then
                spore.description = item.description or spore.description
                break
            end
        end
    end
    if doc.servers and doc.servers[1] then
        spore.base_url = doc.servers[1].url
    end

    local function populate (paths)
        local function deref (obj)
            local ref = obj['$ref']
            if ref then
                local path, fragment = split_ref(ref)
                assert(not path, 'external ref: ' .. ref)
                local jptr = gsub(fragment, '%%(%x%x)', function (n)
                                                            return char(tonumber(n, 16))
                                                        end)
                obj = assert(get_rfc6901(doc, jptr))
            end
            return obj
        end  -- deref

        for path, methods in pairs(paths) do
            for op, meth in pairs(methods) do
                if ops[op] then
                    local found
                    if tag and meth.tags then
                        for i = 1, #meth.tags do
                            if tag == meth.tags[i] then
                                found = true
                                break
                            end
                        end
                    end
                    if found or not tag then
                        local required_params, optional_params
                        local headers

                        local function aggregate_param (param)
                            param = deref(param)
                            local name = assert(param.name)
                            if param.required then
                                if not required_params then
                                    required_params = {}
                                end
                                required_params[#required_params+1] = name
                            else
                                if not optional_params then
                                    optional_params = {}
                                end
                                optional_params[#optional_params+1] = name
                            end
                            if param['in'] == 'header' then
                                if not headers then
                                    headers = {}
                                end
                                headers[name] = ':' .. name
                            end
                        end  -- aggregate_param

                        if methods.parameters then
                            for i = 1, #methods.parameters do
                                aggregate_param(methods.parameters[i])
                            end
                        end
                        if meth.parameters then
                            for i = 1, #meth.parameters do
                                aggregate_param(meth.parameters[i])
                            end
                        end

                        local required_payload, optional_payload
                        local form_data
                        local request_body = meth.requestBody
                        if request_body then
                            request_body = deref(request_body)
                            local form = request_body.content['multipart/form-data']
                            if form then
                                form_data = {}
                                for name in pairs(form.schema.properties) do
                                    form_data[name] = ':' .. name
                                end
                            else
                                if request_body.required then
                                    required_payload = true
                                else
                                    optional_payload = true
                                end
                            end
                        end

                        local expected_status
                        if not meth.responses.default then
                            expected_status = {}
                            for status in pairs(meth.responses) do
                                expected_status[#expected_status+1] = tonumber(status)
                            end
                        end

                        spore.methods[meth.operationId] = {
                            method = upper(op),
                            path = (m.spore == '1.0') and convert_uri_template(path) or path,
                            headers = headers,
                            ['form-data'] = form_data,
                            required_params = required_params,
                            optional_params = optional_params,
                            required_payload = required_payload,
                            optional_payload = optional_payload,
                            expected_status = expected_status,
                            deprecated = meth.deprecated,
                            authentication = meth.security and true or nil,
                            description = meth.summary or meth.description,
                        }
                    end
                end
            end
        end
    end  -- populate

    populate(doc.paths)
    return spore
end

local function convert (doc, tag)
    if doc.swagger then
        return convert2(doc, tag)
    else
        return convert3(doc, tag)
    end
end
m.convert = convert

function m.new_from_swagger (api, opts, tag)
    opts = opts or {}
    checktype('new_from_swagger', 1, api, 'string')
    checktype('new_from_swagger', 2, opts, 'table')
    checktype('new_from_swagger', 3, tag or '', 'string')
    local doc, _, msg = decode(slurp(api, Spore.debug))
    assert(doc, msg)
    return new_from_lua(convert(doc, tag), opts, doc)
end

return m
--
-- Copyright (c) 2016-2025 Francois Perrad
--
-- This library is licensed under the terms of the MIT/X11 license,
-- like Lua itself.
--
