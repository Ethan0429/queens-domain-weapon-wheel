-- A separate, additive mix preserves the game's music/SFX volume settings.
-- All loaded sound classes get one pitch multiplier, including UI-class music.
-- The low-pass is our own master-submix effect; only that effect is removed.
local Audio={};Audio.__index=Audio
local PITCH=.5
local CUTOFF=2200
local FADE_IN,FADE_OUT=.16,.02
local function valid(o) return o and o:IsValid() end
local function gs() return StaticFindObject('/Script/Engine.Default__GameplayStatics') end
local function mixer() return StaticFindObject('/Script/AudioMixer.Default__AudioMixerBlueprintLibrary') end
local function keep(name,value) ModRef:SetSharedVariable('QueensWheelAudio'..name,value) end
local function saved(name) return ModRef:GetSharedVariable('QueensWheelAudio'..name) end
function Audio.new()
    return setmetatable({mix=saved('Mix'),filter=saved('Filter'),
        mixActive=saved('MixActive') or false,filterActive=saved('FilterActive') or false,
        cutoff=20000,target=20000,active=false},Audio)
end
function Audio:construct(className,objectName,c)
    -- Root these two small runtime objects so GC cannot collect an active effect.
    -- Reuse them across reloads instead of creating new objects on every opening.
    return StaticConstructObject(StaticFindObject(className),c.gi,FName(objectName),0,0x40000000)
end
function Audio:prepare(c)
    if not valid(self.mix) then
        self.mix=self:construct('/Script/Engine.SoundMix','QueensWheelSlowMotionMix',c)
        assert(valid(self.mix),'Cannot create slow-motion audio mix')
        self.mix.InitialDelay=0;self.mix.Duration=-1
        self.mix.FadeInTime=FADE_IN;self.mix.FadeOutTime=FADE_OUT
        keep('Mix',self.mix)
    end
    if not valid(self.filter) then
        self.filter=self:construct('/Script/Synthesis.SubmixEffectFilterPreset','QueensWheelSlowMotionFilter',c)
        assert(valid(self.filter),'Cannot create slow-motion audio filter')
        -- Scalar UFunctions avoid marshaling any native audio settings structs.
        self.filter:SetFilterType(0) -- LowPass
        self.filter:SetFilterAlgorithm(0) -- OnePole, without resonant gain.
        self.filter:SetFilterQ(.707)
        self.filter:SetFilterCutoffFrequency(20000)
        keep('Filter',self.filter)
    end
end
function Audio:ramp(c,target,duration)
    self.from=self.cutoff;self.target=target;self.began=gs():GetRealTimeSeconds(c.pc)
    self.duration=duration
end
function Audio:start(c)
    self:prepare(c)
    for _,soundClass in ipairs(FindAllOf('SoundClass') or {}) do
        if valid(soundClass) and soundClass:GetFName():ToString()~='Default__SoundClass' then
            -- Children are listed separately, so never multiply a hierarchy twice.
            gs():SetSoundMixClassOverride(c.pc,self.mix,soundClass,1,PITCH,FADE_IN,false)
        end
    end
    if not self.mixActive then
        -- Record before native calls so the error cleanup can undo partial setup.
        self.mixActive=true;keep('MixActive',true)
        gs():PushSoundMixModifier(c.pc,self.mix)
    end
    if not self.filterActive then
        self.filter:SetFilterCutoffFrequency(20000);self.cutoff=20000
        self.filterActive=true;keep('FilterActive',true)
        mixer():AddMasterSubmixEffect(c.pc,self.filter)
    end
    self.active=true
    self:ramp(c,CUTOFF,FADE_IN)
end
function Audio:stop(c,immediate)
    self.active=false
    if self.mixActive and valid(self.mix) then
        gs():PopSoundMixModifier(c.pc,self.mix)
        self.mixActive=false;keep('MixActive',false)
    end
    if self.filterActive and valid(self.filter) then
        if immediate then
            mixer():RemoveMasterSubmixEffect(c.pc,self.filter)
            self.filterActive=false;keep('FilterActive',false)
            self.cutoff=20000;self.target=20000;self.began=nil
        else self:ramp(c,20000,FADE_OUT) end
    end
end
function Audio:update(c)
    if not self.filterActive or not self.began or not valid(self.filter) then return end
    local t=math.max(0,math.min(1,(gs():GetRealTimeSeconds(c.pc)-self.began)/self.duration))
    -- Log-frequency interpolation gives a smooth, perceptually even sweep.
    local eased=t*t*(3-2*t)
    self.cutoff=math.exp(math.log(self.from)+(math.log(self.target)-math.log(self.from))*eased)
    self.filter:SetFilterCutoffFrequency(self.cutoff)
    if t>=1 then
        self.began=nil
        if not self.active then self:stop(c,true) end
    end
end
return Audio
