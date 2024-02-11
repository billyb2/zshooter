const std = @import("std");
const game = @import("game.zig");
const gameNet = @import("net.zig");

pub const io_mode = std.io.Mode.evented;

pub fn main() !void {
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = allocator.deinit();
    const alloc = allocator.allocator();

    std.debug.print("Starting server\n", .{});

    var sock = std.net.StreamServer.init(.{});
    // zig 0.11 doesn't give the option for non blocking sockets
    var address = try std.net.Address.parseIp6("::", 9999);
    const nonblock = 0;
    const sock_flags = std.os.SOCK.STREAM | std.os.SOCK.CLOEXEC | nonblock | std.os.SOCK.NONBLOCK;
    const proto = std.os.IPPROTO.TCP;

    const sockfd = try std.os.socket(address.any.family, sock_flags, proto);
    sock.sockfd = sockfd;

    var socklen = address.getOsSockLen();
    try std.os.bind(sockfd, &address.any, socklen);
    try std.os.listen(sockfd, @as(u31, 128));
    try std.os.getsockname(sockfd, &address.any, &socklen);

    defer sock.close();

    var stream_list = try StreamList.init(&alloc);

    _ = try std.Thread.spawn(std.Thread.SpawnConfig{
        .allocator = alloc,
    }, accept, .{
        &sock,
        &socklen,
        &alloc,
        &stream_list,
    });

    var state = game.State{
        .alloc = &alloc,
        .position = 0,
    };

    while (true) {
        state = try state.update();

        stream_list.lock.lockShared();
        defer stream_list.lock.unlockShared();

        for (stream_list.streams) |stream| {
            const message = read_message(stream, alloc) catch |err| switch (err) {
                std.os.ReadError.WouldBlock => {
                    std.debug.print("Would block\n", .{});
                    continue;
                },
                else => return err,
            };

            std.debug.print("Received message of type {}\n", .{message.type});

            switch (message.data) {
                .get_state => {
                    const response = gameNet.Response{
                        .type = gameNet.ResponseType.state,
                        .data = gameNet.ResponseData{
                            .state = state,
                        },
                    };
                    const response_bytes = try response.serialize(&alloc);
                    _ = try stream.write(response_bytes);
                },
            }
        }

        // 120 ticks per second
        std.time.sleep(8333333);
    }
}

const StreamList = struct {
    streams: []std.net.Stream,
    lock: std.Thread.RwLock.DefaultRwLock,

    pub fn init(alloc: *const std.mem.Allocator) !StreamList {
        return StreamList{
            .streams = try alloc.alloc(std.net.Stream, 0),
            .lock = std.Thread.RwLock.DefaultRwLock{},
        };
    }

    pub fn push(self: *StreamList, alloc: *const std.mem.Allocator, stream: std.net.Stream) !void {
        self.lock.lock();
        defer self.lock.unlock();

        self.streams = try alloc.realloc(self.streams, self.streams.len + 1);
        self.streams[self.streams.len - 1] = stream;
    }
};

fn accept(sock: *std.net.StreamServer, addrlen: *std.os.socklen_t, alloc: *const std.mem.Allocator, stream_list: *StreamList) !void {
    while (true) {
        const conn = std.os.accept(sock.sockfd.?, &sock.listen_address.any, addrlen, 0) catch |err| switch (err) {
            std.os.AcceptError.WouldBlock => continue,
            else => return err,
        };
        const stream = std.net.Stream{
            .handle = conn,
        };

        stream_list.push(alloc, stream) catch |err| {
            std.debug.print("Failed to push stream: {}\n", .{err});
        };

        // 1 second in nanoseconds
        std.time.sleep(1000000000);
    }
}

fn read_message(stream: std.net.Stream, alloc: std.mem.Allocator) !gameNet.Message {
    var tag_bytes: [@sizeOf(u16)]u8 = undefined;
    _ = try stream.read(&tag_bytes);
    const tag_int = std.mem.readInt(u16, &tag_bytes, std.builtin.Endian.little);
    const tag: gameNet.MessageType = @enumFromInt(tag_int);

    var data_len_bytes: [@sizeOf(u32)]u8 = undefined;
    _ = try stream.read(&data_len_bytes);
    const data_len = std.mem.readInt(u32, &data_len_bytes, std.builtin.Endian.little);

    const data: []u8 = try alloc.alloc(u8, data_len);
    _ = try stream.read(data);

    const message_data = switch (tag) {
        .get_state => gameNet.MessageData{
            .get_state = .{},
        },
    };

    return gameNet.Message{ .data = message_data, .type = tag };
}
