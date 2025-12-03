function love.conf(t)
    t.title = "Hello World Love2D"
    t.version = "11.5"  -- Match love.js version
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false

    -- Recommended settings for web
    t.modules.thread = false  -- Threads have limited browser support
end
