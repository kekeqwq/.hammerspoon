hs.hotkey.bind({ "cmd", "ctrl" }, "C", function()
	-- 0. 先清空剪贴板，防止读到旧内容
	hs.pasteboard.clearContents()

	-- 1. 尝试通过 AppleScript 复制 URL
	local script = [[
        tell application "Firefox"
            activate
            delay 0.1 -- 等待窗口获得焦点
            tell application "System Events"
                keystroke "l" using {command down} -- 选中地址栏
                delay 0.2
                keystroke "c" using {command down} -- 复制
                delay 0.3
            end tell
        end tell
    ]]
	hs.applescript.applescript(script)

	-- 2. 轮询读取剪贴板（最多等 1 秒），解决延迟问题
	local url = nil
	local count = 0
	while (not url or url == "") and count < 10 do
		url = hs.pasteboard.readString()
		if url and url:match("^https?://") then
			break
		end
		hs.timer.usleep(100000) -- 等待 0.1 秒
		count = count + 1
	end

	-- 3. 判断并执行
	if url and url:match("^https?://") then
		-- 确定拿到 URL 后，再关闭 Firefox 标签页
		hs.applescript.applescript([[
            tell application "Firefox" to activate
            tell application "System Events" to keystroke "w" using {command down}
        ]])

		-- 调用系统 open 指令启动 Chrome
		hs.task.new("/usr/bin/open", nil, { "-b", "com.google.Chrome", url }):start()
		hs.alert.show("💖 迁移成功: " .. url)
	else
		-- 错误排查提示
		local currentClip = hs.pasteboard.readString() or "剪贴板为空"
		hs.alert.show("获取失败！当前内容: " .. string.sub(currentClip, 1, 20))
	end
end)

-- 如果运行后弹出“无法读取 Chrome”，请务必检查：
-- Chrome 菜单栏 -> 查看 (View) -> 开发 (Developer) -> 允许 AppleScript 脚本控制 (Allow JavaScript from AppleScript) 是否被勾选。
-- 如果你的 Mac 系统提示“Hammerspoon 想要控制 Google Chrome”，请点击 允许。

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "C", function()
	-- 1. 物理刷新
	hs.eventtap.keyStroke({ "cmd" }, "R")
	hs.alert.show("🔄 正在同步本地时间...", 1)

	-- 抓取逻辑函数
	local function performGrab()
		local script = [[
            tell application "Google Chrome"
                tell active tab of front window
                    execute javascript "
                        (function() {
                            try {
                                // 锁定作者区域
                                const authorEl = document.querySelector('#upload-info a[href*=\"/@\"]') || 
                                                 document.querySelector('#upload-info a[href*=\"/channel/\"]') ||
                                                 document.querySelector('yt-formatted-string.ytd-channel-name a');
                                
                                // 获取原始日期标签
                                const rawDate = document.querySelector('meta[itemprop=\"uploadDate\"]')?.getAttribute('content') ||
                                                document.querySelector('meta[itemprop=\"datePublished\"]')?.getAttribute('content');

                                // 只有当作者和原始日期【同时存在】时才进行处理
                                if (authorEl && authorEl.innerText.trim() && rawDate) {
                                    const author = authorEl.innerText.trim();
                                    
                                    // 时区转换：将 UTC 转为本地时间
                                    const dateObj = new Date(rawDate);
                                    if (isNaN(dateObj.getTime())) return 'not_ready'; // 防止日期格式半加载

                                    const yy = String(dateObj.getFullYear()).slice(-2);
                                    const mm = String(dateObj.getMonth() + 1).padStart(2, '0');
                                    const dd = String(dateObj.getDate()).padStart(2, '0');
                                    
                                    return author + '|||' + yy + '.' + mm + '.' + dd;
                                }
                            } catch (e) {}
                            return 'not_ready';
                        })()
                    "
                end tell
            end tell
        ]]

		local ok, result = hs.applescript.applescript(script)
		if ok and result ~= "not_ready" and result ~= "" then
			local author, date = result:match("^(.-)|||(.-)$")
			local final = string.format("Watch %s(%s) Via Youtube", author:gsub("[\n\r]", ""), date)
			hs.pasteboard.setContents(final)
			hs.alert.show("✅ 完美同步\n" .. final, 2)
			return true
		end
		return false
	end

	-- 2. 第一次尝试 (稍微多给一点点时间，2.8秒)
	hs.timer.doAfter(2.8, function()
		if not performGrab() then
			-- 3. 补刀尝试 (4.5秒)
			hs.timer.doAfter(1.7, function()
				if not performGrab() then
					hs.alert.show("❌ 加载超时，请稍后再试", 2)
				end
			end)
		end
	end)
end)

-- ==========================================
-- 功能 A: Firefox 转移至 Chrome (你已做好)
-- 快捷键: Cmd + Ctrl + C
-- ==========================================

-- ==========================================
-- 功能 B: Chrome 完美提取 (刚才磨合好的)
-- 快捷键: Cmd + Alt + Ctrl + C
-- ==========================================

-- ==========================================
-- 功能 C: 【终极一键全自动】
-- 快捷键: Cmd + Ctrl + Y
-- ==========================================
hs.hotkey.bind({ "cmd", "ctrl" }, "y", function()
	-- 1. 触发转移 (Firefox -> Chrome)
	hs.eventtap.keyStroke({ "cmd", "ctrl" }, "c")
	hs.alert.show("🚀 转移、提取、记账一键启动...", 1.5)

	-- 2. 核心等待：给 Chrome 加载视频页留出 4 秒
	hs.timer.doAfter(4.0, function()
		-- 3. 触发提取 (Chrome 抓取剪贴板)
		hs.eventtap.keyStroke({ "cmd", "alt", "ctrl" }, "c")

		-- 4. 触发记账 App (给抓取留 0.5s 写入时间)
		hs.timer.doAfter(0.5, function()
			-- 如果 App 名字完全匹配，它会直接跳转或启动
			hs.application.launchOrFocus("Refold Tracker")
			hs.alert.show("📊 搞定！直接粘贴即可", 1.5)
			hs.alert.show("💖💖💖 Happy Learning！记得手动让 Migaku 生成一下字幕~", 1.5)
		end)
	end)
end)
