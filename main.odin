package main

import "core:os"
import "core:fmt"
import "core:math"
import "core:time"
import "core:strings"
import "core:reflect"
import "core:os/os2"
import "core:path/filepath"
import "core:thread"
import "core:unicode/utf8"
import rl "vendor:raylib"

Action :: enum {
    NONE,
    COPY,
    OPEN,
}

Button :: struct {
    action: Action,
    name:   cstring,
    buffer: string,
}

PAD    : i32 : 8
MARGIN : i32 : 4

COLS_PER_512 :: 4
ROWS_PER_512 :: 10 

big_font: rl.Font
big_atlas: rl.Image
big_font_done: bool

die_in: int = -1

problems: [dynamic] cstring

main :: proc() {
    
    monitor := rl.GetCurrentMonitor()
    rl.SetConfigFlags({ .WINDOW_RESIZABLE })
    rl.InitWindow(rl.GetMonitorWidth(monitor) / 2, rl.GetMonitorHeight(monitor) / 2, "ulti's master program") 
    rl.SetTargetFPS(60)

    DATA_PATH := filepath.dir(os.args[0])
    data_file := fmt.aprint(DATA_PATH, "\\data.txt", sep="")
    fmt.println("Data path: ", data_file)
    buttons := parse_data(data_file)
    defer      write_data(data_file, buttons)
    
    SH : rl.Color = {  20, 20,  20,  255 }
    BG : rl.Color = {  40,  40,  40, 255 }
    FG : rl.Color = { 250, 249, 233, 255 }
    TINTS : [Action] rl.Color = { 
        .NONE = { 255,   0,   0, 255 },
        .COPY = { 154, 153,  28, 255 },
        .OPEN = {  69, 133, 136, 255 },
    }

    font: rl.Font
    font.baseSize = 24
    font.glyphCount = 8000
    
    font_data := #load("font.ttf")
    font.glyphs = rl.LoadFontData(transmute(rawptr) raw_data(font_data), i32(len(font_data)), font.baseSize, nil, font.glyphCount, .DEFAULT)
    atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, font.baseSize, 4, 0)
    font.texture = rl.LoadTextureFromImage(atlas)
    rl.SetTextureFilter(font.texture, .BILINEAR)
    rl.UnloadImage(atlas)

    second := thread.create_and_start_with_poly_data(font_data, proc(data: [] byte) {
        big_font.baseSize = 64
        big_font.glyphCount = 16000
        big_font.glyphs = rl.LoadFontData(transmute(rawptr) raw_data(data), i32(len(data)), big_font.baseSize, nil, big_font.glyphCount, .SDF)
        big_atlas = rl.GenImageFontAtlas(big_font.glyphs, &big_font.recs, big_font.glyphCount, big_font.baseSize, 4, 0)
        big_font_done = true
    })

    rl.InitAudioDevice()
    click_sound := rl.LoadSound(fmt.caprint(DATA_PATH, "\\click.wav", sep=""))
    rl.PlaySound(click_sound)

    frames: int
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()
        defer frames += 1

        if die_in >  0 do die_in -= 1
        if die_in == 0 do os.exit(0)
     
        if big_font_done {
            thread.join(second)
            big_font.texture = rl.LoadTextureFromImage(big_atlas)
            rl.SetTextureFilter(big_font.texture, .BILINEAR)
            rl.UnloadFont(font)
            font = big_font
            big_font_done = false
        }

        width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
        cols := COLS_PER_512 * cast(int) math.ceil(f32(width)  / 512)
        rows := ROWS_PER_512 * cast(int) math.ceil(f32(height) / 512)

        mx, my := rl.GetMouseX(), rl.GetMouseY()
        key := rl.GetCharPressed()

        x, y := PAD, PAD
        button_width  := (width  - 2*PAD) / cast(i32) cols
        button_height := (height - 2*PAD) / cast(i32) rows
        
        rl.ClearBackground(BG)

        for a in Action {
            if a == .NONE do continue

            for b in buttons[a] {
                rect(x + 4, y + 4, button_width, button_height, SH)
                rect(x, y, button_width, button_height, TINTS[a])
                if mx > x && mx < x + button_width && my > y && my < y + button_height {
                    rect(x, y, button_width, button_height, brighten(TINTS[a], 80))

                    if rl.IsMouseButtonReleased(.LEFT) {
                        rl.PlaySound(click_sound)
                        handle_click(b)
                    }
                } 
                if key != 0 && utf8.rune_at(string(b.name), 0) == key do handle_click(b)

                text_y := y + button_height/2 - button_height/3 * 2/3

                rl.DrawTextEx(font, b.name, v(x + MARGIN + 1, text_y + 1), f32(button_height) / 3, 1, SH)
                rl.DrawTextEx(font, b.name, v(x + MARGIN, text_y), f32(button_height) / 3, 1, FG)
                rl.DrawLine(x + MARGIN, text_y + button_height/3 + 1, x + button_height / 3 * 2 / 3 + 4, text_y + button_height / 3 + 1, FG)
                // to simplify or not to simplify

                x += button_width + MARGIN
                if x + button_width >= width + PAD - 1 {
                    x = PAD
                    y = y + button_height + cast(i32) MARGIN
                }
            }
            
            x = PAD
            y = y + 2 * (button_height + cast(i32) MARGIN)
        }
        
        for problem, i in problems {
            rl.DrawTextEx(font, problem, v(PAD + 1, f32(height - i32(len(problems) - i)*16 - PAD + 1)), 16, 1, SH)
            rl.DrawTextEx(font, problem, v(PAD, f32(height - i32(len(problems) - i)*16 - PAD)), 16, 1, { 249, 47, 84, 255 })
        }
    }

}

