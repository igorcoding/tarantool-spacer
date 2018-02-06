local stmt_methods = {
    requires = function(self, req, name)
        self.requirements[req] = {
            name = name or req
        }
    end,
    only_up = function(self, only_up)
        if only_up == nil then
            only_up = true
        end
        self._only_up = only_up
    end,
    up = function(self, f, ...)
        table.insert(self.statements_up, string.format(f, ...))
    end,
    down = function(self, f, ...)
        if self._only_up then return end
        table.insert(self.statements_down, string.format(f, ...))
    end,
    up_apply = function(self, statements)
        if statements == nil then return end

        for _, s in ipairs(statements) do
            local f = table.remove(s, 1)
            self:up(f, unpack(s))
        end
    end,
    down_apply = function(self, statements)
        if self._only_up then return end
        if statements == nil then return end

        for _, s in ipairs(statements) do
            local f = table.remove(s, 1)
            self:down(f, unpack(s))
        end
    end,
    up_last = function(self, f, ...)
        -- insert in fifo order
        table.insert(self.statements_up_last, string.format(f, ...))
    end,
    down_last = function(self, f, ...)
        -- insert in fifo order
        if self._only_up then return end
        table.insert(self.statements_down_last, string.format(f, ...))
    end,
    up_tx_begin = function(self)
        if self.up_in_transaction then
            return
        end

        -- Space _space does not support multi-statement transactions
        --self:up('box.begin()')
        self.up_in_transaction = true
    end,
    up_tx_commit = function(self)
        if not self.up_in_transaction then
            return
        end

        -- Space _space does not support multi-statement transactions
        --self:up('box.commit()')
        self.up_in_transaction = false
    end,
    down_tx_begin = function(self)
        if self._only_up then return end
        if self.up_in_transaction then
            return
        end

        -- Space _space does not support multi-statement transactions
        --self:down('box.begin()')
        self.down_in_transaction = true
    end,
    down_tx_commit = function(self)
        if self._only_up then return end
        if not self.down_in_transaction then
            return
        end

        -- Space _space does not support multi-statement transactions
        --self:down('box.commit()')
        self.down_in_transaction = false
    end,
    build_up = function(self)
        local statements = {}
        for _, s in ipairs(self.statements_up) do
            table.insert(statements, s)
        end

        for i = #self.statements_up_last, 1, -1 do
            table.insert(statements, self.statements_up_last[i])
        end

        return statements
    end,
    build_down = function(self)
        local statements = {}
        for _, s in ipairs(self.statements_down) do
            table.insert(statements, s)
        end

        for i = #self.statements_down_last, 1, -1 do
            table.insert(statements, self.statements_down_last[i])
        end

        return statements
    end
}

return {
    new = function()
        return setmetatable({
            _only_up = false,
            up_in_transaction = false,
            down_in_transaction = false,
            requirements = {},
            statements_up = {},
            statements_down = {},

            statements_up_last = {},
            statements_down_last = {},
        }, {
            __index = stmt_methods
        })
    end
}
