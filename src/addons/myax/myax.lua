
_addon.author   = 'Eleven Pies';
_addon.name     = 'MyActionsStarted';
_addon.version  = '3.0.0';

require 'common'
require 'mob.mobinfo'

local lor_packets = require 'lor.lor_packets_mod'

---------------------------------------------------------------------------------------------------
-- desc: MyActionsStarted global table.
---------------------------------------------------------------------------------------------------
local axstarted = { };

-- Alias for on-top font object must be last alphabetically
local font_alias = '__myax_addon_zz';
local font_alias_o1 = '__myax_addon_o1';
local font_alias_o2 = '__myax_addon_o2';
local font_alias_o3 = '__myax_addon_o3';
local font_alias_o4 = '__myax_addon_o4';

local lastrender = 0;

---------------------------------------------------------------------------------------------------
-- desc: Default MyActionsStarted configuration table.
---------------------------------------------------------------------------------------------------
local default_config =
{
    font =
    {
        reference       = { 1680, 1050 },
        family          = 'Arial',
        size            = 28,
        color           = 0x99FEFEFE,
        position        = { 520, 0 },
        offset          = { 0, 80 },
        bold            = true,
        italic          = true,
        outline_enabled = true,
        outline_color   = 0x992B2B2B,
        outline_size    = 2
    },
    show_actor_self = false,
    show_actor_nonself = false,
    show_actor_mob = true
};
local myax_config = default_config;

local function createFont(conf, alias, color, x, y, parent)
    -- Create the font object..
    local f = AshitaCore:GetFontManager():Create(alias);
    f:SetColor(color);
    f:SetFontFamily(conf.font.family);
    f:SetFontHeight(conf.font.size);
    f:SetBold(conf.font.bold);
    f:SetItalic(conf.font.italic);
    f:SetPositionX(x);
    f:SetPositionY(y);
    f:SetText('');
    f:SetVisibility(true);

    if (parent ~= nil) then
        f:SetParent(parent);
    end

    return f;
end

local function createFontAll(conf)
    local x = conf.font.position[1];
    local y = conf.font.position[2];
    local w = conf.font.outline_size;

    local f = createFont(conf, font_alias, conf.font.color, x, y, nil);

    if (conf.font.outline_enabled) then
        createFont(conf, font_alias_o1, conf.font.outline_color, 0 - w, 0 - w, f);
        createFont(conf, font_alias_o2, conf.font.outline_color, 0 - w, 0 + w, f);
        createFont(conf, font_alias_o3, conf.font.outline_color, 0 + w, 0 - w, f);
        createFont(conf, font_alias_o4, conf.font.outline_color, 0 + w, 0 + w, f);
    end
end

local function deleteFont(conf, alias)
    -- Delete the font object..
    AshitaCore:GetFontManager():Delete(alias);
end

local function deleteFontAll(conf)
    if (conf.font.outline_enabled) then
        deleteFont(conf, font_alias_o1);
        deleteFont(conf, font_alias_o2);
        deleteFont(conf, font_alias_o3);
        deleteFont(conf, font_alias_o4);
    end

    deleteFont(conf, font_alias);
end

local function setText(conf, alias, text)
    local f = AshitaCore:GetFontManager():Get(alias);
    if (f == nil) then return; end

    f:SetText(text);
end

local function setTextAll(conf, text)
    if (conf.font.outline_enabled) then
        setText(conf, font_alias_o1, text);
        setText(conf, font_alias_o2, text);
        setText(conf, font_alias_o3, text);
        setText(conf, font_alias_o4, text);
    end

    setText(conf, font_alias, text);
end

local function round(num) 
    if num >= 0 then
        return math.floor(num + 0.5) 
    else
        return math.ceil(num - 0.5)
    end
end

local function unsz(s)
    local pos = string.find(s, '\0');
    if (pos ~= nil and pos > 0) then
        return string.sub(s, 1, pos - 1);
    end

    return s;
end

