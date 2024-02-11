const std = @import("std");
const game = @import("game.zig");
const gameNet = @import("net.zig");

const rl = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocator.deinit();
    const alloc = allocator.allocator();

    const address = try std.net.Address.parseIp6("::1", 9999);
    var stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    var game_state = try init(&stream, &alloc);

    rl.InitWindow(800, 600, "zshooter");
    defer rl.CloseWindow();

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        game_state = try init(&stream, &alloc);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        // Side effects make me cry
        draw(&game_state);
    }
}

pub fn init(stream: *std.net.Stream, alloc: *const std.mem.Allocator) !game.State {
    const msg = gameNet.Message{ .type = gameNet.MessageType.get_state, .data = gameNet.MessageData{ .get_state = gameNet.GetStateMessageData{} } };
    const bytes = try msg.serialize(alloc);
    defer alloc.free(bytes);

    try stream.writeAll(bytes);

    var resp_tag_bytes: [@sizeOf(u16)]u8 = undefined;
    _ = try stream.readAtLeast(&resp_tag_bytes, @sizeOf(u16));
    const resp_tag_int = std.mem.readInt(u16, &resp_tag_bytes, std.builtin.Endian.little);
    const resp_tag: gameNet.ResponseType = @enumFromInt(resp_tag_int);

    std.debug.print("Received response type: {}\n", .{resp_tag});

    var data_len_bytes: [@sizeOf(u32)]u8 = undefined;
    _ = try stream.readAtLeast(&data_len_bytes, @sizeOf(u32));
    const data_len = std.mem.readInt(u32, &data_len_bytes, std.builtin.Endian.little);

    std.debug.print("Received data length: {}\n", .{data_len});

    const data: []u8 = try alloc.alloc(u8, data_len);
    _ = try stream.readAtLeast(data, data_len);

    const state = switch (resp_tag) {
        .state => try game.State.deserialize(data),
        //TODO: make this an error
        //else => std.debug.panic("Unknown response type"),
    };
    return state;
}

pub fn draw(state: *const game.State) void {
    rl.ClearBackground(rl.RAYWHITE);
    rl.DrawRectangle(@as(c_int, state.position), 0, 50, 50, rl.BLACK);
}
