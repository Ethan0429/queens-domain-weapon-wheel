local UI={};UI.__index=UI
-- Layout is authored in 1920x1080 units and scaled to the viewport.
-- Artwork in Assets/ is produced by tools/generate_assets.py; shared geometry is marked there.
UI.CATALOG_PER_PAGE=18
UI.FAVORITES_PER_PAGE=8
UI.WHEEL_INNER=172
UI.WHEEL_OUTER=430
local FONT=24 -- approximate em size of the game's DefaultTextStyle, in layout units
local SECTOR_RADIUS=282
local HOVER_WEDGE_SCALE,HOVER_ICON_SCALE=1.035,1.15

-- UMG colors are linear; convert from sRGB hex so they match the artwork.
local function srgb(hex,a)
    local function ch(i) return (tonumber(hex:sub(i,i+1),16)/255)^2.2 end
    return {R=ch(1),G=ch(3),B=ch(5),A=a or 1}
end
local colors={text=srgb('ECE4D0'),muted=srgb('9A9382'),dim=srgb('5E5A50'),brass=srgb('D9BC80'),
    brassLight=srgb('F2DDA8'),ember=srgb('F0B860'),verdigris=srgb('7CD3BE'),clear={R=0,G=0,B=0,A=0}}
local VISIBLE,COLLAPSED=4,1

local function valid(o) return o and o:IsValid() end
local function class(n) return StaticFindObject('/Script/UMG.'..n) end
function UI.new(pc,root)
    local self=setmetatable({pc=pc,root=root,hitboxes={},wedges={},icons={},cache={},kept={}},UI)
    local host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C')
    if not valid(host) then LoadAsset('/Game/UI/Title/CreditLinkText');host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C') end
    self.widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,host,pc)
    assert(valid(self.widget),'Could not construct weapon wheel UI')
    self.tree=self.widget.WidgetTree
    self.canvas=StaticConstructObject(class('CanvasPanel'),self.tree)
    self.tree.RootWidget=self.canvas
    self.style=StaticFindObject('/Game/UI/UI_Style/FontStyles/DefaultTextStyle.DefaultTextStyle_C')
    pcall(function() self.widget.bIsFocusable=false end)
    self.widget:SetVisibility(COLLAPSED)
    self.widget:AddToViewport(20000)
    self:layout()
    return self
end
function UI:layout()
    local lib=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
    local size=lib:GetViewportSize(self.pc);local dpi=lib:GetViewportScale(self.pc)
    self.width,self.height=size.X/dpi,size.Y/dpi
    self.scale=math.min(self.width/1920,self.height/1080)
end
function UI:make(n) return StaticConstructObject(class(n),self.tree) end
function UI:place(o,x,y,w,h)
    local s=self.canvas:AddChildToCanvas(o)
    s:SetPosition({X=self.width/2+(x-960)*self.scale,Y=self.height/2+(y-540)*self.scale})
    s:SetSize({X=w*self.scale,Y=h*self.scale})
    return o
end

-- Text sits inside a transparent Border: the Border's content color tints it (CommonTextBlock
-- re-applies its style color, so tinting the text block directly does not stick), and a
-- render scale sets the size relative to the style's native font size.
function UI:text(value,x,y,w,h,size,color,align,wrap)
    local s=(size or FONT)/FONT
    local t=StaticConstructObject(StaticFindObject('/Script/CommonUI.CommonTextBlock'),self.tree)
    if valid(self.style) then t:SetStyle(self.style) end
    t:SetText(FText(tostring(value)));t:SetJustification(align or 0)
    pcall(function() t:SetAutoWrapText(wrap~=false) end)
    local box=self:make('Border')
    box:SetBrushColor(colors.clear);box:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    pcall(function() box:SetVerticalAlignment(2) end)
    box:SetContentColorAndOpacity(color or colors.text)
    box:SetContent(t)
    self:place(box,x,y,w/s,h/s)
    box:SetRenderTransformPivot({X=0,Y=0})
    box:SetRenderScale({X=s,Y=s})
    return box,t
