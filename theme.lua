-- Colours, tetromino shapes and a text helper shared by the game and its screens.
local pc = picocalc

-- 80s Neon Colors
local C = {
    BG = pc.display.rgb(10, 0, 20),
    GRID = pc.display.rgb(40, 20, 80),
    TEXT = pc.display.rgb(220, 220, 255),
    GAMEOVER = pc.display.rgb(255, 50, 50),
    -- Piece colors
    CYAN = pc.display.rgb(0, 255, 255),
    BLUE = pc.display.rgb(0, 100, 255),
    ORANGE = pc.display.rgb(255, 150, 0),
    YELLOW = pc.display.rgb(255, 255, 0),
    GREEN = pc.display.rgb(50, 255, 50),
    PURPLE = pc.display.rgb(150, 50, 255),
    PINK = pc.display.rgb(255, 50, 150),
    WHITE = pc.display.rgb(255, 255, 255),
    -- Title screen and panels
    RAIN = pc.display.rgb(0, 110, 130),
    PANEL = pc.display.rgb(8, 0, 18),
    DIM = pc.display.rgb(110, 110, 150),
}
C.BORDER = C.CYAN
C.FLASH = C.YELLOW

-- Tetromino shapes and colors
-- Coordinates are relative to top-left of a 4x4 grid
local TETROMINOES = {
    -- I
    { rotations = { {{0,1},{1,1},{2,1},{3,1}}, {{1,0},{1,1},{1,2},{1,3}} }, color = C.CYAN },
    -- J
    { rotations = { {{0,0},{0,1},{1,1},{2,1}}, {{1,0},{2,0},{1,1},{1,2}}, {{0,1},{1,1},{2,1},{2,2}}, {{1,0},{1,1},{0,2},{1,2}} }, color = C.BLUE },
    -- L
    { rotations = { {{2,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{1,2},{2,2}}, {{0,1},{1,1},{2,1},{0,2}}, {{0,0},{1,0},{1,1},{1,2}} }, color = C.ORANGE },
    -- O
    { rotations = { {{1,1},{2,1},{1,2},{2,2}} }, color = C.YELLOW },
    -- S
    { rotations = { {{1,0},{2,0},{0,1},{1,1}}, {{1,0},{1,1},{2,1},{2,2}} }, color = C.GREEN },
    -- T
    { rotations = { {{1,0},{0,1},{1,1},{2,1}}, {{1,0},{1,1},{2,1},{1,2}}, {{0,1},{1,1},{2,1},{1,2}}, {{1,0},{0,1},{1,1},{1,2}} }, color = C.PURPLE },
    -- Z
    { rotations = { {{0,0},{1,0},{1,1},{2,1}}, {{2,0},{1,1},{2,1},{1,2}} }, color = C.PINK }
}

-- Draws text centred across the screen in the current font, with no background.
local function centre(text, y, colour)
    local w = pc.display.textWidth(text)
    pc.display.drawText(math.floor((320 - w) / 2), y, text, colour, false)
end

return { C = C, TETROMINOES = TETROMINOES, centre = centre }
