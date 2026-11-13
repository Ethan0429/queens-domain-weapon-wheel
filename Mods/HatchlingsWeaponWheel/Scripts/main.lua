local source=debug.getinfo(1,'S').source:gsub('^@',''):gsub('\\','/')
local ROOT=assert(source:match('^(.*)/Scripts/main.lua$'),'Cannot locate mod folder')
local Model=dofile(ROOT..'/Scripts/model.lua')
local UI=dofile(ROOT..'/Scripts/ui.lua')
local Audio=dofile(ROOT..'/Scripts/audio.lua')
local audio=Audio.new()
local UE=require('UEHelpers')
local DATA=(os.getenv('LOCALAPPDATA') or '.')..'/QueensDomain/Saved/WeaponWheel/'
local CONFIG=DATA..'config.lua'
local TAG='[HatchlingsWeaponWheel] '
local config,initialized=nil,false
local owned,lookup={},{}
local session,view,pending=nil,nil,nil
local page,catalogPage,favoritePage,selectedFavorite=1,1,1,1
local wasAlt,wasRight,wasEsc=false,false,false
local clickRequested,rightRequested=false,false
local editorRequested,waitForAltUp=false,false
local frame,lastError,lastStatus=0,nil,''
local hooksReady=false
local pageBy
local diagnosticHold=false
local function widgets() return StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary') end

os.execute('mkdir "'..DATA:gsub('/','\\')..'" >NUL 2>NUL')

local function log(s) print(TAG..tostring(s)..'\n') end
local function valid(o) return o~=nil and o:IsValid() end
local function key(n) return {KeyName=FName(n)} end
local function down(pc,n) return pc:IsInputKeyDown(key(n)) end
local function path(o) return o:GetFullName():match('^%S+ (.+)$') end
local function same(a,b) return valid(a) and valid(b) and a:GetAddress()==b:GetAddress() end
local function context()
    local pc=UE.GetPlayerController()
    if not valid(pc) then return nil end
    local pawn=pc.Pawn
    if not valid(pawn) or not pawn:GetClass():GetFName():ToString():find('PlayerChar',1,true) then return nil end
    local gi=FindFirstOf('FS_GameInstance_C')
    if not valid(gi) then return nil end
    local save=gi.ActiveSaveSlot
    if not valid(save) or not valid(pawn.WeaponSelection) then return nil end
    return {pc=pc,pawn=pawn,gi=gi,save=save,world=pawn:GetWorld():GetFName():ToString(),owner=pc:GetAddress()}
end
local function busy(c)
    if UE.GetGameplayStatics():IsGamePaused(c.pawn) or c.gi.InCutscene or c.pawn.Health<=0 then return true end
    for _,name in ipairs({'CurrentGameMenu','CurrentShopMenu','CurrentSaveMenu','KeyMenu'}) do
        local menu=c.pawn[name]
        if valid(menu) then
            local ok,shown=pcall(function() return menu:IsInViewport() and menu:IsVisible() and menu:GetRenderOpacity()>.01 end)
            if ok and shown then return true end
        end
    end
    return false
end
local function writeConfig()
    local f,err=io.open(CONFIG..'.tmp','wb');assert(f,'Cannot save wheel configuration: '..tostring(err))
    f:write(Model.serialize(config));f:close()
    os.remove(CONFIG);assert(os.rename(CONFIG..'.tmp',CONFIG),'Cannot replace wheel configuration')
end
local function readConfig()
    local f=io.open(CONFIG,'rb')
    if not f then config=Model.clean({});return false end
    local bytes=f:read('a');f:close()
    local chunk,err=load(bytes,'@'..CONFIG,'t',{})
    if not chunk then error('Invalid wheel config: '..tostring(err)) end
    local ok,value=pcall(chunk);assert(ok,'Invalid wheel config data')
    config=Model.clean(value);return true
