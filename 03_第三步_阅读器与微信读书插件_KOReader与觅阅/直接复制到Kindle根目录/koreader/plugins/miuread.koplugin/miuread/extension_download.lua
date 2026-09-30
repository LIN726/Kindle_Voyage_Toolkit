-- MiuRead built-in extension downloader v5 (beta.15).
--
-- Policy:
--   * the official GitHub Release asset identity never changes while retrying
--   * large packages probe available transports before starting fresh
--   * meaningful partials outrank a fresh speed race and may seed another route
--     for Range resume without destroying the original checkpoint
--   * slow transfers keep running; only a genuine no-data stall is reconnected
--   * official size + SHA-256 validate assets before installation when available
--
-- The installer owns archive and KOReader plugin structure validation.

local Config=require("miuread.config")
local Http=require("miuread.http")
local Json=require("miuread.json")
local U=require("miuread.util")
local logger=require("logger")
local ok_socket,socket=pcall(require,"socket")

local M={}

local LARGE_FILE_BYTES=tonumber(Config.EXTENSION_LARGE_FILE_BYTES) or 5*1024*1024
local RESUME_BYTES=tonumber(Config.EXTENSION_RESUME_BYTES) or 512*1024

local function now()
    if ok_socket and socket and type(socket.gettime)=="function" then return socket.gettime() end
    return os.time()
end

local function sleep(seconds)
    seconds=tonumber(seconds) or .4
    if ok_socket and socket and type(socket.sleep)=="function" then socket.sleep(seconds); return end
    os.execute("sleep "..tostring(seconds).." >/dev/null 2>&1")
end

