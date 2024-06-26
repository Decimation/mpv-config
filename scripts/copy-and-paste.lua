--[[
https://github.com/9beach/mpv-config/blob/main/scripts/copy-and-paste.lua

This script gives **mpv** the capability to copy and paste file paths and URLs.
You can paste and play multiple lines of media file paths, media URLs, and
HTML page URLs including YouTube, Twitter, Twitch.tv, Naver, Kakao...

You can edit key bindings below in `script-opts/copy-and-paste.conf`:

- Pastes file paths or URLs in clipboard to playlist. (`Ctrl+V, Alt+V, Meta+V`)
- Appends file paths or URLs in clipboard to playlist.
  (`Ctrl+b, Alt+b, Meta+b`)
- Appends file paths or URLs in clipboard to current track.
  (`Ctrl+v, Alt+v, Meta+v`)
- Copies file path or URL of current track. (`Ctrl+c, Alt+c, Meta+c`)

Please notice that:

1. To play and download media from URLs with **mpv**, you need to install
   [yt-dlp](https://github.com/yt-dlp/yt-dlp/releases). For
   _Microsoft Windows_ users, download
   [yt-dlp.exe](https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe)
   and copy it to `C:\Windows`.
2. For _OSX_ users, when option key pressed, the context menu of a file
   reveals `Copy as pathname` menu item (or just press `⌘⌥C`). You
   can paste the pull paths of local media to **mpv** with this.
]]

local options = require 'mp.options'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local o = {
	-- Sets Linux commands for copy and paste. We do not need the alternatives
	-- for copy and paste commands of OSX and Microsoft Windows.
	linux_copy = 'xclip -silent -selection clipboard -in',
	linux_paste = 'xclip -selection clipboard -o',
	-- Enables displaying osd messages when actions occur.
	osd_messages = true,
	-- Keybind for copy file path or URL of current track.
	copy_current_track_keybind = 'Ctrl+c Alt+c Meta+c Ctrl+INS',
	-- Keybind for paste file paths or URLs in clipboard to playlist.
	paste_to_playlist_keybind = 'Ctrl+Shift+v Alt+Shift+v Meta+Shift+v Shift+INS',
	-- Keybind for append file paths or URLs in clipboard to playlist.
	append_to_playlist_keybind = 'Ctrl+b Alt+b Meta+b',
	-- Keybind for append file paths or URLs in clipboard to current track.
	append_to_current_track_keybind = 'Ctrl+v Alt+v Meta+v',
	-- In idle state, there is no path or URL to copy. You can call something
	-- else with `idle_state_copy_script`. `copy-quote` is a script message
	-- of `modernx-and-quotes.lua`.
	idle_state_copy_script = 'script-message copy-quote',
}

if os.getenv('windir') ~= nil then
	o.platform = 'windows'
elseif os.execute '[ $(uname) = "Darwin" ]' == 0 then
	o.platform = 'darwin'
else
	o.platform = 'linux'
end

options.read_options(o, "copy-and-paste")

function osd_info(text)
	msg.info(text)
	if o.osd_messages == true then mp.osd_message(text) end
end

function bind_keys(keys, name, func, opts)
	if not keys or keys == '' then
		mp.add_forced_key_binding(nil, name, func, opts)
		return
	end

	local i = 0
	for key in string.gmatch(keys, "[^%s]+") do
		i = i + 1
		if i == 1 then
			mp.add_forced_key_binding(key, name, func, opts)
		else
			mp.add_forced_key_binding(key, name .. i, func, opts)
		end
	end
end

function pipe_read(cmd)
	local f = io.popen(cmd, 'r')
	local s = f:read('*a')
	f:close()
	return s
end

function pipe_write(cmd, text)
	local f = io.popen(cmd, 'w')
	local s = f:write(text)
	f:close()
end

function get_clipboard()
	if o.platform == 'darwin' then
		return pipe_read('LC_CTYPE=UTF-8 pbpaste')
	elseif o.platform == 'windows' then
		local script = [[
        & {
            Trap {
                Write-Error -ErrorRecord $_
                Exit 1
            }
            $clip = Get-Clipboard -Raw -Format Text -TextFormatType UnicodeText
            if (-not $clip) {
                $clip = Get-Clipboard -Raw -Format FileDropList
            }
            $u8clip = [System.Text.Encoding]::UTF8.GetBytes($clip)
            [Console]::OpenStandardOutput().Write($u8clip, 0, $u8clip.Length)
        }
        ]]
		local args = { 'powershell', '-NoProfile', '-Command', script }
		local res = utils.subprocess({ args = args, cancellable = false })
		if not res.error and res.status == 0 then
			return res.stdout
		else
			msg.error("There was an error getting clipboard: ")
			msg.error("  Status: " .. (res.status or ""))
			msg.error("  Error: " .. (res.error or ""))
			msg.error("args: " .. utils.to_string(args))
			return ''
		end
	else
		return pipe_read(o.linux_paste)
	end

	return ''
end

function ps_quote_string(str)
	return "'" .. str:gsub('`', '``'):gsub('"', '``"'):gsub('%$', '``$')
		:gsub('%[', '``['):gsub('%]', '``]'):gsub("'", "''") .. "'"
end

function set_clipboard(text)
	if o.platform == 'darwin' then
		pipe_write('LC_CTYPE=UTF-8 pbcopy', text)
	elseif o.platform == 'windows' then
		local args = {
			'powershell', '-NoProfile', 'Set-Clipboard', '-value',
			ps_quote_string(text)
		}
		local res = utils.subprocess({ args = args, cancellable = false })
		if res.error then msg.error('paste failed: ' .. res.error) end
	else
		pipe_write(o.linux_copy, text)
	end
end

function copy()
	local path = mp.get_property('path')
	if path ~= nil then
		if path:match('://') == nil then
			local pwd = mp.get_property("working-directory")
			path = utils.join_path(pwd, path)
			if o.platform == 'windows' then
				path = string.gsub(path, '/', '\\')
			end
		end
		local tp = mp.get_property_osd("time-pos")
		-- tp = utils.to_string(tp)
		-- print(tp)
		local tp2 = string.format("%s @ %s", path, tp)
		set_clipboard(tp2)
		if path:match('://') ~= nil then
			osd_info('URL copied')
		else
			osd_info('File path copied:\n' .. tp2)
		end
	elseif (o.idle_state_copy_script ~= '') then
		mp.command(o.idle_state_copy_script)
	end
end

function file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

-- mode: load/append/append-next
function paste_to_playlist(mode)
	clip = get_clipboard()

	if not clip then
		osd_info('Clipboard is empty')
		return
	end

	local length = mp.get_property_number('playlist-count', 0)
	local pos = mp.get_property_number('playlist-pos', 0)

	local i = 0
	for path in clip:gmatch("[^\r\n]+") do
		if path:match('^%a[%a%d-_]+://') ~= nil or file_exists(path) then
			i = i + 1
			if i == 1 then
				if mode == 'load' then
					mp.commandv('loadfile', path)
				else
					mp.commandv('loadfile', path, 'append-play')
				end
			else
				mp.commandv('loadfile', path, 'append-play')
			end
		end
	end

	if mode == 'append-next' and length > 1 then
		local new_length = mp.get_property_number('playlist-count', 0)
		for outer = length, new_length - 1, 1 do
			mp.commandv('playlist-move', new_length - 1, pos + 1)
		end
	end

	if i == 0 then
		osd_info('No valid URLs or file paths from clipboard')
	elseif i == 1 then
		if mode == 'load' then
			osd_info('Loading a item...')
		elseif mode == 'append' then
			osd_info('Adding a item to playlist...')
		else
			osd_info('Adding a item to current track...')
		end
	else
		if mode == 'load' then
			osd_info('Loading ' .. tostring(i) .. ' URLs or files...')
		elseif mode == 'append' then
			osd_info('Adding ' .. tostring(i) .. ' URLs or files to playlist...')
		else
			osd_info(
				'Adding ' .. tostring(i) .. ' URLs or files to current track...'
			)
		end
	end
end

bind_keys(o.copy_current_track_keybind, 'copy-current-track', copy)
bind_keys(o.paste_to_playlist_keybind, 'paste-to-playlist', function()
	paste_to_playlist('load')
end)
bind_keys(o.append_to_playlist_keybind, 'append-to-playlist', function()
	paste_to_playlist('append')
end)
bind_keys(
	o.append_to_current_track_keybind,
	'append-to-current-track',
	function() paste_to_playlist('append-next') end
)
