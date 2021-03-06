-- This file is part of Entrust,
-- a role & permission management solution for Laravel.
-- @license MIT
-- @package Zizaco\Entrust


local lx, _M = oo{
    _cls_ = ''
}

local app, lf, tb, str = lx.kit()

--Big block of caching functionality.
function _M:cachedRoles()

    local userPrimaryKey = self.primaryKey
    local cacheKey = 'entrust_roles_for_user_' .. self[userPrimaryKey]
    
    return Cache.tags(Config.get('entrust.role_user_table')):remember(cacheKey, Config.get('cache.ttl'), function()
        
        return self:roles():get()
    end)
end

function _M:save(options)

    options = options or {}
    --both inserts and updates
    parent.save(options)
    Cache.tags(Config.get('entrust.role_user_table')):flush()
end

function _M:delete(options)

    options = options or {}
    --soft or hard
    parent.delete(options)
    Cache.tags(Config.get('entrust.role_user_table')):flush()
end

function _M:restore()

    --soft delete undo's
    parent.restore()
    Cache.tags(Config.get('entrust.role_user_table')):flush()
end

-- Many-to-Many relations with Role.
-- @return \Illuminate\Database\Eloquent\Relations\BelongsToMany

function _M:roles()

    return self:belongsToMany(Config.get('entrust.role'), Config.get('entrust.role_user_table'), Config.get('entrust.user_foreign_key'), Config.get('entrust.role_foreign_key'))
end

-- Boot the user model
-- Attach event listener to remove the many-to-many records when trying to delete
-- Will NOT delete any records if the user model uses soft deletes.
-- @return void|bool

function _M.s__.boot()

    parent.boot()
    static.deleting(function(user)
        if not Config.get('auth.model'):__has('bootSoftDeletes') then
            user:roles():sync({})
        end
        
        return true
    end)
end

-- Checks if the user has a role by its name.
-- @param string|array name       Role name or table of role names.
-- @param bool         requireAll All roles in the table are required.
-- @return bool

function _M:hasRole(name, requireAll)

    requireAll = requireAll or false
    local hasRole
    if lf.isTbl(name) then
        for _, roleName in pairs(name) do
            hasRole = self:hasRole(roleName)
            if hasRole and not requireAll then
                
                return true
            elseif not hasRole and requireAll then
                
                return false
            end
        end
        -- If we've made it this far and requireAll is FALSE, then NONE of the roles were found
        -- If we've made it this far and requireAll is TRUE, then ALL of the roles were found.
        -- Return the value of requireAll;
        
        return requireAll
    else 
        for _, role in pairs(self:cachedRoles()) do
            if role.name == name then
                
                return true
            end
        end
    end
    
    return false
end

-- Check if user has a permission by its name.
-- @param string|array permission Permission string or table of permissions.
-- @param bool         requireAll All permissions in the table are required.
-- @return bool

function _M:can(permission, requireAll)

    requireAll = requireAll or false
    local hasPerm
    if lf.isTbl(permission) then
        for _, permName in pairs(permission) do
            hasPerm = self:can(permName)
            if hasPerm and not requireAll then
                
                return true
            elseif not hasPerm and requireAll then
                
                return false
            end
        end
        -- If we've made it this far and requireAll is FALSE, then NONE of the perms were found
        -- If we've made it this far and requireAll is TRUE, then ALL of the perms were found.
        -- Return the value of requireAll;
        
        return requireAll
    else 
        for _, role in pairs(self:cachedRoles()) do
            -- Validate against the Permission table
            for _, perm in pairs(role:cachedPermissions()) do
                if str_is(permission, perm.name) then
                    
                    return true
                end
            end
        end
    end
    
    return false
end

-- Checks role(s) and permission(s).
-- @param string|array roles       Array of roles or comma separated string
-- @param string|array permissions Array of permissions or comma separated string.
-- @param table        options     validate_all (true|false) or return_type (boolean|array|both)
-- @throws \InvalidArgumentException
-- @return table|bool

function _M:ability(roles, permissions, options)

    options = options or {}
    local validateAll
    -- Convert string to table if that's what is passed in.
    if not lf.isTbl(roles) then
        roles = str.split(roles, ',')
    end
    if not lf.isTbl(permissions) then
        permissions = str.split(permissions, ',')
    end
    -- Set up default values and validate options.
    if not options['validate_all'] then
        options['validate_all'] = false
    else 
        if options['validate_all'] ~= true and options['validate_all'] ~= false then
            lx.throw(InvalidArgumentException)
        end
    end
    if not options['return_type'] then
        options['return_type'] = 'boolean'
    else 
        if options['return_type'] ~= 'boolean' and options['return_type'] ~= 'array' and options['return_type'] ~= 'both' then
            lx.throw(InvalidArgumentException)
        end
    end
    -- Loop through roles and permissions and check each.
    local checkedRoles = {}
    local checkedPermissions = {}
    for _, role in pairs(roles) do
        checkedRoles[role] = self:hasRole(role)
    end
    for _, permission in pairs(permissions) do
        checkedPermissions[permission] = self:can(permission)
    end
    -- If validate all and there is a false in either
    -- Check that if validate all, then there should not be any false.
    -- Check that if not validate all, there must be at least one true.
    if options['validate_all'] and not (tb.inList(checkedRoles, false) or tb.inList(checkedPermissions, false)) or not options['validate_all'] and (tb.inList(checkedRoles, true) or tb.inList(checkedPermissions, true)) then
        validateAll = true
    else 
        validateAll = false
    end
    -- Return based on option
    if options['return_type'] == 'boolean' then
        
        return validateAll
    elseif options['return_type'] == 'array' then
        
        return {roles = checkedRoles, permissions = checkedPermissions}
    else 
        
        return {validateAll, {roles = checkedRoles, permissions = checkedPermissions}}
    end
end

-- Alias to eloquent many-to-many relation's attach() method.
-- @param mixed role

function _M:attachRole(role)

    if lf.isObj(role) then
        role = role:getKey()
    end
    if lf.isTbl(role) then
        role = role['id']
    end
    self:roles():attach(role)
end

-- Alias to eloquent many-to-many relation's detach() method.
-- @param mixed role

function _M:detachRole(role)

    if lf.isObj(role) then
        role = role:getKey()
    end
    if lf.isTbl(role) then
        role = role['id']
    end
    self:roles():detach(role)
end

-- Attach multiple roles to a user
-- @param mixed roles

function _M:attachRoles(roles)

    for _, role in pairs(roles) do
        self:attachRole(role)
    end
end

-- Detach multiple roles from a user
-- @param mixed roles

function _M:detachRoles(roles)

    if not roles then
        roles = self:roles():get()
    end
    for _, role in pairs(roles) do
        self:detachRole(role)
    end
end

return _M

