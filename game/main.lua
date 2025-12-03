function love.load()
    -- Initialize the message
    message = "Hello World, Love2D!"
end

function love.update(dt)
    -- Update game state (nothing to update for this simple example)
end

function love.draw()
    -- Get window dimensions for centering
    local windowWidth = love.graphics.getWidth()
    local windowHeight = love.graphics.getHeight()

    -- Get the font and calculate text dimensions
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(message)
    local textHeight = font:getHeight()

    -- Calculate centered position
    local x = (windowWidth - textWidth) / 2
    local y = (windowHeight - textHeight) / 2

    -- Draw the message centered on screen
    love.graphics.print(message, x, y)
end
