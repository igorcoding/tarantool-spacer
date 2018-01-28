# spacer
Tarantool Spacer. Automatic models migrations.

# Changes detected by spacer

* Space create and drop
* Index create and drop
* Index options alteration
    * `unique`
    * `type`
    * `sequence`
    * `dimension` and `distance` (for RTREE indexes)
    * `parts`
* Format alterations
    * New fields (only to the end of format list).
      Setting values for existing tuples is handled by the [moonwalker](https://github.com/tarantool/moonwalker) library
    * Field's `is_nullable` and `collation` changes
    * **[IMPORTANT] `type` and `name` changes are prohibited**



# Usage
## Initialize

Initialized spacer somewhere in the beginning of your `init.lua`:
```lua
require 'spacer'({
    migrations = 'path/to/migrations/folder',
})
```

You can assign spacer to a some global variable for easy access:
```lua
box.spacer = require 'spacer'({
    migrations = 'path/to/migrations/folder',
})
```


## Define spaces

You can easily define new spaces in a separate file (e.g. `models.lua`) and all
you will need to do is to `require` it from `init.lua` right after spacer initialization:
```lua
box.spacer = require 'spacer'({
    migrations = 'path/to/migrations/folder',
})
require 'models'
```

### `models.lua` example:

Note that spacer now has methods

```lua
local spacer = require 'spacer'

spacer:space('object', {
    { name = 'id', type = 'unsigned' },
    { name = 'name', type = 'string', is_nullable = true },
}, {
    { name = 'primary', type = 'tree', unique = true, parts = {'id'}, sequence = true },
    { name = 'name', type = 'tree', unique = false, parts = {'name', 'id'} },
})

```

`spacer:space` has 4 arguments:
1. space name (required)
2. space format (required)
3. space indexes array (required)
4. any box.schema.create_space options (optional). Please refer to Tarantool documentation for details.

Indexes parts must be defined using only field names.

## Creating migration

You can autogenerate migration by just running the following snippet in Tarantool console:

```lua
box.spacer:makemigration('init_object', true)
```

There are 2 arguments to the `makemigration` method:
1. Migration name (required)
2. Autogenerate migration (default is `false`). If `false` then empty migration file is generated

After executing this command a new migrations file will be generated under name `<timestamp>_<migration_name>.lua` inside your `migrations` folder:
```lua
return {
    up = function()
        box.schema.create_space("object", nil)
        box.space.object:format({ {
            name = "id",
            type = "unsigned"
          }, {
            is_nullable = false,
            name = "name",
            type = "string"
          } })
        box.space.object:create_index("primary", {
          parts = { { 1, "unsigned",
              is_nullable = false
            } },
          sequence = true,
          type = "tree",
          unique = true
        })
        box.space.object:create_index("name", {
          parts = { { 2, "string",
              is_nullable = false
            }, { 1, "unsigned",
              is_nullable = false
            } },
          type = "tree",
          unique = false
        })
    end,

    down = function()
        box.space.object:drop()
    end,
}
```

Any migration file consists of 2 exported functions (`up` and `down`).
You are free to edit this migration any way you want.

## Applying migrations

You can apply not yet applied migrations by running:
```lua
box.spacer:migrate_up(n)
```

It accepts `n` - number of migrations to apply (by default `n` is infinity, i.e. apply till the end)

Current migration version number is stored in the `_schema` space under `_spacer_ver` key:
```
tarantool> box.space._schema:select{'_spacer_ver'}
---
- - ['_spacer_ver', 1516561029, 'init']
...
```

## Rolling back migrations

If you want to roll back migration you need to run:
```lua
box.spacer:migrate_down(n)
```

It accepts `n` - number of migrations to rollback (by default `n` is 1, i.e. roll back obly the latest migration).
To rollback all migration just pass any huge number.


# Fields

Space fields can be accessed by the global variable `F`, which is set by spacer
or in the spacer directly (`box.spacer.F`):

```lua
box.space.space1:update(
    {1},
    {
        {'=', F.object.name, 'John Watson'},
    }
)
```


# Transformations

You can easily transform a given tuple to a dictionary-like object and vice-a-versa.

These are the functions:
* `T.space_name.dict` or `T.space_name.hash` - transforms a tuple to a dictionary
* `T.space_name.tuple` - transforms a dictionary back to a tuple

T can be accessed through the global variable `T` or in the spacer directly (`box.spacer.T`)

```lua
local john = box.space.object:get({1})
local john_dict = T.object.dict(john) -- or T.object.hash(john)
--[[
john_dict = {
    id = 1,
    name = 'John Watson',
    ...
}
--]]

```

... or vice-a-versa:

```lua
local john_dict = {
    id = 1,
    name = 'John Watson',
    -- ...
}

local john = T.object.tuple(john_dict)
--[[
john = [1, 'John Watson', ...]
--]]

```