v :: proc(#any_int x, y: int) -> rl.Vector2 { return rl.Vector2 { f32(x), f32(y) } }
max :: proc(#any_int a, b: int) -> int { return a if a > b else b }
rect :: proc(#any_int x, y, w, h: int, color: rl.Color) { rl.DrawRectangle(cast(i32) x, cast(i32) y, cast(i32) w, cast(i32) h, color) }
brighten :: proc(color: rl.Color, points: u8) -> rl.Color { color := color + points; return color }

parse_data :: proc(filename: string) -> (output: [Action][dynamic] Button) {//{{{
    
    trim :: strings.trim_space

    buf, ok := os.read_entire_file(filename)
    if !ok { 
        append(&problems, fmt.caprintf("The main data file: '%s' does not exist or cannot be accessed!", filename))
    }


    data := string(buf)
    rows := strings.split(data, "\n")
    for row, i in rows {
        if i == 0 do continue // header
        cols := strings.split(row, "|")
        if len(cols) < 3 {
            if len(cols) > 1 do append(&problems, fmt.caprintf("Found a row without 3 columns! %v", cols))
            continue
        }
        action, ok := reflect.enum_from_name(Action, trim(cols[0]))
        if !ok { append(&problems, fmt.caprintf("Action by the name: '%s' does not exist! Valid actions: %v", trim(cols[0]), reflect.enum_field_names(Action)[1:])) }

        append(&output[action], 
            Button { action = action, name = strings.clone_to_cstring(trim(cols[1])), buffer = trim(cols[2]) })

    }
    return
}//}}}

write_data :: proc(filename: string, data: [Action][dynamic] Button) {//{{{
    using strings
    @static SPACING := "                                                                                                                              "
    builder: Builder
    
    lengths: [2] int = { len("ACTION"), len("NAME") }

    for a in Action { lengths[0] = max(lengths[0], len(reflect.enum_string(a))) }
    for a in Action {
        for b in data[a] {
            lengths[1] = max(lengths[1], len(b.name))
        }
    }

    // HEADER
    write_string(&builder, "ACTION")
    write_string(&builder, SPACING[:lengths[0] - len("ACTION")])
    write_string(&builder, " | NAME")
    write_string(&builder, SPACING[:lengths[1] - len("NAME")])
    write_string(&builder, " | VALUE")
    write_string(&builder, "\r\n")

    for a in Action {
        action := reflect.enum_string(a)
        for b in data[a] {
            write_string(&builder, action)
            write_string(&builder, SPACING[:lengths[0] - len(action)])
            write_string(&builder, " | ")
            write_string(&builder, string(b.name))
            write_string(&builder, SPACING[:lengths[1] - len(b.name)])
            write_string(&builder, " | ")
            write_string(&builder, b.buffer)
            write_string(&builder, "\r\n")
        }
    }
    
    ok := os.write_entire_file(filename, transmute([] u8) to_string(builder))
    if !ok do fmt.println("Couldn't write to file...")

    fmt.println(to_string(builder))
    builder_destroy(&builder)
}//}}}

handle_click :: proc(b: Button) {
    switch b.action {
    case .NONE:
    case .COPY:
        text := strings.clone_to_cstring(b.buffer)
        rl.SetClipboardText(text)
        delete(text)
        die_in = 5
    case .OPEN:
        thread.create_and_start_with_poly_data(b.buffer, proc(input: string) {
            user := strings.split(input, " ")
            pdesc: os2.Process_Desc
            pdesc.command = make([] string, 4 + len(user))
            pdesc.command[0] = "cmd"
            pdesc.command[1] = "/c"
            pdesc.command[2] = "start"
            pdesc.command[3] = "/b"
            for cmd, i in user { pdesc.command[4 + i] = cmd }

            state, stdout, stderr, err := os2.process_exec(pdesc, context.allocator)
            fmt.assertf(err != .Not_Exist, "The process by name: '%s' does not exist!", input)
            fmt.println(state, stdout, stderr, err)
        })
        die_in = 15
        



    }
}