local function findEntity(entityid)
    -- targid < 0x400
    --   TYPE_MOB || TYPE_NPC || TYPE_SHIP
    -- targid < 0x700
    --   TYPE_PC
    -- targid < 0x800
    --   TYPE_PET

    -- Search players
    for x = 0x400, 0x6FF do
        local ent = GetEntity(x);
        if (ent ~= nil and ent.ServerId == entityid) then
            return { id = entityid, index = x, name = ent.Name };
        end
    end

    return nil;
end

local function getEntityInfo(zoneid, entityid)
    local zonemin = bit.lshift(zoneid, 12) + 0x1000000;

    local entityindex;
    local entityname;
    local entitytype;
    local isself = false;

    -- Check if entity looks like a mobid
    if (bit.band(zonemin, entityid) == zonemin) then
        entityindex = bit.band(entityid, 0xfff);
        entityname = MobNameFromTargetId(entityindex);
        entitytype = 0x04; -- TYPE_MOB
    else
        -- Otherwise try finding player in NPC map
        local entityResult = findEntity(entityid);
        if (entityResult ~= nil) then
            entityindex = entityResult.index;
            entityname = entityResult.name;
            entitytype = 0x01; -- TYPE_PC

            -- If player, determine if player is self
            local selftarget = AshitaCore:GetDataManager():GetParty():GetMemberTargetIndex(0);
            if (entityindex == selftarget) then
                isself = true;
            end
        else
            entityindex = 0;
            entityname = nil;
            entitytype = 0x00;
        end
    end

    if (entityname == nil) then
        entityname = 'UNKNOWN_MOB';
    end

    -- Convert null terminated strings
    return { id = entityid, index = entityindex, name = unsz(entityname), entitytype = entitytype, isself = isself };
end

local function getSpellInfo(spellid)
    local spellobj = AshitaCore:GetResourceManager():GetSpellById(spellid);
    local spellname;
    if (spellobj ~= nil) then
        spellname = spellobj.Name[0];
    end

    if (spellname == nil) then
        spellname = 'UNKNOWN_SPELL';
    end

    return { id = spellid, name = spellname };
end

local function getJobAbilityInfo(jobabilityid)
    -- Job abilities begin after 512
    local jobabilityobj = AshitaCore:GetResourceManager():GetAbilityById(jobabilityid + 512);
    local jobabilityname;
    if (jobabilityobj ~= nil) then
        jobabilityname = jobabilityobj.Name[0];
    end

    if (jobabilityname == nil) then
        jobabilityname = 'UNKNOWN_JOBABILITY';
    end

    return { id = jobabilityid, name = jobabilityname };
end

local function getMobAbilityInfo(mobabilityid)
    if (mobabilityid < 256) then
        return { id = mobabilityid, name = 'OUTOFRANGE_MOBABILITY' };
    end

    local mobabilityname = AshitaCore:GetResourceManager():GetString('mobskills', mobabilityid - 256);

    if (mobabilityname == nil) then
        mobabilityname = 'UNKNOWN_MOBABILITY';
    end

    return { id = mobabilityid, name = mobabilityname };
end

local function getDanceInfo(danceid)
    -- Same as job abilities
    -- Job abilities begin after 512
    local danceobj = AshitaCore:GetResourceManager():GetAbilityById(danceid + 512);
    local dancename;
    if (danceobj ~= nil) then
        dancename = danceobj.Name[0];
    end

    if (dancename == nil) then
        dancename = 'UNKNOWN_DANCE';
    end

    return { id = danceid, name = dancename };
end

local function get_ax(category, param, actor_id, actor_name, actor_type, actor_isself, target_id, target_name, target_type, target_isself, message_id, action_param, ax_id, ax_name)
    local axkey = tostring(actor_id) .. '_' .. tostring(target_id) .. '_' .. tostring(ax_id);

    if (axstarted.actions == nil) then
        axstarted.actions = { };
    end

    local axitem = axstarted.actions[axkey];
    if (axitem == nil) then
        axitem = { };
        axitem.category = category;
        axitem.param = param;
        axitem.actor_id = actor_id;
        axitem.actor_name = actor_name;
        axitem.actor_type = actor_type;
        axitem.actor_isself = actor_isself;
        axitem.target_id = target_id;
        axitem.target_name = target_name;
        axitem.target_type = target_type;
        axitem.target_isself = target_isself;
        axitem.message_id = message_id;
        axitem.action_param = action_param;
        axitem.ax_id = ax_id;
        axitem.ax_name = ax_name;
        axstarted.actions[axkey] = axitem;
    end

    return axitem;