end
function UI:texture(name)
    local tex=self.cache[name]
    if not valid(tex) then
        local lib=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
        tex=lib:ImportFileAsTexture2D(self.pc,self.root..'/Assets/'..name..'.png')
        assert(valid(tex),'Could not load wheel artwork '..name)
        self.cache[name]=tex
    end
    if not self.kept[name] then
        -- A collapsed image keeps textures used only for hover swaps referenced (and out of GC).
        self.kept[name]=true
        local keep=self:make('Image');keep:SetBrushFromTexture(tex,false);keep:SetVisibility(COLLAPSED)
        self.canvas:AddChildToCanvas(keep)
    end
    return tex
end
function UI:image(tex,x,y,w,h)
    local image=self:make('Image')
    if valid(tex) then image:SetBrushFromTexture(tex,false) else image:SetVisibility(COLLAPSED) end
    return self:place(image,x,y,w,h)
end
function UI:art(name,x,y,w,h) return self:image(self:texture(name),x,y,w,h) end
function UI:fullscreen(name)
    local image=self:make('Image');image:SetBrushFromTexture(self:texture(name),false)
    local s=self.canvas:AddChildToCanvas(image)
    s:SetPosition({X=0,Y=0});s:SetSize({X=self.width,Y=self.height})
    return image
end
function UI:icon(entry,x,y,size)
    local texture=entry and entry.item.ItemIcon
    if valid(texture) then return self:image(texture,x,y,size,size),true end
    return self:text(entry and entry.name:sub(1,1) or '?',x,y,size,size,size*.6,colors.brass,1,false),false
end
function UI:reset()
    self.canvas:ClearChildren();self.hitboxes={};self.wedges={};self.icons={};self.kept={}
    self.centerIcon=nil;self.centerName=nil;self.centerStatus=nil;self.pointer=nil
    self.hover=nil;self.hoverId=nil;self.currentEntry=nil
    self:layout()
    self:fullscreen('vignette')
