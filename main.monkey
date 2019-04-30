Import coreproc.coreapp
Import coreproc.io.tiledmap
Import coreproc.graphics.drawbox
Import coreproc.graphics.texturepacker
Import coreproc.bitmapfont
Import coreproc.graphics.shaders.solidcolorshader
Import coreproc.audio.soundmanager

'Config
#TEXT_FILES="*.bin|*.dat|*.ini|*.txt|*.json|*.xml|*.cbl|*.lang|*.der|*.fnt|*.htm|*.html|*.css"
#BINARY_FILES="*.bin|*.dat|*.ini|*.txt|*.json|*.xml|*.cbl|*.lang|*.der|*.fnt|*.htm|*.html|*.css"

#SOUND_FILES="*.mp3"
#MUSIC_FILES="*.mp3"

#GLFW_WINDOW_WIDTH=960
#GLFW_WINDOW_HEIGHT=540
#GLFW_WINDOW_DECORATED=1
#GLFW_WINDOW_FLOATING=1
#GLFW_WINDOW_FULLSCREEN=false


Global app:CoreApp

Class MapFlags
    Const BLOCK      := (1 Shl 0)
    Const LEVEL_EXIT := (1 Shl 1)
End

Class Level
    Field x#, y#
    Field dx#, dy#
    Field flags%[]

    Field map:TiledMap
    Field background:TiledMap
    Field currentLevel%


    Method GetCollisionMask(rect:Rect)
        Local result := 0

        Local sx := Floor(rect.x / 16.0)
        Local sy := Floor(rect.y / 16.0)
        Local ex := Ceil((rect.x + rect.w) / 16.0)
        Local ey := Ceil((rect.y + rect.h) / 16.0)

        For Local mx := sx Until ex
            For Local my := sy Until ey
                result |= flags[mx + my * map.width]
            Next
        Next

        Return result
    End

    Method GetCollisionMask(x#, y#, w#, h#)
        Local result := 0

        Local sx := Floor(x / 16.0)
        Local sy := Floor(y / 16.0)
        Local ex := Ceil((x + w) / 16.0)
        Local ey := Ceil((y + h) / 16.0)

        For Local mx := sx Until ex
            For Local my := sy Until ey
                result |= flags[mx + my * map.width]
            Next
        Next

        Return result
    End
End

Class Player
    Const ANIM_IDLE := 0
    Const ANIM_RUN := 1
    Const ANIM_JUMP := 2
    Const ANIM_FALL := 3
    Const ANIM_COUNT := 4

    Const ANIM_SPEED_IDLE := 0.1
    Const ANIM_SPEED_RUN := 0.2
    Const ANIM_SPEED_JUMP := 1.0
    Const ANIM_SPEED_FALL := 0.2

    Const STATE_FALLING := 1
    Const STATE_IDLE := 2
    Const STATE_RUNNING := 3
    Const STATE_JUMP := 4
    Const STATE_DIED := 5
    Const STATE_LEVEL_COMPLETED := 6

    Const GRAVITY := 0.3
    Const MOVE_ACCELERATION := 2.0 / 12.0
    Const RUN_SLOWDOWN:Float = 1.0 - (MOVE_ACCELERATION)
    Const RUN_TRESHOLD := 0.05
    Const MAX_SPEED_X := 2.0
    Const MAX_FALLING_SPEED := 5.0

    Field dx#, dy#
    Field state%
    Field direction% 
    Field jumpFrame% = 0

    Field life%
    Field decLife#
    Field timeRunning?

    Field frame#
    Field jumpVelo# = 1.0

    Field sprite:Sprite[][]

    Field inTheAir%

    Field boundingBox := New Rect()
    Field intermediateBox := New Rect()
    Field canJump?

    Field instaDeath?

    Method New()
        boundingBox.w = 9
        boundingBox.h = 15
    End
End

Class Resources
    Global sprites:Spritesheet
    Global font:BitmapFont
    Global soundsLoaded?     

    Function Init:Void()
        If (Not sprites) Then sprites = TexturePacker.LoadXml("gfx/sprites.xml", Image.Mipmap)
        If (Not font) Then font = BitmapFont.LoadFonts("fonts/fonts.xml", Image.Mipmap).Get("Press_Start 2P-Regular-8")
        If (Not soundsLoaded)
            soundsLoaded = True
            SoundManager.Load("sfx/1")
            SoundManager.Load("sfx/2")
            SoundManager.Load("sfx/3")
            SoundManager.Load("sfx/collect")
            SoundManager.Load("sfx/enemy_hit")
            SoundManager.Load("sfx/explosion")
            SoundManager.Load("sfx/jump")
            SoundManager.Load("sfx/laser")
            SoundManager.Load("sfx/stomp")

            SoundManager.SetDelay("sfx/collect", 50)
            SoundManager.SetDelay("sfx/enemy_hit", 50)
            SoundManager.SetDelay("sfx/explosion", 100)
            SoundManager.SetDelay("sfx/jump", 100)
            SoundManager.SetDelay("sfx/laser", 50)
            SoundManager.SetDelay("sfx/stomp", 50)
        End
    End

    Function DrawText:Void(text$, x#, y#, alignX# = 0.5, alignY# = 0.5)
        font.DrawString(text, x, y, alignX, alignY)
    End
End

Class PlayerBullet
    Const LIFE_COSTS := 60 * 5

    Const ANIM_SPEED := 0.2

    Const LEFT := 0
    Const RIGHT := 1

    Const MAX_SLOTS := 8

    Const ACCELERATION := 0.4
    Const MAX_SPEED := 6.0

    Field boundingBox := New Rect()
    Field frame#

    Field speed#
    Field direction%

    Field active?

    Global slot:PlayerBullet[MAX_SLOTS]
    Global sprites:Sprite[]

    Function Init(s:Sprite[])
        sprites = s
        For Local i := 0 Until MAX_SLOTS
            slot[i] = New PlayerBullet()
            slot[i].active = False
        Next
    End

    Function Launch(x#, y#, direction%, startSpeed# = 0.0, player:Player)
        Local freeSlot:PlayerBullet
        For Local i := 0 Until MAX_SLOTS
            If (Not slot[i].active)
                freeSlot = slot[i]
                Exit
            End
        Next

        If (freeSlot)
            freeSlot.active = True
            freeSlot.frame = 0
            freeSlot.speed = startSpeed
            freeSlot.direction = direction
            freeSlot.boundingBox.w = 26
            freeSlot.boundingBox.h = 6

            freeSlot.boundingBox.x = x - freeSlot.boundingBox.w / 2.0
            freeSlot.boundingBox.y = y - freeSlot.boundingBox.h / 2.0

            player.decLife += LIFE_COSTS
        End
    End

    Function UpdateAndRender:Void(level:Level)
        For Local i := 0 Until MAX_SLOTS
            If (slot[i].active)
                slot[i].speed = Clamp(slot[i].speed + ACCELERATION, -MAX_SPEED, MAX_SPEED)
                Local rotation := 0.0
                Local scaleX := 1.0
                Select (slot[i].direction)
                    Case RIGHT
                        slot[i].boundingBox.x += slot[i].speed
                        rotation = 0.0
                        scaleX = 1.0
                    Case LEFT
                        slot[i].boundingBox.x -= slot[i].speed
                        rotation = 0.0
                        scaleX = -1.0
                End
                slot[i].speed = Clamp(slot[i].speed, -MAX_SPEED, MAX_SPEED)

                If (slot[i].frame < sprites.Length())
                    Local px := slot[i].boundingBox.x + slot[i].boundingBox.w / 2.0
                    Local py := slot[i].boundingBox.y + slot[i].boundingBox.h / 2.0

                    DrawSprite(canvas, sprites[slot[i].frame], px, py, rotation, scaleX)
                Else If (slot[i].frame > sprites.Length())
                    slot[i].active = False
                    Local w := slot[i].boundingBox.w / 2.0
                    Local h := slot[i].boundingBox.h / 2.0
                    Explosion.Launch(slot[i].boundingBox.x + w, slot[i].boundingBox.y + h, 0)
                End
                slot[i].frame += ANIM_SPEED

                Local mask := level.GetCollisionMask(slot[i].boundingBox)
                If (mask & MapFlags.BLOCK)
                    slot[i].active = False
                    Local w := slot[i].boundingBox.w / 2.0
                    Local h := slot[i].boundingBox.h / 2.0
                    Select (slot[i].direction)
                        Case RIGHT
                            w *= 2
                        Case LEFT
                            w = 0
                    End
                    Explosion.Launch(slot[i].boundingBox.x + w, slot[i].boundingBox.y + h, 0)
                End
            End
        Next        
    End

    Method Kill:Void(explosionCount% = 1, radius% = 8)
        active = False
        Local w := boundingBox.w / 2.0
        Local h := boundingBox.h / 2.0
        Select (direction)
            Case RIGHT
                w *= 2
            Case LEFT
                w = 0
        End
        Local t := -10
        For Local i := 0 Until explosionCount
            Explosion.Launch(boundingBox.x + w + Rnd(-radius, radius), boundingBox.y + h + Rnd(-radius, radius), t)
            t += Rnd(15)
        Next
    End
End

Class Enemy
    Const TYPE_CRAWLER := 0

    Global enemies:Enemy[]

    Global sprites:Sprite[][]

    Field boundingBox := New Rect()
    Field type%
    Field active?
    Field frame#
    Field animSpeed#
    Field lifeBonus:ExtraTime

    Field vx#, vy#
    Field speedX#, speedY#
    Field acc#
    Field health#
    Field hitCounter%
    Field hitImpactX#
    Field offsetY#

    Const MAX_FALLING_SPEED := 6.0
    Const GRAVITY := 0.15

    Function Init()
        sprites = sprites.Resize(1)
        sprites[TYPE_CRAWLER] = GetSpriteAnimation(Resources.sprites.frames, "crawler_{n1}.png")
    End

    Function Clear()
        enemies = enemies.Resize(0)
    End

    Function Add(type%, x#, y#)
        enemies = enemies.Resize(enemies.Length() + 1)
        enemies[enemies.Length() - 1] = New Enemy()
        Local e := enemies[enemies.Length() - 1] 
        e.boundingBox.w = sprites[type][0].Width()
        e.boundingBox.h = sprites[type][0].Height()


        e.type = type
        e.active = True
        e.hitCounter = 0

        Select (type)
            Case TYPE_CRAWLER
                e.boundingBox.h = 16
                e.offsetY = -2
                e.animSpeed = 0.05
                e.speedX = 0.5
                e.speedY = 0.0
                e.vx = e.speedX
                e.vy = e.speedY
                e.acc = 0.1
                e.health = 3.0
                e.lifeBonus = ExtraTime.Add(0, 0)
                e.lifeBonus.lifeBonus = 60 * 25
                e.lifeBonus.active = False
                e.lifeBonus.sprite = ExtraTime.sprites
        End

        e.boundingBox.x = x - e.boundingBox.w / 2.0
        e.boundingBox.y = y - e.boundingBox.h
    End

    Function UpdateAndRender(level:Level, player:Player, playerBullets:PlayerBullet[], gameScene:GameScene)
        For Local i := 0 Until enemies.Length()
            Local e := enemies[i]
            If (e.active = False) Then Continue
            e.frame += e.animSpeed

            If (Rect.Intersect(player.boundingBox, e.boundingBox) And player.state <> Player.STATE_DIED)
                player.instaDeath = True
            End

            For Local bullet := EachIn playerBullets
                If (Not bullet.active) Then Continue
                If (Rect.Intersect(bullet.boundingBox, e.boundingBox))
                    e.hitCounter = 8
                    If (bullet.direction = PlayerBullet.RIGHT)
                        e.vx = bullet.speed
                    Else
                        e.vx = -bullet.speed
                    End
                    e.vy -= bullet.speed * 0.25

                    e.health -= 1

                    If (e.health <= 0)
                        gameScene.shakeTimer = 24
                        SoundManager.PlaySfx("sfx/explosion", Rnd(0.8, 1.0))
                        bullet.Kill(3, 8)
                        e.active = False
                        If (e.lifeBonus)
                            e.lifeBonus.Set(e.boundingBox.x + e.boundingBox.w / 2.0, e.boundingBox.y + e.boundingBox.h - 16)
                            e.lifeBonus.active = True
                            e.lifeBonus.dy = -(Rnd(1.0, 5.0))
                        End
    
                        For Local i := 0 Until 16
                            Local pvx := Rnd(1.5, 4.5)
                            Local pvy := -Rnd(1.0, 4.0)
                            If (i Mod 2 = 0) Then pvx *= -1
                            If (i Mod 3 = 0) Then pvy *= -1

                            Particle.Launch(e.boundingBox.x + e.boundingBox.w / 2.0 + Rnd(-4, 4), e.boundingBox.y + e.boundingBox.h / 2.0, pvx, pvy)
                        Next
                    Else
                        gameScene.shakeTimer = 3
                        SoundManager.PlaySfx("sfx/enemy_hit", Rnd(0.8, 1.0))
                        bullet.Kill(1, 0)                        
                    End
                End
            Next

            e.Update(level)

            If (e.hitCounter > 0)
                e.hitCounter -= 1
                Shaders.SolidWhite.DrawSprite(canvas, sprites[e.type][e.frame Mod sprites[e.type].Length()], e.boundingBox.x + e.boundingBox.w / 2.0, e.boundingBox.y + e.boundingBox.h / 2.0 + e.offsetY)
            Else
                DrawSprite(sprites[e.type][e.frame Mod sprites[e.type].Length()], e.boundingBox.x + e.boundingBox.w / 2.0, e.boundingBox.y + e.boundingBox.h / 2.0 + e.offsetY)
            End
'           DrawBox(canvas, e.boundingBox)
        Next
    End

    Method Update(level:Level)
        Local mask%

        Select (type)
            Case TYPE_CRAWLER
                If (vx > 0 And vx < speedX)
                    vx += acc
                Else If (vx < 0 And vx > -speedX)
                    vx -= acc
                End                

                If (vx > speedX)
                    vx *= 0.95
                    If (vx < speedX) Then vx = speedX
                Else If (vx < -speedX)
                    vx *= 0.95
                    If (vx > -speedX) Then vx = -speedX
                End

                If (vx <> 0.0)
                    Local startX := boundingBox.x
                    Local endX := boundingBox.x + vx
                    Local moveDirection := 1
                    If (endX < startX) Then moveDirection = -1
                    While(1)
                        If (moveDirection = 1)
                            startX += 1
                            If (startX > endX) Then startX = endX

                            ' Check for wall
                            mask = level.GetCollisionMask(startX, boundingBox.y, boundingBox.w, boundingBox.h)
                            If (mask & MapFlags.BLOCK)
                                vx = Clamp(vx, -speedX, speedX)
                                vx *= -1
                                Exit
                            End

                            If (vx <= speedX)
                                mask = level.GetCollisionMask(startX + boundingBox.w, boundingBox.y + boundingBox.h, 1, 8)
                                If (mask & MapFlags.BLOCK = 0)
                                    vx *= -1
                                    Exit
                                End
                            End

                            boundingBox.x = startX

                            If (startX = endX) Then Exit
                        Else If (moveDirection = -1)
                            startX -= 1
                            If (startX < endX) Then startX = endX

                            mask = level.GetCollisionMask(startX, boundingBox.y, boundingBox.w, boundingBox.h)
                            If (mask & MapFlags.BLOCK)
                                vx = Clamp(vx, -speedX, speedX)
                                vx *= -1
                                Exit
                            End

                            If (vx >= -speedX)
                                mask = level.GetCollisionMask(startX, boundingBox.y + boundingBox.h, 1, 8)
                                If (mask & MapFlags.BLOCK = 0)
                                    vx *= -1
                                    Exit
                                End
                            End

                            boundingBox.x = startX

                            If (startX = endX) Then Exit
                        End                            
                    Wend                                    
                End

                vy += GRAVITY
                vy = Min(vy, MAX_FALLING_SPEED)
                If (vy <> 0)
                    Local startY := boundingBox.y
                    Local endY := boundingBox.y + vy
                    Local moveDirection := 1
                    If (endY < startY) Then moveDirection = -1
                    While (1)
                        If (moveDirection = 1)
                            startY += 1
                            If (startY > endY) Then startY = endY
                            mask = level.GetCollisionMask(boundingBox.x, startY, boundingBox.w, boundingBox.h)
                            If (mask & MapFlags.BLOCK)
                                vy = 0
                                Exit
                            End

                            boundingBox.y = startY

                            If (startY = endY) Then Exit
                        Else If (moveDirection = -1)
                            startY -= 1
                            If (startY < endY) Then startY = endY
                            mask = level.GetCollisionMask(boundingBox.x, startY, boundingBox.w, boundingBox.h)
                            If (mask & MapFlags.BLOCK)
                                vy = 0
                                Exit
                            End

                            boundingBox.y = startY

                            If (startY = endY) Then Exit
                        End
                    Wend
                End
        End
    End
End

Class Shaders
    Global SolidRed:SolidColorShader
    Global SolidWhite:SolidColorShader

    Function Init:Void()
        SolidRed = New SolidColorShader()
        SolidRed.SetColor(0.368, 0.055, 0.086)

        SolidWhite= New SolidColorShader()
        SolidWhite.SetColor(1.0, 1.0, 1.0)
    End    
End

Class ExtraTime
    Global sprites:Sprite[]
    Global spritesSmall:Sprite[]
    Global slot:ExtraTime[]
    
    Const SPEED := 0.25
    Field frame#
    Field counter%
    Field active?
    Field boundingBox := New Rect()
    Field dy#
    Field fallSpeed#
    Field lifeBonus#
    Field sprite:Sprite[]

    Function Init()
        sprites = GetSpriteAnimation(Resources.sprites.frames, "extra_time_{n1}.png")
        spritesSmall = GetSpriteAnimation(Resources.sprites.frames, "extra_time_small_{n1}.png")
        slot = slot.Resize(0)
    End

    Function Add:ExtraTime(x#, y#)
        slot = slot.Resize(slot.Length() + 1)
        slot[slot.Length() - 1] = new ExtraTime()
        Local nextSlot := slot[slot.Length() - 1]
        nextSlot.boundingBox.w = sprites[0].Width()
        nextSlot.boundingBox.h = sprites[0].Height()
        nextSlot.Set(x, y)
        nextSlot.active = True
        nextSlot.fallSpeed = Rnd(0.1, 0.3)
        nextSlot.lifeBonus = 60 * 5
        nextSlot.sprite = spritesSmall
        Return nextSlot
    End

    Method Set(x#, y#)
        boundingBox.x = x - boundingBox.w / 2.0
        boundingBox.y = y + 16 - boundingBox.h
    End

    Function UpdateAndRender(level:Level, player:Player)
        For Local i := 0 Until slot.Length()
            Local s := slot[i]
            If (s.active)
                If (Rect.Intersect(player.boundingBox, s.boundingBox))
                    s.active = False
                    player.decLife -= s.lifeBonus
                    SoundManager.PlaySfx("sfx/collect")
                End
                s.counter += 1
                s.frame += SPEED
                s.dy += s.fallSpeed
                Local startY := s.boundingBox.y
                Local endY := startY + s.dy
                If (endY < startY)
                    While (1)
                        startY -= 1
                        If (startY <= endY) Then startY = endY
                        Local mask := level.GetCollisionMask(s.boundingBox.x, startY, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.dy = -s.dy * 0.6
                            Exit
                        End

                        s.boundingBox.y = startY

                        If (startY = endY) Then Exit
                    End
                Else
                    While (1)
                        startY += 1
                        If (startY >= endY) Then startY = endY
                        Local mask := level.GetCollisionMask(s.boundingBox.x, startY, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.dy = -s.dy * 0.6
                            Exit
                        End

                        s.boundingBox.y = startY

                        If (startY = endY) Then Exit
                    End
                End
                DrawSprite(s.sprite[s.frame Mod s.sprite.Length], s.boundingBox.x + s.boundingBox.w / 2.0, s.boundingBox.y + s.boundingBox.h / 2.0)
            End
        Next
    End

End

Class Particle
    Const MAX_SLOTS := 128
    Const GRAVITY := 0.1
    Const MAX_FALLING_SPEED := 8.0

    Global sprite:Sprite[]
    Global slot:Particle[MAX_SLOTS]

    Field active?

    Field vx#, vy#, rotation#
    Field frame#
    Field alpha#

    Field boundingBox := New Rect()

    Function Init(s:Sprite[])
        sprite = s
        For Local i := 0 Until slot.Length()
            slot[i] = New Particle()
            slot[i].boundingBox.w = sprite[0].Width()
            slot[i].boundingBox.h = sprite[0].Height()
        Next
    End

    Function Launch(x#, y#, vx#, vy#)
        Local freeSlot:Particle
        For Local i := 0 Until MAX_SLOTS
            If (Not slot[i].active)
                freeSlot = slot[i]
                Exit
            End
        Next

        If (freeSlot)
            freeSlot.active = True
            freeSlot.rotation = Rnd(-360, 360)
            freeSlot.vx = vx
            freeSlot.vy = vy
            freeSlot.frame = (Rnd(0, sprite.Length()))
            freeSlot.boundingBox.x = x - freeSlot.boundingBox.w / 2.0
            freeSlot.boundingBox.y = y - freeSlot.boundingBox.h / 2.0
            freeSlot.alpha = 10.0
        End
    End

    Function UpdateAndRender(level:Level)
        For Local s := EachIn slot
            If (Not s.active) Then Continue

            s.alpha -= 0.05
            If (s.alpha <= 0.0)
                s.active = False
                Continue
            End

            s.vx *= 0.97
            If (s.vx <> 0)
                Local startX := s.boundingBox.x
                Local endX := s.boundingBox.x + s.vx
                Local moveDirection := 1
                If (endX < startX) Then moveDirection = -1
                While (1)
                    If (moveDirection = 1)
                        startX += 1
                        If (startX > endX) THen startX = endX
                        Local mask := level.GetCollisionMask(startX, s.boundingBox.y, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.vx *= -0.6
                            Exit
                        End
                        s.boundingBox.x = startX

                        If (startX = endX) Then Exit
                    Else If (moveDirection = -1)
                        startX -= 1
                        If (startX < endX) THen startX = endX
                        Local mask := level.GetCollisionMask(startX, s.boundingBox.y, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.vx *= -0.6
                            Exit
                        End
                        s.boundingBox.x = startX

                        If (startX = endX) Then Exit
                    End
                Wend
            End

            s.vy += GRAVITY
            s.vy = Min(s.vy, MAX_FALLING_SPEED)
            If (s.vy <> 0)
                Local startY := s.boundingBox.y
                Local endY := s.boundingBox.y + s.vy
                Local moveDirection := 1
                If (endY < startY) Then moveDirection = -1
                While (1)
                    If (moveDirection = 1)
                        startY += 1
                        If (startY > endY) THen startY = endY
                        Local mask := level.GetCollisionMask(s.boundingBox.x, startY, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.vy *= -0.6
                            Exit
                        End
                        s.boundingBox.y = startY

                        If (startY = endY) Then Exit
                    Else If (moveDirection = -1)
                        startY -= 1
                        If (startY < endY) THen startY = endY
                        Local mask := level.GetCollisionMask(s.boundingBox.x, startY, s.boundingBox.w, s.boundingBox.h)
                        If (mask & MapFlags.BLOCK)
                            s.vy *= -0.6
                            Exit
                        End
                        s.boundingBox.y = startY

                        If (startY = endY) Then Exit
                    End
                Wend
            End

            canvas.SetAlpha(Clamp(s.alpha, 0.0, 1.0))
            DrawSprite(sprite[Int(s.frame)], s.boundingBox.x + s.boundingBox.w / 2.0, s.boundingBox.y + s.boundingBox.h / 2.0)
        Next
        canvas.SetAlpha(1.0)
    End

End

Class Explosion
    Const MAX_SLOTS := 16
    Const SPEED := 0.4

    Field x#, y#
    Field preDelay%
    Field active?
    Field frame#

    Global slot:Explosion[MAX_SLOTS]
    Global sprites:Sprite[]

    Function Init(s:Sprite[])
        sprites = s
        For Local i := 0 Until MAX_SLOTS
            slot[i] = New Explosion()
            slot[i].active = False
        Next
    End

    Function AllDone?()
        For Local i := 0 Until MAX_SLOTS
            If (slot[i].active) Then Return False
        Next

        Return True
    End

    Function Launch(x#, y#, preDelay# = 0.0)
        Local freeSlot:Explosion
        For Local i := 0 Until MAX_SLOTS
            If (Not slot[i].active)
                freeSlot = slot[i]
                Exit
            End
        Next

        If (freeSlot)
            freeSlot.active = True
            freeSlot.x = x
            freeSlot.y = y
            freeSlot.preDelay = preDelay
            freeSlot.frame = 0
        End
    End

    Function UpdateAndRender:Void()
        For Local i := 0 Until MAX_SLOTS
            If (slot[i].active)
                slot[i].preDelay -= 1
                If (slot[i].preDelay < 0)
                    If (slot[i].frame < sprites.Length())
                        DrawSprite(canvas, sprites[slot[i].frame], slot[i].x, slot[i].y)
                    Else If (slot[i].frame > sprites.Length())
                        slot[i].active = False
                    End
                    slot[i].frame += SPEED
                End
            End
        Next
    End
End

Class GameScene Implements Scene
    Const LEVEL_COUNT := 3
    Field level:Level
    Field player:Player
    Field fader#
    Field gameOverTimer%
    Field shakeTimer%
    Field readyTimer%

    Method Initialize:Void()
        HideMouse()
        Resources.Init()
        Shaders.Init()
        Explosion.Init(GetSpriteAnimation(Resources.sprites.frames, "explosion_{n1}.png"))
        PlayerBullet.Init(GetSpriteAnimation(Resources.sprites.frames, "player_bullet_{n1}.png"))
        Enemy.Init()
        Particle.Init(GetSpriteAnimation(Resources.sprites.frames, "particles_{n1}.png"))

        ' Initalize Player Sprites
        player = New Player()
        player.sprite = player.sprite.Resize(Player.ANIM_COUNT)
        player.sprite[Player.ANIM_IDLE] = GetSpriteAnimation(Resources.sprites.frames, "player_idle_{n1}.png")
        player.sprite[Player.ANIM_RUN] = GetSpriteAnimation(Resources.sprites.frames, "player_run_{n1}.png")
        player.sprite[Player.ANIM_JUMP] = GetSpriteAnimation(Resources.sprites.frames, "player_jump_{n1}.png")
        player.sprite[Player.ANIM_FALL] = GetSpriteAnimation(Resources.sprites.frames, "player_fall_{n1}.png")
        For Local i := 0 Until Player.ANIM_COUNT
            Local sprite := player.sprite[i]
            For Local j := 0 Until sprite.Length()
                 sprite[j].handleY -= player.boundingBox.h / 2.0 + 4.0
            Next
        Next

        level = New Level()
        ' Start Level
        InitLevel(0)

        #if TARGET="glfw"
            SoundManager.globalSfxVolume = 0.80
        #else
            SoundManager.globalSfxVolume = 0.20
        #end
    End   

    Method InitLevel(lvl%)
        level.currentLevel = lvl
        readyTimer = 60 * 3 + 1
        ExtraTime.Init()
        Enemy.Clear()
        gameOverTimer = 0
        fader = 1.0
        level.map = New TiledMap("maps/" + lvl + ".json")
        level.background = New TiledMap("maps/background.json")

        level.flags = level.flags.Resize(0)
        level.flags = level.flags.Resize(level.map.width * level.map.height)

        For Local i := 0 Until level.map.layers.Length()
            Local layer := level.map.layers[i]
            For Local mx := 0 Until level.map.width
                For Local my := 0 Until level.map.height
                    Local idx := layer.GetContinuousIndex(mx, my)
                    Local tileId := layer.data[idx]
                    If (tileId = 0) Then Continue
                    Local tileset := level.map.GetTilesetForTileId(tileId)
                    If (tileset.GetProperty(tileId, "block") = "1")
                        level.flags[mx + level.map.width * my] |= MapFlags.BLOCK                        
                    End
                    If (tileset.GetProperty(tileId, "start") = "1")
                        layer.data[idx] = 0
                        player.boundingBox.x = mx * 16 + 8
                        player.boundingBox.y = my * 16
                    End
                    If (tileset.GetProperty(tileId, "extra_time") = "1")
                        layer.data[idx] = 0
                        ExtraTime.Add(mx * 16 + 8, my * 16)
                    End
                    If (tileset.GetProperty(tileId, "crawler") = "1")
                        layer.data[idx] = 0
                        Enemy.Add(Enemy.TYPE_CRAWLER, mx * 16 + 8, my * 16 + 16) ' Why 15 and not 16??
                    End
                    If (tileset.GetProperty(tileId, "exit") = "1")
                        level.flags[mx + level.map.width * my] |= MapFlags.LEVEL_EXIT
                    End
                Next
            Next
        Next

        player.direction = 1.0
        player.inTheAir = 0
        player.instaDeath = False
        player.jumpFrame = 0
        player.life = Int(level.map.properties.Get("life")) * 60
        player.decLife = 0
        player.timeRunning = False
        player.state = Player.STATE_IDLE
        player.dx = 0
        player.dy = 0

        player.jumpVelo = 1.0
    End

    Method Execute:Void()
        canvas.PushMatrix()
        canvas.Clear(0.0, 0.0, 0.0, 1.0)
        Local ox := 0.0, oy := 0.0
        If (shakeTimer > 0)
            shakeTimer -= 1
            ox = Int(Rnd(-4, 4))
            oy = Int(Rnd(-4, 4))
        End
        canvas.Translate(0 + ox, 20 + oy)

        level.dx = -level.map.ClampToMapBoundaryX(player.boundingBox.x + player.boundingBox.w / 2 - 160, 304)
        level.dy = -level.map.ClampToMapBoundaryY(player.boundingBox.y + player.boundingBox.h / 2 - 96, 144)
        level.x = level.dx
        level.y = level.dy

        For Local i := 0 Until level.background.layers.Length()
            canvas.PushMatrix()
            Local tx := Int(level.x * (i + 1) * 0.1)
            Local ty := Int(level.y * (i + 1) * 0.1)
            canvas.Translate(tx Mod 16, ty Mod 16)
            level.background.layers[i].Render(canvas, -Int (tx / 16), -Int(ty / 16), 21, 10)
            canvas.PopMatrix()
        Next


        canvas.PushMatrix()
        canvas.Translate(level.x Mod 16, level.y Mod 16)
        Local mapX := -Int (level.x / 16)
        Local mapY := -Int(level.y / 16)
        For Local i := 0 Until level.map.layers.Length()           
            level.map.layers[i].Render(canvas, mapX, mapY, 20, 10)
        Next



        #if FALSE
            canvas.SetColor(1.0,0.0,0.0,1.0)

            For Local tx := mapX Until Min(mapX + 21, level.map.width)
                For Local ty := mapY Until Min(mapY + 11, level.map.height)
                    If (level.flags[tx + ty * level.map.width] & MapFlags.BLOCK)
                        DrawBox(canvas, (tx-mapX) * 16, (ty-mapY) * 16, 16, 16)
                    End
                Next
            Next
            canvas.SetColor(1.0,1.0,1.0,1.0)
        #endif

        canvas.PopMatrix()

        canvas.PushMatrix()
        canvas.Translate(level.x, level.y)        

        Local oldPlayerState := player.state
        If (player.state <> Player.STATE_DIED And player.state <> Player.STATE_LEVEL_COMPLETED And player.timeRunning)
            ' Update Player

            ' Jump / Allow Jumping 4 frames after platform left
            If (Not KeyDown(KEY_UP)) Then player.jumpFrame = 0 ; player.jumpVelo = 1.2 ; player.canJump = False


            If (player.inTheAir <= 4 And KeyDown(KEY_UP) And player.jumpVelo > 0.1 And player.canJump)
                If (KeyHit(KEY_UP)) Then SoundManager.PlaySfx("sfx/jump", Rnd(0.8, 1.0))

                player.jumpVelo = Max(0.0, player.jumpVelo * 0.78)
                player.dy -= player.jumpVelo
                player.jumpFrame += 1
            Else
                ' Falling/Jumping
                player.dy = player.dy + Player.GRAVITY
                If (player.dy > Player.MAX_FALLING_SPEED) Then player.dy = Player.MAX_FALLING_SPEED

                player.inTheAir += 1
            End


            Local oldPosY := player.boundingBox.y
            If (player.dy <> 0)
                Local startY := player.boundingBox.y
                Local endY := player.boundingBox.y + player.dy
                Local moveDirection := 1
                If (endY < startY) Then moveDirection = -1
                While(1)
                    If (moveDirection = 1)
                        startY += 1
                        If (startY > endY) Then startY = endY
                        player.intermediateBox.Set(player.boundingBox.x, startY, player.boundingBox.w, player.boundingBox.h)
                        Local mask := level.GetCollisionMask(player.intermediateBox)
                        If (mask & MapFlags.BLOCK)
                            player.inTheAir = 0
                            player.state = Player.STATE_IDLE
                            player.dy = 0
                            player.canJump = True
                            If (oldPosY <> player.boundingBox.y) Then SoundManager.PlaySfx("sfx/stomp", Rnd(0.3, 0.5))
                            Exit
                        End

                        player.state = Player.STATE_FALLING

                        player.boundingBox.y = startY

                        If (startY = endY) 
                            Exit
                        End
                    Else If (moveDirection = -1)
                        startY -= 1
                        If (startY < endY) Then startY = endY
                        player.intermediateBox.Set(player.boundingBox.x, startY, player.boundingBox.w, player.boundingBox.h)
                        Local mask := level.GetCollisionMask(player.intermediateBox)
                        If (mask & MapFlags.BLOCK)
                            player.state = Player.STATE_FALLING
                            player.dy = 0
                            Exit
                        End        
                        player.state = Player.STATE_JUMP
                        player.boundingBox.y = startY                
                        If (startY = endY) Then Exit
                    End
                Wend
            End

            player.boundingBox.y = Floor(player.boundingBox.y + 0.5)

            ' LEFT/RIGHT
            ' Run Treshold
            If (Not KeyDown(KEY_LEFT) And Not KeyDown(KEY_RIGHT))
                player.dx *= Player.RUN_SLOWDOWN
                If (Abs(player.dx) < Player.RUN_TRESHOLD) Then player.dx = 0.0
            End


            If (KeyDown(KEY_LEFT))
                player.direction = -1.0
                player.dx -= Player.MOVE_ACCELERATION
                If (player.state <> Player.STATE_FALLING And player.state <> Player.STATE_JUMP) Then player.state = Player.STATE_RUNNING
            Else If (KeyDown(KEY_RIGHT))
                player.direction = 1.0
                player.dx += Player.MOVE_ACCELERATION
                If (player.state <> Player.STATE_FALLING And player.state <> Player.STATE_JUMP) Then player.state = Player.STATE_RUNNING
            Else If (player.dx <> 0.0 And player.state <> Player.STATE_FALLING And player.state <> Player.STATE_JUMP) 
                player.state = Player.STATE_RUNNING
            End

            player.dx = Clamp(player.dx, -Player.MAX_SPEED_X, Player.MAX_SPEED_X)

            If (player.dx <> 0.0)
                Local startX := player.boundingBox.x
                Local endX := player.boundingBox.x + player.dx
                Local moveDirection := 1
                If (endX < startX) Then moveDirection = -1
                While (1)
                    If (moveDirection = 1)
                        startX += 1
                        If (startX > endX) Then startX = endX
                        player.intermediateBox.Set(startX, player.boundingBox.y, player.boundingBox.w, player.boundingBox.h)
                        Local mask := level.GetCollisionMask(player.intermediateBox)
                        If (mask & MapFlags.BLOCK)
                            player.dx = 0
                            Exit
                        End
                        player.boundingBox.x = startX
                        If (startX = endX) Then Exit
                    Else If (moveDirection = -1)
                        startX -= 1
                        If (startX < endX) Then startX = endX
                        player.intermediateBox.Set(startX, player.boundingBox.y, player.boundingBox.w, player.boundingBox.h)
                        Local mask := level.GetCollisionMask(player.intermediateBox)
                        If (mask & MapFlags.BLOCK)
                            player.dx = 0
                            Exit
                        End
                        player.boundingBox.x = startX                        
                        If (startX = endX) Then Exit
                    End
                Wend                    
            End

            Local mask := level.GetCollisionMask(player.boundingBox)
            If (mask & MapFlags.LEVEL_EXIT)
                player.state = Player.STATE_LEVEL_COMPLETED
            End

        End

        ExtraTime.UpdateAndRender(level, player)
        Enemy.UpdateAndRender(level, player, PlayerBullet.slot, Self)
        Particle.UpdateAndRender(level)

        Local px := player.boundingBox.x + player.boundingBox.w / 2.0
        Local py := player.boundingBox.y + player.boundingBox.h

        Select player.state            
            Case Player.STATE_FALLING
                If (oldPlayerState <> Player.STATE_FALLING) Then player.frame = 0
                player.frame = Min(player.frame + Player.ANIM_SPEED_FALL, Float(player.sprite[Player.ANIM_FALL].Length-1))

                DrawSprite(canvas, player.sprite[Player.ANIM_FALL][player.frame], px, py, 0.0, player.direction)

            Case Player.STATE_RUNNING
                player.frame += Player.ANIM_SPEED_RUN
                DrawSprite(canvas, player.sprite[Player.ANIM_RUN][player.frame Mod player.sprite[Player.ANIM_RUN].Length], px, py, 0.0, player.direction)

            Case Player.STATE_JUMP
                player.frame += Player.ANIM_SPEED_JUMP
                DrawSprite(canvas, player.sprite[Player.ANIM_JUMP][player.frame Mod player.sprite[Player.ANIM_JUMP].Length], px, py, 0.0, player.direction)

            Case Player.STATE_IDLE
                player.frame += Player.ANIM_SPEED_IDLE
                DrawSprite(canvas, player.sprite[Player.ANIM_IDLE][player.frame Mod player.sprite[Player.ANIM_IDLE].Length], px, py, 0.0, player.direction)
        End

        If (player.state <> Player.STATE_DIED And player.state <> Player.STATE_LEVEL_COMPLETED And player.timeRunning) And (KeyHit(KEY_X))
            Local dir%
            Local startSpeed#
            Local px := player.boundingBox.x + player.boundingBox.w / 2.0
            Local py := player.boundingBox.y + player.boundingBox.h / 2.0

            If (player.direction = 1.0)
                startSpeed = Abs(player.dx)
                dir = PlayerBullet.RIGHT
                px += player.boundingBox.w / 2.0
            Else If (player.direction = -1.0)
                startSpeed = Abs(player.dx)
                dir = PlayerBullet.LEFT
                px -= player.boundingBox.w / 2.0
            End


            PlayerBullet.Launch(px, py, dir, startSpeed, player)
            SoundManager.PlaySfx("sfx/laser", Rnd(0.6, 0.8))
        End

        PlayerBullet.UpdateAndRender(level)
        Explosion.UpdateAndRender()

        ' canvas.SetColor(1.0,0.0,0.0)
        ' DrawBox(canvas, player.boundingBox)
        ' canvas.SetColor(1.0,1.0,1.0)

        canvas.PopMatrix()

        canvas.PopMatrix()


        ' Draw HUD at Bottom
        canvas.SetColor(0,0,0,1)
        canvas.DrawRect(0,0,AppConfig.virtualWidth, 20)
        Local a := Clamp(1.0 - Float(player.life) / 50000.0, 0.2, 0.9)
        canvas.SetColor(255.0 / 255.0, 51.0 / 255.0, 0.0, a)
        canvas.DrawRect(0,0,AppConfig.virtualWidth, 20)
        canvas.SetColor(1,1,1,1)


        canvas.SetColor(255.0 / 255.0 * 0.10, 51.0 / 255.0 * 0.15, 0.0, 1.0)
        canvas.DrawRect(0,19, AppConfig.virtualWidth, 1)
        canvas.SetColor(1,1,1,1)

        Local lifeFmt := ""
        Local seconds% = Floor(player.life / 60.0)
        Local minutes% = Floor(seconds / 60.0) ; seconds -= minutes * 60
        Local hours% = Floor(minutes / 60.0) ; minutes -= hours * 60

        If (hours < 10) Then lifeFmt += "0"
        lifeFmt += hours + ":"

        If (minutes < 10) Then lifeFmt += "0"
        lifeFmt += minutes + ":"

        If (seconds < 10) Then lifeFmt += "0"
        lifeFmt += seconds + " " + String.FromChar(253) 

        Resources.DrawText(lifeFmt, 310, 10, 1.0, 0.5)

        Resources.DrawText("Level: " + (level.currentLevel+1), 10, 10, 0.0, 0.5)
        
        If (player.instaDeath And player.state <> Player.STATE_DIED) Or (player.life <= 0 And player.state <> Player.STATE_DIED)
            KillPlayer()
        End

        canvas.SetColor(0.0, 0.0, 0.0, fader)
        canvas.DrawRect(0,0,AppConfig.virtualWidth, AppConfig.virtualHeight)
        canvas.SetColor(1,1,1,1)

        If (player.timeRunning)
            player.life -= 1
            If (player.decLife > 0)
                Local sub := Max(60.0, Floor(player.decLife * 0.1))
                player.life -= sub
                player.decLife -= sub
            Else If (player.decLife < 0)
                Local add := Min(60.0, Floor(Abs(player.decLife) * 0.1))
                player.life += add
                player.decLife += add
            End
            If (player.life < 0) Then player.life = 0
        Else
            SoundManager.LoadAndPlayMusic("sfx/timezone")
            If (readyTimer = 60 * 3) Then SoundManager.PlaySfx("sfx/3", 3.0)
            If (readyTimer = 60 * 2) Then SoundManager.PlaySfx("sfx/2", 3.0)
            If (readyTimer = 60 * 1) Then SoundManager.PlaySfx("sfx/1", 3.0)

            readyTimer -= 1
            If (readyTimer <= 0)
                player.timeRunning = True
                player.decLife = 0
            End
            fader = Clamp(fader + 0.1, 0.0, 1.0)

            Resources.DrawText("GET READY", 160, 90)  
            Local s := Int(readyTimer / 60) + 1

            If (s <= 3)
                Resources.DrawText(s, 160, 110)
            End
        End


        If (player.state = Player.STATE_DIED And Explosion.AllDone())
            fader = Clamp(fader + 0.1, 0.0, 1.0)
            If (gameOverTimer < 100)
                If (player.instaDeath)
                    Resources.DrawText("YOU DIED!", 160, 100)
                Else
                    Resources.DrawText("OUT OF TIME", 160, 100)
                    Resources.DrawText("YOUR LIFE HAS ENDED", 160, 110)
                End
            End
            gameOverTimer += 1
            If (gameOverTimer > 120)
                InitLevel(level.currentLevel)
            End
        Else If (player.state = Player.STATE_LEVEL_COMPLETED)
            fader = Clamp(fader + 0.1, 0.0, 1.0)
            If (level.currentLevel + 1 >= LEVEL_COUNT)
                Resources.DrawText("GAME COMPELTED", 160, 40)
                If (CoreApp.timer.framesRendered / 30 Mod 2 = 0)
                    Resources.DrawText("THANKS FOR PLAYING !!!", 160, 60)
                End
                Resources.DrawText("A GAME BY", 160, 100)
                Resources.DrawText("JOCHEN HEIZMANN / ASYLUMSQUARE.COM", 160, 110)
                Resources.DrawText("CREATED FOR LUDUM DARE #44", 160, 140)
                Resources.DrawText("ENJOY THE MUSIC!", 160, 170)
            Else
                Resources.DrawText("LEVEL COMPELTED", 160, 100)
                Resources.DrawText("PRESS FIRE (X) TO CONTINUE", 160, 120)
    
                If (KeyHit(KEY_X))
                    InitLevel(level.currentLevel + 1)
                End
            End
        Else
            fader = Clamp(fader - 0.1, 0.0, 1.0)
        End
    End

    Method KillPlayer()
        If (player.state <> Player.STATE_LEVEL_COMPLETED And player.state <> Player.STATE_DIED And player.timeRunning)
            shakeTimer = 16
            SoundManager.PlaySfx("sfx/explosion", Rnd(0.8, 1.0))
            player.state = Player.STATE_DIED
            Local t := -10
            For Local i := 0 Until 8
                Explosion.Launch(player.boundingBox.x + player.boundingBox.w / 2.0 + Rnd(-8, 8), player.boundingBox.y + player.boundingBox.h / 2.0 + Rnd(-10, 10), t)
                t += Rnd(15)
            Next            
        End
    End


    Method Terminate:Void()
    End
End

Function Main()
    app = New CoreApp()

    AppConfig.virtualWidth = 320
    AppConfig.virtualHeight = 180
    AppConfig.frameRate = 60
    AppConfig.resolutionPolicy = ResolutionPolicy.SHOW_ALL | ResolutionPolicy.ALIGN_CENTER

    SceneManager.Register("game", New GameScene())  
End