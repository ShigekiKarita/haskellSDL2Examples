{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances    #-}

module Main (main) where

import qualified Graphics.UI.SDL as SDL
import qualified Graphics.UI.SDL.Image as Image
import Graphics.UI.SDL.Types
import Control.Monad.State hiding (state)
import Foreign.C.Types
import Shared.Input
import Shared.Lifecycle
import Shared.Textures
import Shared.Polling
import Shared.Utilities
import Shared.State


title :: String
title = "lesson15"

size :: ScreenSize
size = (640, 480)

inWindow :: (SDL.Window -> IO ()) -> IO ()
inWindow = withSDL . withWindow title size

initialState :: World
initialState = World { gameover = False, quadrants = map makeEntity allPositions }

makeEntity :: Position -> Entity
makeEntity pos = Entity { mouseState = MouseOut, position = pos }

main :: IO ()
main = inWindow $ \window -> Image.withImgInit [Image.InitPNG] $ do
    _ <- setHint "SDL_RENDER_SCALE_QUALITY" "0" >>= logWarning
    renderer <- createRenderer window (-1) [SDL.SDL_RENDERER_ACCELERATED, SDL.SDL_RENDERER_PRESENTVSYNC] >>= either throwSDLError return
    texture <- loadTexture renderer "./assets/mouse_states.png"
    (w, h) <- getTextureSize texture
    let asset = (texture, w, h)
    let inputSource = pollEvent `into` updateState
    let pollDraw = inputSource ~>~ drawState renderer [asset]
    _ <- runStateT (repeatUntilComplete pollDraw) initialState
    SDL.destroyTexture texture
    SDL.destroyRenderer renderer


data World = World { gameover :: Bool, quadrants :: [Entity] }
data Entity = Entity { mouseState :: EntityState, position :: Position }
type Asset = (SDL.Texture, CInt, CInt)
data Position = TopLeft | TopRight | BottomLeft | BottomRight deriving (Eq, Enum, Bounded)
data EntityState = MouseOut | MouseOver | MouseDown | MouseUp

drawState :: SDL.Renderer -> [Asset] -> World -> IO ()
drawState renderer assets world = withBlankScreen renderer $ mapM render' (quadrants world)
    where (texture, w, h) = head assets
          render' entity = with2 (maskFor entity) (positionFor entity) (SDL.renderCopy renderer texture)
          sprite = toRect 0 0 (w `div` 2) (h `div` 2)
          maskFor entity = maskFromState sprite (mouseState entity) 
          positionFor entity = sprite `moveTo` positionToPoint (position entity)

within :: (Int, Int) -> (Int, Int) -> Bool
within (mx, my) (px, py) = withinX && withinY
    where withinX = px < mx && mx < px + 320
          withinY = py < my && my < py + 240

maskFromState :: SDL.Rect -> EntityState -> SDL.Rect
maskFromState sprite MouseOut = sprite `moveTo` positionToPoint TopLeft
maskFromState sprite MouseOver = sprite `moveTo` positionToPoint TopRight
maskFromState sprite MouseDown = sprite `moveTo` positionToPoint BottomLeft
maskFromState sprite MouseUp = sprite `moveTo` positionToPoint BottomRight

positionToPoint :: Position -> (Int, Int)
positionToPoint TopLeft = (0, 0)
positionToPoint TopRight = (320, 0)
positionToPoint BottomLeft = (0, 240)
positionToPoint BottomRight = (320, 240)

allPositions :: [Position]
allPositions = [minBound .. ]

withBlankScreen :: SDL.Renderer -> IO a -> IO ()
withBlankScreen renderer operation = do
    _ <- SDL.setRenderDrawColor renderer 0xFF 0xFF 0xFF 0xFF
    _ <- SDL.renderClear renderer
    _ <- operation
    SDL.renderPresent renderer

updateState :: Input -> World -> World
updateState (Just (SDL.QuitEvent _ _)) state = state { gameover = True }
updateState (Just (SDL.MouseMotionEvent _ _ _ _ _ x y _ _)) state = state { quadrants = updatedEntities }
    where updatedEntities = map (makeNewEntity (fromIntegral x) (fromIntegral y)) allPositions
updateState (Just (SDL.MouseButtonEvent evtType _ _ _ _ _ _ _ _)) state
    | evtType == SDL.SDL_MOUSEBUTTONDOWN = state
    | evtType == SDL.SDL_MOUSEBUTTONUP = state
    | otherwise = state
updateState _ state = state

makeNewEntity :: Int -> Int -> Position -> Entity
makeNewEntity x y pos = Entity { mouseState = newState, position = pos }
    where newState = getMouseState pos x y

getMouseState :: Position -> Int -> Int -> EntityState
getMouseState pos x y 
    | (x, y) `within` n  = MouseOver
    | otherwise     = MouseOut
    where n = positionToPoint pos

repeatUntilComplete :: (Monad m) => m World -> m ()
repeatUntilComplete game = game >>= \state -> unless (gameover state) $ repeatUntilComplete game

toRect :: (Integral a) => a -> a -> a -> a -> SDL.Rect
toRect x y w h = SDL.Rect { rectX = fromIntegral x, rectY = fromIntegral y, rectW = fromIntegral w, rectH = fromIntegral h }

moveTo :: (Integral a1, Integral a2) => SDL.Rect -> (a1, a2) -> SDL.Rect
moveTo rect (x, y) = rect { rectX = fromIntegral x, rectY = fromIntegral y }
