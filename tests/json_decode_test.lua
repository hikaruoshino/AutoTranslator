-- Run with: lua tests/json_decode_test.lua
package.path = package.path .. ';./libs/?.lua;../libs/?.lua'
local json = require('json')

local function eq(actual, expected, label)
    if actual ~= expected then
        error(string.format('FAIL %s: expected %s got %s', label, tostring(expected), tostring(actual)))
    end
    print('ok ' .. label)
end

local arr = json.decode('[1,2,3]')
eq(type(arr), 'table', 'array decodes to table')
eq(arr[1], 1, 'arr[1]')
eq(arr[2], 2, 'arr[2]')
eq(arr[3], 3, 'arr[3]')
eq(arr[4], nil, 'no extra element')

local obj = json.decode('{"n":10}')
eq(obj.n, 10, 'object number before }')

local nested = json.decode('{"choices":[{"index":0}]}')
eq(nested.choices[1].index, 0, 'nested number before }')

print('All json decode checks passed.')