end
function UI:hit(id,x,y,w,h,visual)
    self.hitboxes[#self.hitboxes+1]={id=id,x=x,y=y,w=w,h=h,visual=visual}
end
function UI:visual(img,base)
    return {img=img,normal=self:texture(base),hover=self:texture(base..'-hover')}
end
-- opts: primary, disabled, arrow ('left'/'right')
function UI:button(id,label,x,y,w,h,opts)
    opts=opts or {}
    local base=opts.arrow and ('arrow-'..opts.arrow) or string.format('btn-%dx%d%s',w,h,opts.primary and '-primary' or '')
    if opts.disabled then
        self:art(base..'-disabled',x,y,w,h)
        if label then self:text(label,x,y,w,h,16,colors.dim,1,false) end
        return
    end
    local img=self:art(base,x,y,w,h)
    if label then self:text(label,x,y,w,h,16,opts.primary and colors.brassLight or colors.text,1,false) end
    self:hit(id,x,y,w,h,self:visual(img,base))
end
-- Centered row of key hints: {{'ALT','RELEASE TO EQUIP'},...}
function UI:hints(list,cy)
    local parts,total={},0
    for i,h in ipairs(list) do
        local kw=#h[1]<=3 and 48 or 72
        local lw=math.ceil(#h[2]*15*.66)
        parts[i]={key=h[1],label=h[2],kw=kw,lw=lw}
        total=total+kw+8+lw+(i>1 and 30 or 0)
    end
    local x=960-total/2
    for i,p in ipairs(parts) do
        if i>1 then x=x+30 end
        self:art('key-'..p.kw,x,cy-15,p.kw,30)
        self:text(p.key,x,cy-15,p.kw,30,13,colors.brassLight,1,false)
        x=x+p.kw+8
        self:text(p.label,x,cy-15,p.lw+40,30,15,colors.muted,0,false)
        x=x+p.lw
    end
end
function UI:setText(node,value,color)
    if not node then return end
    node[2]:SetText(FText(value))
    if color then node[1]:SetContentColorAndOpacity(color) end
end
local function scaleWidget(w,s) pcall(function() w:SetRenderScale({X=s,Y=s}) end) end

function UI:wheel(entries,page,pages,current,currentEntry)
    self:reset();self.mode='wheel';self.entries=entries;self.current=current;self.currentEntry=currentEntry
    self:text('A R S E N A L',560,22,800,44,30,colors.brassLight,1,false)
    self:art('divider',700,70,520,28)
    self:art('wheel-backplate',520,100,880,880)
    local n=#entries
    if n>0 then
        self.baseTexture=self:texture('sector-'..n)
        self.hoverTexture=self:texture('sector-hover-'..n)
        self.currentTexture=self:texture('sector-current-'..n)
        for i,entry in ipairs(entries) do
            local img=self:image(entry.path==current and self.currentTexture or self.baseTexture,560,140,800,800)
            img:SetRenderTransformPivot({X=.5,Y=.5});img:SetRenderTransformAngle((i-1)*360/n)
            self.wedges[i]=img
        end
        for i,entry in ipairs(entries) do
            local angle=(i-1)*2*math.pi/n-math.pi/2
            local cx,cy=960+math.cos(angle)*SECTOR_RADIUS,540+math.sin(angle)*SECTOR_RADIUS
            local icon,isImage=self:icon(entry,cx-46,cy-46,92)
            if isImage then icon:SetRenderTransformPivot({X=.5,Y=.5});self.icons[i]=icon end
        end
    end
    self:art('hub-glow',830,410,260,260)
    self:art('hub',780,360,360,360)
    self.pointer=self:art('pointer',760,340,400,400)
    self.pointer:SetRenderTransformPivot({X=.5,Y=.5});self.pointer:SetVisibility(COLLAPSED)
    self.centerIcon=self:image(nil,904,452,112,112)
    self.centerName={self:text('',810,570,300,32,21,colors.text,1,false)}
    self.centerStatus={self:text('',800,604,320,20,12,colors.muted,1,false)}
    self:setCenter(currentEntry,false)
    if pages>1 then
        local x=960-pages*11
        for p=1,pages do self:art(p==page and 'pip-on' or 'pip',x+(p-1)*22,989,22,22) end
    end
    local hints={{'ALT','RELEASE TO EQUIP'},{'RMB','CANCEL'}}
    if pages>1 then hints[#hints+1]={'SCROLL','PAGE'} end
    hints[#hints+1]={'F10','CUSTOMIZE'}
    self:hints(hints,1044)
    self:addCursor()
    self.widget:SetVisibility(VISIBLE);self.hover=nil
end
function UI:setCenter(entry,hovered)
    local texture=entry and entry.item.ItemIcon
    if valid(texture) then
        self.centerIcon:SetBrushFromTexture(texture,false);self.centerIcon:SetVisibility(VISIBLE)
    else self.centerIcon:SetVisibility(COLLAPSED) end
    if #self.entries==0 then
        self:setText(self.centerName,'Your wheel is empty',colors.text)
        self:setText(self.centerStatus,'PRESS F10 TO ADD WEAPONS',colors.ember)
    elseif not entry then
        self:setText(self.centerName,'',colors.text)
        self:setText(self.centerStatus,'CHOOSE A WEAPON',colors.muted)
    elseif entry.path==self.current then
        self:setText(self.centerName,entry.name,colors.text)
        self:setText(self.centerStatus,'EQUIPPED',colors.verdigris)
    else
        self:setText(self.centerName,entry.name,hovered and colors.brassLight or colors.text)
        self:setText(self.centerStatus,hovered and 'RELEASE TO EQUIP' or '',colors.ember)
    end
end
function UI:hoverSlot(index)
    if self.hover==index then return end
    self.hover=index
    local n=#self.wedges
    for i,img in ipairs(self.wedges) do
        img:SetBrushFromTexture(i==index and self.hoverTexture or (self.entries[i].path==self.current and self.currentTexture or self.baseTexture),false)
        scaleWidget(img,i==index and HOVER_WEDGE_SCALE or 1)
    end
    for i,icon in pairs(self.icons) do scaleWidget(icon,i==index and HOVER_ICON_SCALE or 1) end
    if self.pointer then
        if index then
            self.pointer:SetRenderTransformAngle((index-1)*360/n);self.pointer:SetVisibility(VISIBLE)
        else self.pointer:SetVisibility(COLLAPSED) end
    end
    self:setCenter((index and self.entries[index]) or self.currentEntry,index~=nil)
end

-- Editor layout. Panel geometry and separators are baked into panel.png (generate_assets.py).
local CARD_W,CARD_H,CARD_PITCH_X,CARD_PITCH_Y=272,78,284,88
local ROW_W,ROW_H,ROW_PITCH=454,50,56
local LEFT,RIGHT,TOP=290,1176,298
function UI:editor(owned,favorites,lookup,catalogPage,favoritePage,selected)
    self:reset();self.mode='editor'
    local perCatalog,perFavorites=UI.CATALOG_PER_PAGE,UI.FAVORITES_PER_PAGE
    self:art('panel',212,82,1496,916)
    self:text('W E A P O N   W H E E L',LEFT,136,600,20,13,colors.brass,0,false)
    self:text('Arsenal',LEFT,156,600,46,38,colors.text,0,false)
    self:text('Click a weapon to add it to your wheel or remove it. Changes save automatically.',LEFT,206,1000,24,16,colors.muted,0,false)
    self:button('done','DONE',1480,150,150,46,{primary=true})

    local index={};for i,p in ipairs(favorites) do index[p]=i end
    local inWheel=0;for _,e in ipairs(owned) do if index[e.path] then inWheel=inWheel+1 end end
    self:text('OWNED WEAPONS',LEFT,262,400,24,16,colors.brass,0,false)
    self:text(string.format('%d OWNED',#owned),830,262,300,24,14,colors.muted,2,false)
    local first=(catalogPage-1)*perCatalog+1
    for i=first,math.min(first+perCatalog-1,#owned) do
        local entry=owned[i];local n=i-first;local col=n%3;local row=math.floor(n/3)
        local x,y=LEFT+col*CARD_PITCH_X,TOP+row*CARD_PITCH_Y;local chosen=index[entry.path]
        local base=chosen and 'card-chosen' or 'card'
        local img=self:art(base,x,y,CARD_W,CARD_H)
        self:icon(entry,x+12,y+11,56)
        self:text(entry.name,x+84,y+4,146,CARD_H-8,18,chosen and colors.brassLight or colors.text,0,true)
        if chosen then
            self:art('badge',x+236,y+6,30,30)
            self:text(chosen,x+236,y+6,30,30,12,colors.brassLight,1,false)
        end
        self:hit('toggle:'..i,x,y,CARD_W,CARD_H,self:visual(img,base))
    end
    if #owned==0 then
        self:text('No weapons owned yet',LEFT,480,840,40,24,colors.text,1,false)
        self:text('Weapons you pick up will appear here.',LEFT,520,840,30,16,colors.muted,1,false)
    end
    local catalogPages=math.max(1,math.ceil(#owned/perCatalog))
    self:button('catalog-prev',nil,LEFT,830,44,42,{arrow='left',disabled=catalogPage<=1})
    self:text(string.format('PAGE %d / %d',catalogPage,catalogPages),LEFT+44,830,136,42,15,colors.muted,1,false)
    self:button('catalog-next',nil,LEFT+180,830,44,42,{arrow='right',disabled=catalogPage>=catalogPages})
    self:button('add-all','ADD ALL',960,830,170,42,{disabled=inWheel>=#owned})

    self:text('WHEEL ORDER',RIGHT,262,300,24,16,colors.brass,0,false)
    self:text(string.format('%d ON WHEEL',#favorites),1330,262,300,24,14,colors.muted,2,false)
    local ffirst=(favoritePage-1)*perFavorites+1
    for i=ffirst,math.min(ffirst+perFavorites-1,#favorites) do
        local entry=lookup[favorites[i]];local y=TOP+(i-ffirst)*ROW_PITCH;local isSelected=i==selected
        local base=isSelected and 'row-selected' or 'row'
        local img=self:art(base,RIGHT,y,ROW_W,ROW_H)
        self:text(string.format('%02d',i),RIGHT,y,44,ROW_H,15,isSelected and colors.brassLight or colors.brass,1,false)
        if entry then self:icon(entry,RIGHT+50,y+7,36) end
        self:text(entry and entry.name or 'Not currently owned',RIGHT+96,y,340,ROW_H,18,
            (not entry and colors.dim) or (isSelected and colors.brassLight) or colors.text,0,false)
        self:hit('favorite:'..i,RIGHT,y,ROW_W,ROW_H,self:visual(img,base))
    end
    if #favorites==0 then
        self:text('Your wheel is empty',RIGHT,440,ROW_W,36,22,colors.text,1,false)
        self:text('Click weapons on the left to add them.',RIGHT,476,ROW_W,30,16,colors.muted,1,false)
    end
    local favoritePages=math.max(1,math.ceil(#favorites/perFavorites))
    self:button('favorites-prev',nil,RIGHT,752,44,42,{arrow='left',disabled=favoritePage<=1})
    self:text(string.format('%d / %d',favoritePage,favoritePages),RIGHT+44,752,ROW_W-88,42,15,colors.muted,1,false)
    self:button('favorites-next',nil,RIGHT+ROW_W-44,752,44,42,{arrow='right',disabled=favoritePage>=favoritePages})
    local none=#favorites==0
    self:button('up','MOVE UP',RIGHT,830,144,42,{disabled=none or selected<=1})
    self:button('down','MOVE DOWN',RIGHT+155,830,144,42,{disabled=none or selected>=#favorites})
    self:button('remove','REMOVE',RIGHT+310,830,144,42,{disabled=none})

    self:hints({{'ESC','CLOSE'},{'SCROLL','CHANGE PAGE'},{'ALT','HOLD IN GAME TO OPEN THE WHEEL'}},921)
    self:addCursor()
    self.widget:SetVisibility(VISIBLE)
end
function UI:hoverEditor(id)
    if self.hoverId==id then return end
    local function find(target)
        if not target then return nil end
        for _,r in ipairs(self.hitboxes) do if r.id==target then return r.visual end end
    end
    local old,new=find(self.hoverId),find(id)
    if old and valid(old.img) then old.img:SetBrushFromTexture(old.normal,false) end
    if new and valid(new.img) then new.img:SetBrushFromTexture(new.hover,false) end
    self.hoverId=id
end
function UI:addCursor()
    local x,y=self:mouse()
    self.cursor=self:art('cursor',x,y,27,36)
    self.cursor.Slot:SetZOrder(99999)
end
function UI:moveCursor(x,y)
    if self.cursor and valid(self.cursor) then
        self.cursor.Slot:SetPosition({X=self.width/2+(x-960)*self.scale,Y=self.height/2+(y-540)*self.scale})
    end
end
function UI:mouse()
    local p=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary'):GetMousePositionOnViewport(self.pc)
    return (p.X-self.width/2)/self.scale+960,(p.Y-self.height/2)/self.scale+540
end
function UI:hitAt(x,y)
    for _,r in ipairs(self.hitboxes) do if x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then return r.id end end
end
function UI:hide() if valid(self.widget) then self.widget:SetVisibility(COLLAPSED) end end
function UI:destroy() if valid(self.widget) then self.widget:RemoveFromParent() end end
return UI
