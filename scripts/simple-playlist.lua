--[[
https://github.com/9beach/mpv-config/blob/main/scripts/simple-playlist.lua

This script provides script messages below:

* script-message simple-playlist sort date-desc
* script-message simple-playlist sort date-asc
* script-message simple-playlist sort date-desc startover

`sort` also support `size-asc`, `size-desc`, `name-asc`, `name-desc` with or without
`startover`.

* script-message simple-playlist shuffle
* script-message simple-playlist reverse
* script-message simple-playlist show
* script-message simple-playlist hide
* script-message simple-playlist display-toggle
* script-message simple-playlist playfirst
* script-message simple-playlist playlast
* script-message simple-playlist save

You can edit key binddings in `input.conf`.

Many parts in the code are from <https://github.com/jonniek/mpv-playlistmanager> and
<https://github.com/zsugabubus/dotfiles/blob/master/.config/mpv/scripts/playlist-filtersort.lua>.
]]

local options = require 'mp.options'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local o = {
    playlist_dir = '~~desktop/',
}

options.read_options(o, "simple-playlist")

if os.getenv('windir') ~= nil then
    o.device = 'windows'
elseif os.execute '[ $(uname) = "Darwin" ]' == 0 then
    o.device = 'mac'
else
    o.device = 'linux'
end

if o.playlist_dir == nil or o.playlist_dir == "" then
    o.playlist_dir = mp.command_native({"expand-path", "~~home/"}).."/playlists"
else
    o.playlist_dir = mp.command_native({"expand-path", o.playlist_dir})
end

math.randomseed(os.time())

local visible = false

local sort_modes = {
    {
        id="name-asc",
        title="name",
        compar=function (a, b, playlist)
            return alphanumsort(playlist[a].sort_name, playlist[b].sort_name)
        end,
    },
    {
        id="name-desc",
        title="name in descending order",
        compar=function (a, b, playlist)
            return alphanumsort(playlist[b].sort_name, playlist[a].sort_name)
        end,
    },
    {
        id="date-asc",
        title="date",
        compar=function (a, b)
            return (get_file_info(a).mtime or 0) < (get_file_info(b).mtime or 0)
        end,
    },
    {
        id="date-desc",
        title="date in descending order",
        compar=function (a, b)
            return (get_file_info(a).mtime or 0) > (get_file_info(b).mtime or 0)
        end,
    },
    {
        id="size-asc",
        title="size",
        compar=function (a, b)
            return (get_file_info(a).size or 0) < (get_file_info(b).size or 0)
        end,
    },
    {
        id="size-desc",
        title="size in descending order",
        compar=function (a, b)
            return (get_file_info(a).size or 0) > (get_file_info(b).size or 0)
        end,
    },
}

function is_local_file(path)
    return path ~= nil and string.find(path, '://') == nil
end

function refresh_playlist()
    if visible then
        mp.command("script-message osc-playlist 0")
        mp.command("script-message osc-playlist 60000")
    end
end

function show_playlist()
    visible = true
    mp.command("script-message osc-playlist 60000")
end

function hide_playlist()
    visible = false
    mp.command("script-message osc-playlist 0")
end

function toggle_playlist()
    if visible == false then
        show_playlist()
    else
        hide_playlist();
    end
end

function get_file_info(item)
    local path = mp.get_property('playlist/'..(item-1)..'/filename')
    if not is_local_file(path) then return {} end

    local file_info = utils.file_info(path)
    if not file_info then
        msg.warn('failed to read file info for: '..path)
        return {}
    end

    return file_info
end