end
local function refreshInventory(c)
    owned,lookup={},{}
    c.save.InventoryContents:ForEach(function(k,v)
        local item=k:get()
        if valid(item) and v:get()>0 and (item.Weapon or item.EquipSlot==3) then
            local entry={item=item,path=path(item),name=item.Name:ToString(),sort=item.SortOrder}
            owned[#owned+1]=entry;lookup[entry.path]=entry
        end
    end)
    table.sort(owned,function(a,b) return a.name:lower()<b.name:lower() end)
    if not initialized then
        local existed=readConfig()
        if not existed then

            local equipped={}
            c.save.EquipmentSlots:ForEach(function(k,v)
                local item=v:get();local id=k:get()
                if id>=2000 and id<3000 and valid(item) then equipped[#equipped+1]={id=id,path=path(item)} end
            end)
            table.sort(equipped,function(a,b) return a.id<b.id end)
            for _,e in ipairs(equipped) do if lookup[e.path] and not Model.index(config.favorites,e.path) then config.favorites[#config.favorites+1]=e.path end end
            for _,e in ipairs(owned) do if not Model.index(config.favorites,e.path) then config.favorites[#config.favorites+1]=e.path end end
            writeConfig()
        end
        initialized=true;log('Inventory ready: '..#owned..' owned weapons; '..#config.favorites..' favorites')
    end
end
local function currentPath(c)
    local inHand=c.pawn.CurrentInHandWeapon
    if valid(inHand) and valid(inHand.ItemData) then return path(inHand.ItemData) end
    local item=c.save.CurrentlySelectedWeapon
    return valid(item) and path(item) or nil
end
local function wheelItems() return Model.resolve(config.favorites,lookup) end
local function renderWheel(c)
    local entries,p,pages=Model.page(wheelItems(),page,config.slots_per_page);page=p
    local current=currentPath(c)
    view:wheel(entries,page,pages,current,lookup[current]);session.entries=entries
end
local function renderEditor()
    catalogPage=math.max(1,math.min(catalogPage,math.max(1,math.ceil(#owned/UI.CATALOG_PER_PAGE))))
    favoritePage=math.max(1,math.min(favoritePage,math.max(1,math.ceil(#config.favorites/UI.FAVORITES_PER_PAGE))))
    selectedFavorite=math.max(1,math.min(selectedFavorite,math.max(1,#config.favorites)))
    view:editor(owned,config.favorites,lookup,catalogPage,favoritePage,selectedFavorite)
end
local function restoreControls(s)

    pcall(function() audio:stop(s.c,false) end)
    pcall(function() UE.GetGameplayStatics():SetGlobalTimeDilation(s.c.pc,s.timeScale) end)
    if valid(s.c.pc) then
        pcall(function() s.c.pc:SetIgnoreLookInput(false) end)
        pcall(function() s.c.pc:SetIgnoreMoveInput(false) end)
        local menuOpen=false
        pcall(function() menuOpen=busy(s.c) end)
        if not menuOpen then
            pcall(function() s.c.pc.bShowMouseCursor=s.cursor end)
            pcall(function() s.c.pc.DefaultMouseCursor=s.defaultCursor end)
            pcall(function() s.c.pc.CurrentMouseCursor=s.currentCursor end)
            pcall(function() widgets():SetInputMode_GameOnly(s.c.pc) end)
            if s.mouseCaptureMode~=nil then
                pcall(function() UE.GetGameplayStatics():SetViewportMouseCaptureMode(s.c.pc,s.mouseCaptureMode) end)
            end
        end
    end
    if s.disabled and valid(s.c.pawn) and valid(s.c.pc) then pcall(function() s.c.pawn:EnableInput(s.c.pc) end) end
    ModRef:SetSharedVariable('QueensWheelActive',false)
end
local function close(commit)
    local s=session
    if not s then return end
    session=nil
    clickRequested,rightRequested=false,false
    diagnosticHold=false
    if view then view:hide() end
    restoreControls(s)
    if commit and s.mode=='wheel' and s.hover and s.entries[s.hover] then
        pending={entry=s.entries[s.hover],owner=s.c.owner,world=s.c.world,attempts=0}
    end
    log('Closed '..s.mode..'; restored time scale '..tostring(s.timeScale))
end
-- Releasing game mouse capture makes the engine restore the cursor to where it was before
-- capture a frame or two later, so keep it pinned to the center briefly after opening.
local RECENTER_FRAMES=8
local function centerMouse(c)
    local viewport=StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary'):GetViewportSize(c.pc)
    c.pc:SetMouseLocation(math.floor(viewport.X/2),math.floor(viewport.Y/2))
end
local function open(c,mode)
    if busy(c) then return end
    refreshInventory(c)
    if not view or not valid(view.widget) or view.pc:GetAddress()~=c.owner then
        if view then view:destroy() end
        view=UI.new(c.pc,ROOT)
    end
    local gs=UE.GetGameplayStatics()
    session={c=c,mode=mode,timeScale=gs:GetGlobalTimeDilation(c.pawn),cursor=c.pc.bShowMouseCursor,
        defaultCursor=c.pc.DefaultMouseCursor,currentCursor=c.pc.CurrentMouseCursor,
        mouseCaptureMode=gs:GetViewportMouseCaptureMode(c.pc),hover=nil,disabled=false}

    ModRef:SetSharedVariable('QueensWheelActive',true)
    ModRef:SetSharedVariable('QueensWheelPreviousTimeScale',session.timeScale)
    ModRef:SetSharedVariable('QueensWheelPreviousCursor',session.cursor)
    ModRef:SetSharedVariable('QueensWheelPreviousDefaultCursor',session.defaultCursor)
    ModRef:SetSharedVariable('QueensWheelPreviousCurrentCursor',session.currentCursor)
    ModRef:SetSharedVariable('QueensWheelPreviousMouseCaptureMode',session.mouseCaptureMode)
    ModRef:SetSharedVariable('QueensWheelController',c.pc)
    ModRef:SetSharedVariable('QueensWheelPawn',c.pawn)
    gs:SetGlobalTimeDilation(c.pawn,.1)
    if mode=='wheel' then audio:start(c) end
    c.pc:SetIgnoreLookInput(true);c.pc:SetIgnoreMoveInput(true)
    c.pawn:CancelCurrentAttacks()
    c.pawn:DisableInput(c.pc);session.disabled=true
    c.pc.bShowMouseCursor=true
    c.pc.DefaultMouseCursor=0;c.pc.CurrentMouseCursor=0
    widgets():SetInputMode_GameAndUIEx(c.pc,CreateInvalidObject(),0,false)
    gs:SetViewportMouseCaptureMode(c.pc,0)
    if mode=='wheel' then
        local entries=wheelItems();local current=currentPath(c)
        for i,e in ipairs(entries) do if e.path==current then page=math.floor((i-1)/config.slots_per_page)+1;break end end
        renderWheel(c)
    else renderEditor() end
    centerMouse(c);session.recenterUntil=frame+RECENTER_FRAMES;view:moveCursor(960,540)
    clickRequested,rightRequested=false,false
    wasRight=down(c.pc,'RightMouseButton');wasEsc=down(c.pc,'Escape')
    log('Opened '..mode..' at time scale '..gs:GetGlobalTimeDilation(c.pawn))
end
local function selectWeapon(c,request)
    local entry=request.entry
    if not lookup[entry.path] or c.save:GetInventoryCount(entry.item)<=0 then log('Selection refused: weapon is no longer owned');return true end
    if currentPath(c)==entry.path then return true end
    if c.pawn.WeaponsAreSwapping or c.pawn:AreWeaponsDisabled() then return false end
    if not request.prepared then
        local slot=nil
        c.save.EquipmentSlots:ForEach(function(k,v)
            local id=k:get()
            if id>=2000 and id<3000 and same(v:get(),entry.item) then slot=id-2000 end
        end)
        if slot==nil then
            slot=math.max(0,math.min(2,c.pawn.WeaponSelection.SelectedWeaponSlot))
            c.pawn:EquipItem(entry.item,slot)
        end
        request.prepared=true;request.slot=slot
    end
    if not c.pawn.ItemToWeaponMap:Contains(entry.item) then return false end
    if not valid(c.pawn.ItemToWeaponMap:Find(entry.item):get()) then return false end

    c.pawn:EquipItemWeapon(entry.item)
    log('Requested '..entry.name..' via game equip functions (slot '..request.slot..')')
    return true
end
local function editorClick(id)
    if not id then return end
    local idx=tonumber(id:match(':(%d+)$'))
    if id:find('^toggle:') then
        local e=owned[idx];local added=Model.toggle(config.favorites,e.path)
        if added then selectedFavorite=#config.favorites;favoritePage=math.ceil(selectedFavorite/UI.FAVORITES_PER_PAGE) end
        writeConfig()
    elseif id:find('^favorite:') then selectedFavorite=idx
    elseif id=='up' or id=='down' then
        selectedFavorite=Model.move(config.favorites,selectedFavorite,id=='up' and -1 or 1)
        favoritePage=math.ceil(selectedFavorite/UI.FAVORITES_PER_PAGE);writeConfig()
    elseif id=='remove' then table.remove(config.favorites,selectedFavorite);writeConfig()
    elseif id=='add-all' then
        for _,e in ipairs(owned) do if not Model.index(config.favorites,e.path) then config.favorites[#config.favorites+1]=e.path end end
        writeConfig()
    elseif id=='catalog-prev' then catalogPage=catalogPage-1
    elseif id=='catalog-next' then catalogPage=catalogPage+1
    elseif id=='favorites-prev' then favoritePage=favoritePage-1
    elseif id=='favorites-next' then favoritePage=favoritePage+1
    elseif id=='done' then close(false);waitForAltUp=true;return end
    renderEditor()
end
local function status(c)
    local mode=session and session.mode or 'closed'
    local current=c and currentPath(c) or ''
    local hovered=session and session.hover and session.entries and session.entries[session.hover] or nil
    local line=string.format('mode=%s\nowned=%d\nfavorites=%d\npage=%d\ncurrent=%s\nhover=%s\ntime_scale=%.5f\ncursor_x=%.1f\ncursor_y=%.1f\naudio_pitch=%.2f\naudio_filter_hz=%.0f\naudio_filter_active=%s\nerror=%s\n',
        mode,#owned,config and #config.favorites or 0,page,current or '',hovered and hovered.name or '',
        c and UE.GetGameplayStatics():GetGlobalTimeDilation(c.pawn) or 1,
        session and session.mouseX or -1,session and session.mouseY or -1,audio.mixActive and .5 or 1,
        audio.cutoff,tostring(audio.filterActive),lastError or '')
    if line~=lastStatus then
        local f=io.open(DATA..'status.txt','wb');if f then f:write(line);f:close() end
        lastStatus=line
    end
end
local function recoverReload(c)
    audio:stop(c,true)
    if ModRef:GetSharedVariable('QueensWheelActive') then
        local pc=ModRef:GetSharedVariable('QueensWheelController');local pawn=ModRef:GetSharedVariable('QueensWheelPawn')
        restoreControls({c={pc=valid(pc) and pc or c.pc,pawn=valid(pawn) and pawn or c.pawn},
            timeScale=ModRef:GetSharedVariable('QueensWheelPreviousTimeScale') or 1,
            cursor=ModRef:GetSharedVariable('QueensWheelPreviousCursor') or false,
            defaultCursor=ModRef:GetSharedVariable('QueensWheelPreviousDefaultCursor') or 0,
            currentCursor=ModRef:GetSharedVariable('QueensWheelPreviousCurrentCursor') or 0,
            mouseCaptureMode=ModRef:GetSharedVariable('QueensWheelPreviousMouseCaptureMode'),disabled=true})
        log('Recovered input/time state after script reload')
    end
end
local function diagnostics(c)

    local file=io.open(DATA..'diagnostic.request','rb');if not file then return end
    local command=file:read('a'):gsub('%s+$','');file:close();os.remove(DATA..'diagnostic.request')
    if command=='preview' and not session then open(c,'wheel');diagnosticHold=true
    elseif command=='editor' and not session then open(c,'editor')
    elseif command=='close' then close(false)
    elseif command=='screenshot' then UE.GetKismetSystemLibrary():ExecuteConsoleCommand(c.pawn,'Shot SHOWUI',c.pc)
    elseif command=='inspect' then
        local f=io.open(DATA..'inventory.txt','wb')
        if f then for _,e in ipairs(owned) do f:write(e.name..'\t'..e.path..'\n') end;f:close() end
    end
end
local function tick()
    frame=frame+1
    if frame==1 then
        local probePc=UE.GetPlayerController();local probeGi=FindFirstOf('FS_GameInstance_C')
        log('Polling active; controller='..(valid(probePc) and probePc:GetFullName() or 'none')..'; game instance='..(valid(probeGi) and probeGi:GetFullName() or 'none'))
        if valid(probePc) then log('Polling pawn='..(valid(probePc.Pawn) and probePc.Pawn:GetFullName() or 'none')) end
    end
    local c=context()
    if not c then close(false);wasAlt=false;return end
    if not initialized then recoverReload(c);refreshInventory(c) end
    audio:update(c)
    if not hooksReady then
        local ok=pcall(function()
            RegisterHook('/Script/QueensDomain.FS_PlayerController:OnWindowUnfocused',function() close(false);waitForAltUp=true end)
        end)
        hooksReady=ok
    end
    if session and (session.c.owner~=c.owner or session.c.world~=c.world or busy(c)) then close(false);waitForAltUp=true end
    local alt=down(c.pc,'LeftAlt') or down(c.pc,'RightAlt')
    if not alt then waitForAltUp=false end
    if editorRequested then
        editorRequested=false
        if session then
            if session.mode=='editor' then close(false);waitForAltUp=true
            else close(false);open(c,'editor') end
        else open(c,'editor') end
    elseif not session and alt and not wasAlt and not waitForAltUp then open(c,'wheel') end
    if session then

        c.pc.bShowMouseCursor=true
        c.pc.DefaultMouseCursor=0;c.pc.CurrentMouseCursor=0
        local cursorX,cursorY
        if frame<=(session.recenterUntil or 0) then centerMouse(c);cursorX,cursorY=960,540
        else cursorX,cursorY=view:mouse() end
        session.mouseX,session.mouseY=cursorX,cursorY
        view:moveCursor(cursorX,cursorY)
        if c.pc:WasInputKeyJustPressed(key('MouseScrollUp')) then pageBy(-1) end
        if c.pc:WasInputKeyJustPressed(key('MouseScrollDown')) then pageBy(1) end
        local click=clickRequested;local right=rightRequested or down(c.pc,'RightMouseButton');local esc=down(c.pc,'Escape')
        clickRequested,rightRequested=false,false
        if (esc and not wasEsc) or (right and not wasRight and session.mode=='wheel') then close(false);waitForAltUp=true
        elseif session.mode=='wheel' then
            local x,y=cursorX,cursorY;session.hover=Model.slotAt(x-960,y-540,#session.entries,UI.WHEEL_INNER,UI.WHEEL_OUTER)
            view:hoverSlot(session.hover)
            if wasAlt and not alt and not diagnosticHold then close(true) end
        elseif session.mode=='editor' then
            local target=view:hitAt(cursorX,cursorY)
            view:hoverEditor(target)
            if click then editorClick(target) end
        end
        wasRight,wasEsc=right,esc
    end
    wasAlt=alt
    if pending and not session then
        if pending.owner~=c.owner or pending.world~=c.world or busy(c) then pending=nil
        else
            pending.attempts=pending.attempts+1
            if pending.issued then
                if currentPath(c)==pending.entry.path then log('Equipped '..pending.entry.name);pending=nil
                elseif pending.attempts>180 then log('Weapon switch did not complete; selection canceled');pending=nil end
            elseif currentPath(c)==pending.entry.path then pending=nil
            elseif selectWeapon(c,pending) then pending.issued=true
            elseif pending.attempts>180 then log('Weapon switch was blocked by the game');pending=nil end
        end
    end
    if frame%15==0 then
        diagnostics(c);status(c)
    end
end
RegisterKeyBind(Key.F10,function() editorRequested=true end)
local function requestClick()
    if session and session.mode=='editor' then clickRequested=true end
end
local function requestRightClick()
    if session and session.mode=='wheel' then rightRequested=true end
end
RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,requestClick)
RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,{ModifierKey.ALT},requestClick)
RegisterKeyBind(Key.RIGHT_MOUSE_BUTTON,requestRightClick)
RegisterKeyBind(Key.RIGHT_MOUSE_BUTTON,{ModifierKey.ALT},requestRightClick)
pageBy=function(delta)
    if not session then return end
    if session.mode=='wheel' then page=page+delta;renderWheel(session.c)
    else
        local x=view:mouse()
        if x>=1150 then favoritePage=favoritePage+delta else catalogPage=catalogPage+delta end
        renderEditor()
    end
end
pcall(function() RegisterLoadMapPreHook(function() close(false);waitForAltUp=true end) end)
ModRef.OnUnload=function()
    pcall(function() close(false) end)
    pcall(function() local c=context();if c then audio:stop(c,true) end end)
    if view then pcall(function() view:destroy() end) end
end
local function protectedTick()
    local ok,err=pcall(tick)
    if not ok then
        pcall(function() close(false) end)
        pcall(function() local c=context();if c then audio:stop(c,true) end end)
        if tostring(err)~=lastError then lastError=tostring(err);log('ERROR '..lastError) end
    end
end
local queued=false
LoopAsync(10,function()
    if not queued then queued=true;ExecuteInGameThread(function() protectedTick();queued=false end) end
    return false
end)
log('Loaded v0.2.1. Hold Alt for wheel; F10 edits favorites.')
