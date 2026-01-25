-- Init
-- 自动重载配置
function reloadConfig(files)
	doReload = false
	for _, file in pairs(files) do
		if file:sub(-4) == ".lua" then
			doReload = true
		end
	end
	if doReload then
		hs.reload()
	end
end
myWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

---End

-- ==========================================
-- 1. 自定义“粉嘟嘟果冻”提示 (修复居中与透明度)
-- ==========================================
local alertCanvas = hs.canvas.new({ x = 0, y = 0, w = 0, h = 0 })

local function showPinkAlert(text, duration)
	if not text or text == "" then
		return
	end

	local paddingW = 60 -- 增加左右留白
	local paddingH = 30 -- 增加上下留白
	local fontSize = 26
	local screen = hs.screen.mainScreen():frame()

	-- 计算文字实际大小
	local textSize =
		hs.drawing.getTextDrawingSize("🌸 " .. text .. " 🌸", { font = ".AppleSystemUIFont", size = fontSize })
	local canvasW = textSize.w + paddingW
	local canvasH = textSize.h + paddingH

	-- 重新构建画布内容
	alertCanvas[1] = { -- 背景：调低了 alpha 到 0.75，更显通透
		type = "rectangle",
		action = "fill",
		fillColor = { red = 1, green = 0.55, blue = 0.7, alpha = 0.75 },
		roundedRectRadii = { xRadius = canvasH / 2, yRadius = canvasH / 2 }, -- 胶囊形状
	}
	alertCanvas[2] = { -- 文字：确保在画布内绝对居中
		type = "text",
		text = "🌸 " .. text .. " 🌸",
		textSize = fontSize,
		textColor = { white = 1, alpha = 1 },
		textAlignment = "center",
		frame = { x = 0, y = (paddingH / 2) - 2, w = "100%", h = "100%" }, -- 微调 y 偏置实现垂直居中
	}

	-- 居中显示画布
	alertCanvas:frame({
		x = (screen.w - canvasW) / 2,
		y = (screen.h - canvasH) / 2,
		w = canvasW,
		h = canvasH,
	})

	alertCanvas:show()

	if _G.pinkAlertTimer then
		_G.pinkAlertTimer:stop()
	end
	_G.pinkAlertTimer = hs.timer.doAfter(duration or 1.2, function()
		alertCanvas:hide(0.3) -- 增加一个简单的淡出效果
	end)
end

-- ==========================================
-- 2. 窗口切换核心逻辑 (保持之前稳定的版本)
-- ==========================================
local switcher = {
	allWindows = {},
	index = 0,
	isActive = false,
	isMouseDown = false,
	keyTap = nil,
	mouseTap = nil,
	modifierTap = nil,
}

-- 监听鼠标状态
switcher.mouseTap = hs.eventtap
	.new({ hs.eventtap.event.types.leftMouseDown, hs.eventtap.event.types.leftMouseUp }, function(event)
		switcher.isMouseDown = (event:getType() == hs.eventtap.event.types.leftMouseDown)
		return false
	end)
	:start()

-- 获取目标窗口
local function getTargetWindows(mouseDown)
	local rawWindows = hs.window.orderedWindows()
	local filtered = {}
	local targetAppName = nil

	if mouseDown then
		local mousePos = hs.mouse.absolutePosition()
		for _, win in ipairs(rawWindows) do
			local frame = win:frame()
			if
				frame
				and mousePos.x >= frame.x
				and mousePos.x <= (frame.x + frame.w)
				and mousePos.y >= frame.y
				and mousePos.y <= (frame.y + frame.h)
			then
				local app = win:application()
				if app and win:isStandard() then
					targetAppName = app:name()
					break
				end
			end
		end
	end

	if targetAppName then
		for _, win in ipairs(rawWindows) do
			local app = win:application()
			if app and app:name() == targetAppName and win:isStandard() and win:isVisible() then
				table.insert(filtered, win)
			end
		end
		showPinkAlert(targetAppName, 1.2) -- 触发自定义提示
	else
		local seenApps = {}
		for _, win in ipairs(rawWindows) do
			local app = win:application()
			if app and win:isStandard() and win:isVisible() and not win:isMinimized() then
				local name = app:name()
				if name and not seenApps[name] then
					table.insert(filtered, win)
					seenApps[name] = true
				end
			end
		end
	end
	return filtered
