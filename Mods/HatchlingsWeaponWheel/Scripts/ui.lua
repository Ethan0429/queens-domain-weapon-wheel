-- Native Unreal UMG UI. All measurements use a 1920x1080 design canvas.
local UI={};UI.__index=UI
local colors={white={R=.93,G=.92,B=.88,A=1},muted={R=.55,G=.59,B=.63,A=1},gold={R=.91,G=.76,B=.46,A=1},
    card={R=.055,G=.067,B=.085,A=.98},hover={R=.17,G=.135,B=.075,A=1},green={R=.37,G=.76,B=.61,A=1}}
local function valid(o) return o and o:IsValid() end
local function class(n) return StaticFindObject('/Script/UMG.'..n) end
function UI.new(pc,root)
    local self=setmetatable({pc=pc,root=root,hitboxes={},wedges={},cards={},cache={},serial=0},UI)
    local host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C')
    if not valid(host) then LoadAsset('/Game/UI/Title/CreditLinkText');host=StaticFindObject('/Game/UI/Title/CreditLinkText.CreditLinkText_C') end
    self.widget=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,host,pc)
    assert(valid(self.widget),'Could not construct weapon wheel UI')
    self.tree=self.widget.WidgetTree
    self.canvas=StaticConstructObject(class('CanvasPanel'),self.tree)
    self.tree.RootWidget=self.canvas
    self.style=StaticFindObject('/Game/UI/UI_Style/FontStyles/DefaultTextStyle.DefaultTextStyle_C')
    pcall(function() self.widget.bIsFocusable=false end)
    self.widget:SetVisibility(1)
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
function UI:panel(x,y,w,h,c)
    local b=self:make('Border');b:SetBrushColor(c or colors.card);b:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    return self:place(b,x,y,w,h)
end
function UI:text(value,x,y,w,h,size,color,center)
    local t=StaticConstructObject(StaticFindObject('/Script/CommonUI.CommonTextBlock'),self.tree)
    if valid(self.style) then t:SetStyle(self.style) end
    t:SetText(FText(value));t:SetJustification(center and 1 or 0)
    pcall(function()
        t:SetColorAndOpacity({SpecifiedColor=color or colors.white,ColorUseRule=0})
        t:SetAutoWrapText(true);t:SetWrapTextAt(w*self.scale)
    end)
    -- ScaleBox fits the game's original styled font inside the allotted bounds.
    -- Never read, mutate or marshal FSlateFontInfo through Lua in this UE4SS build.
    local box=self:make('ScaleBox')
    box:SetStretch(1);box:SetStretchDirection(1) -- ScaleToFit, DownOnly.
    box:SetContent(t)
    return self:place(box,x,y,w,h),t