end

local function handleActionPacket(id, size, packet)
    -- Action packet only sends actor/target id, not index

    local zoneid = MobInfoZoneId();

    local pp = lor_packets.parse_action_full(packet);

    local actorInfo = getEntityInfo(zoneid, pp.actor_id); -- For debug purposes

    for x = 1, pp.target_count do
        local target = pp.targets[x];

        local hasTarget;

        local targetInfo = getEntityInfo(zoneid, target.id);
        if (targetInfo ~= nil and targetInfo.entitytype > 0x00) then
            hasTarget = true;
        else
            hasTarget = false;
        end

        for y = 1, target.action_count do
            local action = target.actions[y];

            local spellInfo;
            local jobAbilityInfo;
            local mobAbilityInfo;
            local danceInfo;

            local ax_id;
            local ax_name;
            local has_ax = false;

            if (pp.category == 6) then
                -- ACTION_JOBABILITY_FINISH = 6
                -- 100 - The <player> uses ..
                -- message id varies

                jobAbilityInfo = getJobAbilityInfo(pp.param);

                ax_id = jobAbilityInfo.id;
                ax_name = jobAbilityInfo.name;
                has_ax = true;
            elseif (pp.category == 7) then
                -- ACTION_WEAPONSKILL_START = 7 (and [fake] ACTION_MOBABILITY_START = 33)
                -- 043 - The <player> readies <ability>.

                mobAbilityInfo = getMobAbilityInfo(action.param);

                ax_id = mobAbilityInfo.id;
                ax_name = mobAbilityInfo.name;
                has_ax = true;
            elseif (pp.category == 8) then
                -- ACTION_MAGIC_START = 8
                -- 327 - The <player> starts casting <spell> on <target>.

                -- Getting message_id of zero when casting is interrupted
                if (action.message_id > 0) then
                    spellInfo = getSpellInfo(action.param);

                    ax_id = spellInfo.id;
                    ax_name = spellInfo.name;
                    has_ax = true;
                end
            elseif (pp.category == 14) then
                -- 100 - The <player> uses ..

                danceInfo = getDanceInfo(pp.param);

                ax_id = danceInfo.id;
                ax_name = danceInfo.name;
                has_ax = true;
            end

            if (has_ax) then
                local axitem = get_ax(pp.category, pp.param, pp.actor_id, actorInfo.name, actorInfo.entitytype, actorInfo.isself, target.id, targetInfo.name, targetInfo.entitytype, targetInfo.isself, action.message_id, action.param, ax_id, ax_name);
                axitem.modified = os.clock();
            end
        end
    end
end

