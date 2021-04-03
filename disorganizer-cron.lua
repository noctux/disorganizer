#!/usr/bin/env lua

local dirent = require("posix.dirent")
local stat   = require("posix.sys.stat")
local time   = require("posix.time")
local errnoc = require("posix.errno")

-- Sleep time Jitter in seconds
local MAC_PATTERN = "%x%x:%x%x:%x%x:%x%x:%x%x:%x%x"
local WOL_CLI = "etherwake -i br-lan "

-- Special variant of mkdir that accepts eexist
function mkdir(path)
	local status, errstr, errno = stat.mkdir(path)
	assert(0 == status or errno == errnoc.EEXIST, "Failed to create directory at '" .. path .. "': " .. errstr)
end


-- From: https://stackoverflow.com/a/8316375 CC-BY-SA 3.0
function BuildArray(...)
  local arr = {}
  for v in ... do
    arr[#arr + 1] = v
  end
  return arr
end

-- From: https://stackoverflow.com/a/31857671 CC-BY-SA 3.0
function read_file(path)
    local file = io.open(path, "rb") -- r read mode and b binary mode
    if not file then return nil end
    local content = file:read "*a" -- *a or *all reads the whole file
    file:close()
    return content
end

function send_wol(mac)
	-- etherwake -i br-lan 00:14:fd:1a:9b:f5
	-- Security check, hardening against shell injections
	assert(string.match(mac, "^" .. MAC_PATTERN .. "$"), "Illegal mac specified for etherwake (shell injection possible): " .. mac)
	local cmd = WOL_CLI .. " " .. mac
	assert(os.execute(cmd) == 0, "os.execute returned nonzero exitcode for '" .. cmd .. "'")
end

function check_wakups(ref_time, wake_dir)
	-- Unroll the iterator so that we can remove entries
	-- whenever we have done some work
	local checkingentries = BuildArray(dirent.files(wake_dir))

	for _, file in ipairs(checkingentries) do
		if not (file == "." or file == "..") then
			assert(string.match(file, "^%d+$"), "All wakeups use epoch time as the filename")
			local ts = tonumber(file)

			-- Execute the scheduled wol call
			if (ts < ref_time) then
				local path = wake_dir .. "/" .. file
				local mac = read_file(path)

				-- Remove potential trailing newlines
				mac = string.gsub(mac, "[\r\n]*$", "")

				print("Sending wake signal for timestamp " .. file .. " -> " .. mac)
				local ok, errmsg = pcall(send_wol, mac)
				if not ok then
					io.stderr:write("Failed to send wol: " .. errmsg .. "\n")
				end
				-- Cleanup
				os.remove(path)
			end
		end
	end
end

function usage()
	io.stderr:write(arg[0] .. " <period in seconds> <working directory>\n")
	os.exit(1)
end

-- Argument parsing
local interval = tonumber(arg[1])
if (#arg ~= 2 or not interval) then
	usage()
end
local wakeupdir = arg[2]

-- Create the requestdir (if it does not already exist)
mkdir(wakeupdir)

-- Actually process the wakeups
local now = time.time()
-- Wake all jobs that lie within the next execution period
check_wakups(now + interval, wakeupdir)