end

-- 键盘拦截
switcher.keyTap = hs.eventtap
	.new({ hs.eventtap.event.types.keyDown }, function(event)
		local flags = event:getFlags()
		local keyCode = event:getKeyCode()

		if flags.cmd and keyCode == 48 then
			if not switcher.isActive then
				switcher.allWindows = getTargetWindows(switcher.isMouseDown)
				switcher.index = 1
				switcher.isActive = true
			end
			if #switcher.allWindows > 1 then
				switcher.index = (switcher.index % #switcher.allWindows) + 1
				local targetWin = switcher.allWindows[switcher.index]
				if targetWin then
					targetWin:focus()
				end
			end
			return true
		end
		return false
	end)
	:start()

-- 释放重置
switcher.modifierTap = hs.eventtap
	.new({ hs.eventtap.event.types.flagsChanged }, function(event)
		local flags = event:getFlags()
		if not flags.cmd and switcher.isActive then
			switcher.isActive = false
			switcher.index = 0
			switcher.allWindows = {}
		end
		return false
	end)
	:start()

-- Input method Manager

-- 1. 定义 ID
local LANG_ABC = "com.apple.keylayout.ABC"
local LANG_RIME = "im.rime.inputmethod.Squirrel.Hans"

-- 2. 定义 App 规则
local app_rules = {
	["WezTerm"] = LANG_ABC,
	["Emacs"] = LANG_ABC,
	["WeChat"] = LANG_RIME,
	["微信"] = LANG_RIME,
}

-- 3. 核心切换函数
local function switchInput(appName)
	local target = app_rules[appName]
	if target and hs.keycodes.currentSourceID() ~= target then
		hs.keycodes.currentSourceID(target)
	end
end

-- 【改进版】监听窗口焦点变化：处理鼠标点击、Command+Tab、Dock点击等所有行为
wf = hs.window.filter.new(nil)
wf:subscribe(hs.window.filter.windowFocused, function(window)
	local appName = window:application():name()
	switchInput(appName)
end)

-- 4. 暴力劫持 Cmd + Space (保留你最满意的 Raycast 方案)
-- --- 单击 Cmd 唤起 Raycast 逻辑 ---

local sendCmdSpace = function()
	-- 1. 先切输入法
	hs.keycodes.currentSourceID(LANG_ABC)
	-- 2. 模拟你之前设置的 Raycast 复杂快捷键
	hs.timer.doAfter(0.01, function()
		hs.eventtap.keyStroke({ "ctrl", "alt", "cmd", "shift" }, "space")
	end)
end

local lastModifiers = {}
local cmdDownTime = 0
local cmdTapSuccess = false

-- 监听修饰键变化
cmdWatcher = hs.eventtap
	.new({ hs.eventtap.event.types.flagsChanged }, function(event)
		local modifiers = event:getFlags()
		local keyCode = event:getKeyCode()

		-- 检查是否只有 Cmd 被按下 (Left Cmd: 55, Right Cmd: 54)
		if keyCode == 55 or keyCode == 54 then
			if modifiers.cmd and not (modifiers.alt or modifiers.shift or modifiers.ctrl or modifiers.fn) then
				-- Cmd 按下
				cmdDownTime = hs.timer.secondsSinceEpoch()
				cmdTapSuccess = true -- 先假设它会成功
			elseif not modifiers.cmd and cmdTapSuccess then
				-- Cmd 放开
				local duration = hs.timer.secondsSinceEpoch() - cmdDownTime
				-- 如果按下到放开的时间小于 0.3 秒，则视为单击
				if duration < 0.3 then
					sendCmdSpace()
				end
				cmdTapSuccess = false
			end
		else
			-- 如果按下了其他修饰键，取消判定
			cmdTapSuccess = false
		end
		return false
	end)
	:start()

-- 监听普通按键按下
-- 如果在 Cmd 按住期间按了任何字母/数字键，立即取消单击判定
keyDownWatcher = hs.eventtap
	.new({ hs.eventtap.event.types.keyDown }, function(event)
		if cmdTapSuccess then
			cmdTapSuccess = false
		end
		return false
	end)
	:start()

-- ENd

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
		hs.task.new("/usr/bin/open", nil, { "-b", "com.google.Chrome.canary", url }):start()
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