end
function UI:arcText(value,angle,radius,availableAngle,color)
    local glyphs,units={},0
    for _,code in utf8.codes(value) do
        local char=utf8.char(code)
        local unit=(char==' ' and .32) or (char:find('[ilI.,!\']') and .30) or (char:find('[MWmw]') and .86) or .60
        glyphs[#glyphs+1]={char=char,unit=unit};units=units+unit
    end
    local fontSize=math.min(18,(availableAngle*radius-24)/math.max(units,1))
    fontSize=math.max(11,fontSize)
    local total=units*fontSize
    local flip=math.sin(angle)>.01
    local direction=flip and -1 or 1
    local advance=-total/2
    for _,glyph in ipairs(glyphs) do
        local width=glyph.unit*fontSize
        local a=angle+direction*(advance+width/2)/radius
        local x,y=960+math.cos(a)*radius,540+math.sin(a)*radius
        if glyph.char~=' ' then
            local node=self:text(glyph.char,x-(width+2)/2,y-fontSize*.75,width+2,fontSize*1.5,fontSize,color,true)
            node:SetRenderTransformPivot({X=.5,Y=.5})
            node:SetRenderTransformAngle(a*180/math.pi+90+(flip and 180 or 0))
        end
        advance=advance+width
    end
end
function UI:texture(name)
    if self.cache[name] and valid(self.cache[name]) then return self.cache[name] end
    local lib=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
    local tex=lib:ImportFileAsTexture2D(self.pc,self.root..'/Assets/'..name..'.png')
    assert(valid(tex),'Could not load wheel artwork '..name)
    self.cache[name]=tex
    return tex
end
function UI:image(tex,x,y,w,h)
    local image=self:make('Image')
    -- A brush without a texture renders a white rectangle in UMG.
    if valid(tex) then image:SetBrushFromTexture(tex,false) else image:SetVisibility(1) end
    return self:place(image,x,y,w,h)
end
function UI:icon(entry,x,y,size)
    local texture=entry and entry.item.ItemIcon
    if valid(texture) then return self:image(texture,x,y,size,size) end
    return self:text(entry and entry.name:sub(1,1) or '?',x,y,size,size,size*.65,colors.gold,true)
end
function UI:reset()
    self.canvas:ClearChildren();self.hitboxes={};self.wedges={};self.cards={}
    self.centerIcon=nil;self.currentEntry=nil;self.hover=nil
    self:layout()
    self:panel(0,0,1920,1080,{R=.005,G=.008,B=.013,A=.62})
end
function UI:hit(id,x,y,w,h)
    self.hitboxes[#self.hitboxes+1]={id=id,x=x,y=y,w=w,h=h}
end
function UI:button(id,label,x,y,w,h,active)
    self:panel(x,y,w,h,active and colors.hover or colors.card)
    self:text(label,x+8,y+8,w-16,h-8,17,active and colors.gold or colors.white,true)
    self:hit(id,x,y,w,h)
end
function UI:wheel(entries,page,pages,current,currentEntry)
    self:reset();self.mode='wheel';self.entries=entries;self.current=current;self.currentEntry=currentEntry
    self:text('A R S E N A L',560,42,800,44,31,colors.gold,true)
    self:text('HOLD ALT  /  RELEASE TO EQUIP',560,88,800,30,17,colors.muted,true)
    local n=#entries
    if n==0 then
        self:text('Your wheel is empty',580,270,760,70,30,colors.white,true)
        self:text('Release Alt and press F10 to add weapons.',580,850,760,60,20,colors.gold,true)
    else
        local base=self:texture('sector-'..n)
        self.hoverTexture=self:texture('sector-hover-'..n)
        self.currentTexture=self:texture('sector-current-'..n)
        -- Hidden brush references keep every imported texture alive through Unreal GC.
        for _,tex in ipairs({self.hoverTexture,self.currentTexture}) do local o=self:image(tex,0,0,1,1);o:SetVisibility(1) end
        self.baseTexture=base
        for i,entry in ipairs(entries) do
            local img=self:image(entry.path==current and self.currentTexture or base,580,160,760,760)
            img:SetRenderTransformPivot({X=.5,Y=.5});img:SetRenderTransformAngle((i-1)*360/n)
            self.wedges[i]=img
            local angle=(i-1)*2*math.pi/n-math.pi/2
            local cx,cy=960+math.cos(angle)*272,540+math.sin(angle)*272
            self:icon(entry,cx-43,cy-58,86)
            self:arcText(entry.name,angle,342,2*math.pi/n,entry.path==current and colors.green or colors.white)
        end
    end
    self:image(self:texture('center'),815,395,290,290)
    self.centerIcon=self:image(nil,888,468,144,144)
    -- Initialize explicitly: the first hover index is nil, just like reset().
    self:setCenterEntry(currentEntry)
    self:text(string.format('PAGE %d / %d%s',page,pages,pages>1 and '   ·   SCROLL TO CHANGE PAGE' or ''),430,982,1060,30,17,colors.white,true)
    self:text('F10  CUSTOMIZE',430,1025,1060,30,16,colors.muted,true)
    self:addCursor()
    self.widget:SetVisibility(4);self.hover=nil
end
function UI:setCenterEntry(entry)
    local texture=entry and entry.item.ItemIcon
    if valid(texture) then
        self.centerIcon:SetBrushFromTexture(texture,false);self.centerIcon:SetVisibility(4)
    else self.centerIcon:SetVisibility(1) end
end
function UI:hoverSlot(index)
    if self.hover==index then return end
    self.hover=index
    for i,img in ipairs(self.wedges) do
        img:SetBrushFromTexture(i==index and self.hoverTexture or (self.entries[i].path==self.current and self.currentTexture or self.baseTexture),false)
    end
    self:setCenterEntry((index and self.entries[index]) or self.currentEntry)
end
function UI:editor(owned,favorites,lookup,catalogPage,favoritePage,selected)
    self:reset();self.mode='editor'
    self:panel(250,100,1420,885,{R=.018,G=.025,B=.037,A=.99})
    self:text('Click an owned weapon to add or remove it. Your choices save automatically.',290,181,1120,40,18,colors.muted,false)
    self:button('done','DONE',1510,126,120,45,true)
    self:text('OWNED WEAPONS',290,244,830,30,17,colors.white,false)
    self:text('WHEEL ORDER  ·  CLOCKWISE',1170,244,440,30,17,colors.white,false)
    local index={};for i,p in ipairs(favorites) do index[p]=i end
    local first=(catalogPage-1)*18+1
    for i=first,math.min(first+17,#owned) do
        local entry=owned[i];local localIndex=i-first;local col=localIndex%3;local row=math.floor(localIndex/3)
        local x,y=290+col*280,290+row*93;local chosen=index[entry.path]
        self:panel(x,y,266,80,chosen and colors.hover or colors.card)
        self:icon(entry,x+8,y+12,54)
        self:text(entry.name,x+72,y+11,179,55,16,chosen and colors.gold or colors.white,false)
        if chosen then self:text(tostring(chosen),x+242,y+55,20,22,12,colors.gold,true) end
        self:hit('toggle:'..i,x,y,266,80)
    end
    local catalogPages=math.max(1,math.ceil(#owned/18))
    self:button('catalog-prev','PREV',290,866,115,42,false)
    self:text(string.format('%d / %d',catalogPage,catalogPages),432,875,200,30,17,colors.muted,true)
    self:button('catalog-next','NEXT',707,866,115,42,false)
    self:button('add-all','ADD ALL',840,866,275,42,false)
    local ffirst=(favoritePage-1)*9+1
    for i=ffirst,math.min(ffirst+8,#favorites) do
        local entry=lookup[favorites[i]];local y=290+(i-ffirst)*56
        self:panel(1170,y,455,48,i==selected and colors.hover or colors.card)
        self:text(string.format('%02d',i),1181,y+10,42,30,15,colors.gold,false)
        self:text(entry and entry.name or '(not currently owned)',1230,y+9,375,33,16,entry and colors.white or colors.muted,false)
        self:hit('favorite:'..i,1170,y,455,48)
    end
    self:button('favorites-prev','<',1170,807,56,40,false)
    self:text(string.format('%d / %d',favoritePage,math.max(1,math.ceil(#favorites/9))),1234,815,310,30,16,colors.muted,true)
    self:button('favorites-next','>',1569,807,56,40,false)
    self:button('up','MOVE UP',1170,866,140,42,false)
    self:button('down','MOVE DOWN',1328,866,140,42,false)
    self:button('remove','REMOVE',1486,866,140,42,false)
    self:text('F10 / ESC  CLOSE     ·     HOLD ALT IN GAME TO USE YOUR WHEEL',290,938,1330,30,16,colors.muted,true)
    self:addCursor()
    self.widget:SetVisibility(4)
end
function UI:addCursor()
    self.cursor=self:image(self:texture('cursor'),960,540,27,36)
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
function UI:hide() if valid(self.widget) then self.widget:SetVisibility(1) end end
function UI:destroy() if valid(self.widget) then self.widget:RemoveFromParent() end end
return UI
