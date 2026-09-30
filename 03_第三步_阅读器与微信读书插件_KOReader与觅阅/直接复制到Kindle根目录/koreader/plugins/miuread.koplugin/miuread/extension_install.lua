-- MiuRead deterministic extension installer v4.
-- Accepts only a package that has already passed size + SHA-256 verification.
-- KOReader's own Archiver is the single archive authority. Installation is
-- staged and swapped transactionally so a failed update keeps the old plugin.

local DataStorage=require("datastorage")
local lfs=require("libs/libkoreader-lfs")
local Json=require("miuread.json")
local U=require("miuread.util")
local Compat=require("miuread.extension_compat")
local logger=require("logger")
local archiver_ok,Archiver=pcall(require,"ffi/archiver")

local M={}
local MAX_ARCHIVE_ENTRIES=6000
local MAX_PLUGIN_FILES=5000
local DEFAULT_MAX_PLUGIN_BYTES=96*1024*1024

local function trim(value) return U.trim(tostring(value or "")) end
local function dirname(path)
    local out=tostring(path or ""):gsub("/+$",""):match("^(.*)/[^/]+$")
    return out and out~="" and out or "."
end
local function valid_plugin_dir(name)
    return type(name)=="string" and name:match("^[%w%._%-]+%.koplugin$")~=nil and name~="miuread.koplugin"
end
local function mode(path)
    return lfs.attributes(path,"mode")
end
local function read_meta(path)
    local raw=U.read_file(path.."/_meta.lua",true) or ""
    local version=raw:match('[%s,{]version%s*=%s*["\']([^"\']+)["\']')
        or raw:match('^version%s*=%s*["\']([^"\']+)["\']') or ""
    local identity=raw:match('[%s,{]fullname%s*=%s*["\']([^"\']+)["\']')
        or raw:match('[%s,{]name%s*=%s*["\']([^"\']+)["\']') or ""
    return {version=version,identity=identity}
end
local function write_json(path,value)
    return U.atomic_write(path,Json.encode(type(value)=="table" and value or {}),true)
end

local function open_archiver(path)
    if not archiver_ok or type(Archiver)~="table" or type(Archiver.Reader)~="table" then
        return nil,"KOReader Archiver 不可用"
    end
    local ok,reader=pcall(function() return Archiver.Reader:new() end)
    if not ok or not reader then return nil,"无法创建 KOReader Archiver" end
    local opened_ok,opened=pcall(function() return reader:open(path) end)
    if not opened_ok or not opened then
        pcall(function() reader:close() end)
        return nil,"KOReader Archiver 无法打开安装包"
    end
    return reader
end
local function close_archiver(reader)
    if reader then pcall(function() reader:close() end) end
end

local function validate_archive_path(name)
    name=tostring(name or "")
    if name=="" then return nil,"ZIP 包含空路径" end
    if name:sub(1,1)=="/" or name:find("\\",1,true) or name:find("%z") then return nil,"ZIP 包含不安全路径" end
    for part in name:gmatch("[^/]+") do
        if part==".." or part=="." then return nil,"ZIP 包含目录穿越路径" end
    end
    return true
end

local function inspect_archive(reader)
    local entries,files=0,0
    local ok,err=pcall(function()
        for entry in reader:iterate() do
            entries=entries+1
            if entries>MAX_ARCHIVE_ENTRIES then error("ZIP 文件数量过多") end
            local safe,path_error=validate_archive_path(entry.path)
            if not safe then error(path_error) end
            local entry_mode=tostring(entry.mode or "")
            if entry_mode:lower():find("link",1,true) then error("插件包包含符号链接") end
            if entry_mode=="file" then files=files+1 end
        end
    end)
    if not ok then return nil,tostring(err):gsub("^.-:%d+:%s*","") end
    if entries==0 or files==0 then return nil,"ZIP 中没有可安装文件" end
    return {entries=entries,files=files}
end

local function extract_archive(reader,root,limit)
    local files,bytes=0,0
    local ok,err=pcall(function()
        for entry in reader:iterate() do
            if tostring(entry.mode or "")=="file" then
                local safe,path_error=validate_archive_path(entry.path)
                if not safe then error(path_error) end
                local dest=root.."/"..tostring(entry.path)
                U.mkdir(dirname(dest))
                if not reader:extractToPath(entry.path,dest) then error("解压插件文件失败："..tostring(entry.path)) end
                files=files+1
                bytes=bytes+(tonumber(lfs.attributes(dest,"size")) or 0)
                if files>MAX_PLUGIN_FILES then error("插件文件数量过多") end
                if bytes>limit then error("插件解压后体积超过安全上限") end
            end
        end
    end)
    if not ok then return nil,tostring(err):gsub("^.-:%d+:%s*","") end
    return {files=files,bytes=bytes}
end

