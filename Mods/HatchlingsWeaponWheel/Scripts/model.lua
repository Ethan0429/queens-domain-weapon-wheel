-- Engine-independent selection and configuration logic.
local M = {}
function M.slotAt(x, y, count, innerRadius, outerRadius)
    local radiusSquared=x*x+y*y
    if count < 1 or radiusSquared < innerRadius*innerRadius or (outerRadius and radiusSquared>outerRadius*outerRadius) then return nil end
    local angle = (math.atan(y,x) + math.pi/2) % (2*math.pi)
    return (math.floor((angle+math.pi/count) / (2*math.pi/count)) % count)+1
end
function M.page(items, page, size)
    local pages=math.max(1,math.ceil(#items/size))
    page=((page-1)%pages)+1
    local out={}
    for i=(page-1)*size+1,math.min(page*size,#items) do out[#out+1]=items[i] end
    return out,page,pages
end
function M.clean(config)
    config=type(config)=='table' and config or {}
    local out={version=1,slots_per_page=math.max(4,math.min(12,math.floor(tonumber(config.slots_per_page) or 8))),favorites={}}
    local seen={}
    for _,path in ipairs(type(config.favorites)=='table' and config.favorites or {}) do
        if type(path)=='string' and path:sub(1,6)=='/Game/' and #path<512 and not seen[path] then
            out.favorites[#out.favorites+1]=path;seen[path]=true
        end
    end
    return out
end
function M.serialize(config)
    local rows={'-- Queens Weapon Wheel favorites, in clockwise order. Edit in-game with F10.',
        'return {','  version = 1,','  slots_per_page = '..config.slots_per_page..',','  favorites = {'}
    for _,path in ipairs(config.favorites) do rows[#rows+1]='    '..string.format('%q',path)..',' end
    rows[#rows+1]='  },';rows[#rows+1]='}';return table.concat(rows,'\n')..'\n'
end
function M.index(t,value)
    for i,v in ipairs(t) do if v==value then return i end end
end
function M.toggle(t,value)
    local i=M.index(t,value)
    if i then table.remove(t,i);return false end
    t[#t+1]=value;return true
end
function M.move(t,index,delta)
    local target=index+delta
    if index<1 or index>#t or target<1 or target>#t then return index end
    t[index],t[target]=t[target],t[index];return target
end
function M.resolve(paths,owned)
    local out={}
    for _,path in ipairs(paths) do if owned[path] then out[#out+1]=owned[path] end end
    return out
end
return M
