# tarantool-spacer
Spacer for Tarantool. For managing spaces easily.

# Usage examples

```lua

spacer.create_space('space1', {
    { name='id', type='unsigned' },
    { name='name', type='string' },
    { name='type', type='string' },
    { name='status', type='string' },
    { name='extra', type='*' },  -- * just a stub for practically any type
    
}, {
    { name = 'primary', type = 'hash', parts = { 'id' } },
    { name = 'type', type = 'tree', unique = false, parts = { 'type', 'status' } },
})

-- space3 will be identical to space1 (structure + indexes)
spacer.duplicate_space('space3', 'space1')

-- space4 will be identical to space1 (structure + indexes, extra indexes will be created)
spacer.duplicate_space('space4', 'space1', {
    indexes = {
        { name = 'status', type = 'tree', unique = false, parts = { 'status' } },
    }
})

-- space5 will be identical to space1 (only structure, indexes will be omitted)
spacer.duplicate_space('space5', 'space1', {
    dupindex = false
})

-- space6 will be identical to space1 (only structure, indexes will be omitted, extra indexes will be created)
spacer.duplicate_space('space6', 'space1', {
    dupindex = false,
    indexes = {
        { name = 'status', type = 'tree', unique = false, parts = { 'status' } },
    }
})
```


# Fields

Space fields can be accessed by the global variable `F`:

```lua
box.space.space1:update(
    {1},
    {
        {'=', F.space1.name, 'John Watson'},
        {'=', F.space1.type, 'Doctor'},
    }
)
```


# Transofrmations

You can easily transform a given tuple to a dictionary-like object and vice-a-versa.

These are the functions:
* `T.space_name.dict` or `T.space_name.hash` - transforms a tuple to a dictionary
* `T.space_name.tuple` - transforms a dictionary back to a tuple

```lua
local john = box.space.space1:get({1})
local john_dict = T.space1.dict(john) -- or hash() function
--[[
john_dict = {
    id = 1,
    name = 'John Watson',
    type = 'Doctor',
    ...
}
--]]

```


... or vice-a-versa:

```lua
local john_dict = {
    id = 1,
    name = 'John Watson',
    type = 'Doctor',
    -- ...
}

local john = T.space1.tuple(john_dict)
--[[
john = [1, 'John Watson', 'Doctor', ...]
--]]

```