local function trim(value) return U.trim(tostring(value or "")) end
local function starts_with(value,prefix)
    value,prefix=tostring(value or ""),tostring(prefix or "")
    return value:sub(1,#prefix)==prefix
end
local function command_ok(rc) return rc==true or rc==0 end
local function command_available(name)
    return command_ok(os.execute("command -v "..tostring(name).." >/dev/null 2>&1"))
end
local function process_alive(pid)
    pid=tonumber(pid)
    return pid and pid>1 and command_ok(os.execute("kill -0 "..tostring(math.floor(pid)).." >/dev/null 2>&1")) or false
end
local function read_number(path)
    local raw=trim(U.read_file(path,true) or "")
    return tonumber(raw)
end
local function ensure_dir(path)
    return U.mkdir(path) or U.file_exists(path) or false
end

local function route_label(key)
    if key=="direct" then return "GitHub 官方" end
    if key=="git_zh" then return "GitHub 中文社区" end
    if key=="custom" then return "自定义镜像" end
    return tostring(key or "下载源")
end

local function normalize_prefix(prefix)
    prefix=trim(prefix)
    if not prefix:match("^https://") then return nil end
    if prefix:sub(-1)~="/" then prefix=prefix.."/" end
    return prefix
end

local function build_route_url(url,descriptor)
    descriptor=type(descriptor)=="table" and descriptor or {}
    local mode=tostring(descriptor.mode or "prefix")
    local base=trim(descriptor.base or descriptor.prefix or "")
    if mode=="direct" then return url end
    if mode=="replace_host" then
        local suffix=tostring(url or ""):match("^https://github%.com/(.+)$")
        if not suffix or base=="" or not base:match("^https://") then return nil end
        base=base:gsub("/+$","")
        return base.."/"..suffix
    end
    local prefix=normalize_prefix(base)
    if not prefix then return nil end
    return prefix..url
end

local function configured_routes(url,routes,mirrors)
    local out={}
    if type(routes)=="table" and #routes>0 then
        for index,descriptor in ipairs(routes) do
            if type(descriptor)=="table" then
                local route_url=build_route_url(url,descriptor)
                if route_url then
                    local key=trim(descriptor.key)
                    if key=="" then key="route_"..tostring(index) end
                    out[#out+1]={
                        key=key,label=trim(descriptor.label)~="" and trim(descriptor.label) or route_label(key),
                        url=route_url,index=index,preferred=descriptor.preferred==true,mode=tostring(descriptor.mode or "prefix"),
                    }
                end
            end
        end
        return out
    end
    -- Compatibility with beta.14 settings/tests and the OTA mirror list.
    out[#out+1]={key="direct",label="GitHub 官方",url=url,index=1,mode="direct"}
    for index,prefix in ipairs(type(mirrors)=="table" and mirrors or Config.GITHUB_MIRRORS or {}) do
        prefix=normalize_prefix(prefix)
        if prefix then
            out[#out+1]={key="mirror:"..tostring(index),label="镜像 "..tostring(index),url=prefix..url,index=index+1,mode="prefix"}
        end
    end
    return out
end

function M.build_sources(url,network,mirrors,routes)
    url=tostring(url or "")
    network=type(network)=="table" and network or {mode="auto",custom_prefix=""}
    if not starts_with(url,"https://github.com/") then return {{key="direct",label="官方下载",url=url,index=1,mode="direct"}} end

    local configured=configured_routes(url,routes or Config.EXTENSION_DOWNLOAD_ROUTES,mirrors)
    local custom=normalize_prefix(network.custom_prefix)
    local custom_route=custom and {key="custom",label="自定义镜像",url=custom..url,index=100,mode="prefix"} or nil
    local mode=tostring(network.mode or "auto")
    if mode=="direct" then
        for _,route in ipairs(configured) do if route.key=="direct" then return {route} end end
        return {{key="direct",label="GitHub 官方",url=url,index=1,mode="direct"}}
    end
    if mode=="custom" then return custom_route and {custom_route} or {} end
    local route_key=mode:match("^route:(.+)$")
    if route_key then
        for _,route in ipairs(configured) do if route.key==route_key then return {route} end end
        return {}
    end
    -- Preserve old mirror:N preferences after upgrading from beta.14.
    if mode:match("^mirror:%d+$") then
        for _,route in ipairs(configured) do if route.key==mode then return {route} end end
        local index=tonumber(mode:match("(%d+)$"))
        local prefix=index and normalize_prefix((type(mirrors)=="table" and mirrors or Config.GITHUB_MIRRORS or {})[index]) or nil
        return prefix and {{key=mode,label="镜像 "..tostring(index),url=prefix..url,index=index+1,mode="prefix"}} or {}
    end

    local out={}
    for _,route in ipairs(configured) do out[#out+1]=route end
    if custom_route then out[#out+1]=custom_route end
    return out
end

local function classify_error(value,status)
    local text=tostring(value or "")
    local lower=text:lower()
    status=tostring(status or "")
    if status=="404" then return "source_unavailable" end
    if status=="403" or status=="429" then return "http_error" end
    if lower:find("could not resolve",1,true) or lower:find("dns",1,true)
        or lower:find("name or service not known",1,true) then return "dns_unavailable" end
    if lower:find("network is unreachable",1,true) or lower:find("no route to host",1,true) then return "network_offline" end
    if lower:find("timed out",1,true) or lower:find("timeout",1,true) then return "connect_timeout" end
    if lower:find("ssl",1,true) or lower:find("tls",1,true) then return "tls_error" end
    if status=="416" or lower:find("range",1,true) or lower:find("resume",1,true) then return "range_rejected" end
    return "transport_error"
end

local function sha256_file(path)
    if not U.file_exists(path) then return nil,"文件不存在" end
    local commands={}
    if command_available("sha256sum") then commands[#commands+1]="sha256sum "..U.shell_quote(path).." 2>/dev/null" end
    if command_available("busybox") then commands[#commands+1]="busybox sha256sum "..U.shell_quote(path).." 2>/dev/null" end
    if command_available("openssl") then commands[#commands+1]="openssl dgst -sha256 "..U.shell_quote(path).." 2>/dev/null" end
    for _,cmd in ipairs(commands) do
        local pipe=io.popen(cmd,"r")
        if pipe then
            local raw=pipe:read("*l") or ""
            pipe:close()
            local value=raw:match("([0-9a-fA-F][0-9a-fA-F]+)%s*$") or raw:match("^([0-9a-fA-F]+)")
            if value and #value==64 then return value:lower() end
        end
    end
    -- Last resort: MiuRead's bounded streaming SHA-256. Unlike the old fallback
    -- it never reads a 60+ MiB plugin archive into the Lua heap.
    local ok,D=pcall(require,"miuread.digests")
    if ok and D and type(D.sha256_file)=="function" then
        local value,err=D.sha256_file(path,256*1024)
        if value and #value==64 then return tostring(value):lower() end
        return nil,err or "流式 SHA-256 校验失败"
    end
    return nil,"设备缺少可用于大文件的 SHA-256 校验工具"
end

local function validate_download(path,spec)
    if not U.file_exists(path) then return nil,"下载文件不存在","missing" end
    local size=U.file_size(path) or 0
    if size<=0 then return nil,"下载文件为空","empty" end
    local expected=tonumber(spec.size or 0) or 0
    if expected>0 and size~=expected then
        return nil,"下载大小不完整：应为 "..tostring(expected).." 字节，实际 "..tostring(size).." 字节","size"
    end
    local expected_sha=trim(spec.sha256):lower():gsub("[^0-9a-f]","")
    if expected_sha=="" then
        if spec.allow_missing_sha==true then
            -- GitHub does not expose a digest for every historical Release.
            -- Compute and persist our own package fingerprint when possible;
            -- archive/plugin validation remains mandatory even if this device
            -- lacks a SHA-256 implementation.
            local actual=sha256_file(path)
            return {size=size,sha256=actual or "",integrity=actual and "sha256-recorded" or "size+archive"}
        end
        return nil,"内置扩展缺少 SHA-256 目录记录","catalog_integrity"
    end
    local actual,sha_error=sha256_file(path)
    if not actual then return nil,sha_error or "无法计算 SHA-256","sha_unavailable" end
    if actual~=expected_sha then
        return nil,"SHA-256 校验失败；下载内容与目录记录不一致","sha256"
    end
    return {size=size,sha256=actual,integrity="sha256"}
end

local function progress_writer(task_dir,spec,total_sources)
    local progress_path=task_dir.."/progress.json"
    local last_bytes,last_clock,last_write=0,now(),0
    local ema=0
    return function(bytes,route,transport,force,message,source_index)
        bytes=math.max(0,tonumber(bytes) or 0)
        local clock=now()
        local dt=clock-last_clock
        if dt>.15 and bytes>=last_bytes then
            local instant=(bytes-last_bytes)/dt
            if instant>=0 then ema=ema<=0 and instant or (ema*.72+instant*.28) end
            last_bytes,last_clock=bytes,clock
        end
        if force~=true and clock-last_write<.8 then return end
        last_write=clock
        local total=tonumber(spec.size or 0) or 0
        local percent=total>0 and math.min(1,bytes/total) or 0
        local payload={
            kind="extension",state="downloading",stage="download",downloaded_bytes=bytes,total_bytes=total,
            percent=percent,speed_bps=math.floor(ema+.5),route_key=route and route.key or "",
            source=route and route.label or "",transport=tostring(transport or ""),message=tostring(message or ""),
            source_index=tonumber(source_index) or 1,source_total=tonumber(total_sources) or 1,updated_at=os.time(),
        }
        U.atomic_write(progress_path,Json.encode(payload),true)
    end
end

local function write_transport_script(task_dir,route,target,resume,connect_timeout,stall_seconds)
    ensure_dir(task_dir)
    local script=task_dir.."/transport.sh"
    local pid_path=task_dir.."/transport.pid"
    local exit_path=task_dir.."/transport.exit"
    local status_path=task_dir.."/transport.status"
    local error_path=task_dir.."/transport.error"
    os.remove(pid_path); os.remove(exit_path); os.remove(status_path); os.remove(error_path)
    -- Treat only a true no-data stall as dead. A Kindle may legitimately stay
    -- below 1 KiB/s for a while; beta.14 killed those healthy slow transfers.
    local cmd="curl -L --fail --silent --show-error --connect-timeout "..tostring(connect_timeout)
        .." --speed-limit 1 --speed-time "..tostring(stall_seconds)
    if resume then cmd=cmd.." -C -" end
    cmd=cmd.." -o "..U.shell_quote(target)
        .." -w "..U.shell_quote("%{http_code}")
        .." "..U.shell_quote(route.url)
        .." >"..U.shell_quote(status_path).." 2>"..U.shell_quote(error_path)
    local body=table.concat({
        "#!/bin/sh","rm -f "..U.shell_quote(exit_path),cmd.." &","cpid=$!",
        "echo \"$cpid\" > "..U.shell_quote(pid_path),"wait \"$cpid\"","rc=$?",
        "echo \"$rc\" > "..U.shell_quote(exit_path),"exit \"$rc\"","",
    },"\n")
    if not U.atomic_write(script,body,true) then return nil,"无法创建下载脚本" end
    os.execute("chmod 700 "..U.shell_quote(script).." >/dev/null 2>&1")
    if not command_ok(os.execute("sh "..U.shell_quote(script).." >/dev/null 2>&1 &")) then return nil,"无法启动 curl" end
    local deadline=now()+3
    while now()<deadline and not U.file_exists(exit_path) and not U.file_exists(pid_path) do sleep(.05) end
    if not U.file_exists(exit_path) and not U.file_exists(pid_path) then
        return nil,"curl 子进程未能启动"
    end
    return {pid_path=pid_path,exit_path=exit_path,status_path=status_path,error_path=error_path}
end

local function run_curl(task_dir,route,target,resume,publish,spec,source_index,total_sources)
    local info,launch_error=write_transport_script(task_dir,route,target,resume,
        tonumber(spec.connect_timeout) or tonumber(Config.EXTENSION_CONNECT_TIMEOUT_SECONDS) or 20,
        tonumber(spec.stall_seconds) or tonumber(Config.EXTENSION_STALL_SECONDS) or 90)
    if not info then return nil,{error=launch_error or "curl 启动失败",kind="transport_error"} end
    publish(U.file_size(target) or 0,route,"curl",true,resume and "正在继续同一下载源" or "",source_index)
    local last_size=U.file_size(target) or 0
    while true do
        local rc=read_number(info.exit_path)
        local pid=read_number(info.pid_path)
        local current=U.file_size(target) or 0
        if current~=last_size then last_size=current; publish(current,route,"curl",false,"",source_index) end
        if rc~=nil then break end
        if pid and not process_alive(pid) and not U.file_exists(info.exit_path) then
            sleep(.15)
            if not U.file_exists(info.exit_path) then break end
        end
        sleep(.45)
    end
    local rc=read_number(info.exit_path)
    local status=trim(U.read_file(info.status_path,true) or "")
    local err=trim(U.read_file(info.error_path,true) or "")
    local size=U.file_size(target) or 0
    publish(size,route,"curl",true,"",source_index)
    if tonumber(rc)==0 and size>0 then return {path=target,bytes=size,status=status} end
    return nil,{error=err~="" and err or "curl 下载失败",kind=classify_error(err,status),status=status,bytes=size}
end

local function promote(candidate,package_path)
    os.remove(package_path)
    local ok,err=os.rename(candidate,package_path)
    if ok then return package_path end
    local copied,copy_err=U.copy_file_stream(candidate,package_path,256*1024)
    if not copied then return nil,"无法保存插件包："..tostring(copy_err or err or "copy failed") end
    os.remove(candidate)
    return package_path
end

local function attempt_record(attempts,route,transport,ok,kind,error,bytes)
    attempts[#attempts+1]={
        key=route.key,label=route.label,url=route.url,transport=transport,ok=ok==true,
        kind=tostring(kind or (ok and "verified" or "transport_error")),error=error and U.first_line(tostring(error),180) or nil,
        bytes=tonumber(bytes) or 0,
    }
end

local function network_link_ready()
    -- This is deliberately a link-state check, not a repair routine or an
    -- Internet probe. The parent task performs the normal NetworkMgr readiness
    -- gate; the child only uses this to distinguish a real Wi-Fi drop from one
    -- hostname/route failing while another mirror may still be reachable.
    local ok_nm,NetworkMgr=pcall(require,"ui/network/manager")
    if not ok_nm or not NetworkMgr then return true end
    if type(NetworkMgr.isConnected)=="function" then
        local ok,value=pcall(NetworkMgr.isConnected,NetworkMgr)
        if ok then return value==true end
    end
    if type(NetworkMgr.isWifiOn)=="function" then
        local ok,value=pcall(NetworkMgr.isWifiOn,NetworkMgr)
        if ok then return value==true end
    end
    return true
end

local function should_wait_network(_,kind)
    if kind~="network_offline" and kind~="dns_unavailable" then return false end
    return network_link_ready()~=true
end

local function source_part(task_dir,route)
    return task_dir.."/source-"..U.id_name(route.key)..".part"
end

local function probe_route(route,spec)
    if not command_available("curl") then return nil,"curl unavailable" end
    local bytes=math.max(32*1024,tonumber(spec.probe_bytes) or tonumber(Config.EXTENSION_PROBE_BYTES) or 128*1024)
    local connect=math.max(2,tonumber(spec.probe_connect_timeout) or tonumber(Config.EXTENSION_PROBE_CONNECT_TIMEOUT_SECONDS) or 6)
    local max_time=math.max(connect+1,tonumber(spec.probe_max_seconds) or tonumber(Config.EXTENSION_PROBE_MAX_SECONDS) or 10)
    local cmd="curl -L --fail --silent --show-error --connect-timeout "..tostring(connect)
        .." --max-time "..tostring(max_time)
        .." --range 0-"..tostring(bytes-1)
        .." -o /dev/null -w "..U.shell_quote("%{http_code} %{speed_download} %{size_download}")
        .." "..U.shell_quote(route.url).." 2>/dev/null"
    local pipe=io.popen(cmd,"r")
    if not pipe then return nil,"probe unavailable" end
    local raw=trim(pipe:read("*a") or "")
    local ok=pipe:close()
    local code,speed,size=raw:match("^(%d+)%s+([%d%.]+)%s+([%d%.]+)")
    code=tonumber(code) or 0; speed=tonumber(speed) or 0; size=tonumber(size) or 0
    if not ok or (code~=200 and code~=206) or size<=0 then return nil,"probe failed" end
    return {speed_bps=speed,bytes=size,http_code=code}
end

local function order_sources(task_dir,sources,spec,expected)
    if #sources<=1 then return sources end
    -- A meaningful existing partial is more valuable than a fresh speed race.
    local partial_rank={}
    local biggest=0
    for _,route in ipairs(sources) do
        local size=U.file_size(source_part(task_dir,route)) or 0
        partial_rank[route.key]=size
        if size>biggest then biggest=size end
    end
    if biggest>=RESUME_BYTES then
        table.sort(sources,function(a,b)
            local aa,bb=partial_rank[a.key] or 0,partial_rank[b.key] or 0
            if aa~=bb then return aa>bb end
            if a.preferred~=b.preferred then return a.preferred==true end
            return (tonumber(a.index) or 999)<(tonumber(b.index) or 999)
        end)
        return sources
    end

    local network=type(spec.network)=="table" and spec.network or {}
    if tostring(network.mode or "auto")~="auto" then return sources end
    local health_key=tostring(network.preferred_route_key or "")

    -- For small packages the probe itself can cost more than the download. Use
    -- the recent successful route first, then the configured preference order.
    if expected<LARGE_FILE_BYTES or not command_available("curl") then
        if health_key~="" then
            table.sort(sources,function(a,b)
                local ah,bh=a.key==health_key,b.key==health_key
                if ah~=bh then return ah end
                if a.preferred~=b.preferred then return a.preferred==true end
                return (tonumber(a.index) or 999)<(tonumber(b.index) or 999)
            end)
        end
        return sources
    end

    -- Probe only the first few high-value routes. A sequential five-route
    -- speed race can itself cost tens of seconds on a slow Kindle. Successful
    -- probes are ordered by measured speed; unprobed routes remain normal
    -- fallbacks; routes that just failed a probe are tried last.
    local probe_max=math.max(1,tonumber(spec.probe_max_routes)
        or tonumber(Config.EXTENSION_PROBE_MAX_ROUTES) or 3)
    for position,route in ipairs(sources) do
        route._probe_position=position
        if position<=probe_max then
            route._probe_attempted=true
            local result=probe_route(route,spec)
            if result then
                route._probe_ok=true
                route.probe_speed_bps=result.speed_bps
                logger.info("[MiuRead][ExtensionDownload] route probe","source=",route.key,
                    "speed_bps=",tostring(math.floor(result.speed_bps+.5)),"code=",tostring(result.http_code))
            else
                route._probe_ok=false
                route.probe_speed_bps=0
                logger.info("[MiuRead][ExtensionDownload] route probe unavailable","source=",route.key)
            end
        end
    end
    local function probe_group(route)
        if route._probe_attempted and route._probe_ok then return 1 end
        if not route._probe_attempted then return 2 end
        return 3
    end
    table.sort(sources,function(a,b)
        local ag,bg=probe_group(a),probe_group(b)
        if ag~=bg then return ag<bg end
        if ag==1 then
            local aa,bb=tonumber(a.probe_speed_bps) or 0,tonumber(b.probe_speed_bps) or 0
            if aa~=bb then return aa>bb end
        end
        local ah,bh=a.key==health_key,b.key==health_key
        if ah~=bh then return ah end
        if a.preferred~=b.preferred then return a.preferred==true end
        return (tonumber(a._probe_position) or tonumber(a.index) or 999)
            <(tonumber(b._probe_position) or tonumber(b.index) or 999)
    end)
    for _,route in ipairs(sources) do
        route._probe_position=nil; route._probe_attempted=nil; route._probe_ok=nil
    end
    return sources
end

local function best_other_partial(task_dir,sources,current,expected)
    local best_path,best_bytes=nil,0
    for _,route in ipairs(sources) do
        if route.key~=current.key then
            local path=source_part(task_dir,route)
            local size=U.file_size(path) or 0
            if size>=RESUME_BYTES and size>best_bytes and (expected<=0 or size<expected) then
                best_path,best_bytes=path,size
            end
        end
    end
    return best_path,best_bytes
end

local function import_resume_partial(task_dir,sources,route,expected)
    local target=source_part(task_dir,route)
    if (U.file_size(target) or 0)>0 then return U.file_size(target) or 0 end
    local source,bytes=best_other_partial(task_dir,sources,route,expected)
    if not source then return 0 end
    local ok,err=U.copy_file_stream(source,target,256*1024)
    if ok then
        logger.info("[MiuRead][ExtensionDownload] cross-route resume seed copied","source=",route.key,"bytes=",tostring(bytes))
        return bytes
    end
    logger.warn("[MiuRead][ExtensionDownload] cross-route resume seed failed","source=",route.key,"error=",tostring(err or "copy failed"))
    os.remove(target)
    return 0
end

function M.run(store,task_dir,spec)
    spec=type(spec)=="table" and spec or {}
    if not ensure_dir(task_dir) then return {ok=false,error="无法创建扩展下载目录",kind="task_storage"} end
    local package_path=task_dir.."/package.zip"
    local sources=M.build_sources(spec.url,spec.network,spec.mirrors,spec.routes)
    if #sources==0 then return {ok=false,error="没有可用扩展下载源",kind="no_source"} end
    local attempts={}
    local expected=tonumber(spec.size or 0) or 0
    local persistent_resume=expected>=RESUME_BYTES
    sources=order_sources(task_dir,sources,spec,expected)
    local publish=progress_writer(task_dir,spec,#sources)

    -- Cache is never trusted. It is revalidated before reuse.
    if U.file_exists(package_path) then
        local verified,verify_error,verify_kind=validate_download(package_path,spec)
        if verified then
            logger.info("[MiuRead][ExtensionDownload] cached package verified","repo=",tostring(spec.repo),"bytes=",tostring(verified.size))
            publish(verified.size,sources[1],"cache",true,"已验证现有下载文件",1)
            return {ok=true,path=package_path,bytes=verified.size,sha256=verified.sha256,route_key="cached",used_url=tostring(spec.url),transport="cache",attempts=attempts}
        end
        logger.warn("[MiuRead][ExtensionDownload] cached package rejected","kind=",tostring(verify_kind),"error=",tostring(verify_error))
        os.remove(package_path)
    end

    local curl_available=command_available("curl")
    for index,route in ipairs(sources) do
        local part=source_part(task_dir,route)
        local existing=U.file_size(part) or 0
        if expected>0 and existing>expected then os.remove(part); existing=0 end
        if not persistent_resume and existing>0 then os.remove(part); existing=0 end
        if persistent_resume and existing==0 then existing=import_resume_partial(task_dir,sources,route,expected) end

        -- A previously completed source-local partial may already be valid.
        if existing>0 and (expected<=0 or existing==expected) then
            local verified,verify_error,verify_kind=validate_download(part,spec)
            if verified then
                local final,promote_error=promote(part,package_path)
                if not final then return {ok=false,error=promote_error,kind="task_storage",attempts=attempts} end
                attempt_record(attempts,route,"resume_cache",true,"verified",nil,verified.size)
                logger.info("[MiuRead][ExtensionDownload] source verified","source=",route.key,"transport=resume_cache","bytes=",tostring(verified.size))
                return {ok=true,path=final,bytes=verified.size,sha256=verified.sha256,route_key=route.key,used_url=route.url,transport="resume_cache",attempts=attempts}
            end
            attempt_record(attempts,route,"resume_cache",false,verify_kind,verify_error,existing)
            os.remove(part); existing=0
        end

        -- KOReader HTTP remains the byte-zero path for small packages. Large
        -- packages and meaningful partials use curl. A checkpoint may seed a
        -- later route only for this exact same official asset; the original
        -- route-local checkpoint is never destroyed by that copy.
        if existing==0 and not (curl_available and expected>=LARGE_FILE_BYTES) then
            local http=Http:new(store)
            logger.info("[MiuRead][ExtensionDownload] source start","source=",route.key,"transport=koreader_http","index=",tostring(index),"total=",tostring(#sources))
            publish(0,route,"koreader_http",true,"正在尝试 "..route.label,index)
            local called,result=pcall(function()
                return http:download_to_file(route.url,part,{
                    auth=false,retries=0,redirects=10,timeout={math.max(8,tonumber(Config.EXTENSION_CONNECT_TIMEOUT_SECONDS) or 20),6*60*60},integrity_attempts=1,preserve_partial=true,
                    on_chunk=function(bytes) publish(bytes,route,"koreader_http",false,"",index) end,
                    heartbeat_seconds=1,heartbeat_bytes=256*1024,
                })
            end)
            local bytes=U.file_size(part) or 0
            if called and bytes>0 then
                local verified,verify_error,verify_kind=validate_download(part,spec)
                if verified then
                    local final,promote_error=promote(part,package_path)
                    if not final then return {ok=false,error=promote_error,kind="task_storage",attempts=attempts} end
                    attempt_record(attempts,route,"koreader_http",true,"verified",nil,verified.size)
                    logger.info("[MiuRead][ExtensionDownload] source verified","source=",route.key,"transport=koreader_http","bytes=",tostring(verified.size))
                    return {ok=true,path=final,bytes=verified.size,sha256=verified.sha256,route_key=route.key,used_url=route.url,transport="koreader_http",attempts=attempts}
                end
                attempt_record(attempts,route,"koreader_http",false,verify_kind,verify_error,bytes)
                logger.warn("[MiuRead][ExtensionDownload] source content rejected","source=",route.key,"transport=koreader_http","kind=",tostring(verify_kind),"bytes=",tostring(bytes),"error=",tostring(verify_error))
                if verify_kind=="sha_unavailable" or verify_kind=="catalog_integrity" then
                    return {ok=false,error=verify_error,kind=verify_kind,attempts=attempts,partial_bytes=bytes}
                end
                -- A full-size wrong-SHA file is not a resumable partial. Retry
                -- this same source once through curl from byte zero.
                if expected>0 and bytes>=expected then os.remove(part); bytes=0 end
                if not persistent_resume then os.remove(part); bytes=0 end
            else
                local err=called and tostring(result or "KOReader HTTP 下载失败") or tostring(result or "KOReader HTTP 下载失败")
                local kind=classify_error(err,"")
                attempt_record(attempts,route,"koreader_http",false,kind,err,bytes)
                logger.warn("[MiuRead][ExtensionDownload] transport failed","source=",route.key,"transport=koreader_http","kind=",kind,"bytes=",tostring(bytes),"error=",err)
                if should_wait_network(route,kind) then
                    return {ok=false,waiting_network=true,error=err,kind=kind,attempts=attempts,partial_bytes=bytes}
                end
                if not persistent_resume then os.remove(part); bytes=0 end
            end
        end

        if curl_available then
            local bytes=U.file_size(part) or 0
            local resume=persistent_resume and bytes>0 and (expected<=0 or bytes<expected)
            logger.info("[MiuRead][ExtensionDownload] source start","source=",route.key,"transport=curl","resume=",tostring(resume),"bytes=",tostring(bytes))
            local curl_result,curl_error=run_curl(task_dir,route,part,resume,publish,spec,index,#sources)
            if curl_result then
                local verified,verify_error,verify_kind=validate_download(part,spec)
                if verified then
                    local final,promote_error=promote(part,package_path)
                    if not final then return {ok=false,error=promote_error,kind="task_storage",attempts=attempts} end
                    attempt_record(attempts,route,resume and "curl_resume" or "curl",true,"verified",nil,verified.size)
                    logger.info("[MiuRead][ExtensionDownload] source verified","source=",route.key,"transport=curl","bytes=",tostring(verified.size))
                    return {ok=true,path=final,bytes=verified.size,sha256=verified.sha256,route_key=route.key,used_url=route.url,transport=resume and "curl_resume" or "curl",attempts=attempts}
                end
                attempt_record(attempts,route,resume and "curl_resume" or "curl",false,verify_kind,verify_error,U.file_size(part) or 0)
                logger.warn("[MiuRead][ExtensionDownload] source content rejected","source=",route.key,"transport=curl","kind=",tostring(verify_kind),"error=",tostring(verify_error))
                if verify_kind=="sha_unavailable" or verify_kind=="catalog_integrity" then
                    return {ok=false,error=verify_error,kind=verify_kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                end
                -- A resumable partial may itself have been polluted by an
                -- interrupted/proxy response. Before rejecting this source,
                -- retry it once from byte zero through curl.
                if resume then
                    os.remove(part)
                    local fresh,fresh_error=run_curl(task_dir,route,part,false,publish,spec,index,#sources)
                    if fresh then
                        local fresh_verified,fresh_verify_error,fresh_verify_kind=validate_download(part,spec)
                        if fresh_verified then
                            local final,promote_error=promote(part,package_path)
                            if not final then return {ok=false,error=promote_error,kind="task_storage",attempts=attempts} end
                            attempt_record(attempts,route,"curl_restart",true,"verified",nil,fresh_verified.size)
                            logger.info("[MiuRead][ExtensionDownload] source verified","source=",route.key,"transport=curl_restart","bytes=",tostring(fresh_verified.size))
                            return {ok=true,path=final,bytes=fresh_verified.size,sha256=fresh_verified.sha256,route_key=route.key,used_url=route.url,transport="curl_restart",attempts=attempts}
                        end
                        attempt_record(attempts,route,"curl_restart",false,fresh_verify_kind,fresh_verify_error,U.file_size(part) or 0)
                        if fresh_verify_kind=="sha_unavailable" or fresh_verify_kind=="catalog_integrity" then
                            return {ok=false,error=fresh_verify_error,kind=fresh_verify_kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                        end
                    else
                        fresh_error=type(fresh_error)=="table" and fresh_error or {error=tostring(fresh_error or "curl 重新下载失败"),kind="transport_error"}
                        attempt_record(attempts,route,"curl_restart",false,fresh_error.kind,fresh_error.error,U.file_size(part) or 0)
                        if should_wait_network(route,fresh_error.kind) then
                            return {ok=false,waiting_network=true,error=fresh_error.error,kind=fresh_error.kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                        end
                    end
                end
                os.remove(part)
            else
                curl_error=type(curl_error)=="table" and curl_error or {error=tostring(curl_error or "curl 下载失败"),kind="transport_error"}
                attempt_record(attempts,route,resume and "curl_resume" or "curl",false,curl_error.kind,curl_error.error,U.file_size(part) or 0)
                logger.warn("[MiuRead][ExtensionDownload] transport failed","source=",route.key,"transport=curl","kind=",tostring(curl_error.kind),"error=",tostring(curl_error.error))
                if curl_error.kind=="range_rejected" and resume then
                    os.remove(part)
                    local fresh,fresh_error=run_curl(task_dir,route,part,false,publish,spec,index,#sources)
                    if fresh then
                        local verified,verify_error,verify_kind=validate_download(part,spec)
                        if verified then
                            local final,promote_error=promote(part,package_path)
                            if not final then return {ok=false,error=promote_error,kind="task_storage",attempts=attempts} end
                            attempt_record(attempts,route,"curl_restart",true,"verified",nil,verified.size)
                            return {ok=true,path=final,bytes=verified.size,sha256=verified.sha256,route_key=route.key,used_url=route.url,transport="curl_restart",attempts=attempts}
                        end
                        attempt_record(attempts,route,"curl_restart",false,verify_kind,verify_error,U.file_size(part) or 0)
                        if verify_kind=="sha_unavailable" or verify_kind=="catalog_integrity" then
                            return {ok=false,error=verify_error,kind=verify_kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                        end
                        os.remove(part)
                    else
                        fresh_error=type(fresh_error)=="table" and fresh_error or {error=tostring(fresh_error or "curl 重新下载失败"),kind="transport_error"}
                        attempt_record(attempts,route,"curl_restart",false,fresh_error.kind,fresh_error.error,U.file_size(part) or 0)
                        if should_wait_network(route,fresh_error.kind) then
                            return {ok=false,waiting_network=true,error=fresh_error.error,kind=fresh_error.kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                        end
                    end
                end
                if should_wait_network(route,curl_error.kind) then
                    return {ok=false,waiting_network=true,error=curl_error.error,kind=curl_error.kind,attempts=attempts,partial_bytes=U.file_size(part) or 0}
                end
                if not persistent_resume then os.remove(part) end
            end
        else
            logger.warn("[MiuRead][ExtensionDownload] curl unavailable","source=",route.key)
        end
    end

    local partial=0
    for _,route in ipairs(sources) do partial=math.max(partial,U.file_size(source_part(task_dir,route)) or 0) end
    local network_only=#attempts>0
    local all_unavailable=#attempts>0
    local transient_seen=false
    for _,attempt in ipairs(attempts) do
        local kind=tostring(attempt.kind or "")
        if kind~="dns_unavailable" and kind~="network_offline" then network_only=false end
        if kind~="source_unavailable" then all_unavailable=false end
        if kind=="dns_unavailable" or kind=="network_offline" or kind=="connect_timeout"
            or kind=="transport_error" or kind=="tls_error" then transient_seen=true end
    end
    if network_only then
        return {ok=false,waiting_network=true,error="当前网络或 DNS 尚未就绪，已保留下载进度",kind="network_unready",attempts=attempts,partial_bytes=partial}
    end
    -- A route-local 404, truncated proxy response or bad mirror content must not
    -- turn another route's temporary timeout into a permanent task failure. If
    -- at least one real transport failure occurred, park and retry later. Only
    -- a uniformly unavailable set (all routes 404) or pure content/integrity
    -- failures are reported as terminal here.
    if transient_seen and not all_unavailable then
        return {ok=false,waiting_network=true,error="下载线路暂时不稳定，断点已保留，稍后自动继续",kind="transport_retry",attempts=attempts,partial_bytes=partial}
    end
    if all_unavailable then
        return {ok=false,error="正式安装包在所有下载通道均不可用",kind="source_unavailable",attempts=attempts,partial_bytes=partial}
    end
    return {ok=false,error="所有可用下载源均失败",kind="sources_failed",attempts=attempts,partial_bytes=partial}
end

M.validate_download=validate_download
M.LARGE_FILE_BYTES=LARGE_FILE_BYTES
M.RESUME_BYTES=RESUME_BYTES

return M
