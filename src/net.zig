const std = @import("std");
const game = @import("game.zig");
const serde = @import("serialize.zig");

pub const MessageType = enum(u16) {
    get_state,
};

pub const GetStateMessageData = struct {};

pub const MessageData = union(MessageType) {
    get_state: GetStateMessageData,
};

pub const Message = struct {
    type: MessageType,
    data: MessageData,

    pub fn serialize(self: Message, alloc: *const std.mem.Allocator) ![]u8 {
        var data = try alloc.alloc(u8, 2);
        std.mem.writeInt(u16, data[0..2], @intFromEnum(self.type), std.builtin.Endian.little);

        switch (self.data) {
            MessageType.get_state => |get_state_data| {
                const data_bytes = try serde.serialize(GetStateMessageData, &get_state_data, alloc);
                data = try alloc.realloc(data, 2 + data_bytes.len);
                std.mem.copyForwards(u8, data[2 .. 2 + data_bytes.len], data_bytes);
            },
        }

        return data;
    }
};

pub const ResponseType = enum(u16) {
    state,
};

pub const ResponseData = union(ResponseType) {
    state: game.State,
};

pub const Response = struct {
    type: ResponseType,
    data: ResponseData,

    pub fn serialize(self: Response, alloc: *const std.mem.Allocator) ![]u8 {
        var data = try alloc.alloc(u8, 2);
        std.mem.writeInt(u16, data[0..2], @intFromEnum(self.type), std.builtin.Endian.little);

        switch (self.data) {
            ResponseType.state => |state| {
                const data_bytes = try state.serialize(alloc);

                data = try alloc.realloc(data, 2 + data_bytes.len);
                std.mem.copyForwards(u8, data[2 .. 2 + data_bytes.len], data_bytes);
            },
        }

        return data;
    }

    pub fn deserialize(data: []u8, alloc: *const std.mem.Allocator) !Response {
        const tag = std.mem.readInt(u16, data[0..2], std.builtin.Endian.little);
        const bytes = data[2..];

        switch (tag) {
            ResponseType.state => {
                const state = try serde.deserialize(game.State, bytes, alloc);
                return Response{ .type = ResponseType.state, .data = ResponseData.state(state) };
            },
        }
    }
};