function alphanumsort(a, b)
    local function padnum(d)
        local dec, n = string.match(d, "(%.?)0*(.+)")
        return #dec > 0 and ("%.12f"):format(d) or
               ("%s%03d%s"):format(dec, #n, n)
    end
    return tostring(a):lower():gsub("%.?%d+",padnum)..("%3d"):format(#b) <
           tostring(b):lower():gsub("%.?%d+",padnum)..("%3d"):format(#a)
end

function reverse_playlist()
    local length = mp.get_property_number('playlist-count', 0)
    if length < 2 then return end
    for outer=1, length-1, 1 do
        mp.commandv('playlist-move', outer, 0)
    end
    refresh_playlist()
    mp.osd_message("Playlist reversed")
end

function shuffle_playlist()
    local length = mp.get_property_number('playlist-count', 0)
    if length < 2 then return end

    local pos = mp.get_property_number('playlist-pos', 0)

    mp.command("playlist-shuffle")
    mp.commandv("playlist-move", pos, math.random(0, length-1))

    mp.set_property('playlist-pos', 0)

    refresh_playlist()
    mp.osd_message("Playlist shuffled")
end

-- From https://github.com/zsugabubus/dotfiles/blob/master/.config/mpv/scripts/playlist-filtersort.lua
function sort_playlist_by(sort_id, startover)
    sort_mode = 1
    for mode, sort_data in pairs(sort_modes) do
        if sort_data.id == sort_id then
            sort_mode = mode
        end
    end

    local playlist = mp.get_property_native('playlist')
    if #playlist < 2 then return end

    local order = {}
    for i=1, #playlist do
        order[i] = i
        playlist[i].sort_name = mp.get_property('playlist/'..(i-1)..'/filename')
    end

    table.sort(order, function(a, b)
        return sort_modes[sort_mode].compar(a, b, playlist)
    end)

    for i=1, #playlist do
        playlist[order[i]].new_pos = i
    end

    for i=1, #playlist do
        while true do
            local j = playlist[i].new_pos
            if i == j then
                break
            end
            mp.commandv('playlist-move', (i)     - 1, (j + 1) - 1)
            mp.commandv('playlist-move', (j - 1) - 1, (i)     - 1)
            playlist[j], playlist[i] = playlist[i], playlist[j]
        end
    end

    if startover == 'startover' then
        mp.set_property('playlist-pos', 0)
    end

    refresh_playlist()

    mp.osd_message("Playlist sorted by "..sort_modes[sort_mode].title)
end

function osd_error(text)
    msg.error(text)
    mp.osd_message(text)
end

function osd_info(text)
    msg.info(text)
    mp.osd_message(text)
end

function create_dir(dir)
    if utils.readdir(dir) == nil then
        local args
        if o.device == 'windows' then
            args = {
                'powershell', '-NoProfile', '-Command', 'mkdir', dir
            }
        else
            args = {'mkdir', dir}
        end

        local res = utils.subprocess({args=args, cancellable=false})
        return res.status == 0
    end
    return true
end

function save_playlist()
    local length = mp.get_property_number('playlist-count', 0)
    if length == 0 then return end

    if create_dir(o.playlist_dir) == false then
        osd_error('Failed to create playlist directory "'..o.playlist_dir..'"')
        return
    end

    local date = os.date("*t")
    local name = ("mpv-%03d-%02d%02d%02d-%02d%02d%02d.m3u"):format(
        length, date.year-2000, date.month, date.day, date.hour, date.min, date.sec
    )

    local path = utils.join_path(o.playlist_dir, name)
    local file, err = io.open(path, "w")
    if not file then
        osd_error('Error in creating playlist file "'..path..'"')
        return
    end

    file:write("#EXTM3U\n")
    local pwd = mp.get_property("working-directory")

    local i=0
    while i < length do
        local item_path = mp.get_property('playlist/'..i..'/filename')
        if is_local_file(item_path) then
            item_path = utils.join_path(pwd, item_path)
        end
        local title = mp.get_property('playlist/'..i..'/title')
        if title then
            file:write("#EXTINF:,"..title.."\n")
        end
        file:write(item_path, "\n")
        i=i+1
    end

    osd_info('Playlist written to "'..path..'"')
    file:close()
end

mp.observe_property('playlist-count', "number", function()
    refresh_playlist()
end)

mp.register_event("file-loaded", function ()
    refresh_playlist()
end)

mp.register_script_message("simple-playlist", function (param1, param2, param3)
    if param1 == 'sort' then
        sort_playlist_by(param2, param3)
    elseif param1 == 'shuffle' then
        shuffle_playlist()
    elseif param1 == 'reverse' then
        reverse_playlist()
    elseif param1 == 'show' then
        show_playlist()
    elseif param1 == 'hide' then
        hide_playlist()
    elseif param1 == 'display-toggle' then
        toggle_playlist()
    elseif param1 == 'save' then
        save_playlist()
    elseif param1 == 'playfirst' then
        local playlist = mp.get_property_native('playlist')
        if #playlist < 2 then
            return
        else
            mp.set_property("playlist-pos", 0)
        end
    elseif param1 == 'playlast' then
        local playlist = mp.get_property_native('playlist')
        if #playlist < 2 then
            return
        else
            mp.set_property("playlist-pos", #playlist - 1)
        end
    end
end)