local function tree_stats(root,limit)
    local files,bytes=0,0
    local function walk(path)
        local ok,iter,state=pcall(lfs.dir,path)
        if not ok or type(iter)~="function" then return nil,"无法读取插件目录" end
        for name in iter,state do
            if name~="." and name~=".." then
                local child=path.."/"..name
                local child_mode=type(lfs.symlinkattributes)=="function" and lfs.symlinkattributes(child,"mode") or lfs.attributes(child,"mode")
                if child_mode=="link" then return nil,"插件目录包含符号链接" end
                if child_mode=="directory" then
                    local worked,err=walk(child); if not worked then return nil,err end
                elseif child_mode=="file" then
                    files=files+1; bytes=bytes+(tonumber(lfs.attributes(child,"size")) or 0)
                    if files>MAX_PLUGIN_FILES then return nil,"插件文件数量过多" end
                    if bytes>limit then return nil,"插件体积超过安全上限" end
                end
            end
        end
        return true
    end
    local ok,err=walk(root)
    if not ok then return nil,err end
    return {files=files,bytes=bytes}
end

local function find_expected_plugin(root,expected_dir)
    if not valid_plugin_dir(expected_dir) then return nil,"目录记录缺少有效插件目录" end
    local exact,candidates={},{}
    local visited=0
    local function consider(path,name)
        if not U.file_exists(path.."/main.lua") or not U.file_exists(path.."/_meta.lua") then return end
        candidates[#candidates+1]=path
        if name==expected_dir or path:match("/"..expected_dir:gsub("([%%%-%+%.%*%?%[%]%^%$%(%)])","%%%1").."$") then
            exact[#exact+1]=path
        end
    end
    consider(root,root:match("([^/]+)$"))
    local function walk(path,depth)
        if depth>4 or visited>MAX_ARCHIVE_ENTRIES then return end
        local ok,iter,state=pcall(lfs.dir,path)
        if not ok or type(iter)~="function" then return end
        for name in iter,state do
            if name~="." and name~=".." then
                local child=path.."/"..name
                if mode(child)=="directory" then
                    visited=visited+1
                    consider(child,name)
                    walk(child,depth+1)
                end
            end
        end
    end
    walk(root,0)
    if #exact==1 then return exact[1] end
    if #exact>1 then return nil,"安装包中出现多个目录记录指定的插件，已停止安装" end
    -- Release authors commonly ship either `foo.koplugin/` or the plugin files
    -- directly under one wrapper directory. The target dirname is never guessed:
    -- when the exact named directory is absent, accept only one unambiguous
    -- complete KOReader plugin payload and still install it as expected_dir.
    if #candidates==1 then return candidates[1] end
    if #candidates==0 then return nil,"安装包中没有找到完整 KOReader 插件（缺少 main.lua / _meta.lua）" end
    return nil,"安装包中包含多个插件根目录，无法安全对应内置目录"
end

local function safe_remove(path)
    if path and path~="" and mode(path) then U.remove_tree(path) end
end

local function rename_dir(from,to)
    if not mode(from) then return nil,"源目录不存在" end
    if mode(to) then return nil,"目标目录已存在" end
    local ok,err=os.rename(from,to)
    if ok then return true end
    return nil,tostring(err or "rename failed")
end

function M.install(store,task_dir,zip_path,spec)
    spec=type(spec)=="table" and spec or {}
    local function phase(state,message)
        if type(spec.on_phase)=="function" then pcall(spec.on_phase,state,message) end
    end
    local repo=tostring(spec.repo or "")
    local expected_dir=tostring(spec.expected_dir or "")
    local limit=tonumber(spec.max_plugin_bytes) or DEFAULT_MAX_PLUGIN_BYTES
    if not valid_plugin_dir(expected_dir) then return nil,"内置目录未提供有效安装目录","catalog" end
    if not U.file_exists(zip_path) then return nil,"已验证安装包不存在","missing" end

    local stage=task_dir.."/stage"
    local unpacked=stage.."/unpacked"
    local journal_path=task_dir.."/install-journal.json"
    safe_remove(stage); U.mkdir(unpacked)

    logger.info("[MiuRead][ExtensionInstall] archive open","repo=",repo,"bytes=",tostring(U.file_size(zip_path) or 0))
    local reader,open_error=open_archiver(zip_path)
    if not reader then safe_remove(stage); os.remove(zip_path); return nil,open_error,"archive_open" end
    local inspected,inspect_error=inspect_archive(reader)
    if not inspected then close_archiver(reader); safe_remove(stage); os.remove(zip_path); return nil,inspect_error,"archive_validate" end
    logger.info("[MiuRead][ExtensionInstall] archive verified","repo=",repo,"entries=",tostring(inspected.entries),"files=",tostring(inspected.files))
    phase("extracting","安装包校验通过，正在解压并检查插件")
    local stats,extract_error=extract_archive(reader,unpacked,limit)
    close_archiver(reader)
    if not stats then safe_remove(stage); os.remove(zip_path); return nil,extract_error,"extract" end

    local incoming,detect_error=find_expected_plugin(unpacked,expected_dir)
    if not incoming then safe_remove(stage); os.remove(zip_path); return nil,detect_error,"plugin_detect" end
    local compatibility=type(spec.compatibility)=="table" and spec.compatibility or Compat.evaluate(spec.entry or {},spec.plugin)
    local candidate_ok,candidate_error=Compat.validate_candidate(spec.entry or {},incoming,compatibility)
    if not candidate_ok then safe_remove(stage); os.remove(zip_path); return nil,candidate_error,"architecture_validate" end

    local existing_path=tostring(spec.existing_path or "")
    local target_root=existing_path~="" and dirname(existing_path) or (DataStorage:getDataDir().."/plugins")
    U.mkdir(target_root)
    local target=target_root.."/"..expected_dir
    if existing_path~="" and existing_path~=target then
        safe_remove(stage); os.remove(zip_path); return nil,"已安装插件位置与目录记录不一致","collision_check"
    end
    if mode(target)=="directory" and (not U.file_exists(target.."/main.lua") or not U.file_exists(target.."/_meta.lua")) then
        safe_remove(stage); os.remove(zip_path); return nil,"目标目录已存在但不是完整 KOReader 插件，已拒绝覆盖","collision_check"
    end

    local token=tostring(os.time()).."-"..tostring(math.random(1000,9999))
    local new_path=target_root.."/."..expected_dir..".miuread-new-"..token
    local old_path=target_root.."/."..expected_dir..".miuread-old-"..token
    safe_remove(new_path); safe_remove(old_path)

    -- task_dir and KOReader's plugins directory normally share the same data
    -- filesystem. Prefer a rename so large plugins are not duplicated during
    -- staging. If a platform places them on different filesystems, fall back to
    -- a streamed tree copy after checking that enough free space remains.
    local prepared=os.rename(incoming,new_path)
    if not prepared then
        local free=U.free_space(target_root)
        local copy_need=(tonumber(stats.bytes) or 0)+8*1024*1024
        if free and free<copy_need then
            safe_remove(stage); safe_remove(new_path); os.remove(zip_path)
            return nil,"存储空间不足，无法准备新插件","space_check"
        end
        local copied,copy_error=U.copy_tree(incoming,new_path)
        if not copied then safe_remove(stage); safe_remove(new_path); os.remove(zip_path); return nil,"准备新插件失败："..tostring(copy_error),"prepare_new" end
    end
    if not U.file_exists(new_path.."/main.lua") or not U.file_exists(new_path.."/_meta.lua") then
        safe_remove(stage); safe_remove(new_path); os.remove(zip_path); return nil,"新插件结构不完整","prepare_new"
    end
    local new_stats,new_stats_error=tree_stats(new_path,limit)
    if not new_stats then safe_remove(stage); safe_remove(new_path); os.remove(zip_path); return nil,new_stats_error,"prepare_new" end

    phase("installing","正在安全切换插件版本")
    local journal={phase="prepared",target=target,new_path=new_path,old_path=old_path,repo=repo,expected_dir=expected_dir,updated_at=os.time()}
    write_json(journal_path,journal)

    local had_old=mode(target)=="directory"
    if had_old then
        local moved,move_error=rename_dir(target,old_path)
        if not moved then
            os.remove(journal_path); safe_remove(stage); safe_remove(new_path); os.remove(zip_path)
            return nil,"无法暂存旧插件："..tostring(move_error),"swap_old"
        end
        journal.phase="old_moved"; journal.updated_at=os.time(); write_json(journal_path,journal)
    end

    local installed,install_error=rename_dir(new_path,target)
    if not installed then
        if had_old and mode(old_path)=="directory" and not mode(target) then os.rename(old_path,target) end
        os.remove(journal_path); safe_remove(stage); safe_remove(new_path); os.remove(zip_path)
        return nil,"无法切换到新插件："..tostring(install_error)..(had_old and "；已恢复旧版本" or ""),"swap_new"
    end
    journal.phase="new_installed"; journal.updated_at=os.time(); write_json(journal_path,journal)

    local final_stats,final_error=tree_stats(target,limit)
    if not final_stats or not U.file_exists(target.."/main.lua") or not U.file_exists(target.."/_meta.lua") then
        safe_remove(target)
        if had_old and mode(old_path)=="directory" then os.rename(old_path,target) end
        os.remove(journal_path); safe_remove(stage); os.remove(zip_path)
        return nil,tostring(final_error or "安装后的插件结构不完整")..(had_old and "；已恢复旧版本" or ""),"post_validate"
    end

    safe_remove(old_path)
    os.remove(journal_path)
    safe_remove(stage)
    os.remove(zip_path)
    local meta=read_meta(target)
    logger.info("[MiuRead][ExtensionInstall] completed","repo=",repo,"dir=",expected_dir,"files=",tostring(final_stats.files),"bytes=",tostring(final_stats.bytes),"version=",tostring(meta.version))
    return {
        dir=expected_dir,path=target,version=meta.version,files=final_stats.files,bytes=final_stats.bytes,updated=had_old,
    }
end

return M