ashita.register_event('command', function(cmd, nType)
    local args = cmd:args();

    if (#args > 0 and args[1] == '/ax')  then
        if (#args > 1)  then
            if (args[2] == 'reset')  then
                print('Resetting ax...');
                axstarted = { };
                return true;
            elseif (args[2] == 'debug')  then
                -- TODO: Clean up display (e.g., show action per line)
                print('Debug ax...');
                if (axstarted.actions ~= nil) then
                    for k, v in pairs(axstarted.actions) do
                        print(tostring(k) .. ':' .. ashita.settings.JSON:encode(v));
                    end
                else
                    print('Empty!');
                end
                return true;
            elseif (args[2] == 'dump')  then
                print('Dumping ax...');
                ashita.settings.save(_addon.path .. 'settings/dump.json', axstarted.actions);
                return true;
            end
        end
    end

    return false;
end);

ashita.register_event('incoming_packet', function(id, size, packet)
    __mobinfo_incoming_packet(id, size, packet);

    -- Check for zone-in packets..
    if (id == 0x0A) then
        axstarted = { };
    end

    if (id == 0x0028) then -- Action (Spells, Abilities, Weapon skills, etc.)
        handleActionPacket(id, size, packet);
        return false;
    end

    return false;
end );

ashita.register_event('load', function()
    __mobinfo_load();

    -- Attempt to load the MyActionsStarted configuration..
    myax_config = ashita.settings.load(_addon.path .. 'settings/myax.json') or default_config;
    myax_config = table.merge(default_config, myax_config);

    local window_x = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_x', 800);
    local window_y = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_y', 800);

    local scale_x = window_x / myax_config.font.reference[1];
    local scale_y = window_y / myax_config.font.reference[2];

    -- Build configuration with scaled dimensions
    local conf = { };
    conf.font = { };
    conf.font.size = myax_config.font.size * scale_y;

    -- Not scaling outline size
    ----conf.font.outline_size = myax_config.font.outline_size * scale_y;

    ----if (conf.font.outline_size < 1) then
    ----    conf.font.outline_size = 1;
    ----end

    -- Add in fixed offset (since native UI elements do not scale)
    conf.font.position = { round(myax_config.font.position[1] * scale_x) + myax_config.font.offset[1], round(myax_config.font.position[2] * scale_y) + myax_config.font.offset[2] };

    conf = table.merge(myax_config, conf);

    createFontAll(conf);
end );

ashita.register_event('unload', function()
    local window_x = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_x', 800);
    local window_y = AshitaCore:GetConfigurationManager():get_int32('boot_config', 'window_y', 800);

    local scale_x = window_x / myax_config.font.reference[1];
    local scale_y = window_y / myax_config.font.reference[2];

    local f = AshitaCore:GetFontManager():Get( font_alias );
    -- Subtract out fixed offset (since native UI elements do not scale)
    myax_config.font.position = { round((f:GetPositionX() - myax_config.font.offset[1]) / scale_x), round((f:GetPositionY() - myax_config.font.offset[2]) / scale_y) };

    -- Ensure the settings folder exists..
    if (not ashita.file.dir_exists(_addon.path .. 'settings')) then
        ashita.file.create_dir(_addon.path .. 'settings');
    end

    -- Save the configuration..
    ashita.settings.save(_addon.path .. 'settings/myax.json', myax_config);

    deleteFontAll(myax_config);
end );

---------------------------------------------------------------------------------------------------
-- func: Render
-- desc: Called when our addon is rendered.
---------------------------------------------------------------------------------------------------
ashita.register_event('render', function()
    local currenttime = os.clock();

    -- Only render at 1/10s tick
    if ((lastrender + 0.1) < currenttime) then
        lastrender = currenttime;

        ----local f = AshitaCore:GetFontManager():Get( font_alias );
        local e = { }; -- Effect entries..
        local rm = { };

        if (axstarted.actions ~= nil) then
            local count = 0;
            local totalcount = 0;
            local s;

            for k, v in pairs(axstarted.actions) do
                local axitem = v;

                local timeRemaining = axitem.modified - currenttime;

                local show = true;

                if (axitem.actor_type == 0x04) then
                    -- TYPE_MOB

                    if (myax_config.show_actor_mob == false) then
                        show = false;
                    end
                elseif (axitem.actor_type == 0x01) then
                    -- TYPE_PC

                    if (axitem.actor_isself == true) then
                        if (myax_config.show_actor_self == false) then
                            show = false;
                        end
                    else
                        if (myax_config.show_actor_nonself == false) then
                            show = false;
                        end
                    end
                end

                if (show) then
                    if (count < 32) then
                        if (axitem.actor_id == axitem.target_id) then
                            s = string.format('(%s) %s', axitem.actor_name, axitem.ax_name);
                        else
                            s = string.format('(%s) %s >>> %s', axitem.actor_name, axitem.ax_name, axitem.target_name);
                        end
                        table.insert(e, s);
                        count = count + 1;
                    end
                end

                if (timeRemaining < -5) then
                    table.insert(rm, k);
                end

                totalcount = totalcount + 1;
            end

            for k, v in pairs(rm) do
                axstarted.actions[v] = nil;
            end
        end

        local output = table.concat( e, '\n' );
        ----f:SetText( output );
        setTextAll(myax_config, output);
    end
end );
